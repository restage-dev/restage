import 'dart:io';

import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show CanonicalJsonCodec, requireCanonicalObject;
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

PlacementBatchRequestV1 _fixture() {
  final bytes = File(
    'test/fixtures/placements/shared_blob_two_mounts_v1.json',
  ).readAsBytesSync();
  final fixture = requireCanonicalObject(
    CanonicalJsonCodec.decode(bytes),
    'fixture',
  );
  final request = PlacementBatchRequestV1.fromJson(fixture['request']);
  final build = request.buildContract;
  return startupRequestFor(
    platform: build.platform,
    mounts: build.mounts.toList(),
    contractsByHash: build.contractsByHash,
    capability: build.installedCapability,
    builtIns: const {'platform': 'android'},
  );
}

/// [request] with [edit] applied to its JSON, decoded again.
PlacementBatchRequestV1 _edited(
  PlacementBatchRequestV1 request,
  void Function(Map<String, Object?> json) edit,
) {
  final json = Map<String, Object?>.of(request.toJson());
  edit(json);
  return PlacementBatchRequestV1.fromJson(json);
}

PlacementBatchRequestV1 _withCapability(
  PlacementBatchRequestV1 request,
  InstalledCapability capability,
) {
  final build = request.buildContract;
  return startupRequestFor(
    platform: build.platform,
    mounts: build.mounts.toList(),
    contractsByHash: build.contractsByHash,
    capability: capability,
    builtIns: const {'platform': 'android'},
  );
}

InstalledCapability _vocabulary(
  Set<String> widgets,
  Map<String, Set<int>> icons,
) =>
    InstalledCapability(
      builtInCatalogVersion: 1,
      installedLibraries: const [],
      vocabulary: WidgetVocabulary(widgetNames: widgets, iconCodePoints: icons),
    );

void main() {
  final mine = _fixture();

  test('the same request fits', () {
    expect(startupAnswerMismatch(sent: mine, mine: mine), isNull);
  });

  test('inline artifacts and the mounted-surface report never matter', () {
    final sent = _edited(mine, (json) => json.remove('inlineMounts'))
        .withMountedSince(const []);
    expect(sent.inlineMounts, isNot(mine.inlineMounts));
    expect(startupAnswerMismatch(sent: sent, mine: mine), isNull);
  });

  test('another mount list is a build mismatch', () {
    final sent = _edited(mine, (json) {
      json['mounts'] = (json['mounts']! as List).reversed.toList();
    });
    expect(
      startupAnswerMismatch(sent: sent, mine: mine),
      StartupAnswerMismatch.build,
    );
  });

  group('capability', () {
    final small = _vocabulary(
      {'restage.core:Text'},
      {
        'MaterialIcons': {1},
      },
    );
    final large = _vocabulary(
      {'restage.core:Text', 'restage.core:Column'},
      {
        'MaterialIcons': {1, 2},
        'CupertinoIcons': {3},
      },
    );

    test('a claim the app covers fits', () {
      expect(capabilityCovers(installed: large, claimed: small), isTrue);
      expect(
        startupAnswerMismatch(
          sent: _withCapability(mine, small),
          mine: _withCapability(mine, large),
        ),
        isNull,
      );
    });

    test('a claim the app does not cover is a capability mismatch', () {
      expect(capabilityCovers(installed: small, claimed: large), isFalse);
      expect(
        startupAnswerMismatch(
          sent: _withCapability(mine, large),
          mine: _withCapability(mine, small),
        ),
        StartupAnswerMismatch.capability,
      );
    });

    test('a newer catalog or a missing library is not covered', () {
      final newer = InstalledCapability(
        builtInCatalogVersion: 2,
        installedLibraries: const [],
        vocabulary: small.vocabulary,
      );
      expect(capabilityCovers(installed: small, claimed: newer), isFalse);
      final withLibrary = InstalledCapability(
        builtInCatalogVersion: 1,
        installedLibraries: const [
          InstalledLibrary(namespace: 'acme.widgets', version: 2),
        ],
        vocabulary: small.vocabulary,
      );
      expect(capabilityCovers(installed: small, claimed: withLibrary), isFalse);
      final later = InstalledCapability(
        builtInCatalogVersion: 1,
        installedLibraries: const [
          InstalledLibrary(namespace: 'acme.widgets', version: 3),
        ],
        vocabulary: small.vocabulary,
      );
      expect(capabilityCovers(installed: later, claimed: withLibrary), isTrue);
    });
  });

  test('a library covers another exactly when it renders all it renders', () {
    const namespace = 'acme.widgets';
    final libraries = [
      for (var version = 1; version <= 4; version++)
        for (var since = 1; since <= version; since++)
          for (var generated = 1; generated <= 2; generated++)
            InstalledLibrary(
              namespace: namespace,
              version: version,
              compatibleSince: since,
              generated: generated,
            ),
    ];
    final requirements = [
      for (var version = 1; version <= 4; version++)
        for (var generated = 1; generated <= 2; generated++)
          LibraryRequirement(
            namespace: namespace,
            minVersion: version,
            minGenerated: generated,
          ),
    ];
    InstalledCapability holding(InstalledLibrary library) =>
        InstalledCapability(
          builtInCatalogVersion: 1,
          installedLibraries: [library],
        );
    for (final claimed in libraries) {
      for (final installed in libraries) {
        final rendersAll = requirements.every(
          (required) =>
              LibraryCompatibility.evaluate(claimed, required) !=
                  LibraryCompatibility.satisfied ||
              LibraryCompatibility.evaluate(installed, required) ==
                  LibraryCompatibility.satisfied,
        );
        expect(
          capabilityCovers(
            installed: holding(installed),
            claimed: holding(claimed),
          ),
          rendersAll,
          reason:
              'installed ${installed.toJson()}, claimed ${claimed.toJson()}',
        );
      }
    }
  });

  test('another install id is an analytics mismatch', () {
    final sent = _edited(mine, (json) => json.remove('analyticsAnonymousId'));
    expect(
      startupAnswerMismatch(sent: sent, mine: mine),
      StartupAnswerMismatch.analytics,
    );
  });

  test('a registration only one side sends is a measurement mismatch', () {
    final dart = _edited(
      mine,
      (json) => json
        ..remove('registrationNonce')
        ..remove('registrationCreatedAtMicros'),
    );
    expect(
      startupAnswerMismatch(sent: mine, mine: dart),
      StartupAnswerMismatch.measurement,
    );
  });

  test('another metering key is an assignment mismatch', () {
    final sent = _edited(
      mine,
      (json) => json['meteringKey'] = '11111111-1111-4111-8111-111111111111',
    );
    expect(
      startupAnswerMismatch(sent: sent, mine: mine),
      StartupAnswerMismatch.assignment,
    );
  });
}
