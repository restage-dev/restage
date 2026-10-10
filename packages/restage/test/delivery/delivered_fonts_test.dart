import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/delivery/delivered_fonts.dart';
import 'package:restage/src/restage_rpc_client/surface_artifact_assembly.dart';
import 'package:restage_shared/restage_shared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fontBytes = File(
    '../restage_shared/test/fonts/fixtures/material_icons_subset.otf',
  ).readAsBytesSync();
  final covered = readSfntCoveredCodePoints(fontBytes);
  final font = DeliveredIconFont(family: 'MaterialIcons', bytes: fontBytes);

  var loads = <String>[];
  setUp(() {
    DeliveredIconFontLoader.reset();
    loads = <String>[];
    DeliveredIconFontLoader.loadFont = (family, bytes) async {
      loads.add(family);
    };
  });
  tearDown(DeliveredIconFontLoader.reset);

  test('a font is loaded under a name taken from its content hash', () {
    final hash = crypto.sha256.convert(fontBytes).toString();
    expect(
      DeliveredIconFontLoader.familyFor(fontBytes),
      'restage-icons-${hash.substring(0, 12)}',
    );
  });

  test('a font is loaded once per process and scoped by source family',
      () async {
    expect(
        DeliveredIconFontLoader.scopeFor(<DeliveredIconFont>[font]), isEmpty);

    expect(await DeliveredIconFontLoader.loadAll(<DeliveredIconFont>[font]),
        isTrue);
    expect(await DeliveredIconFontLoader.loadAll(<DeliveredIconFont>[font]),
        isTrue);

    final family = DeliveredIconFontLoader.familyFor(fontBytes);
    expect(loads, <String>[family]);
    final scope = DeliveredIconFontLoader.scopeFor(<DeliveredIconFont>[font]);
    expect(scope.keys, <String>['MaterialIcons']);
    expect(scope['MaterialIcons']!.loadedFamily, family);
    expect(scope['MaterialIcons']!.codePoints, covered);
  });

  test('a failed load is reported, left out of scope, and retried', () async {
    DeliveredIconFontLoader.loadFont = (family, bytes) async {
      loads.add(family);
      throw StateError('engine refused the font');
    };

    expect(await DeliveredIconFontLoader.loadAll(<DeliveredIconFont>[font]),
        isFalse);
    expect(
        DeliveredIconFontLoader.scopeFor(<DeliveredIconFont>[font]), isEmpty);
    expect(await DeliveredIconFontLoader.loadAll(<DeliveredIconFont>[font]),
        isFalse);
    expect(loads, hasLength(2));
  });

  test('bytes that are not a font never reach the engine', () async {
    final junk = DeliveredIconFont(
      family: 'MaterialIcons',
      bytes: Uint8List.fromList(List<int>.filled(64, 7)),
    );
    expect(await DeliveredIconFontLoader.loadAll(<DeliveredIconFont>[junk]),
        isFalse);
    expect(await DeliveredIconFontLoader.loadAll(<DeliveredIconFont>[junk]),
        isFalse);
    expect(loads, isEmpty);
  });

  test('the real engine loads the delivered font', () async {
    DeliveredIconFontLoader.reset();
    expect(await DeliveredIconFontLoader.loadAll(<DeliveredIconFont>[font]),
        isTrue);
  });

  group('the assembly font step', () {
    final withFont = BlobSurfacePayload(
      minClient: kSurfaceFeatureClientFloor,
      blob: Uint8List.fromList(const <int>[1, 2, 3]),
      iconFonts: <DeliveredIconFont>[font],
    );
    final plain = BlobSurfacePayload(
      minClient: 1,
      blob: Uint8List.fromList(const <int>[1, 2, 3]),
    );

    SurfaceArtifactOutcome assembled(SurfacePayload payload) =>
        assembleSurfaceArtifact(
          descriptor: SurfaceArtifactDescriptor(
            payloadFormatVersion: payload.carriesSections
                ? kSurfaceArtifactSectionsPayloadFormatVersion
                : kSurfaceArtifactPayloadFormatVersion,
            surfaceType: Surface.paywall,
            surfaceSlug: 'pro_upgrade',
            version: 4,
            publishedAtMicros: DateTime.utc(2026, 9, 29).microsecondsSinceEpoch,
            contentHash: payload.contentHash,
            artifactUrl: 'https://artifacts.test/artifacts/orgs/1/artifacts/1/'
                '${payload.contentHash}',
            artifactPass: 'v1.k1.4102444800.${'a' * 64}',
          ),
          artifactBytes: payload.canonicalBytes,
        );

    test('a surface whose fonts load is kept', () async {
      final outcome = assembled(withFont);
      expect(outcome, isA<SurfaceArtifactAssembled>());
      expect(await loadSurfaceArtifactIconFonts(outcome), same(outcome));
      expect(loads, hasLength(1));
    });

    test('a surface whose font fails to load is unavailable', () async {
      DeliveredIconFontLoader.loadFont = (family, bytes) async {
        throw StateError('engine refused the font');
      };
      final outcome = await loadSurfaceArtifactIconFonts(assembled(withFont));
      expect(
        (outcome as SurfaceArtifactUnavailable).reason,
        SurfaceArtifactFetchFailure.iconFontLoad,
      );
    });

    test('a surface without fonts loads nothing', () async {
      final outcome = assembled(plain);
      expect(await loadSurfaceArtifactIconFonts(outcome), same(outcome));
      expect(loads, isEmpty);
    });
  });
}
