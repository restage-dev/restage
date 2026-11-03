import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Restage state files that builds read as inputs.
const List<String> restageStateBuildInputs = <String>[
  '.restage/measurement-state.json',
  '.restage/wire-ids.events.jsonl',
  '.restage/receipts/**',
];

/// What [planStateBuildInputs] would do to `build.yaml`.
enum StateBuildInputsAction {
  /// Write a new file.
  create,

  /// Add the missing entries.
  update,

  /// Leave the file as it is; every entry is already listed.
  keep,

  /// The file cannot be edited safely; the user adds the entries.
  manual,
}

/// The planned `build.yaml` edit.
@immutable
class StateBuildInputsPlan {
  /// Construct a plan.
  const StateBuildInputsPlan(this.action, this.source);

  /// What applying the plan does.
  final StateBuildInputsAction action;

  /// The source to write; the original for [StateBuildInputsAction.keep] and
  /// [StateBuildInputsAction.manual].
  final String source;
}

/// Plans listing [restageStateBuildInputs] under `additional_public_assets`
/// in `build.yaml`, whose current [source] is null when the file is absent.
/// Only missing entries are added; the rest of the file is left untouched.
StateBuildInputsPlan planStateBuildInputs(String? source) {
  if (source == null || source.trim().isEmpty) {
    final created = StringBuffer(source ?? '')
      ..writeln('additional_public_assets:');
    for (final entry in restageStateBuildInputs) {
      created.writeln('  - $entry');
    }
    return StateBuildInputsPlan(
      source == null
          ? StateBuildInputsAction.create
          : StateBuildInputsAction.update,
      created.toString(),
    );
  }

  final manual = StateBuildInputsPlan(StateBuildInputsAction.manual, source);
  final Object? doc;
  try {
    doc = loadYaml(source);
  } on YamlException {
    return manual;
  }
  if (doc is! YamlMap) return manual;

  try {
    final editor = YamlEditor(source);
    final listed = doc['additional_public_assets'];
    if (listed == null) {
      editor.update(['additional_public_assets'], restageStateBuildInputs);
    } else if (listed is YamlList) {
      final missing = [
        for (final entry in restageStateBuildInputs)
          if (!listed.contains(entry)) entry,
      ];
      if (missing.isEmpty) {
        return StateBuildInputsPlan(StateBuildInputsAction.keep, source);
      }
      for (final entry in missing) {
        editor.appendToList(['additional_public_assets'], entry);
      }
    } else {
      return manual;
    }
    return StateBuildInputsPlan(
      StateBuildInputsAction.update,
      editor.toString(),
    );
  } on Exception {
    return manual;
  }
}

/// The builder that writes the startup request templates.
const String earlyRequestBuilderKey = 'restage_codegen:restage_early_template';

/// Plans the options of the startup request builder in `build.yaml`, whose
/// current [source] is null when the file is absent.
///
/// Existing options are never replaced. [apiKey] and [baseUrl] are written
/// when given; [enabled] false writes `early_request: false`.
StateBuildInputsPlan planEarlyRequestOptions(
  String? source, {
  String? baseUrl,
  String? apiKey,
  bool enabled = true,
}) {
  final wanted = <String, Object>{
    if (!enabled) 'early_request': false,
    if (enabled && baseUrl != null) 'base_url': baseUrl,
    if (enabled && apiKey != null) 'api_key': apiKey,
  };
  final current = source ?? '';
  if (wanted.isEmpty) {
    return StateBuildInputsPlan(StateBuildInputsAction.keep, current);
  }
  final Object? doc;
  try {
    doc = current.trim().isEmpty ? YamlMap() : loadYaml(current);
  } on YamlException {
    return StateBuildInputsPlan(StateBuildInputsAction.manual, current);
  }
  if (doc is! YamlMap) {
    return StateBuildInputsPlan(StateBuildInputsAction.manual, current);
  }
  try {
    final editor = YamlEditor(current);
    const path = ['targets', r'$default', 'builders', earlyRequestBuilderKey];
    Object? at(List<Object> keys) {
      Object? node = doc;
      for (final key in keys) {
        if (node is! YamlMap) return null;
        node = node[key];
      }
      return node;
    }

    final existing = at([...path, 'options']);
    final merged = <String, Object>{
      if (existing is YamlMap)
        for (final entry in existing.entries)
          entry.key as String: entry.value as Object,
      for (final entry in wanted.entries)
        if (existing is! YamlMap || !existing.containsKey(entry.key))
          entry.key: entry.value,
    };
    if (existing is YamlMap && merged.length == existing.length) {
      return StateBuildInputsPlan(StateBuildInputsAction.keep, current);
    }
    // Create the missing levels in one step; the editor cannot make parents.
    final full = [...path, 'options'];
    var present = 0;
    Object? node = doc;
    while (present < full.length &&
        node is YamlMap &&
        node.containsKey(full[present])) {
      node = node[full[present]];
      present++;
    }
    Object value = merged;
    for (var i = full.length - 1; i > present; i--) {
      value = {full[i]: value};
    }
    if (present == full.length) {
      editor.update(full, merged);
    } else if (present == 0 && current.trim().isEmpty) {
      editor.update([], {full.first: value});
    } else {
      editor.update(full.sublist(0, present + 1), value);
    }
    return StateBuildInputsPlan(
      current.trim().isEmpty
          ? StateBuildInputsAction.create
          : StateBuildInputsAction.update,
      editor.toString(),
    );
  } on Exception {
    return StateBuildInputsPlan(StateBuildInputsAction.manual, current);
  }
}
