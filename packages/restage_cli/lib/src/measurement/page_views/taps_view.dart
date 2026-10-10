import 'package:restage_cli/src/output/held_count.dart';

import 'page_view_support.dart';

const int _tapsPerVersion = 10;

/// Writes one published version's screens and taps.
void renderSurfaceTapsPage(StringSink out, Map<String, Object?> document) {
  final floor = figureAt(document, ['disclosureFloor']);
  final versions = figureList(document, ['versions']);
  out
    ..writeln('Surface: ${plainFigure(document, ['surfaceId'])}')
    ..writeln(
      'Reporting floor: ${floor == null ? kFigureUnavailable : '$floor users'}',
    )
    ..writeln('Versions: ${versions.length}');
  for (final version in versions) {
    out.writeln(
      'v${plainFigure(version, ['revisionOrdinal'])}  '
      '${countFigure(version, ['rootCounts', 'presented'])} views',
    );
    final taps = figureList(version, ['taps']).toList()
      ..sort((a, b) => _reach(b).compareTo(_reach(a)));
    for (final tap in taps.take(_tapsPerVersion)) {
      final reach = figureAt(tap, ['reach']);
      out.writeln(
        '  ${plainFigure(tap, ['eventName'])}  '
        '${reach is int ? groupedCount(reach) : heldCountText} taps',
      );
    }
  }
}

int _reach(Object? tap) {
  final reach = figureAt(tap, ['reach']);
  return reach is int ? reach : -1;
}
