import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/resolver/surface_assignment_built_ins.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';

SurfaceDeliveryObservations snapshot({
  String? country = 'SE',
  String? platform = 'ios',
  int? build = 42,
  String? device = 'phone',
  int level = assignmentSdkApiLevel,
}) =>
    SurfaceDeliveryObservations(
      presentationCountry: country,
      platform: platform,
      appBuildOrdinal: build,
      deviceClass: device,
      sdkApiLevel: level,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(debugResetAppBuildOrdinal);
  tearDown(debugResetAppBuildOrdinal);

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
    'level': snapshot(level: 2),
  }.entries) {
    test('changing ${entry.key} changes equality', () {
      expect(snapshot(), isNot(entry.value));
    });
  }

  test('string representation lists all fields', () {
    expect(
        snapshot().toString(),
        'SurfaceDeliveryObservations(presentationCountry: SE, platform: ios, '
        'appBuildOrdinal: 42, deviceClass: phone, sdkApiLevel: 3)');
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
