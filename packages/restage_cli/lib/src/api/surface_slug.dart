import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/byte_data_wire.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/measurement/page_read.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart' show isValidSurfaceSlug;

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
  if (!isValidSurfaceSlug(value)) {
    final list = currentSelectorSyntax.command(
      const FollowUp('surface list', 'restage_list_surfaces'),
    );
    throw TargetSelectionException(
      "$value isn't a surface slug. Try the slug shown by $list, or the "
      'measurement id, which starts with $kMintedSurfaceIdPrefix',
    );
  }
  final matches = <String>{};
  String? cursor;
  do {
    final raw = await api.call('measurementRead', 'readSurfacePage', {
      ...pageTargetArgs(target),
      'queryBytes': encodeByteDataWire(surfaceSlugRosterQuery(value, cursor)),
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
    if (page is Map<String, Object?> && page['kind'] == 'refused') {
      final detail = page['detail'];
      throw TargetSelectionException(
        'Restage refused to look up the surface named $value'
        '${detail is String && detail.isNotEmpty ? ': $detail' : '.'} '
        'Try passing its measurement id, which starts with '
        '$kMintedSurfaceIdPrefix',
      );
    }
    if (page is Map<String, Object?> && page['state'] == 'cursorStale') {
      throw const TargetSelectionException(
        'The surface list changed while Restage was reading it. Try the '
        'command again.',
      );
    }
    if (page is! Map<String, Object?> || page['state'] != 'served') {
      throw TargetSelectionException(
        'Restage could not read the surface list to look up $value. Try the '
        'command again, or pass the measurement id, which starts with '
        '$kMintedSurfaceIdPrefix',
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

/// The roster query that looks up [slug], in the canonical bytes the
/// service decodes.
@visibleForTesting
List<int> surfaceSlugRosterQuery(String slug, String? cursor) =>
    CanonicalJsonCodec.encode({
      'kind': 'measurementRosterQueryV1',
      'search': slug,
      'sort': 'createdNewest',
      'archive': 'all',
      'lifecycle': null,
      'surfaceType': null,
      'surfaceId': null,
      'attentionOnly': false,
      'limit': _rosterPageLimit,
      'cursor': cursor,
    });
