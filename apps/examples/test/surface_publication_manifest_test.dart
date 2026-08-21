import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import 'package:restage_example/surfaces/categorized_screens.dart';

/// The shipped publication closure, asserted through the artifacts the app
/// actually ships.
///
/// Generated surfaces are packaged as deterministic `.rsbundle` containers
/// declared in `pubspec.yaml`, not as loose blobs beside them, so this reads
/// the same way the runtime does: through the generated bundle locator and the
/// asset-backed bundle provider. It deliberately touches no build metadata —
/// the index and publication manifest are reproducible build output, while a
/// bundle and its generated descriptor are what a released package contains.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const provider = AssetSurfaceScreenBundleProvider();

  final screens = <String, SurfaceScreenRef<Object?>>{
    'onboarding_welcome': onboardingWelcomeRef,
    'message_notice': messageNoticeRef,
    'general_status': generalStatusRef,
  };

  test('every generated screen resolves its packaged bundle closure', () async {
    for (final entry in screens.entries) {
      final ref = entry.value;
      final locator = ref.provenance.bundle;
      expect(
        locator,
        isNotNull,
        reason: '${entry.key} ships bundled and must carry a bundle locator.',
      );

      final bundle = await provider.load(locator!);
      expect(bundle.packageName, 'restage_example');
      expect(bundle.authoredLibraryPath, locator.authoredLibraryPath);

      final byPath = <String, RestageBundleEntry>{
        for (final packaged in bundle.entries) packaged.logicalPath: packaged,
      };
      for (final reference in locator.entries) {
        final packaged = byPath[reference.logicalPath];
        expect(
          packaged,
          isNotNull,
          reason: '${entry.key} references ${reference.logicalPath}, which is '
              'absent from ${locator.assetKey}.',
        );
        expect(packaged!.role, reference.role);
        expect(packaged.byteLength, reference.byteLength);
        expect(packaged.sha256, reference.sha256);
        expect(packaged.bytes, hasLength(reference.byteLength));
      }

      // The two roles every screen closure needs to render must be present as
      // real bytes, not merely declared.
      expect(byPath, contains(locator.screenBlob.logicalPath));
      expect(byPath, contains(locator.capabilitySidecar.logicalPath));
    }
  });

  test('generated screen identity matches its packaged provenance', () {
    for (final entry in screens.entries) {
      final ref = entry.value;
      expect(ref.provenance.slug, entry.key);
      expect(ref.sourceKind, SurfaceSourceKind.screen);
      expect(ref.payloadKind, SurfacePayloadKind.blob);
      expect(ref.contractFingerprint, ref.provenance.contractFingerprint);
      expect(ref.eventContract.hash, ref.provenance.eventContractHash);
      expect(ref.capabilities.builtInFloor,
          ref.provenance.capabilities.builtInFloor);
    }

    expect(onboardingWelcomeRef.surface, Surface.onboarding);
    expect(messageNoticeRef.surface, Surface.message);
    expect(generalStatusRef.surface, Surface.general);
  });

  test('flow documents ship inside their authored library bundles', () async {
    // Each authored library owns one bundle, so a flow's document travels in
    // the bundle named after the library that declares it.
    const flows = <String, String>{
      'assets/restage/bundles/lib/surfaces/general_flow.rsbundle':
          'assets/general/flows/general_journey.flow.json',
      'assets/restage/bundles/lib/surfaces/message_offer_flow.rsbundle':
          'assets/message/flows/message_offer.flow.json',
    };

    for (final entry in flows.entries) {
      final bundle = await _loadBundle(entry.key);
      final document = bundle.entries.singleWhere(
        (packaged) => packaged.logicalPath == entry.value,
        orElse: () => throw StateError(
          '${entry.value} is absent from ${entry.key}.',
        ),
      );
      expect(document.role, RestageBundleEntryRole.flowDocument);
      // The packaged bytes must be the canonical encoding the runtime expects.
      final decoded = FlowDocumentCodec.decodeJson(
        String.fromCharCodes(document.bytes),
      );
      expect(
        String.fromCharCodes(document.bytes),
        String.fromCharCodes(FlowDocumentCodec.encodeCanonicalJson(decoded)),
      );
    }
  });
}

Future<RestageBundle> _loadBundle(String assetKey) async {
  final data = await rootBundle.load(assetKey);
  return RestageBundleCodec.decode(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}
