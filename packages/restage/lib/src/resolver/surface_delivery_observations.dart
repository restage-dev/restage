import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show BuildContext, View, WidgetsBinding, WidgetsFlutterBinding;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import '../delivery/render_deadline.dart';
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
// A read in flight that already outlasted one request's wait.
Future<void>? _timedOutFirstLaunchRead;
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
  Duration renderDeadline = RenderDeadline.defaultDuration,
}) {
  _installDateWait = renderDeadline ~/ 3;
  if (!initializeFirstLaunch && _firstLaunchRead != null) {
    // A read left in flight is dropped with the store it waits on.
    _firstLaunchGeneration += 1;
    _firstLaunchRead = null;
    _timedOutFirstLaunchRead = null;
    _firstLaunchStore = FirstLaunchStore();
  }
  _channel = normalizeDeliveryChannel(channel);
  _firstLaunchEnabled = initializeFirstLaunch;
  _scheduleFirstLaunchRead();
}

void _scheduleFirstLaunchRead() {
  if (!_firstLaunchEnabled) return;
  final nowUtc = _utcNow();
  final generation = _firstLaunchGeneration;
  scheduleMicrotask(() => unawaited(_readFirstLaunch(generation, nowUtc)));
}

Future<void>? _readFirstLaunch(int generation, DateTime nowUtc) {
  if (generation != _firstLaunchGeneration) return null;
  // A known origin whose write failed is read again, which retries the write.
  if (_firstLaunchUtc != null && !_firstLaunchStore.unconfirmed) return null;
  return _firstLaunchRead ??=
      _firstLaunchStore.readOrCreate(nowUtc).then((origin) {
    if (generation == _firstLaunchGeneration) {
      _firstLaunchUtc = origin ?? _firstLaunchUtc;
    }
  }).whenComplete(() {
    if (generation == _firstLaunchGeneration) _firstLaunchRead = null;
  });
}

/// The longest a request waits for the install date before reporting none:
/// a third of the render deadline, leaving the rest for the answer.
Duration _installDateWait = RenderDeadline.defaultDuration ~/ 3;

// A request reports the install age the device knows, waiting briefly for a
// read in flight; a slow store costs only the age.
Future<void> _installFactsSettled() {
  if (!_firstLaunchEnabled) return Future<void>.value();
  final read = _readFirstLaunch(_firstLaunchGeneration, _utcNow());
  if (read == null || identical(read, _timedOutFirstLaunchRead)) {
    return Future<void>.value();
  }
  return read.timeout(_installDateWait, onTimeout: () {
    _timedOutFirstLaunchRead = read;
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
  _timedOutFirstLaunchRead = null;
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

/// How many build or operating-system reads this process has asked the
/// platform for.
@visibleForTesting
int get debugPlatformReadsStarted => _platformReadsStarted;
int _platformReadsStarted = 0;

Future<T> _platformRead<T>(Future<T> Function() read) {
  _platformReadsStarted++;
  return read();
}

/// Replaces the platform build-number read in tests.
@visibleForTesting
Future<String?> Function()? debugAppBuildNumberSource;

Future<int?>? _appBuildOrdinalRead;
bool _appBuildOrdinalKnown = false;
int? _appBuildOrdinalValue;

/// The app build ordinal for this process.
///
/// It cannot change while the app runs, so a successful read is kept and every
/// later presentation reuses it. A read that fails is not kept: the platform may
/// be able to answer later, so the next presentation asks again.
Future<int?> _appBuildOrdinal(Future<String?> Function()? source) =>
    _appBuildOrdinalRead ??= () async {
      final read = source ?? debugAppBuildNumberSource;
      try {
        final ordinal = normalizeAppBuildOrdinal(
          read == null
              ? await _platformRead(app_build.readPlatformAppBuildNumber)
              : await read(),
        );
        _appBuildOrdinalKnown = true;
        return _appBuildOrdinalValue = ordinal;
      } on Object {
        _appBuildOrdinalRead = null;
        return null;
      }
    }();

Completer<void> _firstPresentation = Completer<void>();

/// Reads the same process build facts used by hosted delivery without
/// identity, once a presentation first reads its observations.
@internal
Future<({String? platform, int? buildOrdinal, String? appVersion})>
    readDeliveryBuildInputs() async {
  await _firstPresentation.future;
  return (
    platform: normalizeDeliveryPlatform(
        isWeb: kIsWeb, targetPlatform: defaultTargetPlatform),
    buildOrdinal: await _appBuildOrdinal(null),
    appVersion: await readDeliveryAppVersion(),
  );
}

Future<String?>? _appVersionRead;
bool _appVersionKnown = false;
String? _appVersionValue;

/// The display version when already read, without asking the platform.
@internal
String? knownDeliveryAppVersion() => _appVersionKnown ? _appVersionValue : null;

/// The display version for this process; a failed read is asked again later.
@internal
Future<String?> readDeliveryAppVersion() {
  if (_appVersionKnown) return Future<String?>.value(_appVersionValue);
  return _appVersionRead ??= () async {
    try {
      final version =
          (await _platformRead(app_build.readPlatformAppVersion))?.trim();
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

/// Forgets the process-wide build ordinal, version and first presentation, as
/// a new process would.
@visibleForTesting
void debugResetAppBuildOrdinal() {
  _firstPresentation = Completer<void>();
  _appBuildOrdinalRead = null;
  _appBuildOrdinalKnown = false;
  _appBuildOrdinalValue = null;
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
      final version = source == null
          ? await _platformRead(() => readPlatformOsVersion(platform))
          : await source(platform);
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
  // A deferred platform read answers what is already known.
  final deferred = Zone.current[_deferredFactsKey];
  final defer = deferred is Set<String> ? deferred : const <String>{};
  if (defer.isEmpty && !_firstPresentation.isCompleted) {
    _firstPresentation.complete();
  }
  // The build and OS reads run while the install date is awaited.
  final ordinalRead = defer.contains('appBuildOrdinal')
      ? Future<int?>.value(_appBuildOrdinalValue)
      : _appBuildOrdinal(buildNumberSource);
  final osVersionRead = defer.contains('osVersion')
      ? Future<int?>.value(_osVersionKnown ? _osVersionValue : null)
      : _osVersion(platform, osVersionSource);
  await _installFactsSettled();
  final (channel, installAge) = _installObservationStamp();
  final country = normalizePresentationCountry(
    deviceRegion ??
        WidgetsBinding.instance.platformDispatcher.locale.countryCode,
  );
  final language = normalizePresentationLanguage(
    deviceLanguage ??
        WidgetsBinding.instance.platformDispatcher.locale.languageCode,
  );
  final ordinal = await ordinalRead;
  final osVersion = await osVersionRead;
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

/// The observations known without asking the platform for anything.
@internal
Future<SurfaceDeliveryObservations> readKnownSurfaceDeliveryObservations() =>
    runZoned(readSurfaceDeliveryObservations,
        zoneValues: {_deferredFactsKey: _platformFacts});

const _platformFacts = {'appBuildOrdinal', 'osVersion'};

/// The facts this process holds without a platform read, and those it lacks.
@internal
(SurfaceDeliveryObservations, Set<String>)
    inMemorySurfaceDeliveryObservations() {
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final view = dispatcher.implicitView;
  final ratio = view?.devicePixelRatio ?? 0;
  final deviceClass = classifyDeliveryDevice(
      isWeb: kIsWeb,
      shortestLogicalSide:
          ratio > 0 ? view!.physicalSize.shortestSide / ratio : null);
  return (
    SurfaceDeliveryObservations(
      presentationCountry:
          normalizePresentationCountry(dispatcher.locale.countryCode),
      presentationLanguage:
          normalizePresentationLanguage(dispatcher.locale.languageCode),
      platform: normalizeDeliveryPlatform(
          isWeb: kIsWeb, targetPlatform: defaultTargetPlatform),
      appBuildOrdinal: _appBuildOrdinalValue,
      deviceClass: deviceClass,
      osVersion: _osVersionValue,
      sdkApiLevel: assignmentSdkApiLevel,
      channel: _channel,
    ),
    {
      if (!_appBuildOrdinalKnown) 'appBuildOrdinal',
      if (!_osVersionKnown) 'osVersion',
      if (deviceClass == null) 'deviceClass',
      'daysSinceInstall',
    },
  );
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

  /// The observations without waiting for the [defer]red platform reads, and
  /// which of those are not known yet. The full read starts behind it.
  Future<(SurfaceDeliveryObservations, Set<String>)> readKnown(
      Set<String> defer) async {
    final pending = {
      if (defer.contains('appBuildOrdinal') && !_appBuildOrdinalKnown)
        'appBuildOrdinal',
      if (defer.contains('osVersion') && !_osVersionKnown) 'osVersion',
    };
    if (_value != null || pending.isEmpty) {
      return (await read(), const <String>{});
    }
    unawaited(read().then<void>((_) {}, onError: (Object _) {}));
    final known =
        await runZoned(_read, zoneValues: {_deferredFactsKey: pending});
    return (known, pending);
  }

  Future<SurfaceDeliveryObservations> read() {
    if (_value == null) {
      // The first read already waits for the install date in flight.
      return _resolution ??= _read().then((observations) {
        _value = observations;
        _installStamp = (observations.channel, observations.daysSinceInstall);
        _resolution = null;
        return observations;
      });
    }
    return _installFactsSettled().then((_) {
      final stamp = _installObservationStamp();
      if (_installStamp != stamp) {
        _value = _value!._withInstallFacts(stamp);
        _installStamp = stamp;
      }
      return _value!;
    });
  }
}

const Object _observationsZoneKey = #restageSurfaceDeliveryObservations;
const Object _deferredFactsKey = #restageDeferredPlatformFacts;

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
