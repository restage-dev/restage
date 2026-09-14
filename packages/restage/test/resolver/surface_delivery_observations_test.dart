import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage/src/resolver/surface_assignment_built_ins.dart';
import 'package:restage/src/resolver/platform_app_build_stub.dart'
    as build_stub;
import 'package:restage/src/resolver/platform_os_version_stub.dart' as stub;
import 'package:restage/src/resolver/surface_delivery_observations.dart';

SurfaceDeliveryObservations snapshot({
  String? country = 'SE',
  String? language,
  String? platform = 'ios',
  int? build = 42,
  String? device = 'phone',
  int? osVersion,
  int level = assignmentSdkApiLevel,
}) =>
    SurfaceDeliveryObservations(
      presentationCountry: country,
      presentationLanguage: language,
      platform: platform,
      appBuildOrdinal: build,
      deviceClass: device,
      osVersion: osVersion,
      sdkApiLevel: level,
    );

const _deviceInfoChannel =
    MethodChannel('dev.fluttercommunity.plus/device_info');

void _mockDeviceInfo(Map<String, Object?> reply) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    _deviceInfoChannel,
    (call) async => call.method == 'getDeviceInfo' ? reply : null,
  );
  addTearDown(
    () => messenger.setMockMethodCallHandler(_deviceInfoChannel, null),
  );
}

Map<String, Object?> _iosReply(String systemVersion) => <String, Object?>{
      'name': 'iPhone',
      'systemName': 'iOS',
      'systemVersion': systemVersion,
      'model': 'iPhone',
      'modelName': 'iPhone 15',
      'localizedModel': 'iPhone',
      'identifierForVendor': '00000000-0000-0000-0000-000000000000',
      'isPhysicalDevice': true,
      'physicalRamSize': 4096,
      'availableRamSize': 2048,
      'isiOSAppOnMac': false,
      'isiOSAppOnVision': false,
      'freeDiskSize': 1024,
      'totalDiskSize': 2048,
      'utsname': <String, Object?>{
        'sysname': 'Darwin',
        'nodename': 'iPhone',
        'release': '23.4.0',
        'version': 'Darwin Kernel',
        'machine': 'iPhone16,1',
      },
    };

Map<String, Object?> _androidReply(int sdkInt) => <String, Object?>{
      'version': <String, Object?>{
        'baseOS': '',
        'codename': 'REL',
        'incremental': '1',
        'previewSdkInt': 0,
        'release': '14',
        'sdkInt': sdkInt,
        'securityPatch': '2026-01-01',
      },
      'board': 'board',
      'bootloader': 'bootloader',
      'brand': 'brand',
      'device': 'device',
      'display': 'display',
      'fingerprint': 'fingerprint',
      'hardware': 'hardware',
      'host': 'host',
      'id': 'id',
      'manufacturer': 'manufacturer',
      'model': 'model',
      'product': 'product',
      'name': 'name',
      'supported32BitAbis': <String>[],
      'supported64BitAbis': <String>['arm64-v8a'],
      'supportedAbis': <String>['arm64-v8a'],
      'tags': 'tags',
      'type': 'user',
      'isPhysicalDevice': true,
      'freeDiskSize': 1024,
      'totalDiskSize': 2048,
      'systemFeatures': <String>[],
      'isLowRamDevice': false,
      'physicalRamSize': 4096,
      'availableRamSize': 2048,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(debugResetAppBuildOrdinal);
  setUp(debugResetOsVersion);
  tearDown(debugResetAppBuildOrdinal);
  tearDown(debugResetOsVersion);

  group('country normalization', () {
    for (final value in ['se', 'SE', ' se ']) {
      test('normalizes "$value"', () {
        expect(normalizePresentationCountry(value), 'SE');
      });
    }
    for (final value in [null, '', 'S', 'SWE', 'S1', '12', '   ', 'İS']) {
      test('rejects "$value"', () {
        expect(normalizePresentationCountry(value), isNull);
      });
    }
  });

  group('language normalization', () {
    for (final value in ['sv', 'SV', ' sv ', 'Sv']) {
      test('normalizes "$value"', () {
        expect(normalizePresentationLanguage(value), 'sv');
      });
    }
    for (final value in [
      null,
      '',
      's',
      'swe',
      'fil',
      's1',
      '12',
      '   ',
      'İs'
    ]) {
      test('rejects "$value"', () {
        expect(normalizePresentationLanguage(value), isNull);
      });
    }
  });

  group('operating-system version', () {
    for (final entry
        in {'17.4.1': 17, '17': 17, '0.1': 0, '26.0': 26}.entries) {
      test('reads ${entry.key} as ${entry.value}', () {
        expect(parseMarketingMajorVersion(entry.key), entry.value);
      });
    }
    for (final value in [null, '', '.', 'x.1', '-1.0', '17a.1', ' 17.4.1']) {
      test('rejects "$value"', () {
        expect(parseMarketingMajorVersion(value), isNull);
      });
    }
    test('keeps a reported API level', () {
      expect(normalizeOsVersionOrdinal(34), 34);
      expect(normalizeOsVersionOrdinal(0), 0);
    });
    for (final value in [null, -1, kMaximumPortableJsonInteger + 1]) {
      test('rejects the ordinal $value', () {
        expect(normalizeOsVersionOrdinal(value), isNull);
      });
    }
  });

  group('device class', () {
    test('599 is a phone', () {
      expect(classifyDeliveryDevice(isWeb: false, shortestLogicalSide: 599),
          'phone');
    });
    test('600 is a tablet', () {
      expect(classifyDeliveryDevice(isWeb: false, shortestLogicalSide: 600),
          'tablet');
    });
    for (final side in [
      null,
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity
    ]) {
      test('non-web rejects side $side', () {
        expect(classifyDeliveryDevice(isWeb: false, shortestLogicalSide: side),
            isNull);
      });
    }
    for (final side in [399.0, null, 0.0, -1.0, double.nan, double.infinity]) {
      test('web takes precedence over side $side', () {
        expect(classifyDeliveryDevice(isWeb: true, shortestLogicalSide: side),
            'web');
      });
    }
  });

  group('build ordinal', () {
    for (final entry
        in {'0': 0, '42': 42, '9007199254740991': 9007199254740991}.entries) {
      test('accepts ${entry.key}', () {
        expect(normalizeAppBuildOrdinal(entry.key), entry.value);
      });
    }
    for (final value in [
      null,
      '',
      '007',
      'release',
      '-1',
      '9007199254740992',
      '999999999999999999999999',
      ' 42'
    ]) {
      test('rejects "$value"', () {
        expect(normalizeAppBuildOrdinal(value), isNull);
      });
    }
  });

  group('platform normalization', () {
    for (final entry in {
      TargetPlatform.android: 'android',
      TargetPlatform.iOS: 'ios',
      TargetPlatform.linux: 'linux',
      TargetPlatform.macOS: 'macos',
      TargetPlatform.windows: 'windows',
      TargetPlatform.fuchsia: null,
    }.entries) {
      test('maps ${entry.key}', () {
        expect(
            normalizeDeliveryPlatform(isWeb: false, targetPlatform: entry.key),
            entry.value);
      });
      test('web takes precedence over ${entry.key}', () {
        expect(
            normalizeDeliveryPlatform(isWeb: true, targetPlatform: entry.key),
            'web');
      });
    }
  });

  test('unknown build preserves platform and country', () {
    final value = snapshot(build: null);
    expect(value.platform, 'ios');
    expect(value.presentationCountry, 'SE');
  });

  test('unknown country preserves platform and build', () {
    final value = snapshot(country: null);
    expect(value.platform, 'ios');
    expect(value.appBuildOrdinal, 42);
  });

  test('country and device class change carrier bytes and document size', () {
    final full = snapshot().canonicalBuiltInsBase64()!;
    final absent =
        snapshot(country: null, device: null).canonicalBuiltInsBase64()!;
    expect(full, isNot(absent));
    expect(snapshot(country: null).canonicalBuiltInsBase64(), isNot(full));
    expect(snapshot(device: null).canonicalBuiltInsBase64(), isNot(full));
    final fullDocument =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(full))))
            as Map;
    final absentDocument =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(absent))))
            as Map;
    expect(fullDocument, hasLength(5));
    expect(absentDocument.length, lessThan(fullDocument.length));
    expect(absentDocument.containsKey('country'), isFalse);
    expect(absentDocument.containsKey('deviceClass'), isFalse);
  });

  test('carrier retains the canonical five-field encoding', () {
    expect(snapshot().canonicalBuiltInsBase64(),
        'eyJhcHBCdWlsZE9yZGluYWwiOjQyLCJjb3VudHJ5Ijoic2UiLCJkZXZpY2VDbGFzcyI6InBob25lIiwicGxhdGZvcm0iOiJpb3MiLCJzZGtBcGlMZXZlbCI6M30');
  });

  test('absent country and device class retain the three-field encoding', () {
    expect(snapshot(country: null, device: null).canonicalBuiltInsBase64(),
        'eyJhcHBCdWlsZE9yZGluYWwiOjQyLCJwbGF0Zm9ybSI6ImlvcyIsInNka0FwaUxldmVsIjozfQ');
  });

  test('carrier folds country without changing the observation', () {
    final value = snapshot(country: 'SE');
    final document = jsonDecode(utf8.decode(base64Url
        .decode(base64Url.normalize(value.canonicalBuiltInsBase64()!)))) as Map;
    expect(document['country'], 'se');
    expect(value.presentationCountry, 'SE');
  });

  test('a known language adds one key and keeps the rest', () {
    final carrier = snapshot(language: 'sv').canonicalBuiltInsBase64()!;
    final document =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(carrier))))
            as Map;
    expect(document['language'], 'sv');
    expect(document, hasLength(6));
    expect(document['country'], 'se');
    expect(document['deviceClass'], 'phone');
    expect(document['platform'], 'ios');
    expect(document['appBuildOrdinal'], 42);
    expect(document['sdkApiLevel'], assignmentSdkApiLevel);
  });

  test('an absent language leaves the carrier byte-identical', () {
    expect(snapshot(language: null).canonicalBuiltInsBase64(),
        snapshot().canonicalBuiltInsBase64());
    expect(snapshot(language: 'sv').canonicalBuiltInsBase64(),
        isNot(snapshot().canonicalBuiltInsBase64()));
  });

  test('an unknown country still carries a known language', () {
    final carrier =
        snapshot(country: null, language: 'sv').canonicalBuiltInsBase64()!;
    final document =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(carrier))))
            as Map;
    expect(document.containsKey('country'), isFalse);
    expect(document['language'], 'sv');
  });

  test('a known operating-system version adds one key', () {
    final carrier = snapshot(osVersion: 17).canonicalBuiltInsBase64()!;
    final document =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(carrier))))
            as Map;
    expect(document['osVersion'], 17);
    expect(document, hasLength(6));
  });

  test('a carrier with neither new observation is byte-identical', () {
    expect(snapshot(language: null, osVersion: null).canonicalBuiltInsBase64(),
        'eyJhcHBCdWlsZE9yZGluYWwiOjQyLCJjb3VudHJ5Ijoic2UiLCJkZXZpY2VDbGFzcyI6InBob25lIiwicGxhdGZvcm0iOiJpb3MiLCJzZGtBcGlMZXZlbCI6M30');
  });

  test('both new observations travel together', () {
    final carrier =
        snapshot(language: 'sv', osVersion: 34).canonicalBuiltInsBase64()!;
    final document =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(carrier))))
            as Map;
    expect(document, hasLength(7));
    expect(document['language'], 'sv');
    expect(document['osVersion'], 34);
  });

  test('unknown platform omits carrier', () {
    expect(snapshot(platform: null).canonicalBuiltInsBase64(), isNull);
  });

  test('unknown build keeps the carrier and omits only the build', () {
    final carrier = snapshot(build: null).canonicalBuiltInsBase64()!;
    final document =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(carrier))))
            as Map;
    expect(document.containsKey('appBuildOrdinal'), isFalse);
    expect(document['platform'], snapshot().platform);
    expect(document['country'], 'se');
    expect(document['deviceClass'], snapshot().deviceClass);
    expect(document['sdkApiLevel'], snapshot().sdkApiLevel);
  });

  test('identical fields have value equality', () {
    expect(snapshot(), snapshot());
    expect(snapshot().hashCode, snapshot().hashCode);
  });

  for (final entry in {
    'country': snapshot(country: 'US'),
    'platform': snapshot(platform: 'android'),
    'build': snapshot(build: 43),
    'device': snapshot(device: 'tablet'),
    'language': snapshot(language: 'sv'),
    'osVersion': snapshot(osVersion: 17),
    'level': snapshot(level: 2),
  }.entries) {
    test('changing ${entry.key} changes equality', () {
      expect(snapshot(), isNot(entry.value));
    });
  }

  test('string representation lists all fields', () {
    expect(
        snapshot().toString(),
        'SurfaceDeliveryObservations(presentationCountry: SE, '
        'presentationLanguage: null, platform: ios, appBuildOrdinal: 42, '
        'deviceClass: phone, osVersion: null, sdkApiLevel: 3)');
  });

  test('a thrown build source preserves other observations', () async {
    final value = await readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.iOS,
      deviceRegion: 'se',
      shortestLogicalSide: 599,
      buildNumberSource: () async => throw StateError('Build unavailable'),
    );
    expect(value.appBuildOrdinal, isNull);
    expect(value.platform, 'ios');
    expect(value.presentationCountry, 'SE');
    expect(value.deviceClass, 'phone');
    expect(value.sdkApiLevel, assignmentSdkApiLevel);
  });

  test('a reading takes its language from the device locale', () async {
    final value = await readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.iOS,
      deviceRegion: 'se',
      deviceLanguage: 'SV',
      buildNumberSource: () async => '42',
    );
    expect(value.presentationLanguage, 'sv');
    expect(value.presentationCountry, 'SE');
  });

  test('an unreadable language preserves the other observations', () async {
    final value = await readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.android,
      deviceRegion: 'se',
      deviceLanguage: 'fil',
      shortestLogicalSide: 599,
      buildNumberSource: () async => '42',
    );
    expect(value.presentationLanguage, isNull);
    expect(value.presentationCountry, 'SE');
    expect(value.platform, 'android');
    expect(value.appBuildOrdinal, 42);
    expect(value.deviceClass, 'phone');
  });

  test('a reading takes the operating-system version from the platform',
      () async {
    final value = await readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.iOS,
      buildNumberSource: () async => '42',
      osVersionSource: (platform) async => platform == 'ios' ? 17 : null,
    );
    expect(value.osVersion, 17);
    expect(value.platform, 'ios');
  });

  for (final entry in {
    TargetPlatform.linux: 'linux',
    TargetPlatform.windows: 'windows',
  }.entries) {
    test('${entry.value} reports no version and is never asked', () async {
      var asked = 0;
      final value = await readSurfaceDeliveryObservations(
        isWeb: false,
        targetPlatform: entry.key,
        buildNumberSource: () async => '42',
        osVersionSource: (platform) async {
          asked += 1;
          return 34;
        },
      );
      expect(value.osVersion, isNull);
      expect(asked, 0);
      expect(value.platform, entry.value);
      expect(value.appBuildOrdinal, 42);
    });
  }

  test('the web reports no version and is never asked', () async {
    var asked = 0;
    final value = await readSurfaceDeliveryObservations(
      isWeb: true,
      targetPlatform: TargetPlatform.android,
      buildNumberSource: () async => '42',
      osVersionSource: (platform) async {
        asked += 1;
        return 34;
      },
    );
    expect(value.osVersion, isNull);
    expect(asked, 0);
    expect(value.platform, 'web');
    expect(value.deviceClass, 'web');
  });

  test('two presentations read the operating-system version once', () async {
    var reads = 0;
    Future<int?> source(String platform) async {
      reads += 1;
      return 34;
    }

    final first = await readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.android,
      buildNumberSource: () async => '42',
      osVersionSource: source,
    );
    final second = await readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.android,
      buildNumberSource: () async => '42',
      osVersionSource: source,
    );

    expect(reads, 1);
    expect(first.osVersion, 34);
    expect(second.osVersion, 34);
  });

  test('a version that fails to read is asked for again next presentation',
      () async {
    var reads = 0;
    Future<int?> source(String platform) async {
      reads += 1;
      if (reads == 1) throw StateError('Version unavailable');
      return 34;
    }

    final first = await readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.android,
      deviceRegion: 'se',
      buildNumberSource: () async => '42',
      osVersionSource: source,
    );
    final second = await readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.android,
      buildNumberSource: () async => '42',
      osVersionSource: source,
    );

    expect(reads, 2);
    expect(first.osVersion, isNull);
    expect(second.osVersion, 34);
    expect(first.presentationCountry, 'SE');
    expect(first.appBuildOrdinal, 42);
  });

  test('a reading completes once a pending version read answers', () async {
    final pending = Completer<int?>();
    var settled = false;
    final reading = readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.android,
      deviceRegion: 'se',
      buildNumberSource: () async => '42',
      osVersionSource: (platform) => pending.future,
    ).then((value) {
      settled = true;
      return value;
    });
    await pumpEventQueue();
    expect(settled, isFalse);

    pending.complete(34);
    final value = await reading;

    expect(value.osVersion, 34);
    expect(value.presentationCountry, 'SE');
  });

  test('an iOS device reports its marketing major version', () async {
    _mockDeviceInfo(_iosReply('17.4.1'));
    expect(await readPlatformOsVersion('ios'), 17);
  });

  test('an Android device reports its API level', () async {
    _mockDeviceInfo(_androidReply(34));
    expect(await readPlatformOsVersion('android'), 34);
  });

  test('an unreadable iOS version leaves the version absent', () async {
    _mockDeviceInfo(_iosReply('unknown'));
    expect(await readPlatformOsVersion('ios'), isNull);
  });

  test('a runtime without dart:io reports no build number', () async {
    // The stub the web build selects, exercised directly.
    expect(await build_stub.readPlatformAppBuildNumber(), isNull);
    expect(
        normalizeAppBuildOrdinal(await build_stub.readPlatformAppBuildNumber()),
        isNull);
  });

  test('a build the platform cannot report omits only that key', () {
    final carrier = snapshot(build: null, osVersion: 34, language: 'sv')
        .canonicalBuiltInsBase64()!;
    final document =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(carrier))))
            as Map;
    expect(document.containsKey('appBuildOrdinal'), isFalse);
    expect(document['country'], 'se');
    expect(document['deviceClass'], 'phone');
    expect(document['language'], 'sv');
    expect(document['osVersion'], 34);
    expect(document['platform'], 'ios');
  });

  test('a runtime without dart:io reports no version', () async {
    // The stub the web build selects, exercised directly.
    expect(await stub.readPlatformOsVersion('android'), isNull);
    expect(await stub.readPlatformOsVersion('ios'), isNull);
    expect(await stub.readPlatformOsVersion('macos'), isNull);
  });

  test('an invalid country preserves a reported build and platform', () async {
    final value = await readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.android,
      deviceRegion: 'XYZ',
      buildNumberSource: () async => '42',
    );
    expect(value.presentationCountry, isNull);
    expect(value.platform, 'android');
    expect(value.appBuildOrdinal, 42);
  });

  test('two presentations read the build once', () async {
    var reads = 0;
    Future<String?> source() async {
      reads += 1;
      return '42';
    }

    final first = await readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.iOS,
      deviceRegion: 'se',
      buildNumberSource: source,
    );
    final second = await readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.iOS,
      deviceRegion: 'us',
      buildNumberSource: source,
    );

    expect(reads, 1);
    expect(first.appBuildOrdinal, 42);
    expect(second.appBuildOrdinal, 42);
    expect(first.presentationCountry, 'SE');
    expect(second.presentationCountry, 'US');
  });

  test('a build that fails to read is asked for again next presentation',
      () async {
    var reads = 0;
    Future<String?> source() async {
      reads += 1;
      if (reads == 1) throw StateError('Build unavailable');
      return '412';
    }

    final first = await readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.iOS,
      buildNumberSource: source,
    );
    final second = await readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.iOS,
      buildNumberSource: source,
    );

    expect(reads, 2);
    expect(first.appBuildOrdinal, isNull);
    expect(second.appBuildOrdinal, 412);
    expect(first.platform, 'ios');
    expect(second.platform, 'ios');
  });

  test('a reading completes once a pending build read answers', () async {
    final pending = Completer<String?>();
    var settled = false;
    final reading = readSurfaceDeliveryObservations(
      isWeb: false,
      targetPlatform: TargetPlatform.android,
      deviceRegion: 'se',
      shortestLogicalSide: 600,
      buildNumberSource: () => pending.future,
    ).then((value) {
      settled = true;
      return value;
    });
    await pumpEventQueue();
    expect(settled, isFalse);

    pending.complete('412');
    final value = await reading;

    expect(value.appBuildOrdinal, 412);
    expect(value.presentationCountry, 'SE');
    expect(value.platform, 'android');
    expect(value.deviceClass, 'tablet');
  });
}
