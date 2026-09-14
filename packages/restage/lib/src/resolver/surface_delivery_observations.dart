import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show BuildContext, View, WidgetsBinding, WidgetsFlutterBinding;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'surface_assignment_built_ins.dart' show assignmentSdkApiLevel;

final _twoLetterRegion = RegExp(r'^[a-zA-Z]{2}$');
final _buildOrdinal = RegExp(r'^(0|[1-9][0-9]*)$');

String? normalizePresentationCountry(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || !_twoLetterRegion.hasMatch(trimmed)) return null;
  return trimmed.toUpperCase();
}

String? classifyDeliveryDevice({
  required bool isWeb,
  required double? shortestLogicalSide,
}) {
  if (isWeb) return 'web';
  if (shortestLogicalSide == null ||
      !shortestLogicalSide.isFinite ||
      shortestLogicalSide <= 0) {
    return null;
  }
  return shortestLogicalSide < 600 ? 'phone' : 'tablet';
}

int? normalizeAppBuildOrdinal(String? buildNumber) {
  if (buildNumber == null || !_buildOrdinal.hasMatch(buildNumber)) return null;
  final ordinal = int.tryParse(buildNumber);
  if (ordinal == null || ordinal > kMaximumPortableJsonInteger) return null;
  return ordinal;
}

String? normalizeDeliveryPlatform({
  required bool isWeb,
  required TargetPlatform targetPlatform,
}) =>
    isWeb
        ? 'web'
        : switch (targetPlatform) {
            TargetPlatform.android => 'android',
            TargetPlatform.iOS => 'ios',
            TargetPlatform.linux => 'linux',
            TargetPlatform.macOS => 'macos',
            TargetPlatform.windows => 'windows',
            TargetPlatform.fuchsia => null,
          };

@immutable
final class SurfaceDeliveryObservations {
  const SurfaceDeliveryObservations({
    required this.presentationCountry,
    required this.platform,
    required this.appBuildOrdinal,
    required this.deviceClass,
    required this.sdkApiLevel,
  });

  final String? presentationCountry;
  final String? platform;
  final int? appBuildOrdinal;
  final String? deviceClass;
  final int sdkApiLevel;

  String? canonicalBuiltInsBase64() {
    if (platform == null) return null;
    final country = presentationCountry?.toLowerCase();
    // A build the device cannot supply is omitted; the rest still travels.
    return base64UrlEncode(CanonicalJsonCodec.encode({
      if (appBuildOrdinal != null) 'appBuildOrdinal': appBuildOrdinal,
      if (country != null) 'country': country,
      if (deviceClass != null) 'deviceClass': deviceClass,
      'platform': platform,
      'sdkApiLevel': sdkApiLevel,
    })).replaceAll('=', '');
  }

  @override
  bool operator ==(Object other) =>
      other is SurfaceDeliveryObservations &&
      presentationCountry == other.presentationCountry &&
      platform == other.platform &&
      appBuildOrdinal == other.appBuildOrdinal &&
      deviceClass == other.deviceClass &&
      sdkApiLevel == other.sdkApiLevel;

  @override
  int get hashCode => Object.hash(
        presentationCountry,
        platform,
        appBuildOrdinal,
        deviceClass,
        sdkApiLevel,
      );

  @override
  String toString() =>
      'SurfaceDeliveryObservations(presentationCountry: $presentationCountry, '
      'platform: $platform, appBuildOrdinal: $appBuildOrdinal, '
      'deviceClass: $deviceClass, sdkApiLevel: $sdkApiLevel)';
}

Future<int?>? _appBuildOrdinalRead;

/// The app build ordinal for this process.
///
/// It cannot change while the app runs, so a successful read is kept and every
/// later presentation reuses it. A read that fails is not kept: the platform may
/// be able to answer later, so the next presentation asks again.
Future<int?> _appBuildOrdinal(Future<String?> Function()? source) =>
    _appBuildOrdinalRead ??= () async {
      try {
        return normalizeAppBuildOrdinal(
          source == null
              ? (await PackageInfo.fromPlatform()).buildNumber
              : await source(),
        );
      } on Object {
        _appBuildOrdinalRead = null;
        return null;
      }
    }();

/// Forgets the process-wide build ordinal so a test can read it again.
@visibleForTesting
void debugResetAppBuildOrdinal() => _appBuildOrdinalRead = null;

Future<SurfaceDeliveryObservations> readSurfaceDeliveryObservations({
  double? shortestLogicalSide,
  bool? isWeb,
  TargetPlatform? targetPlatform,
  String? deviceRegion,
  Future<String?> Function()? buildNumberSource,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final web = isWeb ?? kIsWeb;
  final platform = normalizeDeliveryPlatform(
    isWeb: web,
    targetPlatform: targetPlatform ?? defaultTargetPlatform,
  );
  final country = normalizePresentationCountry(
    deviceRegion ??
        WidgetsBinding.instance.platformDispatcher.locale.countryCode,
  );
  final ordinal = await _appBuildOrdinal(buildNumberSource);
  return SurfaceDeliveryObservations(
    presentationCountry: country,
    platform: platform,
    appBuildOrdinal: ordinal,
    deviceClass: classifyDeliveryDevice(
      isWeb: web,
      shortestLogicalSide: shortestLogicalSide,
    ),
    sdkApiLevel: assignmentSdkApiLevel,
  );
}

/// The shortest logical side of the view presenting [context], when there is one.
double? requestingViewShortestLogicalSide(BuildContext context) {
  final view = View.maybeOf(context) ??
      WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null) return null;
  final ratio = view.devicePixelRatio;
  if (ratio <= 0) return null;
  final side = view.physicalSize.shortestSide / ratio;
  return side.isFinite && side > 0 ? side : null;
}

/// Reads one presentation's observations at most once, on first use.
@internal
final class SurfaceDeliveryObservationCell {
  SurfaceDeliveryObservationCell(this._read);

  final Future<SurfaceDeliveryObservations> Function() _read;
  Future<SurfaceDeliveryObservations>? _resolution;
  SurfaceDeliveryObservations? _value;

  /// The observations already read for this presentation, if any.
  SurfaceDeliveryObservations? get valueIfRead => _value;

  Future<SurfaceDeliveryObservations> read() {
    final existing = _value;
    if (existing != null) {
      return Future<SurfaceDeliveryObservations>.value(existing);
    }
    return _resolution ??= _read().then((observations) {
      _value = observations;
      _resolution = null;
      return observations;
    });
  }
}

const Object _observationsZoneKey = #restageSurfaceDeliveryObservations;

/// Installs [cell] for the duration of one presentation's resolve.
T withSurfaceDeliveryObservations<T>({
  required SurfaceDeliveryObservationCell cell,
  required T Function() resolve,
}) =>
    runZoned(
      resolve,
      zoneValues: <Object?, Object?>{_observationsZoneKey: cell},
    );

/// The observation cell installed for the current presentation, if any.
@internal
SurfaceDeliveryObservationCell? currentSurfaceDeliveryObservationCell() {
  final value = Zone.current[_observationsZoneKey];
  return value is SurfaceDeliveryObservationCell ? value : null;
}
