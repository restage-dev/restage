import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

const String _reservedMeasurementPrefix = '__restage_measurement_';
const String _measurementRouteV1Key = '__restage_measurement_route_v1';
const String _measurementRouteV1Prefix = 'mrv1.';

/// Private Measurement interpretation of a stripped RFW event payload.
///
/// This is intentionally an SDK-internal detail rather than a public event
/// contract. Every status still supplies [businessValue], so Measurement
/// rejection never interferes with valid business event delivery.
@internal
enum MeasurementEventCarrierStatus {
  /// No top-level reserved Measurement key was supplied.
  noCarrier,

  /// The exact V1 key was the sole reserved key and carried valid V1 syntax.
  exactV1Carrier,

  /// The exact V1 key was present but its value was not a valid V1 carrier.
  malformedOrWrongType,

  /// A reserved key was unknown, future, or collided with another reserved key.
  unknownFutureOrMultipleReservedKeys,
}

/// Sanitized business payload plus private Measurement carrier state.
///
/// The raw carrier is deliberately unavailable through the public `restage`
/// library. A later private resolver may consume [rawV1CarrierForResolution],
/// but no host callback, controller, demuxer, or diagnostic receives it.
@internal
final class MeasurementSanitizedEventValue {
  const MeasurementSanitizedEventValue._({
    required this.businessValue,
    required this.carrierStatus,
    this.rawV1CarrierForResolution,
  });

  /// The event payload safe for ordinary SDK business processing.
  final Object? businessValue;

  /// Private Measurement eligibility for this event occurrence.
  final MeasurementEventCarrierStatus carrierStatus;

  /// The raw exact V1 carrier, retained only for a future private resolver.
  final String? rawV1CarrierForResolution;
}

/// Removes Measurement's reserved top-level event namespace before host logic.
///
/// RFW maps are copied once into the ordinary string-keyed business shape
/// without mutating the source. Nested business values remain untouched.
@internal
abstract final class MeasurementEventSanitizer {
  /// Returns a business-safe event value and its private carrier classification.
  static MeasurementSanitizedEventValue sanitize(Object? rawValue) {
    if (rawValue is! Map) {
      return MeasurementSanitizedEventValue._(
        businessValue: rawValue,
        carrierStatus: MeasurementEventCarrierStatus.noCarrier,
      );
    }

    final businessArguments = <String, Object?>{};
    String? reservedKey;
    Object? reservedValue;
    var reservedKeyCount = 0;
    for (final entry in rawValue.entries) {
      final key = entry.key;
      if (key is String && key.startsWith(_reservedMeasurementPrefix)) {
        reservedKeyCount += 1;
        if (reservedKeyCount == 1) {
          reservedKey = key;
          reservedValue = entry.value;
        }
        continue;
      }
      businessArguments[key as String] = entry.value;
    }

    if (reservedKeyCount == 0) {
      return MeasurementSanitizedEventValue._(
        businessValue: businessArguments,
        carrierStatus: MeasurementEventCarrierStatus.noCarrier,
      );
    }
    if (reservedKeyCount != 1 || reservedKey != _measurementRouteV1Key) {
      return MeasurementSanitizedEventValue._(
        businessValue: businessArguments,
        carrierStatus:
            MeasurementEventCarrierStatus.unknownFutureOrMultipleReservedKeys,
      );
    }
    if (reservedValue is! String || !_isExactV1Carrier(reservedValue)) {
      return MeasurementSanitizedEventValue._(
        businessValue: businessArguments,
        carrierStatus: MeasurementEventCarrierStatus.malformedOrWrongType,
      );
    }
    return MeasurementSanitizedEventValue._(
      businessValue: businessArguments,
      carrierStatus: MeasurementEventCarrierStatus.exactV1Carrier,
      rawV1CarrierForResolution: reservedValue,
    );
  }

  static bool _isExactV1Carrier(String value) {
    if (!value.startsWith(_measurementRouteV1Prefix) || value.length > 256) {
      return false;
    }
    final edgeStart = _measurementRouteV1Prefix.length;
    final separator = value.indexOf('.', edgeStart);
    if (separator == -1 ||
        separator == edgeStart ||
        separator == value.length - 1 ||
        value.indexOf('.', separator + 1) != -1) {
      return false;
    }

    final encodedEdge = value.substring(edgeStart, separator);
    final encodedLocalToken = value.substring(separator + 1);
    if (encodedLocalToken.length != 32 ||
        !_isUnpaddedBase64Url(encodedEdge) ||
        !_isUnpaddedBase64Url(encodedLocalToken)) {
      return false;
    }

    try {
      final edgeBytes = base64Url.decode(encodedEdge);
      final edge = utf8.decode(edgeBytes);
      if (_unpaddedBase64Url(utf8.encode(edge)) != encodedEdge) return false;
      ArtifactOccurrenceEdgeToken(edge);

      final localTokenBytes = base64Url.decode(encodedLocalToken);
      return localTokenBytes.length == 24 &&
          _unpaddedBase64Url(localTokenBytes) == encodedLocalToken;
    } on Object {
      // Carrier parsing is strictly Measurement-private: malformed input merely
      // disables Measurement and must not escape into business event handling.
      return false;
    }
  }

  static bool _isUnpaddedBase64Url(String value) {
    if (value.isEmpty) return false;
    for (var index = 0; index < value.length; index += 1) {
      final code = value.codeUnitAt(index);
      final isAsciiLetter =
          (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
      final isDigit = code >= 0x30 && code <= 0x39;
      if (!isAsciiLetter && !isDigit && code != 0x2d && code != 0x5f) {
        return false;
      }
    }
    return true;
  }

  static String _unpaddedBase64Url(List<int> bytes) {
    final encoded = base64UrlEncode(bytes);
    final padding = encoded.indexOf('=');
    return padding == -1 ? encoded : encoded.substring(0, padding);
  }
}
