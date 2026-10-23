import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_slug.dart';
import 'package:restage_cli/src/measurement/page_read.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// The service answered with a reply addressed to another target, or not
/// shaped as a page reply.
@experimental
final class MeasurementPageMismatchException implements Exception {
  /// Creates the response-binding failure.
  const MeasurementPageMismatchException();

  @override
  String toString() =>
      'The service returned a reading that is not for this target.';
}

/// Reads dashboard pages through the measurement read route.
@experimental
class MeasurementPageApi {
  /// Binds the read to [_api].
  MeasurementPageApi(this._api);

  final RestageApi _api;

  /// Reads [read] at [request]'s target and returns the service's reply
  /// unchanged.
  ///
  /// Throws [MeasurementPageMismatchException] when the reply names another
  /// target.
  Future<String> read(PageRead read, PageRequest request) async {
    if (request.values['surfaceId'] case final String named) {
      final surfaceId = await resolveSurfaceId(_api, request.target, named);
      if (surfaceId != named) {
        request = PageRequest(
          target: request.target,
          values: {...request.values, 'surfaceId': surfaceId},
          window: request.window,
        );
      }
    }
    final reply = await _api.call(
      'measurementRead',
      read.method,
      read.wire(request),
    );
    if (reply is! String) throw const MeasurementPageMismatchException();
    final Object? envelope;
    try {
      envelope = jsonDecode(reply);
    } on FormatException {
      throw const MeasurementPageMismatchException();
    }
    final target = envelope is Map<String, Object?> ? envelope['target'] : null;
    try {
      if (target is! Map<String, Object?>) {
        throw const MeasurementPageMismatchException();
      }
      final named = TargetCoordinate.fromJson(target);
      final expected = request.target;
      final same = read.organizationWide
          ? named.organizationId == expected.organizationId &&
                named.namedEnvironmentId == expected.namedEnvironmentId &&
                named.runtimePlane == expected.runtimePlane
          : named == expected;
      if (!same) throw const MeasurementPageMismatchException();
    } on CanonicalFormatException {
      throw const MeasurementPageMismatchException();
    }
    return reply;
  }
}
