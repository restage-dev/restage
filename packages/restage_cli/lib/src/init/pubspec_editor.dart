import 'package:meta/meta.dart';
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
  });

  /// The edited pubspec source.
  final String source;

  /// Names of dependencies that were newly added.
  final List<String> added;

  /// Names of dependencies that already existed and were left alone.
  final List<String> kept;
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
  });

  /// New `dependencies:` entries → version constraint.
  final Map<String, String> dependenciesToAdd;

  /// New `dev_dependencies:` entries → version constraint.
  final Map<String, String> devDependenciesToAdd;

  /// Existing `dependencies:` entries the editor will leave alone →
  /// the current version constraint.
  final Map<String, String> dependenciesToKeep;

  /// Existing `dev_dependencies:` entries the editor will leave alone →
  /// the current version constraint.
  final Map<String, String> devDependenciesToKeep;

  /// True when applying the plan would make no changes to the source.
  bool get isNoOp => dependenciesToAdd.isEmpty && devDependenciesToAdd.isEmpty;
}

/// Compute the [AddDependenciesPlan] for a future [addDependencies] call.
AddDependenciesPlan planAddDependencies(
  String pubspecSource, {
  Map<String, String> deps = const {},
  Map<String, String> devDeps = const {},
}) {
  final editor = YamlEditor(pubspecSource);
  final depsToAdd = <String, String>{};
  final depsToKeep = <String, String>{};
  for (final entry in deps.entries) {
    final existing = _existingConstraint(editor, 'dependencies', entry.key);
    if (existing == null) {
      depsToAdd[entry.key] = entry.value;
    } else {
      depsToKeep[entry.key] = existing;
    }
  }
  final devDepsToAdd = <String, String>{};
  final devDepsToKeep = <String, String>{};
  for (final entry in devDeps.entries) {
    final existing = _existingConstraint(editor, 'dev_dependencies', entry.key);
    if (existing == null) {
      devDepsToAdd[entry.key] = entry.value;
    } else {
      devDepsToKeep[entry.key] = existing;
    }
  }
  return AddDependenciesPlan(
    dependenciesToAdd: depsToAdd,
    devDependenciesToAdd: devDepsToAdd,
    dependenciesToKeep: depsToKeep,
    devDependenciesToKeep: devDepsToKeep,
  );
}

/// Add the named [deps] and [devDeps] to the `dependencies:` and
/// `dev_dependencies:` blocks respectively, creating either block when
/// absent.
///
/// Existing entries (any name match at any version) are left untouched
/// and reported in [AddDependenciesResult.kept]. Newly-added entries
/// are reported in [AddDependenciesResult.added].
///
/// Returns the edited source and a per-entry summary.
AddDependenciesResult addDependencies(
  String pubspecSource, {
  Map<String, String> deps = const {},
  Map<String, String> devDeps = const {},
}) {
  final editor = YamlEditor(pubspecSource);
  final added = <String>[];
  final kept = <String>[];

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

  return AddDependenciesResult(
    source: editor.toString(),
    added: added,
    kept: kept,
  );
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
  required Map<String, String> desired,
  required List<String> added,
  required List<String> kept,
}) {
  if (desired.isEmpty) return;
  // Ensure the parent block exists.
  try {
    editor.parseAt([block]);
  } on ArgumentError {
    editor.update([block], {});
  }
  for (final entry in desired.entries) {
    if (_existingConstraint(editor, block, entry.key) != null) {
      kept.add(entry.key);
      continue;
    }
    editor.update([block, entry.key], entry.value);
    added.add(entry.key);
  }
}
