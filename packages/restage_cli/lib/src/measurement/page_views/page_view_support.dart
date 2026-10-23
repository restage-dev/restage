import 'dart:convert';

import 'package:restage_cli/src/output/held_count.dart';

/// Shown where a figure is not in the reading.
const String kFigureUnavailable = 'Not available';

/// The value at [path] in [json], or null when any step is missing.
Object? figureAt(Object? json, List<Object> path) {
  var at = json;
  for (final step in path) {
    at = switch ((at, step)) {
      (final Map<String, Object?> map, final String key) => map[key],
      (final List<Object?> list, final int index)
          when index >= 0 && index < list.length =>
        list[index],
      _ => null,
    };
  }
  return at;
}

/// The entries of the list at [path], or none.
List<Object?> figureList(Object? json, List<Object> path) =>
    figureAt(json, path) is List<Object?>
    ? figureAt(json, path)! as List<Object?>
    : const [];

/// Writes the reply for a person: the page's figures, or why it states none.
///
/// [raw] is the service's reply. [render] writes the page document.
void renderPageReply(
  StringSink out,
  String raw,
  void Function(StringSink out, Map<String, Object?> document) render,
) {
  final Object? envelope;
  try {
    envelope = jsonDecode(raw);
  } on FormatException {
    out.writeln('$kFigureUnavailable: the reply could not be read.');
    return;
  }
  if (envelope is! Map<String, Object?>) {
    out.writeln('$kFigureUnavailable: the reply could not be read.');
    return;
  }
  if (envelope['kind'] == 'refused') {
    final detail = envelope['detail'];
    out.writeln(
      detail is String && detail.isNotEmpty
          ? '$kFigureUnavailable: $detail'
          : '$kFigureUnavailable: the service refused this read.',
    );
    return;
  }
  final document = figureAt(envelope, ['projections', 0, 'document']);
  if (document is! Map<String, Object?>) {
    out.writeln('$kFigureUnavailable: there is nothing to show for this yet.');
    return;
  }
  render(out, document);
}

/// The words for an experiment's lifecycle.
String lifecycleLabel(Object? lifecycle) => switch (lifecycle) {
  'draft' => 'Draft',
  'active' => 'Running',
  'paused' => 'Paused',
  'concluded' => 'Finished',
  'archived' => 'Archived',
  _ => 'Unknown',
};

/// A plain figure, or `Not available`.
String plainFigure(Object? json, List<Object> path) =>
    '${figureAt(json, path) ?? kFigureUnavailable}';

/// A count as shown: grouped, `<5` when held beside its siblings, or
/// `Not available` when its parent is missing.
String countFigure(Object? json, List<Object> path) {
  final parent = figureAt(json, path.sublist(0, path.length - 1));
  final value = parent is Map<String, Object?> ? parent[path.last] : null;
  return switch (value) {
    final int count => groupedCount(count),
    _ when parent is Map<String, Object?> => heldCountText,
    _ => kFigureUnavailable,
  };
}

/// One summary sentence as plain text: its parts joined.
String? sentenceText(Object? sentence) {
  final parts = figureList(sentence, ['parts']);
  if (parts.isEmpty) return null;
  final text = StringBuffer();
  for (final part in parts) {
    final piece =
        figureAt(part, ['text']) ??
        figureAt(part, ['label']) ??
        figureAt(part, ['metric']);
    if (piece is! String) return null;
    text.write(piece);
  }
  return text.toString();
}
