import 'package:meta/meta.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;

/// One translated source expression and the RFW text it produced.
@immutable
final class DslEmissionSource {
  /// Creates a record of [dsl] emitted for the expression at [location].
  const DslEmissionSource({
    required this.dsl,
    required this.location,
    required this.construct,
  });

  /// The emitted RFW text.
  final String dsl;

  /// `path:line:column` of the source expression.
  final String location;

  /// A short quote of the source expression.
  final String construct;
}

/// Names the source expression whose emission holds the parse failure in
/// [text], with an excerpt of the text around it.
String dslParseFailureDetail(
  String text,
  fmt.ParserException error,
  Iterable<DslEmissionSource> sources,
) {
  final offset = _offsetOf(text, error.line, error.column);
  final excerpt = _excerpt(text, offset);
  DslEmissionSource? best;
  for (final source in sources) {
    if (source.dsl.isEmpty) continue;
    if (best != null && source.dsl.length >= best.dsl.length) continue;
    if (_covers(text, source.dsl, offset)) best = source;
  }
  final near = 'The emitted text near the error reads `$excerpt`.';
  if (best == null) return near;
  return 'It comes from `${best.construct}` at ${best.location}. $near';
}

bool _covers(String text, String fragment, int offset) {
  var start = text.indexOf(fragment);
  while (start >= 0 && start <= offset) {
    if (offset < start + fragment.length) return true;
    start = text.indexOf(fragment, start + 1);
  }
  return false;
}

int _offsetOf(String text, int line, int column) {
  var offset = 0;
  for (var current = 1; current < line; current++) {
    final next = text.indexOf('\n', offset);
    if (next < 0) return text.length;
    offset = next + 1;
  }
  final position = offset + column - 1;
  return position.clamp(0, text.length);
}

String _excerpt(String text, int offset) {
  const radius = 40;
  final start = (offset - radius).clamp(0, text.length);
  final end = (offset + radius).clamp(0, text.length);
  final body = text.substring(start, end).replaceAll('\n', ' ');
  return '${start > 0 ? '…' : ''}$body${end < text.length ? '…' : ''}';
}

/// A one-line quote of [source], cut to a readable length.
String quoteConstruct(String source) {
  final line = source.replaceAll(RegExp(r'\s+'), ' ');
  return line.length <= 80 ? line : '${line.substring(0, 77)}...';
}
