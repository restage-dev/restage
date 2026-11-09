import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Result of [addDependencies] — the edited YAML source plus the
/// per-entry disposition.
@immutable
class AddDependenciesResult {
  /// Construct a result.
  const AddDependenciesResult({
    required this.source,
    required this.added,
    required this.kept,
    this.converted = const [],
  });

  /// The edited pubspec source.
  final String source;

  /// Names of dependencies that were newly added.
  final List<String> added;

  /// Names of dependencies that already existed and were left alone.
  final List<String> kept;

  /// Names of entries moved from a version constraint to their source in
  /// `sources`.
  final List<String> converted;
}

/// What [addDependencies] *would* do, without writing.
///
/// Returned by [planAddDependencies] so commands can preview the
/// changes before applying them (the `--dry-run` and confirm-before-
/// applying flows).
@immutable
class AddDependenciesPlan {
  /// Construct a plan.
  const AddDependenciesPlan({
    required this.dependenciesToAdd,
    required this.devDependenciesToAdd,
    required this.dependenciesToKeep,
    required this.devDependenciesToKeep,
    this.overridesToAdd = const {},
    this.overridesToKeep = const {},
    this.toConvert = const [],
    this.assetsToAdd = const [],
  });

  /// New `dependencies:` entries → version constraint or source.
  final Map<String, Object> dependenciesToAdd;

  /// New `dev_dependencies:` entries → version constraint or source.
  final Map<String, Object> devDependenciesToAdd;

  /// New `dependency_overrides:` entries → version constraint or source.
  final Map<String, Object> overridesToAdd;

  /// Existing `dependencies:` entries the editor will leave alone →
  /// the current version constraint.
  final Map<String, String> dependenciesToKeep;

  /// Existing `dev_dependencies:` entries the editor will leave alone →
  /// the current version constraint.
  final Map<String, String> devDependenciesToKeep;

  /// Existing `dependency_overrides:` entries the editor will leave alone →
  /// the current version constraint.
  final Map<String, String> overridesToKeep;

  /// Entries whose version constraint moves to their source in `sources`.
  final List<String> toConvert;

  /// Flutter assets to list under `flutter: assets:`.
  final List<String> assetsToAdd;

  /// True when applying the plan would make no changes to the source.
  bool get isNoOp =>
      dependenciesToAdd.isEmpty &&
      devDependenciesToAdd.isEmpty &&
      overridesToAdd.isEmpty &&
      toConvert.isEmpty &&
      assetsToAdd.isEmpty;
}

/// Compute the [AddDependenciesPlan] for a future [addDependencies] call.
AddDependenciesPlan planAddDependencies(
  String pubspecSource, {
  Map<String, Object> deps = const {},
  Map<String, Object> devDeps = const {},
  Map<String, Object> overrides = const {},
  Map<String, Object> sources = const {},
  List<String> flutterAssets = const [],
}) {
  final editor = YamlEditor(pubspecSource);
  final toConvert = [
    for (final (block, name) in _hostedEntries(editor, sources))
      _entryLabel(block, name),
  ];
  // What the add step sees once those entries carry their source.
  for (final (block, name) in _hostedEntries(editor, sources)) {
    editor.update([block, name], sources[name]!);
  }
  final assetsToAdd = _missingAssets(editor, flutterAssets);
  (Map<String, Object>, Map<String, String>) split(
    String block,
    Map<String, Object> desired,
  ) {
    final toAdd = <String, Object>{};
    final toKeep = <String, String>{};
    for (final entry in desired.entries) {
      final existing = _existingConstraint(editor, block, entry.key);
      if (existing == null) {
        toAdd[entry.key] = entry.value;
      } else {
        toKeep[entry.key] = existing;
      }
    }
    return (toAdd, toKeep);
  }

  final (depsToAdd, depsToKeep) = split('dependencies', deps);
  final (devDepsToAdd, devDepsToKeep) = split('dev_dependencies', devDeps);
  final (overridesToAdd, overridesToKeep) = split(
    'dependency_overrides',
    overrides,
  );
  Map<String, String> unconverted(Map<String, String> entries) => {
    for (final entry in entries.entries)
      if (!toConvert.contains(entry.key)) entry.key: entry.value,
  };
  return AddDependenciesPlan(
    dependenciesToAdd: depsToAdd,
    devDependenciesToAdd: devDepsToAdd,
    dependenciesToKeep: unconverted(depsToKeep),
    devDependenciesToKeep: unconverted(devDepsToKeep),
    overridesToAdd: overridesToAdd,
    overridesToKeep: overridesToKeep,
    toConvert: toConvert,
    assetsToAdd: assetsToAdd,
  );
}

/// Add the named [deps], [devDeps] and [overrides] to the `dependencies:`,
/// `dev_dependencies:` and `dependency_overrides:` blocks respectively,
/// creating each block when absent. A value is a version constraint or a
/// source map such as `{'git': {...}}`.
///
/// Existing entries (any name match at any version) are left untouched
/// and reported in [AddDependenciesResult.kept]. Newly-added entries
/// are reported in [AddDependenciesResult.added].
///
/// Returns the edited source and a per-entry summary.
AddDependenciesResult addDependencies(
  String pubspecSource, {
  Map<String, Object> deps = const {},
  Map<String, Object> devDeps = const {},
  Map<String, Object> overrides = const {},
  Map<String, Object> sources = const {},
  List<String> flutterAssets = const [],
}) {
  final editor = YamlEditor(pubspecSource);
  final added = <String>[];
  final kept = <String>[];
  final converted = <String>[];
  for (final (block, name) in _hostedEntries(editor, sources)) {
    editor.update([block, name], sources[name]!);
    converted.add(_entryLabel(block, name));
  }

  _applyBlock(
    editor: editor,
    block: 'dependencies',
    desired: deps,
    added: added,
    kept: kept,
  );
  _applyBlock(
    editor: editor,
    block: 'dev_dependencies',
    desired: devDeps,
    added: added,
    kept: kept,
  );
  for (final asset in _missingAssets(editor, flutterAssets)) {
    final listed = _at(editor, ['flutter', 'assets']);
    if (listed is YamlList) {
      editor.appendToList(['flutter', 'assets'], asset);
    } else if (_at(editor, ['flutter']) is YamlMap) {
      editor.update(['flutter', 'assets'], [asset]);
    } else {
      editor.update(
        ['flutter'],
        {
          'assets': [asset],
        },
      );
    }
    added.add('$asset (asset)');
  }
  var source = editor.toString();
  if (!_present(editor, ['dependency_overrides']) && overrides.isNotEmpty) {
    // A new block goes at the end, after any trailing comments, so it never
    // lands inside the commented examples under `flutter:`.
    final block = YamlEditor('')
      ..update([], {'dependency_overrides': overrides});
    source = '${source.trimRight()}\n\n${block.toString().trimRight()}\n';
    added.addAll([for (final name in overrides.keys) '$name (override)']);
  } else {
    _applyBlock(
      editor: editor,
      block: 'dependency_overrides',
      desired: overrides,
      added: added,
      kept: kept,
      label: (name) => '$name (override)',
    );
    source = editor.toString();
  }

  return AddDependenciesResult(
    source: source,
    added: added,
    kept: [
      for (final name in kept)
        if (!converted.contains(name)) name,
    ],
    converted: converted,
  );
}

const _blocks = ['dependencies', 'dev_dependencies', 'dependency_overrides'];

/// The entries of [sources]' packages given as a version constraint.
List<(String, String)> _hostedEntries(
  YamlEditor editor,
  Map<String, Object> sources,
) => [
  for (final block in _blocks)
    if (_at(editor, [block]) case final YamlMap entries)
      for (final name in entries.keys.cast<String>())
        if (sources.containsKey(name) && entries[name] is String?)
          (block, name),
];

String _entryLabel(String block, String name) =>
    block == 'dependency_overrides' ? '$name (override)' : name;

List<String> _missingAssets(YamlEditor editor, List<String> assets) {
  final listed = _at(editor, ['flutter', 'assets']);
  return [
    for (final asset in assets)
      if (listed is! YamlList || !listed.contains(asset)) asset,
  ];
}

/// Whether [path] is a key in the document, even with no value.
bool _present(YamlEditor editor, List<Object> path) {
  try {
    editor.parseAt(path);
    return true;
  } on ArgumentError {
    return false;
  }
}

Object? _at(YamlEditor editor, List<Object> path) {
  try {
    return editor.parseAt(path).value is Object ? editor.parseAt(path) : null;
  } on ArgumentError {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Sentinel returned by [_existingConstraint] for entries whose value is
/// not a simple version string — path deps, git deps, SDK refs. The
/// printer renders these as "(see pubspec)" so the dry-run summary
/// doesn't surface a confusing literal.
const String complexConstraintMarker = '__complex_constraint__';

String? _existingConstraint(YamlEditor editor, String block, String dep) {
  try {
    final value = editor.parseAt([block, dep]).value;
    if (value is String) return value;
    return complexConstraintMarker;
  } on ArgumentError {
    return null;
  }
}

void _applyBlock({
  required YamlEditor editor,
  required String block,
  required Map<String, Object> desired,
  required List<String> added,
  required List<String> kept,
  String Function(String name)? label,
}) {
  if (desired.isEmpty) return;
  // An absent or empty block is written whole, so it takes block style.
  if (_at(editor, [block]) is! YamlMap) {
    editor.update([block], desired);
    added.addAll([for (final name in desired.keys) label?.call(name) ?? name]);
    return;
  }
  for (final entry in desired.entries) {
    final name = label?.call(entry.key) ?? entry.key;
    if (_existingConstraint(editor, block, entry.key) != null) {
      kept.add(name);
      continue;
    }
    editor.update([block, entry.key], entry.value);
    added.add(name);
  }
}
