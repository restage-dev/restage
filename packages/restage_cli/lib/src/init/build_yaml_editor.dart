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
