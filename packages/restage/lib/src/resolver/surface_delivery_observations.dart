import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show BuildContext, View, WidgetsBinding, WidgetsFlutterBinding;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'platform_app_build_stub.dart'
    if (dart.library.io) 'platform_app_build_io.dart' as app_build;
import 'platform_os_version_stub.dart'
    if (dart.library.io) 'platform_os_version_io.dart' as os_version;
import 'surface_assignment_built_ins.dart' show assignmentSdkApiLevel;

const _osVersionPlatforms = {'android', 'ios', 'macos'};

final _twoLetterSubtag = RegExp(r'^[a-zA-Z]{2}$');
final _buildOrdinal = RegExp(r'^(0|[1-9][0-9]*)$');

String? normalizePresentationCountry(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || !_twoLetterSubtag.hasMatch(trimmed)) return null;
  return trimmed.toUpperCase();
}

String? normalizePresentationLanguage(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || !_twoLetterSubtag.hasMatch(trimmed)) return null;
  return trimmed.toLowerCase();
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

/// The leading integer of a marketing version, so `17.4.1` reads as `17`.
int? parseMarketingMajorVersion(String? version) {
  final leading = version?.split('.').first;
  if (leading == null || !_buildOrdinal.hasMatch(leading)) return null;
  return normalizeOsVersionOrdinal(int.tryParse(leading));
}

int? normalizeOsVersionOrdinal(int? value) {
  if (value == null || value < 0 || value > kMaximumPortableJsonInteger) {
    return null;
  }
  return value;
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
    required this.presentationLanguage,
    required this.platform,
    required this.appBuildOrdinal,
    required this.deviceClass,
    required this.osVersion,
    required this.sdkApiLevel,
  });

  final String? presentationCountry;
  final String? presentationLanguage;
  final String? platform;
  final int? appBuildOrdinal;
  final String? deviceClass;
  final int? osVersion;
  final int sdkApiLevel;

  String? canonicalBuiltInsBase64() {
    if (platform == null) return null;
    final country = presentationCountry?.toLowerCase();
    // A build the device cannot supply is omitted; the rest still travels.
    return base64UrlEncode(CanonicalJsonCodec.encode({
      if (appBuildOrdinal != null) 'appBuildOrdinal': appBuildOrdinal,
      if (country != null) 'country': country,
      if (deviceClass != null) 'deviceClass': deviceClass,
      if (presentationLanguage != null) 'language': presentationLanguage,
      if (osVersion != null) 'osVersion': osVersion,
      'platform': platform,
      'sdkApiLevel': sdkApiLevel,
    })).replaceAll('=', '');
  }

  @override
  bool operator ==(Object other) =>
      other is SurfaceDeliveryObservations &&
      presentationCountry == other.presentationCountry &&
      presentationLanguage == other.presentationLanguage &&
      platform == other.platform &&
      appBuildOrdinal == other.appBuildOrdinal &&
      deviceClass == other.deviceClass &&
      osVersion == other.osVersion &&
      sdkApiLevel == other.sdkApiLevel;

  @override
  int get hashCode => Object.hash(
        presentationCountry,
        presentationLanguage,
        platform,
        appBuildOrdinal,
        deviceClass,
        osVersion,
        sdkApiLevel,
      );

  @override
  String toString() =>
      'SurfaceDeliveryObservations(presentationCountry: $presentationCountry, '
      'presentationLanguage: $presentationLanguage, platform: $platform, '
      'appBuildOrdinal: $appBuildOrdinal, deviceClass: $deviceClass, '
      'osVersion: $osVersion, sdkApiLevel: $sdkApiLevel)';
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
              ? await app_build.readPlatformAppBuildNumber()
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

/// The operating-system version a platform reports as one ordinal, from the
/// implementation the runtime selects. A runtime without `dart:io` has none.
Future<int?> readPlatformOsVersion(String platform) =>
    os_version.readPlatformOsVersion(platform);

Future<int?>? _osVersionRead;
bool _osVersionKnown = false;
int? _osVersionValue;

/// The operating-system version for this process.
///
/// It cannot change while the app runs, so a successful read is kept and every
/// later presentation reuses it. A read that fails is not kept: the platform may
/// be able to answer later, so the next presentation asks again.
Future<int?> _osVersion(
  String? platform,
  Future<int?> Function(String platform)? source,
) {
  // A platform with no documented ordinal answers absent without being asked.
  if (platform == null || !_osVersionPlatforms.contains(platform)) {
    return Future<int?>.value(null);
  }
  if (_osVersionKnown) return Future<int?>.value(_osVersionValue);
  return _osVersionRead ??= () async {
    try {
      final version = await (source ?? readPlatformOsVersion)(platform);
      _osVersionKnown = true;
      _osVersionValue = version;
      _osVersionRead = null;
      return version;
    } on Object {
      _osVersionRead = null;
      return null;
    }
  }();
}

/// Forgets the process-wide operating-system version so a test can read it again.
@visibleForTesting
void debugResetOsVersion() {
  _osVersionRead = null;
  _osVersionKnown = false;
  _osVersionValue = null;
}

/// Supplies the process-wide operating-system version a test should observe.
@visibleForTesting
void debugSetOsVersion(int? version) {
  _osVersionRead = null;
  _osVersionKnown = true;
  _osVersionValue = version;
}

Future<SurfaceDeliveryObservations> readSurfaceDeliveryObservations({
  double? shortestLogicalSide,
  bool? isWeb,
  TargetPlatform? targetPlatform,
  String? deviceRegion,
  String? deviceLanguage,
  Future<String?> Function()? buildNumberSource,
  Future<int?> Function(String platform)? osVersionSource,
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
  final language = normalizePresentationLanguage(
    deviceLanguage ??
        WidgetsBinding.instance.platformDispatcher.locale.languageCode,
  );
  final ordinal = await _appBuildOrdinal(buildNumberSource);
  final osVersion = await _osVersion(platform, osVersionSource);
  return SurfaceDeliveryObservations(
    presentationCountry: country,
    presentationLanguage: language,
    platform: platform,
    appBuildOrdinal: ordinal,
    deviceClass: classifyDeliveryDevice(
      isWeb: web,
      shortestLogicalSide: shortestLogicalSide,
    ),
    osVersion: osVersion,
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
