import 'dart:convert';

import 'package:restage_cli/src/api/byte_data_wire.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/measurement/page_read.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

const _rosterPageLimit = 100;
const _rosterWireLimit = 16 * 1024 * 1024;

/// The measurement surface id [value] names at [target].
///
/// A measurement id passes through. Anything else is a surface slug, looked
/// up in the target's surface roster, page by page until the roster ends.
Future<String> resolveSurfaceId(
  RestageApi api,
  TargetCoordinate target,
  String value,
) async {
  if (value.startsWith(kMintedSurfaceIdPrefix)) return value;
  final matches = <String>{};
  String? cursor;
  do {
    final raw = await api.call('measurementRead', 'readSurfacePage', {
      ...pageTargetArgs(target),
      'queryBytes': encodeByteDataWire(
        utf8.encode(
          jsonEncode({
            'kind': 'measurementRosterQueryV1',
            'search': value,
            'sort': 'createdNewest',
            'archive': 'all',
            'lifecycle': null,
            'surfaceType': null,
            'surfaceId': null,
            'attentionOnly': false,
            'limit': _rosterPageLimit,
            'cursor': cursor,
          }),
        ),
      ),
    });
    final page = jsonDecode(
      utf8.decode(
        decodeByteDataWire(
          raw,
          maximumBytes: _rosterWireLimit,
          malformed: (detail) =>
              TargetSelectionException('The surface list $detail.'),
        ),
      ),
    );
    if (page is! Map<String, Object?> || page['state'] != 'served') {
      throw const TargetSelectionException(
        'The surface list is not available right now.',
      );
    }
    for (final row in page['rows'] as List<Object?>? ?? const []) {
      if (row is Map<String, Object?> &&
          row['surfaceSlug'] == value &&
          row['surfaceId'] is String) {
        matches.add(row['surfaceId']! as String);
      }
    }
    cursor = page['nextCursor'] as String?;
  } while (cursor != null);
  return switch (matches.length) {
    1 => matches.single,
    0 => throw TargetSelectionException(
      'No surface named $value at this target.',
    ),
    _ => throw TargetSelectionException(
      'More than one surface is named $value. Pass its measurement id.',
    ),
  };
}
