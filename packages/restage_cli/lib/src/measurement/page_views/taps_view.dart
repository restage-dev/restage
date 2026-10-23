import 'package:restage_cli/src/output/held_count.dart';

import 'page_view_support.dart';

const int _tapsPerVersion = 10;

/// Writes one published version's screens and taps.
void renderSurfaceTapsPage(
  StringSink out,
  Map<String, Object?> document,
  int floor,
) {
  final versions = figureList(document, ['versions']);
  out.writeln('Surface: ${plainFigure(document, ['surfaceId'])}');
  // A floor of one holds nothing, so it is not worth a line.
  if (floor != 1) {
    out.writeln('Reporting floor: $floor users');
  }
  out.writeln('Versions: ${versions.length}');
  for (final version in versions) {
    out.writeln(
      'v${plainFigure(version, ['revisionOrdinal'])}  '
      '${countFigure(version, ['rootCounts', 'presented'], floor)} views',
    );
    final taps = figureList(version, ['taps']).toList()
      ..sort((a, b) => _reach(b).compareTo(_reach(a)));
    for (final tap in taps.take(_tapsPerVersion)) {
      final reach = figureAt(tap, ['reach']);
      out.writeln(
        '  ${plainFigure(tap, ['eventName'])}  '
        '${reach is int ? groupedCount(reach) : heldCountText(floor)} taps',
      );
    }
  }
}

int _reach(Object? tap) {
  final reach = figureAt(tap, ['reach']);
  return reach is int ? reach : -1;
}
