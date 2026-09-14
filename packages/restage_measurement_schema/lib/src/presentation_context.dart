import 'package:restage_measurement_schema/src/canonical.dart';

/// Observations already available when a surface was presented.
final class MeasurementPresentationContextV1 extends CanonicalValue {
  /// Creates a context with only the known presentation observations.
  MeasurementPresentationContextV1({
    this.presentationCountry,
    this.platform,
    this.appBuildOrdinal,
    this.deviceClass,
  }) {
    if (presentationCountry != null &&
        (presentationCountry!.length != 2 ||
            !RegExp(r'^[A-Z]{2}$').hasMatch(presentationCountry!))) {
      throw ArgumentError.value(presentationCountry, 'presentationCountry');
    }
    if (platform != null &&
        !const {'android', 'ios', 'linux', 'macos', 'windows', 'web'}
            .contains(platform)) {
      throw ArgumentError.value(platform, 'platform');
    }
    if (deviceClass != null &&
        !const {'phone', 'tablet', 'web'}.contains(deviceClass)) {
      throw ArgumentError.value(deviceClass, 'deviceClass');
    }
    if (appBuildOrdinal != null &&
        (appBuildOrdinal! < 0 ||
            appBuildOrdinal! > kMaximumPortableJsonInteger)) {
      throw ArgumentError.value(appBuildOrdinal, 'appBuildOrdinal');
    }
  }

  /// Decodes the closed presentation context object.
  factory MeasurementPresentationContextV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'appBuildOrdinal',
        'deviceClass',
        'kind',
        'platform',
        'presentationCountry',
        'schemaVersion',
      },
      requiredKeys: const {'kind', 'schemaVersion'},
      path: 'measurementPresentationContext',
    );
    validateCanonicalDocument(reader,
        expectedKind: 'measurementPresentationContext');
    return MeasurementPresentationContextV1(
      presentationCountry: reader.optionalString('presentationCountry'),
      platform: reader.optionalString('platform'),
      appBuildOrdinal: reader.optionalInteger('appBuildOrdinal'),
      deviceClass: reader.optionalString('deviceClass'),
    );
  }

  /// Decodes exact canonical bytes for a presentation context.
  factory MeasurementPresentationContextV1.fromCanonicalBytes(
          List<int> bytes) =>
      verifyCanonicalRoundTrip(
        MeasurementPresentationContextV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'measurementPresentationContext',
      );

  /// Uppercase two-letter presentation region, when known.
  final String? presentationCountry;

  /// Platform presenting the surface, when known.
  final String? platform;

  /// Portable non-negative application build ordinal, when known.
  final int? appBuildOrdinal;

  /// Presentation device class, when known.
  final String? deviceClass;

  @override
  Map<String, Object?> toJson() => {
        if (appBuildOrdinal != null) 'appBuildOrdinal': appBuildOrdinal,
        if (deviceClass != null) 'deviceClass': deviceClass,
        'kind': 'measurementPresentationContext',
        if (platform != null) 'platform': platform,
        if (presentationCountry != null)
          'presentationCountry': presentationCountry,
        'schemaVersion': kMeasurementSchemaVersion,
      };
}
