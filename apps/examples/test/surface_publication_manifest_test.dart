import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import 'package:restage_example/surfaces/categorized_screens.dart';
import 'package:restage_example/surfaces/general_flow.dart';
import 'package:restage_example/surfaces/message_offer_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('manifest closure matches generated publication artifacts', () async {
    final manifest = SurfacePublicationManifestV1Codec.decodeJson(
      await rootBundle.loadString(
        'assets/restage/surface-publication-manifest.json',
      ),
    );
    final byIdentity = <String, SurfacePublicationManifestEntryV1>{
      for (final entry in manifest.publications)
        '${entry.publication.surface.wireName}/${entry.publication.slug}':
            entry,
    };

    final onboarding =
        _screenEntry<OnboardingWelcomeEvent>(byIdentity, onboardingWelcomeRef);
    final message =
        _screenEntry<MessageNoticeEvent>(byIdentity, messageNoticeRef);
    final general =
        _screenEntry<GeneralStatusEvent>(byIdentity, generalStatusRef);
    final generalFlow = _entryFor(
      byIdentity,
      surface: generalJourneyRef.surface,
      slug: generalJourneyRef.id,
    );
    final messageFlow = _entryFor(
      byIdentity,
      surface: messageOfferRef.surface,
      slug: messageOfferRef.id,
    );
    final paywall = manifest.publications.singleWhere(
      (entry) =>
          entry.publication.surface == Surface.paywall &&
          entry.publication.sourceKind == SurfaceSourceKind.paywall,
    );
    expect(
      messageFlow.artifacts.any(
        (artifact) => artifact.id == 'paywall_${paywall.publication.slug}',
      ),
      isTrue,
    );

    expect(onboarding.publication.sourceKind, SurfaceSourceKind.screen);
    expect(onboarding.publication.payloadKind, SurfacePayloadKind.blob);
    expect(message.publication.sourceKind, SurfaceSourceKind.screen);
    expect(message.publication.payloadKind, SurfacePayloadKind.blob);
    expect(general.publication.sourceKind, SurfaceSourceKind.screen);
    expect(general.publication.payloadKind, SurfacePayloadKind.blob);
    expect(generalFlow.publication.sourceKind, SurfaceSourceKind.flowGraph);
    expect(generalFlow.publication.payloadKind, SurfacePayloadKind.flow);
    expect(messageFlow.publication.sourceKind, SurfaceSourceKind.flowGraph);
    expect(messageFlow.publication.payloadKind, SurfacePayloadKind.flow);
    expect(paywall.publication.sourceKind, SurfaceSourceKind.paywall);
    expect(paywall.publication.payloadKind, SurfacePayloadKind.blob);
    expect(paywall.publication.surface, Surface.paywall);

    expect(onboarding.publication.contractVersion,
        onboardingWelcomeRef.contractVersion);
    expect(
      onboarding.publication.eventContractHash,
      onboardingWelcomeRef.eventContract.hash,
    );
    expect(
      onboarding.publication.contractFingerprint,
      onboardingWelcomeRef.contractFingerprint,
    );
    expect(
        message.publication.contractVersion, messageNoticeRef.contractVersion);
    expect(
      message.publication.eventContractHash,
      messageNoticeRef.eventContract.hash,
    );
    expect(
      message.publication.contractFingerprint,
      messageNoticeRef.contractFingerprint,
    );
    expect(
      general.publication.contractVersion,
      generalStatusRef.contractVersion,
    );
    expect(
      general.publication.eventContractHash,
      generalStatusRef.eventContract.hash,
    );
    expect(
      general.publication.contractFingerprint,
      generalStatusRef.contractFingerprint,
    );

    final files = <String, List<int>>{};
    for (final entry in manifest.publications) {
      for (final artifact in entry.artifacts) {
        files[artifact.path] = await _loadAsset(artifact.path);
      }
    }
    final closures = manifest.validateArtifactClosure(files);
    expect(closures, hasLength(manifest.publications.length));
  });
}

Future<List<int>> _loadAsset(String path) async {
  final data = await rootBundle.load(path);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  return bytes;
}

SurfacePublicationManifestEntryV1 _entryFor(
  Map<String, SurfacePublicationManifestEntryV1> byIdentity, {
  required Surface surface,
  required String slug,
}) =>
    byIdentity['${surface.wireName}/$slug']!;

SurfacePublicationManifestEntryV1 _screenEntry<E>(
  Map<String, SurfacePublicationManifestEntryV1> byIdentity,
  SurfaceScreenRef<E> screen,
) =>
    _entryFor(byIdentity, surface: screen.surface, slug: screen.slug);
