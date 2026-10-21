import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show BuildContext, View, WidgetsBinding, WidgetsFlutterBinding;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import '../runtime/first_launch_store.dart';
import 'platform_app_build_stub.dart'
    if (dart.library.io) 'platform_app_build_io.dart' as app_build;
import 'platform_os_version_stub.dart'
    if (dart.library.io) 'platform_os_version_io.dart' as os_version;
import 'surface_assignment_built_ins.dart' show assignmentSdkApiLevel;

const _osVersionPlatforms = {'android', 'ios', 'macos'};

final _twoLetterSubtag = RegExp(r'^[a-zA-Z]{2}$');
final _buildOrdinal = RegExp(r'^(0|[1-9][0-9]*)$');

String? _channel;
FirstLaunchStore _firstLaunchStore = FirstLaunchStore();
DateTime? _firstLaunchUtc;
Future<void>? _firstLaunchRead;
DateTime Function() _utcNow = () => DateTime.now().toUtc();
int _firstLaunchGeneration = 0;
bool _firstLaunchEnabled = false;

String? normalizeDeliveryChannel(String? value) {
  if (value == null || value.isEmpty || utf8.encode(value).length > 128) {
    return null;
  }
  try {
    CanonicalJsonCodec.encode(value);
  } on CanonicalFormatException {
    return null;
  }
  return value;
}

/// Configures optional build observations without waiting for local storage.
@internal
void configureSurfaceDeliveryObservations({
  String? channel,
  bool initializeFirstLaunch = true,
}) {
  _channel = normalizeDeliveryChannel(channel);
  _firstLaunchEnabled = initializeFirstLaunch;
  _scheduleFirstLaunchRead();
}

void _scheduleFirstLaunchRead() {
  if (!_firstLaunchEnabled) return;
  final nowUtc = _utcNow();
  final generation = _firstLaunchGeneration;
  scheduleMicrotask(() {
    if (generation != _firstLaunchGeneration ||
        _firstLaunchUtc != null ||
        _firstLaunchRead != null) {
      return;
    }
    _firstLaunchRead = _firstLaunchStore.readOrCreate(nowUtc).then((origin) {
      if (generation == _firstLaunchGeneration) _firstLaunchUtc = origin;
    }).whenComplete(() {
      if (generation == _firstLaunchGeneration) _firstLaunchRead = null;
    });
    unawaited(_firstLaunchRead);
  });
}

(String?, int?) _installObservationStamp() => (
      _channel,
      daysSinceInstall(nowUtc: _utcNow(), firstLaunchUtc: _firstLaunchUtc),
    );

/// Replaces optional storage and clock sources without deleting persisted data.
@visibleForTesting
void debugResetInstallObservations({
  FirstLaunchStore? store,
  DateTime Function()? nowUtc,
}) {
  _firstLaunchGeneration += 1;
  _firstLaunchEnabled = false;
  _channel = null;
  _firstLaunchUtc = null;
  _firstLaunchRead = null;
  _firstLaunchStore = store ?? FirstLaunchStore();
  _utcNow = nowUtc ?? () => DateTime.now().toUtc();
}

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
    this.channel,
    this.daysSinceInstall,
  });

  final String? presentationCountry;
  final String? presentationLanguage;
  final String? platform;
  final int? appBuildOrdinal;
  final String? deviceClass;
  final int? osVersion;
  final int sdkApiLevel;
  final String? channel;
  final int? daysSinceInstall;

  SurfaceDeliveryObservations _withInstallFacts((String?, int?) stamp) =>
      SurfaceDeliveryObservations(
        presentationCountry: presentationCountry,
        presentationLanguage: presentationLanguage,
        platform: platform,
        appBuildOrdinal: appBuildOrdinal,
        deviceClass: deviceClass,
        osVersion: osVersion,
        sdkApiLevel: sdkApiLevel,
        channel: stamp.$1,
        daysSinceInstall: stamp.$2,
      );

  String? canonicalBuiltInsBase64() {
    if (platform == null) return null;
    final country = presentationCountry?.toLowerCase();
    // A build the device cannot supply is omitted; the rest still travels.
    return base64UrlEncode(CanonicalJsonCodec.encode({
      if (appBuildOrdinal != null) 'appBuildOrdinal': appBuildOrdinal,
      if (country != null) 'country': country,
      if (normalizeDeliveryChannel(channel) case final channel?)
        'channel': channel,
      if (daysSinceInstall case final age?
          when age >= 0 && age <= kMaximumPortableJsonInteger)
        'daysSinceInstall': age,
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
      sdkApiLevel == other.sdkApiLevel &&
      channel == other.channel &&
      daysSinceInstall == other.daysSinceInstall;

  @override
  int get hashCode => Object.hash(
        presentationCountry,
        presentationLanguage,
        platform,
        appBuildOrdinal,
        deviceClass,
        osVersion,
        sdkApiLevel,
        channel,
        daysSinceInstall,
      );

  @override
  String toString() =>
      'SurfaceDeliveryObservations(presentationCountry: $presentationCountry, '
      'presentationLanguage: $presentationLanguage, platform: $platform, '
      'appBuildOrdinal: $appBuildOrdinal, deviceClass: $deviceClass, '
      'osVersion: $osVersion, sdkApiLevel: $sdkApiLevel, '
      'channel: $channel, daysSinceInstall: $daysSinceInstall)';
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

/// Reads the same process build facts used by hosted delivery without identity.
@internal
Future<({String? platform, int? buildOrdinal, String? appVersion})>
    readDeliveryBuildInputs() async => (
          platform: normalizeDeliveryPlatform(
              isWeb: kIsWeb, targetPlatform: defaultTargetPlatform),
          buildOrdinal: await _appBuildOrdinal(null),
          appVersion: await readDeliveryAppVersion(),
        );

Future<String?>? _appVersionRead;
bool _appVersionKnown = false;
String? _appVersionValue;

/// The display version for this process; a failed read is asked again later.
@internal
Future<String?> readDeliveryAppVersion() {
  if (_appVersionKnown) return Future<String?>.value(_appVersionValue);
  return _appVersionRead ??= () async {
    try {
      final version = (await app_build.readPlatformAppVersion())?.trim();
      _appVersionValue = version == null ||
              version.isEmpty ||
              version.length > 64 ||
              version.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)
          ? null
          : version;
      _appVersionKnown = true;
      _appVersionRead = null;
      return _appVersionValue;
    } on Object {
      _appVersionRead = null;
      return null;
    }
  }();
}

/// Forgets the process-wide build ordinal and version so a test reads again.
@visibleForTesting
void debugResetAppBuildOrdinal() {
  _appBuildOrdinalRead = null;
  _appVersionRead = null;
  _appVersionKnown = false;
  _appVersionValue = null;
}

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
  _scheduleFirstLaunchRead();
  final (channel, installAge) = _installObservationStamp();
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
    channel: channel,
    daysSinceInstall: installAge,
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

/// Captures presentation facts once and refreshes install facts on request reuse.
@internal
final class SurfaceDeliveryObservationCell {
  SurfaceDeliveryObservationCell(this._read);

  final Future<SurfaceDeliveryObservations> Function() _read;
  Future<SurfaceDeliveryObservations>? _resolution;
  SurfaceDeliveryObservations? _value;
  (String?, int?)? _installStamp;

  /// The observations already read for this presentation, if any.
  SurfaceDeliveryObservations? get valueIfRead => _value;

  /// Current request inputs without changing an earlier immutable observation.
  String? get currentBuiltInsBase64 {
    final existing = _value;
    if (existing == null) return null;
    return existing
        ._withInstallFacts(_installObservationStamp())
        .canonicalBuiltInsBase64();
  }

  Future<SurfaceDeliveryObservations> read() {
    _scheduleFirstLaunchRead();
    final stamp = _installObservationStamp();
    final existing = _value;
    if (existing != null) {
      if (_installStamp != stamp) {
        _value = existing._withInstallFacts(stamp);
        _installStamp = stamp;
      }
      return Future<SurfaceDeliveryObservations>.value(_value);
    }
    return _resolution ??= _read().then((observations) {
      _value = observations;
      _installStamp = stamp;
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
