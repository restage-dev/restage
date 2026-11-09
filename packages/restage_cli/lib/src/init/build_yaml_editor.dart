import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart' show canonicalServiceUrl;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Restage state files that builds read as inputs.
const List<String> restageStateBuildInputs = <String>['.restage/**'];

/// Older entries that [restageStateBuildInputs] covers; init replaces them.
const List<String> _coveredStateInputs = <String>[
  '.restage/measurement-state.json',
  '.restage/wire-ids.events.jsonl',
  '.restage/receipts/**',
];

/// The builder whose options hold the app's publishable key, service URL and
/// delivery channel.
const String deliveryOptionsBuilderKey = 'restage_codegen:user_factories';

/// The builder that held those options before; the build no longer reads them.
const String legacyDeliveryOptionsBuilderKey =
    'restage_codegen:restage_early_template';

const _builders = ['targets', r'$default', 'builders'];
const _movable = ['api_key', 'base_url', 'channel'];

/// What [planBuildYaml] would do to `build.yaml`.
enum StateBuildInputsAction {
  /// Write a new file.
  create,

  /// Change the file.
  update,

  /// Leave the file as it is.
  keep,

  /// The file cannot be edited safely; the user adds the entries.
  manual,
}

/// The planned `build.yaml` edit.
@immutable
class StateBuildInputsPlan {
  /// Construct a plan.
  const StateBuildInputsPlan(
    this.action,
    this.source, {
    this.written = const [],
    this.kept = const [],
    this.hasApiKey = false,
  });

  /// What applying the plan does.
  final StateBuildInputsAction action;

  /// The source to write; the original for [StateBuildInputsAction.keep] and
  /// [StateBuildInputsAction.manual].
  final String source;

  /// What the plan changes, in words, such as `state file tracking` or
  /// `the publishable key`.
  final List<String> written;

  /// Options the plan was given but left alone because the file already sets
  /// a different value.
  final List<String> kept;

  /// Whether the file has a publishable key once the plan is applied.
  final bool hasApiKey;
}

/// Plans `build.yaml`, whose current [source] is null when the file is absent:
/// `.restage/**` under `additional_public_assets`, and [apiKey] and [baseUrl]
/// under the [deliveryOptionsBuilderKey] options.
///
/// Options under [legacyDeliveryOptionsBuilderKey] move to their new place and
/// `early_request` is dropped. Existing values are never replaced.
StateBuildInputsPlan planBuildYaml(
  String? source, {
  String? apiKey,
  String? baseUrl,
}) {
  final current = source ?? '';
  final manual = StateBuildInputsPlan(
    StateBuildInputsAction.manual,
    current,
    hasApiKey: apiKey != null,
  );
  final Object? parsed;
  try {
    parsed = current.trim().isEmpty ? YamlMap() : loadYaml(current);
  } on YamlException {
    return manual;
  }
  if (parsed is! YamlMap) return manual;
  try {
    final editor = YamlEditor(current);
    final written = <String>[];
    if (!_planStateInputs(editor)) return manual;
    if (editor.toString() != current) written.add('state file tracking');
    final delivery = _planDeliveryOptions(
      editor,
      apiKey: apiKey,
      baseUrl: baseUrl == null ? null : canonicalServiceUrl(baseUrl),
    );
    written.addAll(delivery.written);
    final hasApiKey =
        _at(_doc(editor), [
          ..._builders,
          deliveryOptionsBuilderKey,
          'options',
          'api_key',
        ]) !=
        null;
    var next = editor.toString();
    if (next != current && !next.endsWith('\n')) next = '$next\n';
    return StateBuildInputsPlan(
      next == current
          ? StateBuildInputsAction.keep
          : current.trim().isEmpty
          ? StateBuildInputsAction.create
          : StateBuildInputsAction.update,
      next,
      written: written,
      kept: delivery.kept,
      hasApiKey: hasApiKey,
    );
  } on Exception {
    return manual;
  }
}

/// Lists [restageStateBuildInputs] in place of the entries it covers; false
/// when the list is not one the editor can change.
bool _planStateInputs(YamlEditor editor) {
  const path = ['additional_public_assets'];
  final listed = _at(_doc(editor), path);
  if (listed == null) {
    _set(editor, path, restageStateBuildInputs);
    return true;
  }
  if (listed is! YamlList) return false;
  for (var i = listed.length - 1; i >= 0; i--) {
    if (_coveredStateInputs.contains(listed[i])) {
      editor.remove([...path, i]);
    }
  }
  final now = _at(_doc(editor), path)! as YamlList;
  for (final entry in restageStateBuildInputs) {
    if (!now.contains(entry)) editor.appendToList(path, entry);
  }
  return true;
}

({List<String> written, List<String> kept}) _planDeliveryOptions(
  YamlEditor editor, {
  String? apiKey,
  String? baseUrl,
}) {
  final options = [..._builders, deliveryOptionsBuilderKey, 'options'];
  final legacy = [..._builders, legacyDeliveryOptionsBuilderKey];
  final written = <String>[];
  final kept = <String>[];

  // Options under the old builder move unless the new place already has them.
  final old = _at(_doc(editor), [...legacy, 'options']);
  if (old is YamlMap) {
    final moved = <String>[];
    for (final key in [..._movable, 'early_request']) {
      if (!old.containsKey(key)) continue;
      // A blank value moves nothing; a URL moves in canonical form.
      final value = switch ((key, old[key])) {
        ('base_url', final String url) => canonicalServiceUrl(url),
        (_, final Object value) => value,
        _ => null,
      };
      if (value != null &&
          _movable.contains(key) &&
          _at(_doc(editor), [...options, key]) == null) {
        _set(editor, [...options, key], value);
        moved.add(key);
      }
      editor.remove([...legacy, 'options', key]);
    }
    // Drop the levels the move left empty.
    for (var depth = legacy.length + 1; depth > 0; depth--) {
      final path = [...legacy, 'options'].sublist(0, depth);
      final node = _at(_doc(editor), path);
      if (node is YamlMap && node.isEmpty) editor.remove(path);
    }
    written.add(
      moved.isEmpty
          ? 'removed old $legacyDeliveryOptionsBuilderKey options'
          : 'moved ${moved.join(', ')} from $legacyDeliveryOptionsBuilderKey',
    );
  }

  for (final (key, value, words) in [
    ('base_url', baseUrl, 'the service URL'),
    ('api_key', apiKey, 'the publishable key'),
  ]) {
    if (value == null) continue;
    final existing = _at(_doc(editor), [...options, key]);
    if (existing == null) {
      _set(editor, [...options, key], value);
      written.add(words);
    } else if (_comparable(key, existing) != value) {
      kept.add(key);
    }
  }
  return (written: written, kept: kept);
}

// A URL compares in canonical form, so a trailing slash is no difference.
Object? _comparable(String key, Object? value) =>
    key == 'base_url' && value is String ? canonicalServiceUrl(value) : value;

YamlMap _doc(YamlEditor editor) {
  final text = editor.toString();
  final doc = text.trim().isEmpty ? null : loadYaml(text);
  return doc is YamlMap ? doc : YamlMap();
}

Object? _at(Object? node, List<Object> keys) {
  for (final key in keys) {
    if (node is! YamlMap) return null;
    node = node[key];
  }
  return node;
}

/// Sets [path] to [value], creating the missing levels in one step; the
/// editor cannot make parents.
void _set(YamlEditor editor, List<Object> path, Object value) {
  final doc = _doc(editor);
  var present = 0;
  Object? node = doc;
  while (present < path.length - 1 &&
      node is YamlMap &&
      node[path[present]] is YamlMap) {
    node = node[path[present]];
    present++;
  }
  var nested = value;
  for (var i = path.length - 1; i > present; i--) {
    nested = {path[i]: nested};
  }
  if (present == 0 && editor.toString().trim().isEmpty) {
    editor.update([], {path.first: nested});
  } else {
    editor.update(path.sublist(0, present + 1), nested);
  }
}
