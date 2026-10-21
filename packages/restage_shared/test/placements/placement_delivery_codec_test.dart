import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

const _general = DeliveryFamilySelectorV1.general();
final _screenType = DeliverySurfaceTypeId('screen');
final TypeMatcher<CanonicalFormatException> _refusal =
    isA<CanonicalFormatException>();
final SurfaceHostContractV1 _host = _hostContract();
final InstalledCapability _capability = _installed();
final TargetCoordinate _target = _coordinate(1);

void main() {
  test('experiment steps retain only inert original selection identifiers', () {
    final selection = PublicExperimentSelectionV1(
      experimentId: ExperimentPublicIdV1('experiment.original'),
      experimentRevisionId: ExperimentPublicRevisionIdV1('revision.original'),
      experimentEpochId: ExperimentPublicEpochIdV1('epoch.original'),
      armId: ExperimentPublicArmIdV1('arm.original'),
    );
    final step = PublicDeliveryDecisionStepV1(
      scope: _watchSurfaceScope(_target, 'surface.welcome'),
      source: PublicDeliverySelectionSourceV1.experiment,
      experimentSelection: selection,
    );
    final decoded =
        PublicDeliveryDecisionStepV1.fromCanonicalBytes(step.canonicalBytes);
    expect(decoded.experimentSelection, selection);
    expect(decoded.experimentSelection!.toJson().keys.toSet(), {
      'experimentId',
      'experimentRevisionId',
      'experimentEpochId',
      'armId',
    });
    expect(
        () => PublicExperimentSelectionV1.fromJson({
              ...selection.toJson(),
              'outcomeLinkCarrier': 'private',
            }),
        throwsA(_refusal));
    expect(
        () => PublicDeliveryDecisionStepV1(
              scope: step.scope,
              source: PublicDeliverySelectionSourceV1.ownerDefault,
              experimentSelection: selection,
            ),
        throwsA(_refusal));
    final ordinary = PublicDeliveryDecisionStepV1(
      scope: step.scope,
      source: PublicDeliverySelectionSourceV1.ownerDefault,
    );
    expect(ordinary.toJson().containsKey('experimentSelection'), isFalse);
  });
  _batchContractTests();
  group('mount locators and descriptors', () {
    test('strict round trips retain target-free locators and exact descriptors',
        () {
      final locator = _locator();
      final mount = _mount();
      final descriptor = _descriptor(mount);
      expect(
        DeliverySurfaceLocatorV1.fromCanonicalBytes(locator.canonicalBytes),
        locator,
      );
      expect(
        PlacementMountRequestV1.fromCanonicalBytes(mount.canonicalBytes),
        mount,
      );
      expect(
        PlacementMountDescriptorV1.fromCanonicalBytes(
          descriptor.canonicalBytes,
          expectedTarget: _target,
        ),
        descriptor,
      );
      descriptor.validateForRequest(mount, expectedTarget: _target);
      expect(utf8.decode(mount.canonicalBytes), isNot(contains('target')));
    });

    test('generated defaults require the exact type and slug locator', () {
      final key = PlacementKeyV1.generatedDefault(
        surfaceType: _screenType,
        slug: 'welcome',
      );
      for (final locator in [
        null,
        _locator(slug: 'notice'),
        _locator(type: DeliverySurfaceTypeId('message')),
      ]) {
        expect(
          () => PlacementMountRequestV1(
            key: key,
            defaultSurface: locator,
            hostContractHash: _host.contentHash,
          ),
          throwsA(_refusal),
        );
      }
      expect(
        _mount(key: PlacementKeyV1.named(slug: 'notice'), useDefault: false)
            .defaultSurface,
        isNull,
      );
    });

    test('a declared surface type round trips and must agree with the mount',
        () {
      final paywall = DeliverySurfaceTypeId('paywall');
      final declared = _mount(
        key: PlacementKeyV1.named(slug: 'upsell'),
        useDefault: false,
        surfaceType: paywall,
      );
      expect(declared.toJson()['surfaceType'], 'paywall');
      expect(
        PlacementMountRequestV1.fromCanonicalBytes(declared.canonicalBytes),
        declared,
      );
      expect(_mount().toJson(), containsPair('surfaceType', null));
      expect(_mount(surfaceType: _screenType).surfaceType, _screenType);
      for (final build in [
        () => _mount(surfaceType: paywall),
        () => _mount(
              key: PlacementKeyV1.named(slug: 'upsell'),
              surfaceType: paywall,
            ),
      ]) {
        expect(build, throwsA(_refusal));
      }
      final json = declared.toJson();
      for (final invalid in [
        {...json}..remove('surfaceType'),
        {...json, 'surfaceType': 1},
      ]) {
        expect(
          () => PlacementMountRequestV1.fromJson(invalid),
          throwsA(_refusal),
        );
      }
    });

    test('locator refuses none, malformed slug, and a missing exact version',
        () {
      final json = _locator().toJson();
      for (final slug in ['', 'Uppercase', 'a/b', 'a\n', 'a' * 65]) {
        expect(
          () => DeliverySurfaceLocatorV1.fromJson({...json, 'slug': slug}),
          throwsA(_refusal),
        );
      }
      for (final family in [
        {'kind': 'none'},
        {'kind': 'screenContract'},
        {'kind': 'screenContract', 'contractVersion': 0},
        {'kind': 'general', 'contractVersion': 1},
      ]) {
        expect(
          () => DeliverySurfaceLocatorV1.fromJson({...json, 'family': family}),
          throwsA(_refusal),
        );
      }
    });

    test('descriptor checks all shared correlation facts and supplied target',
        () {
      final request = _mount();
      final descriptor = _descriptor(request);
      for (final target in [_coordinate(2), _coordinate(1, sandbox: true)]) {
        expect(
          () => descriptor.validateForRequest(request, expectedTarget: target),
          throwsA(_refusal),
        );
        expect(
          () => PlacementMountDescriptorV1.fromCanonicalBytes(
            descriptor.canonicalBytes,
            expectedTarget: target,
          ),
          throwsA(_refusal),
        );
      }
      final named = _mount(key: PlacementKeyV1.named(slug: 'welcome'));
      for (final wrong in [
        _descriptor(named),
        _descriptor(
          request,
          hostHash: _hostContract(presented: true).contentHash,
        ),
        _descriptor(
          request,
          family: DeliveryFamilySelectorV1.screenContract(contractVersion: 3),
        ),
      ]) {
        expect(
          () => wrong.validateForRequest(request, expectedTarget: _target),
          throwsA(_refusal),
        );
      }
      final widgetOnly = _mount(
        key: PlacementKeyV1.named(slug: 'welcome'),
        useDefault: false,
      );
      expect(
        () => _descriptor(named).validateForRequest(
          widgetOnly,
          expectedTarget: _target,
        ),
        throwsA(_refusal),
      );
      // A declared default with no hosted publication stays unresolved.
      _descriptor(widgetOnly)
          .validateForRequest(named, expectedTarget: _target);
      // A published identity is opaque: the authenticated resolver proves its
      // locator mapping, while this codec proves the shared correlation facts.
      _descriptor(request, surfaceId: 'surface.v1.opaque').validateForRequest(
        request,
        expectedTarget: _target,
      );
    });

    test('descriptor refuses cross-target defaults and keeps unhosted defaults',
        () {
      final request = _mount();
      final descriptor = _descriptor(request);
      final unhosted = PlacementMountDescriptorV1.fromJson(
        {...descriptor.toJson(), 'defaultSurface': null},
        expectedTarget: _target,
      );
      expect(unhosted.defaultSurface, isNull);
      unhosted.validateForRequest(request, expectedTarget: _target);
      expect(
        () => PlacementMountDescriptorV1(
          placement: descriptor.placement,
          hostContractHash: descriptor.hostContractHash,
          defaultSurface: DeliverySurfaceReferenceV1(
            surfaceIdentity: PublishedSurfaceIdentityV1(
              target: _coordinate(2),
              surfaceId: SurfaceId('surface.v1.other'),
            ),
            family: _general,
          ),
        ),
        throwsA(_refusal),
      );
    });
  });

  group('build contract', () {
    test('fixed independent NUL-domain hash vector and explicit null ordinal',
        () {
      // Python hashlib + sorted compact JSON, independently of these codecs.
      const capabilityHash = 'sha256:f02a1939f2e4432eb43818f0957aed5a1'
          '439910ec33161a1155367cdd87cbb7c';
      const canonical = '{"buildOrdinal":null,"contractsByHash":{},'
          '"installedCapability":{"builtInCatalogVersion":1,'
          '"installedLibraries":[]},'
          '"installedCapabilityHash":"$capabilityHash",'
          '"mounts":[],"platform":"ios"}';
      const expected = 'sha256:c761e8fccfe02518aa882bc79276069b2'
          'a718bd621fa50129cd8b6fbfd3211e2';
      final build =
          _build(mounts: [], contracts: {}, capability: _installed(version: 1));
      expect(build.installedCapabilityHash, capabilityHash);
      expect(utf8.decode(build.canonicalBytes), canonical);
      expect(build.appBuildContractHash, expected);
      expect(build.buildOrdinal, isNull);
      expect(build.toJson().containsKey('buildOrdinal'), isTrue);
      expect(
        PlacementBuildContractV1.fromCanonicalBytes(
          utf8.encode(canonical),
          expectedAppBuildContractHash: expected,
        ),
        build,
      );
    });

    test('build has exact catalog fields and excludes target and runtime data',
        () {
      final build = _build();
      expect(build.toJson().keys.toSet(), {
        'platform',
        'buildOrdinal',
        'mounts',
        'contractsByHash',
        'installedCapability',
        'installedCapabilityHash',
      });
      final bytes = utf8.decode(build.canonicalBytes);
      for (final forbidden in [
        'target',
        'appBuildContractHash',
        'apiKey',
        'userId',
        'bounds',
        'route',
      ]) {
        expect(bytes, isNot(contains('"$forbidden"')));
        expect(
          () => PlacementBuildContractV1.fromJson(
            {...build.toJson(), forbidden: 'private'},
          ),
          throwsA(_refusal),
        );
      }
    });

    test(
        'sorts and deduplicates declarations, '
        'retaining distinct host contracts', () {
      final secondHost = _hostContract(presented: true);
      final key = PlacementKeyV1.named(slug: 'notice');
      final one = _mount(key: key);
      final two = _mount(key: key, host: secondHost);
      final contracts = {
        _host.contentHash: _host,
        secondHost.contentHash: secondHost,
      };
      final build = _build(mounts: [two, one, one], contracts: contracts);
      final reversed = _build(mounts: [one, two], contracts: contracts);
      expect(build, reversed);
      expect(build.appBuildContractHash, reversed.appBuildContractHash);
      expect(build.mounts, hasLength(2));
      final encoded = build.mounts
          .map((mount) => utf8.decode(mount.canonicalBytes))
          .toList();
      expect(encoded, [...encoded]..sort());
      expect(build.contractsByHash.keys.toList(), [...contracts.keys]..sort());
      final json = build.toJson();
      for (final raw in [
        [one.toJson(), one.toJson(), two.toJson()],
        build.mounts.reversed.map((mount) => mount.toJson()).toList(),
      ]) {
        expect(
          () => PlacementBuildContractV1.fromCanonicalBytes(
            CanonicalJsonCodec.encode({...json, 'mounts': raw}),
          ),
          throwsA(_refusal),
        );
      }
    });

    test('conflicting defaults for the same key and host refuse', () {
      final key = PlacementKeyV1.named(slug: 'notice');
      for (final other in [
        _mount(key: key, useDefault: false),
        _mount(key: key, defaultSurface: _locator(slug: 'other')),
        _mount(key: key, surfaceType: _screenType),
        _mount(
          key: key,
          defaultSurface: _locator(
            family: DeliveryFamilySelectorV1.screenContract(
              contractVersion: 2,
            ),
          ),
        ),
      ]) {
        expect(
          () => _build(mounts: [_mount(key: key), other]),
          throwsA(_refusal),
        );
      }
    });

    test(
        'rejects exact host hash disagreement, '
        'missing hosts and extra authority', () {
      final build = _build();
      final secondHost = _hostContract(presented: true);
      final json = build.toJson();
      for (final contracts in [
        <String, Object?>{},
        {_host.contentHash: secondHost.toJson()},
        {
          _host.contentHash: {..._host.toJson(), 'hostValues': 'private'},
        },
        {
          _host.contentHash: _host.toJson(),
          secondHost.contentHash: secondHost.toJson(),
        },
      ]) {
        expect(
          () => PlacementBuildContractV1.fromJson(
            {...json, 'contractsByHash': contracts},
          ),
          throwsA(_refusal),
        );
      }
    });

    test('checks complete capability owner hash, including vocabulary', () {
      final build = _build();
      final json = build.toJson();
      for (final malformed in [
        {
          ...json,
          'installedCapabilityHash': _installed(version: 3).contentHash,
        },
        {
          ...json,
          'installedCapability':
              _installed(names: {'restage.core:Text'}).toJson(),
        },
        {...json, 'installedCapabilityHash': 'f' * 64},
      ]) {
        expect(
          () => PlacementBuildContractV1.fromJson(malformed),
          throwsA(_refusal),
        );
      }
    });

    test(
        'host presentation, registry, capability, '
        'platform and ordinal affect hash', () {
      final baseline = _build();
      final presented = _hostContract(presented: true);
      for (final changed in [
        _build(
          mounts: [_mount(host: presented)],
          contracts: {presented.contentHash: presented},
        ),
        _build(mounts: [_mount(key: PlacementKeyV1.named(slug: 'notice'))]),
        _build(capability: _installed(names: {'restage.core:Text'})),
        _build(platform: 'android'),
        _build(ordinal: 0),
        _build(ordinal: 1),
      ]) {
        expect(
          changed.appBuildContractHash,
          isNot(baseline.appBuildContractHash),
        );
      }
    });

    test('build digest verification refuses a substituted build', () {
      final build = _build();
      final changed = _build(ordinal: 17);
      expect(
        () => PlacementBuildContractV1.fromCanonicalBytes(
          build.canonicalBytes,
          expectedAppBuildContractHash: changed.appBuildContractHash,
        ),
        throwsA(_refusal),
      );
      expect(
        () => build.verifyHash(changed.appBuildContractHash),
        throwsA(_refusal),
      );
    });

    test(
        'source collections, schemas, JSON and '
        'returned bytes cannot mutate build', () {
      final shape = <String, SurfaceScreenHostDataShape>{
        'title': const SurfaceScreenHostDataScalarShapeV1(
          SurfaceScreenHostDataScalarKind.string,
        ),
      };
      final host = SurfaceHostContractV1(
        hosting: const SurfaceHostingV1(
          contentKind: SurfaceContentKindV1.single,
          presentation: SurfacePresentationV1.inline,
        ),
        providedContext: SurfaceScreenHostDataSchema(shape),
        handledEvents: SurfaceScreenEventSchema(events: const []),
      );
      final names = {'restage.core:Text'};
      final icons = {
        'Icons': <int>{3},
      };
      final libraries = <InstalledLibrary>[
        const InstalledLibrary(namespace: 'sample.widgets', version: 1),
      ];
      final capability = InstalledCapability(
        builtInCatalogVersion: 2,
        installedLibraries: libraries,
        vocabulary: WidgetVocabulary(widgetNames: names, iconCodePoints: icons),
      );
      final mounts = [_mount(host: host)];
      final contracts = {host.contentHash: host};
      final build =
          _build(mounts: mounts, contracts: contracts, capability: capability);
      final bytes = build.canonicalBytes;
      final digest = build.appBuildContractHash;
      shape.clear();
      mounts.clear();
      contracts.clear();
      names.clear();
      icons['Icons']!.clear();
      libraries.clear();
      build.canonicalBytes.fillRange(0, bytes.length, 0);
      final json = build.toJson();
      (json['mounts']! as List<Object?>).clear();
      (json['contractsByHash']! as Map<String, Object?>).clear();
      expect(build.canonicalBytes, bytes);
      expect(CanonicalJsonCodec.encode(build.toJson()), bytes);
      expect(build.appBuildContractHash, digest);
      expect(build.mounts.clear, throwsUnsupportedError);
      expect(build.contractsByHash.clear, throwsUnsupportedError);
      expect(
        () => build.installedCapability.vocabulary!.widgetNames.clear(),
        throwsUnsupportedError,
      );
    });

    test('capability fields are closed and canonical rather than normalized',
        () {
      final json = _build().toJson();
      final installed = _capability.toJson();
      for (final malformed in [
        {...installed, 'context': 'secret'},
        {...installed, 'builtInCatalogVersion': 0},
        {
          ...installed,
          'installedLibraries': [
            {'namespace': 'sample.widgets', 'version': 1, 'extra': true},
          ],
        },
        {
          ...installed,
          'installedLibraries': [
            {'namespace': 'sample.widgets', 'version': 1},
            {'namespace': 'sample.widgets', 'version': 1},
          ],
        },
        {
          ...installed,
          'installedLibraries': [
            {'namespace': 'sample.widgets', 'version': 1, 'compatibleSince': 1},
          ],
        },
        {
          ...installed,
          'vocabulary': {
            'widgetNames': <String>[],
            'iconCodePoints': <String, Object?>{},
            'values': <Object?>[],
          },
        },
        {
          ...installed,
          'vocabulary': {
            'widgetNames': ['x', 'x'],
            'iconCodePoints': <String, Object?>{},
          },
        },
        {...installed, 'vocabulary': null},
      ]) {
        expect(
          () => PlacementBuildContractV1.fromJson(
            {...json, 'installedCapability': malformed},
          ),
          throwsA(_refusal),
        );
      }
    });
  });

  test('a verified build is reused only for its exact bytes', () {
    final (request, _, _, _) = _batchFixture();
    final json = request.toJson();
    final reused = PlacementBatchRequestV1.fromJson(
      json,
      verifiedBuildContract: (_) => request.buildContract,
    );
    expect(reused.buildContract, same(request.buildContract));

    final other = PlacementBuildContractV1(
      platform: 'android',
      mounts: request.buildContract.mounts,
      contractsByHash: request.buildContract.contractsByHash,
      installedCapability: request.buildContract.installedCapability,
      installedCapabilityHash: request.buildContract.installedCapabilityHash,
    );
    final decoded = PlacementBatchRequestV1.fromJson(
      json,
      verifiedBuildContract: (_) => other,
    );
    expect(decoded.buildContract, isNot(same(other)));
    expect(decoded.buildContract, request.buildContract);
  });

  group('discovery and reported geometry', () {
    test('same-key occurrences remain distinct without changing build hash',
        () {
      final build = _build();
      final bounds = [_bounds(index: 1), _bounds()];
      final report = _report(build: build, bounds: bounds);
      final reordered = _report(build: build, bounds: bounds.reversed.toList());
      expect(report, reordered);
      expect(report.bounds, hasLength(2));
      expect(
        report.bounds.map((bound) => bound.occurrenceIndex).toSet(),
        {0, 1},
      );
      expect(report.appBuildContractHash, build.appBuildContractHash);
      expect(
        PlacementDiscoveryReportV1.fromCanonicalBytes(report.canonicalBytes),
        report,
      );
      final geometry = PlacementReportedGeometryV1(
        appBuildContractHash: build.appBuildContractHash,
        serverObservedAtMicros: 1791067200000000,
        mounts: bounds,
      );
      expect(
        PlacementReportedGeometryV1.fromCanonicalBytes(
          geometry.canonicalBytes,
        ),
        geometry,
      );
      bounds.clear();
      expect(report.bounds, hasLength(2));
      expect(geometry.mounts, hasLength(2));
      expect(report.bounds.clear, throwsUnsupportedError);
      expect(geometry.mounts.clear, throwsUnsupportedError);
    });

    test('a report may carry the app display version, outside the build hash',
        () {
      final build = _build();
      final report = PlacementDiscoveryReportV1(
        mounts: build.mounts,
        buildContract: build,
        appBuildContractHash: build.appBuildContractHash,
        bounds: [_bounds()],
        appVersion: '2.4.1',
      );
      final decoded =
          PlacementDiscoveryReportV1.fromCanonicalBytes(report.canonicalBytes);
      expect(decoded.appVersion, '2.4.1');
      expect(decoded.appBuildContractHash, build.appBuildContractHash);
      expect(_report(build: build).toJson().containsKey('appVersion'), isFalse);
      for (final invalid in ['', 'x' * 65, 'two\nlines']) {
        expect(
          () => PlacementDiscoveryReportV1(
            mounts: build.mounts,
            buildContract: build,
            appBuildContractHash: build.appBuildContractHash,
            bounds: [_bounds()],
            appVersion: invalid,
          ),
          throwsA(_refusal),
        );
      }
    });

    test('discovery build digest verification rejects a changed declaration',
        () {
      final report = _report();
      final changed = _build(ordinal: 1);
      expect(
        () => PlacementDiscoveryReportV1.fromCanonicalBytes(
          CanonicalJsonCodec.encode({
            ...report.toJson(),
            'appBuildContractHash': changed.appBuildContractHash,
          }),
        ),
        throwsA(_refusal),
      );
    });

    test(
        'reported locators and bounds require '
        'exact reachable key/host declarations', () {
      final build = _build();
      final wrongKey = PlacementKeyV1.named(slug: 'unknown');
      expect(
        () => _report(
          build: build,
          mounts: [_mount(key: wrongKey)],
          bounds: [],
        ),
        throwsA(_refusal),
      );
      expect(
        () => _report(build: build, mounts: [], bounds: [_bounds()]),
        throwsA(_refusal),
      );
      expect(
        () => _report(build: build, bounds: [_bounds(key: wrongKey)]),
        throwsA(_refusal),
      );
      expect(
        () => _report(
          build: build,
          bounds: [_bounds(host: _hostContract(presented: true))],
        ),
        throwsA(_refusal),
      );
      expect(
        () => _report(
          build: build,
          mounts: [
            _mount(
              defaultSurface: _locator(
                family: DeliveryFamilySelectorV1.screenContract(
                  contractVersion: 2,
                ),
              ),
            ),
          ],
          bounds: [],
        ),
        throwsA(_refusal),
      );
    });

    test('duplicate occurrence identities refuse even when observations agree',
        () {
      final one = _bounds();
      for (final duplicate in [one, _bounds(x: 4)]) {
        expect(() => _report(bounds: [one, duplicate]), throwsA(_refusal));
        expect(
          () => PlacementReportedGeometryV1(
            appBuildContractHash: _build().appBuildContractHash,
            serverObservedAtMicros: 1,
            mounts: [one, duplicate],
          ),
          throwsA(_refusal),
        );
      }
    });

    test(
        'geometry reuses integer-only bounded owner '
        'and permits offscreen positions', () {
      final bounds = _bounds(x: -12);
      expect(bounds.logicalBounds.x, -12);
      final json = bounds.toJson();
      for (final malformed in [
        {...json, 'occurrenceIndex': -1},
        {...json, 'occurrenceIndex': kMaximumPortableJsonInteger + 1},
        {
          ...json,
          'logicalBounds': {...bounds.logicalBounds.toJson(), 'widthUnits': 0},
        },
        {
          ...json,
          'logicalBounds': {
            ...bounds.logicalBounds.toJson(),
            'xUnits': 67108865,
          },
        },
        {
          ...json,
          'logicalViewport': {
            ...bounds.logicalViewport.toJson(),
            'heightUnits': 0,
          },
        },
        {
          ...json,
          'logicalBounds': {
            ...bounds.logicalBounds.toJson(),
            'xUnits': double.nan,
          },
        },
        {
          ...json,
          'logicalViewport': {
            ...bounds.logicalViewport.toJson(),
            'widthUnits': double.infinity,
          },
        },
      ]) {
        expect(
          () => PlacementMountBoundsV1.fromJson(malformed),
          throwsA(_refusal),
        );
      }
    });

    test('discovery rejects observations, host values and image or route data',
        () {
      final report = _report();
      for (final field in [
        'context',
        'hostValues',
        'routeName',
        'screenLabel',
        'userId',
        'pngBytes',
        'serverObservedAtMicros',
        'target',
      ]) {
        expect(
          () => PlacementDiscoveryReportV1.fromJson(
            {...report.toJson(), field: 'private'},
          ),
          throwsA(_refusal),
        );
        expect(
          () => PlacementMountBoundsV1.fromJson(
            {...report.bounds.single.toJson(), field: 'private'},
          ),
          throwsA(_refusal),
        );
      }
      final geometry = PlacementReportedGeometryV1(
        appBuildContractHash: report.appBuildContractHash,
        serverObservedAtMicros: 1,
        mounts: report.bounds,
      );
      expect(
        () => PlacementReportedGeometryV1.fromJson(
          {...geometry.toJson(), 'userId': 'private'},
        ),
        throwsA(_refusal),
      );
      expect(
        () => PlacementReportedGeometryV1.fromJson(
          {...geometry.toJson(), 'serverObservedAtMicros': -1},
        ),
        throwsA(_refusal),
      );
    });
  });

  test(
      'every public codec refuses unknown fields, '
      'missing fields and byte aliases', () {
    final build = _build();
    final codecs = <(CanonicalValue, CanonicalValue Function(List<int>))>[
      (_locator(), DeliverySurfaceLocatorV1.fromCanonicalBytes),
      (_mount(), PlacementMountRequestV1.fromCanonicalBytes),
      (_descriptor(_mount()), PlacementMountDescriptorV1.fromCanonicalBytes),
      (build, PlacementBuildContractV1.fromCanonicalBytes),
      (_bounds(), PlacementMountBoundsV1.fromCanonicalBytes),
      (_report(build: build), PlacementDiscoveryReportV1.fromCanonicalBytes),
      (
        PlacementReportedGeometryV1(
          appBuildContractHash: build.appBuildContractHash,
          serverObservedAtMicros: 1,
          mounts: [_bounds()],
        ),
        PlacementReportedGeometryV1.fromCanonicalBytes
      ),
    ];
    for (final (value, decode) in codecs) {
      final json = value.toJson();
      expect(
        () => decode(CanonicalJsonCodec.encode({...json, 'unknown': true})),
        throwsA(_refusal),
      );
      for (final field in json.keys) {
        final missing = {...json}..remove(field);
        expect(
          () => decode(CanonicalJsonCodec.encode(missing)),
          throwsA(_refusal),
          reason: '${value.runtimeType}.$field',
        );
      }
      expect(() => decode([...value.canonicalBytes, 0x20]), throwsA(_refusal));
      expect(() => decode(utf8.encode(jsonEncode(json))), throwsA(_refusal));
      expect(
        () => decode(List<int>.filled(kMaximumPlacementRequestBytes + 1, 0)),
        throwsA(_refusal),
      );
    }
  });

  test('512 KiB total transport admits exact limit and rejects the next byte',
      () {
    PlacementBuildContractV1 paddedBuild(int padding) => _build(
          mounts: [],
          contracts: {},
          capability: _installed(names: {'sample.widgets:${'X' * padding}'}),
        );
    final empty = paddedBuild(0);
    final padding = kMaximumPlacementRequestBytes - empty.canonicalBytes.length;
    final atLimit = paddedBuild(padding);
    expect(atLimit.canonicalBytes, hasLength(kMaximumPlacementRequestBytes));
    expect(
      PlacementBuildContractV1.fromCanonicalBytes(atLimit.canonicalBytes),
      atLimit,
    );
    expect(() => paddedBuild(padding + 1), throwsA(_refusal));
    // A bounded child still counts toward the enclosing report's total bound.
    expect(
      () => _report(build: atLimit, mounts: [], bounds: []),
      throwsA(_refusal),
    );
    final declarations = List<PlacementMountRequestV1>.filled(
      kMaximumPlacementRequestBytes,
      _mount(),
    );
    expect(() => _build(mounts: declarations), throwsA(_refusal));
  });
}

SurfaceHostContractV1 _hostContract({bool presented = false}) =>
    SurfaceHostContractV1(
      hosting: SurfaceHostingV1(
        contentKind: SurfaceContentKindV1.single,
        presentation: presented
            ? SurfacePresentationV1.presented
            : SurfacePresentationV1.inline,
      ),
      providedContext: const SurfaceScreenHostDataSchema.empty(),
      handledEvents: SurfaceScreenEventSchema(events: const []),
    );

InstalledCapability _installed({int version = 2, Set<String>? names}) =>
    InstalledCapability(
      builtInCatalogVersion: version,
      installedLibraries: const [],
      vocabulary: names == null ? null : WidgetVocabulary(widgetNames: names),
    );

DeliverySurfaceLocatorV1 _locator({
  String slug = 'welcome',
  DeliverySurfaceTypeId? type,
  DeliveryFamilySelectorV1 family = _general,
}) =>
    DeliverySurfaceLocatorV1(
      surfaceType: type ?? _screenType,
      slug: slug,
      family: family,
    );

PlacementMountRequestV1 _mount({
  PlacementKeyV1? key,
  SurfaceHostContractV1? host,
  DeliverySurfaceLocatorV1? defaultSurface,
  bool useDefault = true,
  DeliverySurfaceTypeId? surfaceType,
}) =>
    PlacementMountRequestV1(
      key: key ??
          PlacementKeyV1.generatedDefault(
            surfaceType: _screenType,
            slug: 'welcome',
          ),
      defaultSurface: defaultSurface ?? (useDefault ? _locator() : null),
      hostContractHash: (host ?? _host).contentHash,
      surfaceType: surfaceType,
    );

PlacementMountDescriptorV1 _descriptor(
  PlacementMountRequestV1 mount, {
  String? hostHash,
  DeliveryFamilySelectorV1? family,
  String surfaceId = 'surface.v1.welcome',
}) =>
    PlacementMountDescriptorV1(
      placement: PlacementIdentityV1(target: _target, key: mount.key),
      defaultSurface: mount.defaultSurface == null
          ? null
          : DeliverySurfaceReferenceV1(
              surfaceIdentity: PublishedSurfaceIdentityV1(
                target: _target,
                surfaceId: SurfaceId(surfaceId),
              ),
              family: family ?? mount.defaultSurface!.family,
            ),
      hostContractHash: hostHash ?? mount.hostContractHash,
    );

PlacementBuildContractV1 _build({
  List<PlacementMountRequestV1>? mounts,
  Map<String, SurfaceHostContractV1>? contracts,
  InstalledCapability? capability,
  String platform = 'ios',
  int? ordinal,
}) =>
    PlacementBuildContractV1(
      platform: platform,
      buildOrdinal: ordinal,
      mounts: mounts ?? [_mount()],
      contractsByHash: contracts ?? {_host.contentHash: _host},
      installedCapability: capability ?? _capability,
      installedCapabilityHash: (capability ?? _capability).contentHash,
    );

PlacementMountBoundsV1 _bounds({
  int index = 0,
  PlacementKeyV1? key,
  SurfaceHostContractV1? host,
  double x = 0,
}) =>
    PlacementMountBoundsV1(
      key: key ?? _mount().key,
      hostContractHash: (host ?? _host).contentHash,
      logicalBounds:
          PlacementLogicalRectV1.fromLogical(x: x, y: 0, width: 40, height: 20),
      logicalViewport:
          PlacementLogicalSizeV1.fromLogical(width: 400, height: 800),
      occurrenceIndex: index,
    );

PlacementDiscoveryReportV1 _report({
  PlacementBuildContractV1? build,
  List<PlacementMountRequestV1>? mounts,
  List<PlacementMountBoundsV1>? bounds,
}) =>
    PlacementDiscoveryReportV1(
      mounts: mounts ?? (build ?? _build()).mounts,
      buildContract: build ?? _build(),
      appBuildContractHash: (build ?? _build()).appBuildContractHash,
      bounds: bounds ?? [_bounds()],
    );

TargetCoordinate _coordinate(int id, {bool sandbox = false}) =>
    TargetCoordinate(
      organizationId: OrganizationId(1),
      appId: ApplicationId(1),
      environmentTargetId: EnvironmentTargetId(id),
      namedEnvironmentId: NamedEnvironmentId(1),
      runtimePlane: sandbox ? RuntimePlane.sandbox : RuntimePlane.live,
    );

void _batchContractTests() {
  group('placement batch and safe delivery', () {
    test('real shared blob fixture retains two correlated decisions once', () {
      final (request, response, target, fixture) = _batchFixture();
      expect(
        request.mounts.map((mount) => mount.key.surfaceType!.value),
        ['general', 'message'],
      );
      expect(
        request.mounts.map((mount) => mount.key.slug),
        ['welcome', 'welcome'],
      );
      expect(response.decisions, hasLength(2));
      expect(response.artifacts, hasLength(1));
      expect(
        response.decisions.map((row) => row.descriptor.placement.key),
        request.mounts.map((mount) => mount.key),
      );
      final rows = response.decisions.cast<PlacementBatchAvailableV1>();
      expect(
        rows[0].artifactClosure.single.identity,
        rows[1].artifactClosure.single.identity,
      );
      expect(
        rows[0].publicDelivery.publicProjectionDigest,
        isNot(rows[1].publicDelivery.publicProjectionDigest),
      );
      final frame = SurfacePayload.decode(response.artifacts.single.bytes)
          as BlobSurfacePayload;
      final library = rfw.decodeLibraryBlob(frame.blob);
      expect(library.widgets.single.name, 'Root');
      expect(library.imports.single.name.parts, ['restage', 'core']);
      expect(
        (library.widgets.single.root as rfw.ConstructorCall).arguments['text'],
        'Welcome',
      );
      expect(
        PlacementBatchRequestV1.fromCanonicalBytes(request.canonicalBytes),
        request,
      );
      expect(
        PlacementBatchResponseV1.fromCanonicalBytes(
          response.canonicalBytes,
          request: request,
          expectedTarget: target,
        ),
        response,
      );
      expect(fixture['response'], response.toJson());
      expect(rows[0].publicDelivery.selectedSurface.family.contractVersion, 7);
      expect(request.mounts[0].defaultSurface!.family.isGeneral, isTrue);
      expect(request.mounts[1].defaultSurface!.family.contractVersion, 3);
    });

    test('public and selection identity domains have independent exact vectors',
        () {
      final (_, response, _, _) = _batchFixture();
      final rows = response.decisions.cast<PlacementBatchAvailableV1>();
      // Independent Python hashlib over compact sorted JSON
      // plus terminated domains.
      expect(
          rows.map(
            (row) => row.publicDelivery.path.selectionIdentityDigest.hex,
          ),
          [
            'e15e2abdfc8c5f33b4474f4437b650a9a88d1a0498acc1aa278395a5d790db71',
            'fc77e71e7f4ee82796476aefddb4c49d0e6c46e0aa7d92f35cf0b5ab66a757d4',
          ]);
      expect(rows.map((row) => row.publicDelivery.publicProjectionDigest.hex), [
        '524614c296721666c4b27bc4e4728555bc636f4d9eccaf660cda3a4dcc48d54e',
        '6d0b3942200c25f56be6d2e4dc8aa126f79fbfe834aa487a3234bd9dd5e9298d',
      ]);
      final delivery = rows.first.publicDelivery;
      final attached = PublicPlacementDeliveryV1.fromJson({
        ...delivery.toJson(),
        'routingSelectionReceipt': 'rsr2.opaque_signature',
        'assignment': PresentationAssignmentCarrierV2(
          owner: PresentationAssignmentOwnerV2.path,
          outcomeLinkCarrier: _base64(List.filled(32, 7)),
        ).toJson(),
      });
      expect(attached.publicProjectionDigest, delivery.publicProjectionDigest);
      expect(
        attached.path.selectionIdentityDigest,
        delivery.path.selectionIdentityDigest,
      );
      final cache = DeliveryCacheValidityV1.fromJson(
        {...delivery.cacheValidity.toJson(), 'contentExpiresAtMicros': 100},
      );
      final changedCache = _copyDelivery(delivery, cache: cache);
      expect(
        changedCache.path.selectionIdentityDigest,
        delivery.path.selectionIdentityDigest,
      );
      expect(
        changedCache.publicProjectionDigest,
        isNot(delivery.publicProjectionDigest),
      );
      final publication = DeliveryPublicationReferenceV1.fromJson(
        {...delivery.actualPublication.toJson(), 'publishedVersion': 10},
      );
      final changedPublication =
          _copyDelivery(delivery, publication: publication);
      expect(
        changedPublication.path.selectionIdentityDigest,
        isNot(delivery.path.selectionIdentityDigest),
      );
      expect(
        changedPublication.publicProjectionDigest,
        isNot(delivery.publicProjectionDigest),
      );
      for (final nonce in [
        CanonicalDigest('1' * 64),
        CanonicalDigest('2' * 64),
      ]) {
        final tuple = MountSelectionAttributionV1(
          resolutionKind: MountResolutionKindV1.hosted,
          evidenceStrength: MountEvidenceStrengthV1.verifiedSelection,
          placementKey: attached.mount.placement.key,
          resolvedTarget: attached.mount.placement.target,
          actualSurface: attached.selectedSurface,
          actualPublication: attached.actualPublication,
          resolvedSelectionDigest: attached.publicProjectionDigest,
          mountNonceDigest: nonce,
        );
        expect(tuple.resolvedSelectionDigest, delivery.publicProjectionDigest);
      }
      expect(
        () => PublicPlacementDeliveryV1.fromJson(
          {...delivery.toJson(), 'publicProjectionDigest': '0' * 64},
        ),
        throwsA(_refusal),
      );
    });

    test('complete fit requirement is mandatory and covered by public digest',
        () {
      final (_, response, _, _) = _batchFixture();
      final delivery = (response.decisions.first as PlacementBatchAvailableV1)
          .publicDelivery;
      final json = delivery.toJson()..remove('fitRequirement');
      expect(
        () => PublicPlacementDeliveryV1.fromJson(json),
        throwsA(_refusal),
      );
      final requirementJson = delivery.fitRequirement.toJson();
      final missingVocabulary = {...requirementJson}
        ..remove('requiredVocabulary');
      for (final malformed in [
        null,
        'opaque',
        missingVocabulary,
        {...requirementJson, 'compilerWitness': true},
        {
          ...requirementJson,
          'hosting': {
            ...delivery.fitRequirement.hosting.toJson(),
            'contentKind': 'unknown',
          },
        },
        {
          ...requirementJson,
          'capabilities': {
            ...delivery.fitRequirement.capabilities.toJson(),
            'builtInFloor': '1',
          },
        },
      ]) {
        expect(
          () => PublicPlacementDeliveryV1.fromJson(
            {...delivery.toJson(), 'fitRequirement': malformed},
          ),
          throwsA(_refusal),
        );
      }
      final requirement = SurfaceFitRequirementV1.fromJson({
        ...requirementJson,
        'capabilities': {
          ...delivery.fitRequirement.capabilities.toJson(),
          'builtInFloor': 2,
        },
      });
      expect(
        () => PublicPlacementDeliveryV1.fromJson(
          {...delivery.toJson(), 'fitRequirement': requirement.toJson()},
        ),
        throwsA(_refusal),
      );
      final changed = _copyDelivery(delivery, requirement: requirement);
      expect(
        changed.publicProjectionDigest,
        isNot(delivery.publicProjectionDigest),
      );
      expect(
        changed.path.selectionIdentityDigest,
        delivery.path.selectionIdentityDigest,
      );
      expect(
        PublicPlacementDeliveryV1.fromCanonicalBytes(changed.canonicalBytes),
        changed,
      );
      expect(identical(changed.fitRequirement, requirement), isFalse);
      expect(
        changed.fitRequirement.hosting.allowedPresentations.clear,
        throwsUnsupportedError,
      );
      expect(
        changed.fitRequirement.requiredVocabulary.widgetNames.clear,
        throwsUnsupportedError,
      );
      final raw = requireCanonicalObject(
        CanonicalJsonCodec.decode(changed.canonicalBytes),
        'publicDelivery',
      );
      final frozen = PublicPlacementDeliveryV1.fromJson(raw);
      final oldBytes = frozen.canonicalBytes;
      requireCanonicalObject(raw['fitRequirement'], 'fitRequirement').clear();
      expect(frozen.canonicalBytes, oldBytes);
    });

    test('fit content kind must match the decoded root artifact', () {
      final payloads = <SurfacePayload>[
        _validPayload(),
        _flowPayload('kind_requirement'),
      ];
      final request = _batch();
      for (var index = 0; index < payloads.length; index++) {
        final payload = payloads[index];
        final entry = _entryFor(request.mounts.single, payload);
        final requirement = _fitRequirement(payloads[1 - index]);
        final delivery =
            _copyDelivery(entry.publicDelivery, requirement: requirement);
        final mismatched = PlacementBatchEntryV1.available(
          entry.descriptor,
          delivery,
          entry.artifactClosure,
        );
        final artifact = _artifact(payload);
        expect(
          () => PlacementBatchResponseV1(
            request: request,
            expectedTarget: _target,
            decisions: [mismatched],
            artifacts: [artifact],
          ),
          throwsA(_refusal),
        );
        expect(
          () => PlacementBatchResponseV1.fromJson(
            {
              'kind': 'placementBatchResponse',
              'schemaVersion': 1,
              'status': 'resolved',
              'decisions': [mismatched.toJson()],
              'artifacts': [artifact.toJson()],
            },
            request: request,
          ),
          throwsA(_refusal),
        );
      }
    });

    test('first authenticated response establishes one consistent target', () {
      final (request, response, target, fixture) = _batchFixture();
      final decoded = PlacementBatchResponseV1.fromCanonicalBytes(
        response.canonicalBytes,
        request: request,
      ) as PlacementBatchResolvedV1;
      expect(decoded, response);
      expect(
        decoded.decisions.map((row) => row.descriptor.placement.target),
        everyElement(target),
      );
      expect(
        PlacementBatchResponseV1.fromJson(
          fixture['response'],
          request: request,
        ),
        response,
      );
    });

    test('response target inference rejects individually valid mixed targets',
        () {
      final (request, response, target, _) = _batchFixture();
      final fallback = PlacementBatchEntryV1.useFallback(
        _descriptor(request.mounts.last),
        PlacementBatchRefusalReasonV1.unavailable,
        [],
      );
      expect(fallback.descriptor.placement.target, isNot(target));
      fallback.descriptor.validateForRequest(
        request.mounts.last,
        expectedTarget: _target,
      );
      final mixed = {
        ...response.toJson(),
        'decisions': [
          response.decisions.first.toJson(),
          fallback.toJson(),
        ],
      };
      expect(
        () => PlacementBatchResponseV1.fromJson(mixed, request: request),
        throwsA(_refusal),
      );
      expect(
        () => PlacementBatchResponseV1.fromCanonicalBytes(
          CanonicalJsonCodec.encode(mixed),
          request: request,
        ),
        throwsA(_refusal),
      );
    });

    test('an explicit response target still rejects mismatch', () {
      final (request, response, _, _) = _batchFixture();
      expect(
        () => PlacementBatchResponseV1.fromCanonicalBytes(
          response.canonicalBytes,
          request: request,
          expectedTarget: _coordinate(99),
        ),
        throwsA(_refusal),
      );
      expect(
        () => PlacementBatchResponseV1.fromJson(
          response.toJson(),
          request: request,
          expectedTarget: _coordinate(99),
        ),
        throwsA(_refusal),
      );
    });

    test('no service body may carry the client-only decodeFailed', () {
      final (request, response, _, _) = _batchFixture();
      final refused = PlacementBatchResponseV1.refused(
        reason: PlacementBatchRefusalReasonV1.decodeFailed,
      );
      expect(
        () => PlacementBatchResponseV1.fromCanonicalBytes(
          refused.canonicalBytes,
          request: request,
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
      expect(
        () => PlacementBatchDiagnosticV1.fromJson(
          {'code': 'decodeFailed', 'detail': null},
        ),
        throwsA(isA<CanonicalFormatException>()),
      );
      final row = response.toJson();
      final decisions = row['decisions']! as List<Object?>;
      final fallback = {
        'descriptor': (decisions.first! as Map)['descriptor'],
        'status': 'useFallback',
        'reason': 'decodeFailed',
        'diagnostics': <Object?>[],
      };
      expect(
        () => PlacementBatchEntryV1.fromJson(fallback),
        throwsA(isA<CanonicalFormatException>()),
      );
    });

    test('refusal and a valid empty response need no target', () {
      final (request, response, _, _) = _batchFixture();
      final refused = PlacementBatchResponseV1.refused(
        reason: PlacementBatchRefusalReasonV1.unknownLocator,
      );
      expect(
        PlacementBatchResponseV1.fromCanonicalBytes(
          refused.canonicalBytes,
          request: request,
        ),
        refused,
      );
      expect(
        PlacementBatchResponseV1.fromJson(
          refused.toJson(),
          request: request,
        ),
        refused,
      );
      final emptyRequest = _batch(
        mounts: [],
        build: _build(mounts: [], contracts: {}),
      );
      final emptyResponse = PlacementBatchResponseV1(
        request: emptyRequest,
        expectedTarget: _target,
        decisions: [],
        artifacts: [],
      );
      expect(
        PlacementBatchResponseV1.fromCanonicalBytes(
          emptyResponse.canonicalBytes,
          request: emptyRequest,
        ),
        emptyResponse,
      );
      expect(
        PlacementBatchResponseV1.fromJson(
          emptyResponse.toJson(),
          request: emptyRequest,
        ),
        emptyResponse,
      );
      expect(
        () => PlacementBatchResponseV1.fromCanonicalBytes(
          emptyResponse.canonicalBytes,
          request: request,
        ),
        throwsA(_refusal),
      );
      expect(
        () => PlacementBatchResponseV1.fromJson(
          {
            ...emptyResponse.toJson(),
            'artifacts': [response.artifacts.single.toJson()],
          },
          request: emptyRequest,
        ),
        throwsA(_refusal),
      );
    });

    test('all rows retain count order target host and fallback correlation',
        () {
      final (request, response, target, _) = _batchFixture();
      final fallback = PlacementBatchEntryV1.useFallback(
          response.decisions[1].descriptor,
          PlacementBatchRefusalReasonV1.unavailable, [
        PlacementBatchDiagnosticV1(
          code: PlacementBatchRefusalReasonV1.unavailable,
        ),
      ]);
      final mixed = PlacementBatchResponseV1(
        request: request,
        expectedTarget: target,
        decisions: [response.decisions.first, fallback],
        artifacts: response.artifacts,
      ) as PlacementBatchResolvedV1;
      expect(mixed.decisions.last, isA<PlacementBatchUseFallbackV1>());
      expect(
        mixed.decisions.last.descriptor,
        response.decisions.last.descriptor,
      );
      for (final rows in [
        [response.decisions.first],
        [response.decisions.first, response.decisions.first],
        response.decisions.reversed.toList(),
        [fallback, response.decisions.first],
      ]) {
        expect(
          () => PlacementBatchResponseV1(
            request: request,
            expectedTarget: target,
            decisions: rows,
            artifacts: response.artifacts,
          ),
          throwsA(_refusal),
        );
      }
      final wrongHost = PlacementBatchEntryV1.useFallback(
        _descriptor(
          request.mounts[1],
          hostHash: _hostContract(presented: true).contentHash,
        ),
        PlacementBatchRefusalReasonV1.unavailable,
        [],
      );
      expect(
        () => PlacementBatchResponseV1(
          request: request,
          expectedTarget: target,
          decisions: [response.decisions.first, wrongHost],
          artifacts: response.artifacts,
        ),
        throwsA(_refusal),
      );
      expect(
        () => PlacementBatchResponseV1.fromCanonicalBytes(
          response.canonicalBytes,
          request: request,
          expectedTarget: _coordinate(99),
        ),
        throwsA(_refusal),
      );
      final refused = PlacementBatchResponseV1.refused(
        reason: PlacementBatchRefusalReasonV1.unknownLocator,
      );
      expect(refused.toJson().containsKey('decisions'), isFalse);
      expect(
        PlacementBatchResponseV1.fromCanonicalBytes(
          refused.canonicalBytes,
          request: request,
          expectedTarget: target,
        ),
        refused,
      );
      expect(
        () => PlacementBatchResponseV1.refused(
          reason: PlacementBatchRefusalReasonV1.unavailable,
        ),
        throwsA(_refusal),
      );
    });

    test('changed default family or declaration cannot correlate to old rows',
        () {
      final (request, response, target, _) = _batchFixture();
      final changed = PlacementMountRequestV1(
        key: request.mounts.first.key,
        hostContractHash: request.mounts.first.hostContractHash,
        defaultSurface: DeliverySurfaceLocatorV1(
          surfaceType: request.mounts.first.defaultSurface!.surfaceType,
          slug: 'welcome',
          family: DeliveryFamilySelectorV1.screenContract(contractVersion: 2),
        ),
      );
      final changedBuild = _build(mounts: [changed, request.mounts.last]);
      final changedRequest =
          _batch(mounts: [changed, request.mounts.last], build: changedBuild);
      expect(
        () => PlacementBatchResponseV1(
          request: changedRequest,
          expectedTarget: target,
          decisions: response.decisions,
          artifacts: response.artifacts,
        ),
        throwsA(_refusal),
      );
      expect(
        () => _batch(mounts: [changed], build: request.buildContract),
        throwsA(_refusal),
      );
      expect(
        () => _batch(
          mounts: [request.mounts.first, request.mounts.first],
          build: request.buildContract,
        ),
        throwsA(_refusal),
      );
      final widgetOnly = _mount(
        key: PlacementKeyV1.named(slug: 'widget_only'),
        useDefault: false,
      );
      expect(
        _batch(mounts: [widgetOnly], build: _build(mounts: [widgetOnly]))
            .mounts
            .single
            .defaultSurface,
        isNull,
      );
    });

    test('prefetch stays keyless and permits current metering and analytics',
        () {
      final request = _batch(
        meteringKey: '00000000-0000-4000-8000-000000000001',
        analyticsAnonymousId: '00000000-0000-4000-8000-000000000002',
      );
      expect(request.localClock, isNull);
      expect(request.toJson().containsKey('assignmentKey'), isFalse);
      expect(request.toJson().containsKey('registrationNonce'), isFalse);
      expect(request.heldAssignments, isEmpty);
      expect(
        PlacementBatchRequestV1.fromCanonicalBytes(request.canonicalBytes),
        request,
      );
      final proof = PlacementHeldAssignmentV1(
        key: request.mounts.single.key,
        hostContractHash: _host.contentHash,
        retainedPathHandle: _base64(List.filled(32, 7)),
      );
      for (final create in <PlacementBatchRequestV1 Function()>[
        () => _batch(assignmentKey: 'ic1.${'a' * 64}'),
        () => _batch(registration: _registrationTuple()),
        () => _batch(heldAssignments: [proof]),
      ]) {
        expect(create, throwsA(_refusal));
      }
      final mounting = _batch(
        mode: PlacementBatchModeV1.mount,
        assignmentKey: 'ic1.${'a' * 64}',
        heldAssignments: [proof],
      );
      expect(
        PlacementBatchRequestV1.fromCanonicalBytes(mounting.canonicalBytes),
        mounting,
      );
    });

    test('held proofs bind only requested key and host without global replay',
        () {
      final first = _mount();
      final second = _mount(key: PlacementKeyV1.named(slug: 'second'));
      final build = _build(mounts: [first, second]);
      final proof = PlacementHeldAssignmentV1(
        key: first.key,
        hostContractHash: first.hostContractHash,
        retainedPathHandle: _base64(List.filled(32, 1)),
      );
      final other = PlacementHeldAssignmentV1(
        key: second.key,
        hostContractHash: second.hostContractHash,
        retainedPathHandle: _base64(List.filled(32, 2)),
      );
      final request = _batch(
        mounts: [second, first],
        build: build,
        mode: PlacementBatchModeV1.mount,
        heldAssignments: [other, proof],
      );
      expect(request.mounts.map((mount) => mount.key), [second.key, first.key]);
      expect(request.heldAssignments, hasLength(2));
      expect(
        () => _batch(
          mounts: [first],
          build: build,
          mode: PlacementBatchModeV1.mount,
          heldAssignments: [other],
        ),
        throwsA(_refusal),
      );
      expect(
        () => _batch(
          mounts: [first, second],
          build: build,
          mode: PlacementBatchModeV1.mount,
          heldAssignments: [proof, proof],
        ),
        throwsA(_refusal),
      );
      expect(
        () => PlacementBatchRequestV1.fromJson({
          ...request.toJson(),
          'retainedPathHandle': proof.retainedPathHandle,
        }),
        throwsA(_refusal),
      );
      expect(
        () => PlacementHeldAssignmentV1(
          key: first.key,
          hostContractHash: first.hostContractHash,
          retainedPathHandle: '${proof.retainedPathHandle}=',
        ),
        throwsA(_refusal),
      );
    });

    test('retained path proof echoes the returned opaque32 handle', () {
      final mount = _mount();
      final returned = PresentationAssignmentCarrierV2(
        owner: PresentationAssignmentOwnerV2.path,
        outcomeLinkCarrier: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
      );
      final proof = PlacementHeldAssignmentV1(
        key: mount.key,
        hostContractHash: mount.hostContractHash,
        retainedPathHandle: returned.outcomeLinkCarrier,
      );
      expect(proof.retainedPathHandle, returned.outcomeLinkCarrier);
      expect(
        proof.toJson(),
        {
          'key': mount.key.toJson(),
          'hostContractHash': mount.hostContractHash,
          'retainedPathHandle': returned.outcomeLinkCarrier,
        },
      );
      expect(
        PlacementHeldAssignmentV1.fromCanonicalBytes(proof.canonicalBytes),
        proof,
      );
      for (final mode in [
        PlacementBatchModeV1.mount,
        PlacementBatchModeV1.refresh,
      ]) {
        final request = _batch(mode: mode, heldAssignments: [proof]);
        expect(
          PlacementBatchRequestV1.fromCanonicalBytes(request.canonicalBytes),
          request,
        );
        expect(
          request.heldAssignments.single.retainedPathHandle,
          returned.outcomeLinkCarrier,
        );
        expect(
          () => _batch(mode: mode, heldAssignments: [proof, proof]),
          throwsA(_refusal),
        );
      }
      final mounting = _batch(
        mode: PlacementBatchModeV1.mount,
        heldAssignments: [proof],
      );
      for (final invalid in [
        _base64(List.filled(31, 1)),
        _base64(List.filled(33, 1)),
        '',
        '${returned.outcomeLinkCarrier}=',
        '${returned.outcomeLinkCarrier.substring(0, 42)}9',
        'ordinary-readable-assignment',
        _base64(CanonicalJsonCodec.encode({'held': 'original'})),
        _base64(returned.canonicalBytes),
        'A' * (measurementOutcomeLinkCarrierMaximumLength + 1),
      ]) {
        final wire = {...proof.toJson(), 'retainedPathHandle': invalid};
        expect(
          () => PlacementHeldAssignmentV1(
            key: mount.key,
            hostContractHash: mount.hostContractHash,
            retainedPathHandle: invalid,
          ),
          throwsA(_refusal),
        );
        expect(
          () => PlacementHeldAssignmentV1.fromJson(wire),
          throwsA(_refusal),
        );
        expect(
          () => PlacementBatchRequestV1.fromCanonicalBytes(
            CanonicalJsonCodec.encode({
              ...mounting.toJson(),
              'heldAssignments': [wire],
            }),
          ),
          throwsA(_refusal),
        );
      }
      final former = _base64(CanonicalJsonCodec.encode({'held': 'original'}));
      for (final wire in [
        {
          'key': mount.key.toJson(),
          'hostContractHash': mount.hostContractHash,
          'assignmentCanonicalBase64': former,
        },
        {...proof.toJson(), 'assignmentCanonicalBase64': former},
        {...proof.toJson()}..remove('retainedPathHandle'),
      ]) {
        expect(
          () => PlacementHeldAssignmentV1.fromJson(wire),
          throwsA(_refusal),
        );
      }
      final bytes = proof.canonicalBytes;
      proof.toJson().clear();
      expect(proof.canonicalBytes, bytes);
    });

    test('refresh retains existing held inputs and forbids registration', () {
      final (original, response, target, _) = _batchFixture();
      final mount = original.mounts.first;
      final proof = PlacementHeldAssignmentV1(
        key: mount.key,
        hostContractHash: mount.hostContractHash,
        retainedPathHandle: _base64(List.filled(32, 3)),
      );
      final clock = DeliveryLocalClockV1(-300);
      final request = PlacementBatchRequestV1.fromJson({
        ...original.toJson(),
        'mode': 'refresh',
        'assignmentKey': 'ic1.${'a' * 64}',
        'heldAssignments': [proof.toJson()],
        'heldArtifacts': [response.artifacts.single.identity.toJson()],
        'localClock': clock.toJson(),
      });
      expect(request.mode, PlacementBatchModeV1.refresh);
      expect(request.mounts, original.mounts);
      expect(request.assignmentKey, 'ic1.${'a' * 64}');
      expect(request.heldAssignments, [proof]);
      expect(request.localClock, clock);
      expect(
        PlacementBatchRequestV1.fromCanonicalBytes(request.canonicalBytes),
        request,
      );
      for (final create in <PlacementBatchRequestV1 Function()>[
        () => _batch(
              mode: PlacementBatchModeV1.refresh,
              registration: _registrationTuple(),
            ),
        () => PlacementBatchRequestV1.fromJson({
              ...request.toJson(),
              ..._registrationTuple().toJson(),
            }),
      ]) {
        expect(create, throwsA(_refusal));
      }
      for (final encoded in [
        {...response.toJson(), ..._registrationMetadata().toJson()},
        {
          ...PlacementBatchResponseV1.refused(
            reason: PlacementBatchRefusalReasonV1.invalidAuthority,
          ).toJson(),
          ..._registrationMetadata().toJson(),
        },
      ]) {
        expect(
          () => PlacementBatchResponseV1.fromJson(
            encoded,
            request: request,
            expectedTarget: target,
          ),
          throwsA(_refusal),
        );
      }
    });

    test(
        'folded registration confirms mount request with original exact fields',
        () {
      final mount = _mount();
      final request = _batch(
        mode: PlacementBatchModeV1.mount,
        registration: _registrationTuple(),
      );
      final row = PlacementBatchEntryV1.useFallback(
        _descriptor(mount),
        PlacementBatchRefusalReasonV1.unavailable,
        [],
      );
      final metadata = _registrationMetadata();
      final response = PlacementBatchResponseV1(
        request: request,
        expectedTarget: _target,
        decisions: [row],
        artifacts: [],
        registration: metadata,
      ) as PlacementBatchResolvedV1;
      expect(response.toJson()['credentialHandle'], metadata.credentialHandle);
      expect(response.toJson()['expiresAtMicros'], metadata.expiresAtMicros);
      expect(response.toJson()['serverNowMicros'], metadata.serverNowMicros);
      expect(
        PlacementBatchResponseV1.fromCanonicalBytes(
          response.canonicalBytes,
          request: request,
          expectedTarget: _target,
        ),
        response,
      );
      for (final field in [
        'registrationNonce',
        'registrationCreatedAtMicros',
      ]) {
        final partial = request.toJson()..remove(field);
        expect(
          () => PlacementBatchRequestV1.fromJson(partial),
          throwsA(_refusal),
        );
      }
      for (final field in metadata.toJson().keys) {
        final partial = response.toJson()..remove(field);
        expect(
          () => PlacementBatchResponseV1.fromJson(
            partial,
            request: request,
            expectedTarget: _target,
          ),
          throwsA(_refusal),
        );
      }
      expect(
        () => PlacementBatchResponseV1.fromJson(
          response.toJson(),
          request: _batch(),
          expectedTarget: _target,
        ),
        throwsA(_refusal),
      );
    });

    test('library report metadata preserves placement capability correlation',
        () {
      final build = _batch().buildContract;
      final catalog = build.installedCapability.builtInCatalogVersion;
      final report = SdkInstalledLibrariesV1(
        libraries: const [],
        builtInCatalogVersion: catalog,
        appVersion: '2.4.1',
      );
      final request =
          _batch(sdkInstalledLibraries: _base64(report.canonicalBytes));
      expect(
        PlacementBatchRequestV1.fromCanonicalBytes(request.canonicalBytes),
        request,
      );
      expect(
        () => _batch(
          sdkInstalledLibraries: _base64(
            SdkInstalledLibrariesV1(
              libraries: const [],
              builtInCatalogVersion: catalog + 1,
              appVersion: '2.4.1',
            ).canonicalBytes,
          ),
        ),
        throwsA(_refusal),
      );
    });

    test(
        'library and policy carriers use '
        'existing codecs and built-ins stay opaque', () {
      final report = SdkInstalledLibrariesV1(libraries: const []);
      final policy = SdkSupportedPolicyRevisionsV1(
        sdkVersion: '2.0.0',
        assignmentApiLevel: 4,
        platform: 'ios',
        privacyPolicyFloor: 0,
        collectionBudgetFloor: 0,
      );
      final request = _batch(
        sdkInstalledLibraries: _base64(report.canonicalBytes),
        sdkSupportedPolicyRevisions: _base64(policy.canonicalBytes),
        sdkBuiltInsCanonicalBase64: _base64(
          CanonicalJsonCodec.encode({'opaqueBuiltInObservation': 1}),
        ),
      );
      expect(
        PlacementBatchRequestV1.fromCanonicalBytes(request.canonicalBytes),
        request,
      );
      for (final carrier in ['A', 'e30=', _base64(utf8.encode('{ "x":1}'))]) {
        expect(
          () => _batch(sdkBuiltInsCanonicalBase64: carrier),
          throwsA(_refusal),
        );
      }
      expect(
        () => _batch(
          sdkInstalledLibraries: _base64(
            SdkInstalledLibrariesV1(
              libraries: [
                SdkInstalledLibraryV1(
                  namespace: 'sample.widgets',
                  version: 1,
                  compatibleSince: 1,
                ),
              ],
            ).canonicalBytes,
          ),
        ),
        throwsA(_refusal),
      );
      expect(
        () => _batch(
          sdkSupportedPolicyRevisions:
              'A' * (sdkSupportedPolicyRevisionsMaximumCarrierCharacters + 1),
        ),
        throwsA(_refusal),
      );
    });

    test('safe path cache joins and immutable sorted watch set are exact', () {
      final (_, response, _, _) = _batchFixture();
      final delivery = (response.decisions.first as PlacementBatchAvailableV1)
          .publicDelivery;
      final closure = delivery.dependencyClosure;
      final encoded = DeliveryDependencyClosureV1Codec.encode(closure);
      expect(DeliveryDependencyClosureV1Codec.decode(encoded), closure);
      expect(
        () => DeliveryDependencyClosureV1Codec.decode(
          [...encoded, encoded.first],
        ),
        throwsA(_refusal),
      );
      expect(
        () => DeliveryDependencyClosureV1Codec.decode(
          encoded.reversed.toList(),
        ),
        throwsA(_refusal),
      );
      expect(
        () => _copyDelivery(delivery, dependencies: {}),
        throwsA(_refusal),
      );
      final wrongScope = DeliveryPolicyScopeV1(
        root: DeliveryRootIdentityV1.surface(
          PublishedSurfaceIdentityV1(
            target: delivery.selectedSurface.target,
            surfaceId: SurfaceId('surface.v1.other'),
          ),
        ),
        family: _general,
      );
      final wrongCache = DeliveryCacheValidityV1.fromJson({
        ...delivery.cacheValidity.toJson(),
        'policySelections': [_policySelection(wrongScope).toJson()],
      });
      expect(
        () => _copyDelivery(delivery, cache: wrongCache),
        throwsA(_refusal),
      );
      final rightCache = DeliveryCacheValidityV1.fromJson({
        ...delivery.cacheValidity.toJson(),
        'policySelections': [
          for (final step in delivery.path.steps)
            _policySelection(step.scope).toJson(),
        ],
      });
      expect(
        _copyDelivery(delivery, cache: rightCache)
            .cacheValidity
            .policySelections,
        hasLength(2),
      );
      final direct = PublicDeliveryDecisionPathV1(
        steps: [delivery.path.steps.last],
        actualPublication: delivery.actualPublication,
      );
      expect(
        PublicDeliveryDecisionPathV1.fromCanonicalBytes(
          direct.canonicalBytes,
        ),
        direct,
      );
      expect(
        () => PublicPlacementDeliveryV1(
          mount: delivery.mount,
          path: direct,
          selectedSurface: delivery.selectedSurface,
          actualPublication: delivery.actualPublication,
          fitRequirement: delivery.fitRequirement,
          cacheValidity: delivery.cacheValidity,
          dependencyClosure: delivery.dependencyClosure,
        ),
        throwsA(_refusal),
      );
      final oldBytes = delivery.canonicalBytes;
      delivery.toJson().clear();
      expect(delivery.canonicalBytes, oldBytes);
      expect(closure.clear, throwsUnsupportedError);
      expect(delivery.path.steps.clear, throwsUnsupportedError);
      expect(response.decisions.clear, throwsUnsupportedError);
      expect(response.artifacts.clear, throwsUnsupportedError);
      final bytes = response.artifacts.single.bytes;
      bytes[0] ^= 0xff;
      expect(response.artifacts.single.bytes[0], isNot(bytes[0]));
    });

    test(
        'optional watch preserves fixture bytes and public projection identity',
        () {
      final (request, response, target, fixture) = _batchFixture();
      final row = response.decisions.first as PlacementBatchAvailableV1;
      expect(row.watch, isNull);
      expect(row.toJson().containsKey('watch'), isFalse);
      expect(
        response.canonicalBytes,
        CanonicalJsonCodec.encode(fixture['response']),
      );
      final watched = PlacementBatchEntryV1.available(
        row.descriptor,
        row.publicDelivery,
        row.artifactClosure,
        watch: _watchFor(row.publicDelivery),
      ) as PlacementBatchAvailableV1;
      final rotated = PlacementBatchAvailableV1(
        row.descriptor,
        row.publicDelivery,
        row.artifactClosure,
        watch: _watchFor(row.publicDelivery, token: _rotatedWatchToken),
      );
      expect(watched.watch, isNotNull);
      expect(watched.canonicalBytes, isNot(rotated.canonicalBytes));
      expect(
        watched.publicDelivery.canonicalBytes,
        row.publicDelivery.canonicalBytes,
      );
      expect(
        rotated.publicDelivery.publicProjectionDigest,
        row.publicDelivery.publicProjectionDigest,
      );
      final complete = PlacementBatchResponseV1(
        request: request,
        expectedTarget: target,
        decisions: [watched, response.decisions.last],
        artifacts: response.artifacts,
      );
      expect(
        PlacementBatchResponseV1.fromCanonicalBytes(
          complete.canonicalBytes,
          request: request,
        ),
        complete,
      );
    });

    test('watch covers skipped candidates in the complete dependency closure',
        () {
      final (_, response, target, _) = _batchFixture();
      final row = response.decisions.first as PlacementBatchAvailableV1;
      final skipped = _watchSurfaceScope(target, 'surface.v1.skipped');
      final delivery = _copyDelivery(
        row.publicDelivery,
        dependencies: {...row.publicDelivery.dependencyClosure, skipped},
      );
      final watch = _watchFor(delivery);
      final complete = PlacementBatchAvailableV1(
        row.descriptor,
        delivery,
        row.artifactClosure,
        watch: watch,
      );
      expect(
        complete.watch!.channels.map((channel) => channel.scope),
        contains(skipped),
      );
      expect(
        complete.watch!.channels.map((channel) => channel.scope),
        delivery.dependencyClosure,
      );
      expect(
        () => PlacementBatchAvailableV1(
          row.descriptor,
          delivery,
          row.artifactClosure,
          watch: _watchFor(row.publicDelivery),
        ),
        throwsA(_refusal),
      );
      final missing = PlacementDeliveryWatchV1(
        decisionIdentityDigest: watch.decisionIdentityDigest,
        channels: watch.channels
            .where((channel) => channel.scope != skipped)
            .toList(),
      );
      expect(
        () => PlacementBatchEntryV1.fromJson({
          ...complete.toJson(),
          'watch': missing.toJson(),
        }),
        throwsA(_refusal),
      );
      expect(
        () => PlacementBatchAvailableV1(
          row.descriptor,
          row.publicDelivery,
          row.artifactClosure,
          watch: watch,
        ),
        throwsA(_refusal),
      );
      final substituted = PlacementDeliveryWatchV1(
        decisionIdentityDigest: watch.decisionIdentityDigest,
        channels: [
          for (final channel in watch.channels)
            if (channel.scope == skipped)
              PlacementDeliveryWatchChannelV1(
                scope: _watchSurfaceScope(target, 'surface.v1.unrequested'),
                token: channel.token,
              )
            else
              channel,
        ],
      );
      expect(substituted.channels, hasLength(watch.channels.length));
      expect(
        () => PlacementBatchAvailableV1(
          row.descriptor,
          delivery,
          row.artifactClosure,
          watch: substituted,
        ),
        throwsA(_refusal),
      );
    });

    test('a fallback watches only its own placement scope', () {
      final (request, _, _, _) = _batchFixture();
      final descriptor = _descriptor(request.mounts.first);
      final own = DeliveryPolicyScopeV1(
        root: DeliveryRootIdentityV1.placement(descriptor.placement),
        family: const DeliveryFamilySelectorV1.none(),
      );
      PlacementDeliveryWatchV1 watching(DeliveryPolicyScopeV1 scope) =>
          PlacementDeliveryWatchV1(
            decisionIdentityDigest: CanonicalDigest('d' * 64),
            channels: [
              PlacementDeliveryWatchChannelV1(scope: scope, token: _watchToken),
            ],
          );
      final fallback = PlacementBatchEntryV1.useFallback(
        descriptor,
        PlacementBatchRefusalReasonV1.unavailable,
        [],
        watch: watching(own),
      ) as PlacementBatchUseFallbackV1;
      expect(fallback.fallbackWatchScope, own);
      expect(PlacementBatchEntryV1.fromJson(fallback.toJson()), fallback);
      final other = DeliveryPolicyScopeV1(
        root: DeliveryRootIdentityV1.placement(
          PlacementIdentityV1(
            target: descriptor.placement.target,
            key: PlacementKeyV1.named(slug: 'other'),
          ),
        ),
        family: const DeliveryFamilySelectorV1.none(),
      );
      expect(
        () => PlacementBatchEntryV1.useFallback(
          descriptor,
          PlacementBatchRefusalReasonV1.unavailable,
          [],
          watch: watching(other),
        ),
        throwsA(_refusal),
      );
      expect(
        PlacementBatchEntryV1.useFallback(
          descriptor,
          PlacementBatchRefusalReasonV1.unavailable,
          [],
        ).toJson(),
        isNot(contains('watch')),
      );
    });

    test('watch channels freeze scope order and reject duplicates or targets',
        () {
      final (_, response, target, _) = _batchFixture();
      final row = response.decisions.first as PlacementBatchAvailableV1;
      final expectedScopes = row.publicDelivery.dependencyClosure;
      final channels = [
        for (final scope in expectedScopes.toList().reversed)
          PlacementDeliveryWatchChannelV1(scope: scope, token: _watchToken),
      ];
      final watch = PlacementDeliveryWatchV1(
        decisionIdentityDigest: CanonicalDigest('c' * 64),
        channels: channels,
      );
      channels.clear();
      expect(watch.channels.map((channel) => channel.scope), expectedScopes);
      expect(watch.channels.clear, throwsUnsupportedError);
      final bytes = watch.canonicalBytes;
      watch.toJson().clear();
      watch.channels.first.toJson().clear();
      expect(watch.canonicalBytes, bytes);
      expect(
        PlacementDeliveryWatchV1.fromCanonicalBytes(bytes),
        watch,
      );
      expect(
        PlacementDeliveryWatchChannelV1.fromCanonicalBytes(
          watch.channels.first.canonicalBytes,
        ),
        watch.channels.first,
      );
      for (final invalid in [
        [...watch.channels, watch.channels.first],
        [
          ...watch.channels,
          PlacementDeliveryWatchChannelV1(
            scope: _watchSurfaceScope(_coordinate(99), 'surface.v1.other'),
            token: _watchToken,
          ),
        ],
      ]) {
        expect(
          () => PlacementDeliveryWatchV1(
            decisionIdentityDigest: watch.decisionIdentityDigest,
            channels: invalid,
          ),
          throwsA(_refusal),
        );
        expect(
          () => PlacementDeliveryWatchV1.fromJson({
            ...watch.toJson(),
            'channels': [for (final channel in invalid) channel.toJson()],
          }),
          throwsA(_refusal),
        );
      }
      expect(
        () => PlacementDeliveryWatchV1.fromJson({
          ...watch.toJson(),
          'channels': [
            for (final channel in watch.channels.reversed) channel.toJson(),
          ],
        }),
        throwsA(_refusal),
      );
      final foreign = PlacementDeliveryWatchV1(
        decisionIdentityDigest: watch.decisionIdentityDigest,
        channels: [
          PlacementDeliveryWatchChannelV1(
            scope: _watchSurfaceScope(_coordinate(99), 'surface.v1.foreign'),
            token: _watchToken,
          ),
        ],
      );
      expect(
        () => PlacementBatchAvailableV1(
          row.descriptor,
          row.publicDelivery,
          row.artifactClosure,
          watch: foreign,
        ),
        throwsA(_refusal),
      );
      expect(expectedScopes.every((scope) => scope.target == target), isTrue);
    });

    test('watch wire is closed and cannot attach to refusal or fallback', () {
      final (request, response, target, _) = _batchFixture();
      final row = response.decisions.first as PlacementBatchAvailableV1;
      final watch = _watchFor(row.publicDelivery);
      for (final invalid in [
        {...watch.toJson(), 'decisionDigest': watch.decisionIdentityDigest.hex},
        {...watch.toJson(), 'dependencyGenerations': <Object?>[]},
        {...watch.toJson(), 'assignmentCanonicalBase64': 'opaque'},
        {...watch.toJson()}..remove('decisionIdentityDigest'),
        {...watch.toJson()}..remove('channels'),
        {...watch.toJson(), 'decisionIdentityDigest': 'C' * 64},
        {...watch.toJson(), 'decisionIdentityDigest': 'sha256:${'c' * 64}'},
        {...watch.toJson(), 'decisionIdentityDigest': null},
      ]) {
        expect(
          () => PlacementDeliveryWatchV1.fromJson(invalid),
          throwsA(_refusal),
        );
      }
      for (final invalid in [
        {...watch.channels.first.toJson(), 'channel': 'derived-channel'},
        {...watch.channels.first.toJson()}..remove('scope'),
        {...watch.channels.first.toJson()}..remove('token'),
        {...watch.channels.first.toJson(), 'token': null},
      ]) {
        expect(
          () => PlacementDeliveryWatchChannelV1.fromJson(invalid),
          throwsA(_refusal),
        );
      }
      expect(
        () => PlacementBatchEntryV1.fromJson({...row.toJson(), 'watch': null}),
        throwsA(_refusal),
      );
      final fallback = PlacementBatchEntryV1.useFallback(
        row.descriptor,
        PlacementBatchRefusalReasonV1.unavailable,
        [],
      );
      expect(
        () => PlacementBatchEntryV1.fromJson({
          ...fallback.toJson(),
          'watch': watch.toJson(),
        }),
        throwsA(_refusal),
      );
      final refused = PlacementBatchResponseV1.refused(
        reason: PlacementBatchRefusalReasonV1.invalidAuthority,
      );
      expect(
        () => PlacementBatchResponseV1.fromJson(
          {...refused.toJson(), 'watch': watch.toJson()},
          request: request,
          expectedTarget: target,
        ),
        throwsA(_refusal),
      );
    });

    test('watch tokens accept existing vectors and bound only their wire shape',
        () {
      final scope = _watchSurfaceScope(_coordinate(42), 'surface.v1.welcome');
      for (final token in [
        _watchToken,
        _rotatedWatchToken,
        _unicodeWatchToken,
      ]) {
        expect(
          PlacementDeliveryWatchChannelV1(scope: scope, token: token).token,
          token,
        );
      }
      final parts = _watchToken.split('.');
      String replacePart(int index, String part) =>
          ([...parts]..[index] = part).join('.');
      for (final token in [
        '',
        'opaque',
        '$_watchToken.extra',
        replacePart(0, 'v1'),
        replacePart(1, 'short'),
        replacePart(1, 'bad/key!'),
        replacePart(2, '0'),
        replacePart(2, '-1'),
        replacePart(2, '01767229200'),
        replacePart(2, '9007199254740992'),
        replacePart(2, '1e9'),
        replacePart(3, ''),
        replacePart(3, '${parts[3]}='),
        replacePart(3, 'A'),
        replacePart(3, _base64([0xff])),
        replacePart(4, 'A' * 42),
        replacePart(4, 'A' * 44),
        replacePart(4, '${parts[4].substring(0, 42)}B'),
        replacePart(4, '${parts[4]}='),
        replacePart(3, _base64(utf8.encode('x' * (16 * 1024)))),
      ]) {
        expect(
          () => PlacementDeliveryWatchChannelV1(scope: scope, token: token),
          throwsA(_refusal),
          reason: token.length > 200 ? 'oversized token' : token,
        );
        expect(
          () => PlacementDeliveryWatchChannelV1.fromJson({
            'scope': scope.toJson(),
            'token': token,
          }),
          throwsA(_refusal),
        );
      }
      final boundParts = [...parts]
        ..[2] = '17672292000'
        ..[3] = _base64(utf8.encode('x' * 12237));
      final atBound = boundParts.join('.');
      expect(atBound.length, 16 * 1024);
      expect(
        PlacementDeliveryWatchChannelV1(scope: scope, token: atBound).token,
        atBound,
      );
      expect(
        () =>
            PlacementDeliveryWatchChannelV1(scope: scope, token: '${atBound}A'),
        throwsA(_refusal),
      );
    });

    test('watch metadata shares the existing response byte budget', () {
      final parts = _watchToken.split('.');
      parts[2] = '17672292000';
      parts[3] = _base64(utf8.encode('x' * 12237));
      final token = parts.join('.');
      final channels = [
        for (var index = 0; index < 2100; index++)
          PlacementDeliveryWatchChannelV1(
            scope: _watchSurfaceScope(_target, 'surface.v1.watched_$index'),
            token: token,
          ),
      ];
      expect(
        () => PlacementDeliveryWatchV1(
          decisionIdentityDigest: CanonicalDigest('c' * 64),
          channels: channels,
        ),
        throwsA(
          _refusal.having(
            (error) => error.message,
            'response budget',
            contains('exceeds'),
          ),
        ),
      );
    });

    test('missing duplicate conflicting and mismatched content closure refuses',
        () {
      final (request, response, target, _) = _batchFixture();
      final artifact = response.artifacts.single;
      expect(
        () => PlacementBatchResponseV1(
          request: request,
          expectedTarget: target,
          decisions: response.decisions,
          artifacts: [],
        ),
        throwsA(_refusal),
      );
      expect(
        () => PlacementBatchResponseV1(
          request: request,
          expectedTarget: target,
          decisions: response.decisions,
          artifacts: [artifact, artifact],
        ),
        throwsA(_refusal),
      );
      final otherValidFrame = _validPayload(text: 'Different valid frame');
      expect(
        () => PlacementBatchArtifactV1(
          identity: artifact.identity,
          bytes: otherValidFrame.canonicalBytes,
        ),
        throwsA(_refusal),
      );
      final bytes = artifact.bytes..[0] ^= 1;
      expect(
        () => PlacementBatchArtifactV1(
          identity: artifact.identity,
          bytes: bytes,
        ),
        throwsA(_refusal),
      );
      final available = response.decisions.first as PlacementBatchAvailableV1;
      final ref = available.artifactClosure.single;
      expect(
        () => PlacementBatchEntryV1.available(
          available.descriptor,
          available.publicDelivery,
          [],
        ),
        throwsA(_refusal),
      );
      expect(
        () => PlacementBatchEntryV1.available(
          available.descriptor,
          available.publicDelivery,
          [ref, ref],
        ),
        throwsA(_refusal),
      );
      expect(
        () => PlacementArtifactReferenceV1.fromJson({
          ...ref.toJson(),
          'descriptor': {
            ...ref.descriptor.toJson(),
            'contentHash': 'sha256:${'0' * 64}',
          },
        }),
        throwsA(_refusal),
      );
      final wrongKind = PlacementArtifactReferenceV1(
        publication: ref.publication!,
        descriptor: SurfaceArtifactDescriptorV1Codec.decode(
          {...ref.descriptor.toJson(), 'payloadKind': 'flow'},
        ),
      );
      expect(
        () => PlacementBatchResponseV1(
          request: request,
          expectedTarget: target,
          decisions: [
            PlacementBatchEntryV1.available(
              available.descriptor,
              available.publicDelivery,
              [wrongKind],
            ),
            response.decisions.last,
          ],
          artifacts: response.artifacts,
        ),
        throwsA(_refusal),
      );
      final conflictingMounts = [
        _mount(),
        _mount(key: PlacementKeyV1.named(slug: 'second')),
      ];
      final conflictingRequest = _batch(
        mounts: conflictingMounts,
        build: _build(mounts: conflictingMounts),
      );
      final one = _validPayload(text: 'One');
      final two = _validPayload(text: 'Two');
      expect(
        () => PlacementBatchResponseV1(
          request: conflictingRequest,
          expectedTarget: _target,
          decisions: [
            _entryFor(conflictingMounts[0], one),
            _entryFor(conflictingMounts[1], two),
          ],
          artifacts: [
            _artifact(one),
            _artifact(two),
          ],
        ),
        throwsA(_refusal),
      );
      final extra = _artifact(_validPayload(text: 'Unused'));
      expect(
        () => PlacementBatchResponseV1(
          request: request,
          expectedTarget: target,
          decisions: response.decisions,
          artifacts: [...response.artifacts, extra],
        ),
        throwsA(_refusal),
      );
    });

    test('held content permits omission only with verified original bytes', () {
      final (original, response, target, _) = _batchFixture();
      final artifact = response.artifacts.single;
      final request = _batch(
        mounts: original.mounts,
        build: original.buildContract,
        heldArtifacts: {artifact.identity},
      );
      expect(
        () => PlacementBatchResponseV1(
          request: request,
          expectedTarget: target,
          decisions: response.decisions,
          artifacts: [],
        ),
        throwsA(_refusal),
      );
      final held = {artifact.identity: artifact.bytes};
      final omitted = PlacementBatchResponseV1(
        request: request,
        expectedTarget: target,
        decisions: response.decisions,
        artifacts: [],
        heldArtifactBytes: held,
      );
      expect(
        PlacementBatchResponseV1.fromCanonicalBytes(
          omitted.canonicalBytes,
          request: request,
          expectedTarget: target,
          heldArtifactBytes: held,
        ),
        omitted,
      );
      held[artifact.identity]![0] ^= 1;
      expect(
        () => PlacementBatchResponseV1.fromCanonicalBytes(
          omitted.canonicalBytes,
          request: request,
          expectedTarget: target,
          heldArtifactBytes: held,
        ),
        throwsA(_refusal),
      );
    });

    test(
      'retained flow dependencies need no child publication and transfer once',
      () {
        final (request, response, payloads) = _retainedFlowFixture();
        final fixture = requireCanonicalObject(
          CanonicalJsonCodec.decode(
            File(
              'test/fixtures/placements/retained_flow_dependencies_v1.json',
            ).readAsBytesSync(),
          ),
          'fixture',
        );
        expect(fixture['request'], request.toJson());
        expect(fixture['response'], response.toJson());
        expect(
          PlacementBatchResponseV1.fromCanonicalBytes(
            CanonicalJsonCodec.encode(fixture['response']),
            request: request,
          ),
          response,
        );
        expect(response.decisions, hasLength(2));
        expect(response.artifacts, hasLength(4));
        final rows = response.decisions.cast<PlacementBatchAvailableV1>();
        expect(
          rows.map(
            (row) => row.publicDelivery.actualPublication.publishedVersion,
          ),
          [29, 41],
        );
        expect(
          [
            payloads['first_root']!,
            payloads['second_root']!,
          ].map((payload) => payload.flowDocument.version),
          [5, 8],
        );
        for (final row in rows) {
          final root = row.artifactClosure.singleWhere(
            (reference) => reference.publication != null,
          );
          expect(root.publication, row.publicDelivery.actualPublication);
          final dependencies = row.artifactClosure.where(
            (reference) => reference.publication == null,
          );
          expect(dependencies, hasLength(2));
          expect(
            dependencies.map((reference) => reference.descriptor.surfaceSlug),
            unorderedEquals(['shared_child', 'shared_leaf']),
          );
          for (final reference in dependencies) {
            final payload = payloads[reference.descriptor.surfaceSlug]!;
            expect(reference.toJson()['publication'], isNull);
            expect(reference.toJson().containsKey('publication'), isTrue);
            expect(reference.descriptor.version, payload.flowDocument.version);
            expect(
              reference.descriptor.publishedAtMicros,
              root.descriptor.publishedAtMicros,
            );
            expect(
              response.artifacts.where(
                (artifact) => artifact.identity == reference.identity,
              ),
              hasLength(1),
            );
            expect(
              PlacementArtifactReferenceV1.fromCanonicalBytes(
                reference.canonicalBytes,
              ),
              reference,
            );
          }
          expect(
            SurfaceFitEvaluator.evaluate(
              host: request.buildContract
                  .contractsByHash[row.descriptor.hostContractHash]!,
              requirement: row.publicDelivery.fitRequirement,
              installed: request.buildContract.installedCapability,
            ).accepted,
            isTrue,
          );
        }
        final childReferences = rows.map(
          (row) => row.artifactClosure.singleWhere(
            (reference) => reference.descriptor.surfaceSlug == 'shared_child',
          ),
        );
        expect(childReferences.first.identity, childReferences.last.identity);
        expect(
          childReferences.first.descriptor.publishedAtMicros,
          isNot(childReferences.last.descriptor.publishedAtMicros),
        );
      },
    );

    test('dependency references require explicit null and one exact root', () {
      final (_, response, payloads) = _retainedFlowFixture();
      final row = response.decisions.first as PlacementBatchAvailableV1;
      final root = row.artifactClosure.singleWhere(
        (reference) => reference.publication != null,
      );
      final dependency = row.artifactClosure.firstWhere(
        (reference) => reference.publication == null,
      );
      expect(
        () => PlacementArtifactReferenceV1.fromJson(
          dependency.toJson()..remove('publication'),
        ),
        throwsA(_refusal),
      );
      for (final field in ['surfaceIdentity', 'family', 'flowVersion']) {
        expect(
          () => PlacementArtifactReferenceV1.fromJson(
            {...dependency.toJson(), field: true},
          ),
          throwsA(_refusal),
        );
      }
      final absentRoot = PlacementArtifactReferenceV1.dependency(
        descriptor: root.descriptor,
      );
      final differentPublication = DeliveryPublicationReferenceV1.fromJson({
        ...root.publication!.toJson(),
        'publishedVersion': root.publication!.publishedVersion + 1,
      });
      final differentRoot = PlacementArtifactReferenceV1(
        publication: differentPublication,
        descriptor: SurfaceArtifactDescriptorV1Codec.decode({
          ...root.descriptor.toJson(),
          'version': differentPublication.publishedVersion,
        }),
      );
      for (final roots in [
        <PlacementArtifactReferenceV1>[],
        [absentRoot],
        [differentRoot],
        [root, root],
      ]) {
        expect(
          () => PlacementBatchEntryV1.available(
            row.descriptor,
            row.publicDelivery,
            [
              ...roots,
              ...row.artifactClosure.where(
                (reference) => reference.publication == null,
              ),
            ],
          ),
          throwsA(_refusal),
        );
      }
      final child = row.artifactClosure.singleWhere(
        (reference) => reference.descriptor.surfaceSlug == 'shared_child',
      );
      final conflicting = _dependencyFor(
        _flowPayload(
          'shared_child',
          version: 7,
          child: payloads['shared_leaf'],
          screenText: 'Different child',
        ),
      );
      for (final duplicate in [child, conflicting]) {
        expect(
          () => PlacementBatchEntryV1.available(
            row.descriptor,
            row.publicDelivery,
            [...row.artifactClosure, duplicate],
          ),
          throwsA(_refusal),
        );
      }
    });

    test('retained dependency bytes must match the original document hash', () {
      final (fullRequest, response, payloads) = _retainedFlowFixture();
      final row = response.decisions.first as PlacementBatchAvailableV1;
      final request = _batch(
        mounts: [fullRequest.mounts.first],
        build: fullRequest.buildContract,
      );
      final changed = _flowPayload(
        'shared_child',
        version: 7,
        child: payloads['shared_leaf'],
        screenText: 'Valid changed child',
      );
      final changedArtifact = _artifact(changed);
      expect(
        FlowDocumentCodec.canonicalJsonSha256(changed.flowDocument),
        isNot(
          FlowDocumentCodec.canonicalJsonSha256(
            payloads['shared_child']!.flowDocument,
          ),
        ),
      );
      final changedRow = PlacementBatchEntryV1.available(
        row.descriptor,
        row.publicDelivery,
        [
          for (final reference in row.artifactClosure)
            if (reference.descriptor.surfaceSlug == 'shared_child')
              _dependencyFor(changed)
            else
              reference,
        ],
      );
      expect(
        () => PlacementBatchResponseV1(
          request: request,
          expectedTarget: _target,
          decisions: [changedRow],
          artifacts: [
            _artifact(payloads['first_root']!),
            changedArtifact,
            _artifact(payloads['shared_leaf']!),
          ],
        ),
        throwsA(_refusal),
      );
    });

    test(
      'retained dependency tuple mode kind and reachable set stay exact',
      () {
        final (fullRequest, response, payloads) = _retainedFlowFixture();
        final row = response.decisions.first as PlacementBatchAvailableV1;
        final request = _batch(
          mounts: [fullRequest.mounts.first],
          build: fullRequest.buildContract,
        );
        final leaf = payloads['shared_leaf']!;
        final wrongChildren = [
          _flowPayload('shared_child', version: 8, child: leaf),
          _flowPayload('wrong_child', version: 7, child: leaf),
          _flowPayload(
            'shared_child',
            version: 7,
            schemaVersion: 2,
            child: leaf,
          ),
          _flowPayload('shared_child', version: 7, minClient: 4, child: leaf),
          _flowPayload(
            'shared_child',
            version: 7,
            deliveryMode: FlowDeliveryMode.general,
            child: leaf,
          ),
        ];
        for (final child in wrongChildren) {
          final artifact = _artifact(child);
          expect(
            () => PlacementBatchResponseV1(
              request: request,
              expectedTarget: _target,
              decisions: [
                PlacementBatchEntryV1.available(
                  row.descriptor,
                  row.publicDelivery,
                  [
                    for (final reference in row.artifactClosure)
                      if (reference.descriptor.surfaceSlug == 'shared_child')
                        _dependencyFor(child)
                      else
                        reference,
                  ],
                ),
              ],
              artifacts: [
                _artifact(payloads['first_root']!),
                artifact,
                _artifact(leaf),
              ],
            ),
            throwsA(_refusal),
          );
        }
        final childReference = row.artifactClosure.singleWhere(
          (reference) => reference.descriptor.surfaceSlug == 'shared_child',
        );
        final wrongKind = PlacementArtifactReferenceV1.dependency(
          descriptor: SurfaceArtifactDescriptorV1Codec.decode({
            ...childReference.descriptor.toJson(),
            'payloadKind': 'blob',
          }),
        );
        final blob = _validPayload();
        final blobChild = PlacementArtifactReferenceV1.dependency(
          descriptor: SurfaceArtifactDescriptorV1Codec.decode({
            ...childReference.descriptor.toJson(),
            'contentHash': blob.contentHash,
            'payloadKind': blob.payloadKind,
          }),
        );
        final extra = _flowPayload('unreachable', version: 17);
        for (final closure in [
          [
            for (final reference in row.artifactClosure)
              if (reference == childReference) wrongKind else reference,
          ],
          [
            for (final reference in row.artifactClosure)
              if (reference == childReference) blobChild else reference,
          ],
          row.artifactClosure
              .where((reference) => reference != childReference)
              .toList(),
          [...row.artifactClosure, _dependencyFor(extra)],
        ]) {
          expect(
            () => PlacementBatchResponseV1(
              request: request,
              expectedTarget: _target,
              decisions: [
                PlacementBatchEntryV1.available(
                  row.descriptor,
                  row.publicDelivery,
                  closure,
                ),
              ],
              artifacts: [
                for (final reference in closure)
                  _artifact(
                    reference == blobChild
                        ? blob
                        : reference.descriptor.surfaceSlug == 'unreachable'
                            ? extra
                            : payloads[reference.descriptor.surfaceSlug]!,
                  ),
              ],
            ),
            throwsA(_refusal),
          );
        }
      },
    );

    test(
        'decoded flow references require '
        'full subflow and embedded screen closure', () {
      final child = _flowPayload('child');
      final parent = _flowPayload('parent', child: child);
      final mount = _mount();
      final childReference = _dependencyFor(child);
      final parentEntry = _entryFor(mount, parent, slug: 'parent');
      final root = PlacementBatchEntryV1.available(
          parentEntry.descriptor, parentEntry.publicDelivery, [
        parentEntry.artifactClosure.single,
        childReference,
      ]);
      final request = _batch();
      final artifacts = [_artifact(parent), _artifact(child)];
      final response = PlacementBatchResponseV1(
        request: request,
        expectedTarget: _target,
        decisions: [root],
        artifacts: artifacts,
      );
      expect(
        PlacementBatchResponseV1.fromCanonicalBytes(
          response.canonicalBytes,
          request: request,
          expectedTarget: _target,
        ),
        response,
      );
      expect(
        () => PlacementBatchResponseV1(
          request: request,
          expectedTarget: _target,
          decisions: [parentEntry],
          artifacts: [_artifact(parent)],
        ),
        throwsA(_refusal),
      );
      final unrelated = _dependencyFor(_flowPayload('unrelated'));
      expect(
        () => PlacementBatchResponseV1(
          request: request,
          expectedTarget: _target,
          decisions: [
            PlacementBatchEntryV1.available(
                parentEntry.descriptor, parentEntry.publicDelivery, [
              parentEntry.artifactClosure.single,
              unrelated,
            ]),
          ],
          artifacts: [
            _artifact(parent),
            _artifact(_flowPayload('unrelated')),
          ],
        ),
        throwsA(_refusal),
      );
      final invalidFrame = Uint8List.fromList(parent.canonicalBytes)..[0] ^= 1;
      final invalidIdentity = ArtifactIdentityV1(
        payloadFormatVersion: 1,
        contentHash: 'sha256:${crypto.sha256.convert(invalidFrame)}',
      );
      expect(
        () => PlacementBatchArtifactV1(
          identity: invalidIdentity,
          bytes: invalidFrame,
        ),
        throwsA(_refusal),
      );
    });

    test(
        'same slug and version across '
        'families retains separate publication uses', () {
      final mounts = [
        _mount(),
        _mount(key: PlacementKeyV1.named(slug: 'second')),
      ];
      final payload = _validPayload();
      final rows = [
        _entryFor(mounts[0], payload),
        _entryFor(
          mounts[1],
          payload,
          family: DeliveryFamilySelectorV1.screenContract(contractVersion: 2),
        ),
      ];
      final response = PlacementBatchResponseV1(
        request: _batch(mounts: mounts, build: _build(mounts: mounts)),
        expectedTarget: _target,
        decisions: rows,
        artifacts: [_artifact(payload)],
      ) as PlacementBatchResolvedV1;
      expect(response.artifacts, hasLength(1));
      expect(
        rows[0].artifactClosure.single.publication!.surface.family,
        _general,
      );
      expect(
        rows[1]
            .artifactClosure
            .single
            .publication!
            .surface
            .family
            .contractVersion,
        2,
      );
    });

    test(
        'strict batch public allowlists '
        'reject extra private fields at every layer', () {
      final (request, response, target, _) = _batchFixture();
      final row = response.decisions.first as PlacementBatchAvailableV1;
      for (final field in [
        'audience',
        'ruleId',
        'rollout',
        'fitWitness',
        'metricWitness',
        'ledgerRow',
        'members',
        'privateEvidence',
        'mountNonce',
      ]) {
        expect(
          () => PublicPlacementDeliveryV1.fromJson(
            {...row.publicDelivery.toJson(), field: true},
          ),
          throwsA(_refusal),
        );
        expect(
          () => PublicDeliveryDecisionPathV1.fromJson(
            {...row.publicDelivery.path.toJson(), field: true},
          ),
          throwsA(_refusal),
        );
        expect(
          () => PublicDeliveryDecisionStepV1.fromJson(
            {...row.publicDelivery.path.steps.first.toJson(), field: true},
          ),
          throwsA(_refusal),
        );
        expect(
          () => PlacementBatchRequestV1.fromJson(
            {...request.toJson(), field: true},
          ),
          throwsA(_refusal),
        );
        expect(
          () => PlacementBatchResponseV1.fromJson(
            {...response.toJson(), field: true},
            request: request,
            expectedTarget: target,
          ),
          throwsA(_refusal),
        );
        expect(
          () => PlacementBatchEntryV1.fromJson({...row.toJson(), field: true}),
          throwsA(_refusal),
        );
        expect(
          () => PlacementBatchArtifactV1.fromJson(
            {...response.artifacts.single.toJson(), field: true},
          ),
          throwsA(_refusal),
        );
      }
      expect(
        () => PublicDeliveryDecisionStepV1.fromJson({
          ...row.publicDelivery.path.steps.first.toJson(),
          'source': 'privateRuleRollout',
        }),
        throwsA(_refusal),
      );
      expect(
        () => PlacementBatchRequestV1.fromCanonicalBytes(
          [...request.canonicalBytes, 0x20],
        ),
        throwsA(_refusal),
      );
      expect(
        () => PlacementBatchResponseV1.fromCanonicalBytes(
          [...response.canonicalBytes, 0x20],
          request: request,
          expectedTarget: target,
        ),
        throwsA(_refusal),
      );
      for (final field in [
        'hostData',
        'bounds',
        'target',
        'apiKey',
        'userId',
      ]) {
        expect(
          () => PlacementBatchRequestV1.fromJson(
            {...request.toJson(), field: <String, Object?>{}},
          ),
          throwsA(_refusal),
        );
      }
    });

    test(
        'response watch closure may exceed '
        'request budget without a count cap', () {
      final (request, response, target, _) = _batchFixture();
      final row = response.decisions.first as PlacementBatchAvailableV1;
      final scopes = <DeliveryPolicyScopeV1>{
        ...row.publicDelivery.dependencyClosure,
        for (var i = 0; i < 1600; i++)
          DeliveryPolicyScopeV1(
            root: DeliveryRootIdentityV1.surface(
              PublishedSurfaceIdentityV1(
                target: target,
                surfaceId: SurfaceId('surface.v1.watch-$i'),
              ),
            ),
            family: _general,
          ),
      };
      final delivery = _copyDelivery(row.publicDelivery, dependencies: scopes);
      expect(
        delivery.canonicalBytes.length,
        greaterThan(kMaximumPlacementRequestBytes),
      );
      final large = PlacementBatchResponseV1(
        request: request,
        expectedTarget: target,
        decisions: [
          PlacementBatchEntryV1.available(
            row.descriptor,
            delivery,
            row.artifactClosure,
          ),
          response.decisions.last,
        ],
        artifacts: response.artifacts,
      );
      expect(
        PlacementBatchResponseV1.fromCanonicalBytes(
          large.canonicalBytes,
          request: request,
          expectedTarget: target,
        ),
        large,
      );
      expect(
        PublicPlacementDeliveryV1.fromCanonicalBytes(delivery.canonicalBytes),
        delivery,
      );
    });

    test('request bound includes complete build and all envelope bytes', () {
      PlacementBatchRequestV1 padded(int padding) => _batch(
            mounts: [],
            build: _build(
              mounts: [],
              contracts: {},
              capability:
                  _installed(names: {'sample.widgets:${'X' * padding}'}),
            ),
          );
      final length = padded(0).canonicalBytes.length;
      final exact = padded(kMaximumPlacementRequestBytes - length);
      expect(exact.canonicalBytes.length, kMaximumPlacementRequestBytes);
      expect(
        PlacementBatchRequestV1.fromCanonicalBytes(exact.canonicalBytes),
        exact,
      );
      expect(
        () => padded(kMaximumPlacementRequestBytes - length + 1),
        throwsA(_refusal),
      );
    });

    test(
        'decoded artifact transfer and '
        'expanded closure budgets are independent', () {
      final empty = _validPayload(text: '');
      final payload = _validPayload(
        text: 'x' *
            (kMaximumPlacementArtifactBytes - empty.canonicalBytes.length),
      );
      final artifact = _artifact(payload);
      expect(artifact.decodedByteLength, kMaximumPlacementArtifactBytes);
      expect(
        (artifact.toJson()['canonicalBase64Url']! as String).length,
        greaterThan(kMaximumPlacementArtifactBytes),
      );
      expect(
        () => _artifact(
          _validPayload(
            text: 'x' *
                (kMaximumPlacementArtifactBytes -
                    empty.canonicalBytes.length +
                    1),
          ),
        ),
        throwsA(_refusal),
      );
      final mounts = [
        for (var index = 0; index < 5; index++)
          _mount(key: PlacementKeyV1.named(slug: 'mount_$index')),
      ];
      final rows = [for (final mount in mounts) _entryFor(mount, payload)];
      final request = _batch(mounts: mounts, build: _build(mounts: mounts));
      final four =
          _batch(mounts: mounts.take(4).toList(), build: request.buildContract);
      expect(
        PlacementBatchResponseV1(
          request: four,
          expectedTarget: _target,
          decisions: rows.take(4).toList(),
          artifacts: [artifact],
        ),
        isA<PlacementBatchResolvedV1>(),
      );
      expect(
        () => PlacementBatchResponseV1(
          request: request,
          expectedTarget: _target,
          decisions: rows,
          artifacts: [artifact],
        ),
        throwsA(_refusal),
      );
      final otherPayload = _validPayload(
        text: 'y' *
            (kMaximumPlacementArtifactBytes - empty.canonicalBytes.length),
      );
      final two =
          _batch(mounts: mounts.take(2).toList(), build: request.buildContract);
      expect(
        () => PlacementBatchResponseV1(
          request: two,
          expectedTarget: _target,
          decisions: [
            rows.first,
            _entryFor(mounts[1], otherPayload, slug: 'other'),
          ],
          artifacts: [
            artifact,
            _artifact(otherPayload),
          ],
        ),
        throwsA(_refusal),
      );
      expect(
        () => PlacementBatchResponseV1.fromCanonicalBytes(
          Uint8List(kMaximumPlacementResponseBytes + 1),
          request: request,
          expectedTarget: _target,
        ),
        throwsA(_refusal),
      );
    });
  });
}

String _base64(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

// Existing watch token vectors also used by the edge verifier.
const _watchToken =
    'v2.i5p7lxR3.1767229200.NDI6b25ib2FyZGluZzp3ZWxjb21lLWZsb3c.'
    'kV0gFtXCrtsWdYcIFXaVNEQDQFjXwvrEn4t_WY_KX44';
const _rotatedWatchToken =
    'v2.URRZ_qOW.1767229200.NDI6b25ib2FyZGluZzp3ZWxjb21lLWZsb3c.'
    'SY4KO-D4AXE2MBM9LFtuVKTCno2ePOhS6_KKv_ckG9w';
const _unicodeWatchToken =
    'v2.i5p7lxR3.1767229200.NDI6b25ib2FyZGluZzp2w6Rsa29tbWVu.'
    'y28ajW3cKP_7pCRXepScTHbNUBqY4qOPTA-DLnWoeVc';

DeliveryPolicyScopeV1 _watchSurfaceScope(TargetCoordinate target, String id) =>
    DeliveryPolicyScopeV1(
      root: DeliveryRootIdentityV1.surface(
        PublishedSurfaceIdentityV1(target: target, surfaceId: SurfaceId(id)),
      ),
      family: _general,
    );

PlacementDeliveryWatchV1 _watchFor(
  PublicPlacementDeliveryV1 delivery, {
  String token = _watchToken,
}) =>
    PlacementDeliveryWatchV1(
      decisionIdentityDigest: CanonicalDigest('c' * 64),
      channels: [
        for (final scope in delivery.dependencyClosure)
          PlacementDeliveryWatchChannelV1(scope: scope, token: token),
      ],
    );

(
  PlacementBatchRequestV1,
  PlacementBatchResolvedV1,
  TargetCoordinate,
  Map<String, Object?>
) _batchFixture() {
  final bytes = File('test/fixtures/placements/shared_blob_two_mounts_v1.json')
      .readAsBytesSync();
  final fixture =
      requireCanonicalObject(CanonicalJsonCodec.decode(bytes), 'fixture');
  final target = TargetCoordinate.fromJson(
    requireCanonicalObject(fixture['expectedTarget'], 'expectedTarget'),
  );
  final request = PlacementBatchRequestV1.fromJson(fixture['request']);
  final response = PlacementBatchResponseV1.fromJson(
    fixture['response'],
    request: request,
    expectedTarget: target,
  ) as PlacementBatchResolvedV1;
  return (request, response, target, fixture);
}

PlacementBatchRequestV1 _batch({
  List<PlacementMountRequestV1>? mounts,
  PlacementBuildContractV1? build,
  PlacementBatchModeV1 mode = PlacementBatchModeV1.prefetch,
  Set<ArtifactIdentityV1> heldArtifacts = const {},
  List<PlacementHeldAssignmentV1> heldAssignments = const [],
  String? assignmentKey,
  SurfaceRegistrationTupleV1? registration,
  String? meteringKey,
  String? analyticsAnonymousId,
  String? sdkInstalledLibraries,
  String? sdkBuiltInsCanonicalBase64,
  String? sdkSupportedPolicyRevisions,
}) {
  final contract = build ?? _build(mounts: mounts);
  return PlacementBatchRequestV1(
    mounts: mounts ?? contract.mounts,
    buildContract: contract,
    appBuildContractHash: contract.appBuildContractHash,
    mode: mode,
    heldArtifacts: heldArtifacts,
    heldAssignments: heldAssignments,
    assignmentKey: assignmentKey,
    registration: registration,
    meteringKey: meteringKey,
    analyticsAnonymousId: analyticsAnonymousId,
    sdkInstalledLibraries: sdkInstalledLibraries,
    sdkBuiltInsCanonicalBase64: sdkBuiltInsCanonicalBase64,
    sdkSupportedPolicyRevisions: sdkSupportedPolicyRevisions,
  );
}

PublicPlacementDeliveryV1 _copyDelivery(
  PublicPlacementDeliveryV1 original, {
  DeliveryPublicationReferenceV1? publication,
  SurfaceFitRequirementV1? requirement,
  DeliveryCacheValidityV1? cache,
  DeliveryDependencyClosureV1? dependencies,
}) {
  final actual = publication ?? original.actualPublication;
  final path = PublicDeliveryDecisionPathV1(
    steps: original.path.steps,
    actualPublication: actual,
  );
  final validity = cache ??
      DeliveryCacheValidityV1.fromJson({
        ...original.cacheValidity.toJson(),
        'selectionIdentityDigest': path.selectionIdentityDigest.hex,
      });
  return PublicPlacementDeliveryV1(
    mount: original.mount,
    path: path,
    selectedSurface: actual.surface,
    actualPublication: actual,
    fitRequirement: requirement ?? original.fitRequirement,
    cacheValidity: validity,
    dependencyClosure: dependencies ?? original.dependencyClosure,
  );
}

DeliveryPolicyDocumentSelectionV1 _policySelection(
  DeliveryPolicyScopeV1 scope,
) =>
    DeliveryPolicyDocumentSelectionV1(
      policyRevision: DeliveryPolicyRevisionRefV1(
        scope: scope,
        ordinal: 1,
        canonicalPolicyDigest: CanonicalDigest('a' * 64),
        revisionId: 'revision-1',
      ),
      documentRef: ExactRoutingDocumentRefV1(
        schemaVersion: 2,
        canonicalDigest: CanonicalDigest('b' * 64),
      ),
    );

SurfaceRegistrationTupleV1 _registrationTuple() => SurfaceRegistrationTupleV1(
      registrationNonce: _base64(List.filled(32, 7)),
      registrationCreatedAtMicros: 1791072000000000,
    );
SurfaceRegistrationMetadataV1 _registrationMetadata() =>
    SurfaceRegistrationMetadataV1(
      credentialHandle: 'ic1.${'a' * 64}',
      expiresAtMicros: 1791073000000000,
      serverNowMicros: 1791072000000000,
    );

BlobSurfacePayload _validPayload({String text = 'Welcome'}) =>
    BlobSurfacePayload(
      minClient: 3,
      blob: rfw.encodeLibraryBlob(
        rfw.RemoteWidgetLibrary(const [
          rfw.Import(rfw.LibraryName(['restage', 'core'])),
        ], [
          rfw.WidgetDeclaration(
            'Root',
            null,
            rfw.ConstructorCall('Text', {'text': text}),
          ),
        ]),
      ),
    );

SurfaceFitRequirementV1 _fitRequirement(SurfacePayload payload) =>
    SurfaceFitRequirementV1(
      hosting: SurfaceHostingRequirementV1(
        contentKind: payload is FlowSurfacePayload
            ? SurfaceContentKindV1.flow
            : SurfaceContentKindV1.single,
        allowedPresentations: const {SurfacePresentationV1.inline},
      ),
      requiredContext: const SurfaceScreenHostDataSchema.empty(),
      emittedEvents: SurfaceScreenEventSchema(events: const []),
      capabilities: CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const [],
      ),
      requiredVocabulary: WidgetVocabulary(
        widgetNames: const {'restage.core:Text'},
      ),
      flowBoundary: payload is FlowSurfacePayload
          ? FlowHostBoundaryV1.fromDocument(
              payload.flowDocument,
              signals: const {},
            )
          : null,
    );

PlacementBatchArtifactV1 _artifact(SurfacePayload payload) =>
    PlacementBatchArtifactV1(
      identity: ArtifactIdentityV1(
        payloadFormatVersion: surfaceArtifactPayloadFormatVersionFor(payload),
        contentHash: payload.contentHash,
      ),
      bytes: payload.canonicalBytes,
    );

PlacementBatchAvailableV1 _entryFor(
  PlacementMountRequestV1 mount,
  SurfacePayload payload, {
  String slug = 'welcome',
  DeliveryFamilySelectorV1 family = _general,
  int publishedVersion = 1,
  int publishedAtMicros = 1791072000000000,
  InstalledCapability? capability,
}) {
  final descriptor = _descriptor(mount);
  final surface = DeliverySurfaceReferenceV1(
    surfaceIdentity: PublishedSurfaceIdentityV1(
      target: _target,
      surfaceId: SurfaceId('surface.v1.$slug'),
    ),
    family: family,
  );
  final publication = DeliveryPublicationReferenceV1(
    surface: surface,
    publishedVersion: publishedVersion,
    payloadFormatVersion: surfaceArtifactPayloadFormatVersionFor(payload),
    contentHash: CanonicalDigest(payload.contentHash.substring(7)),
  );
  final artifactDescriptor = SurfaceArtifactDescriptor(
    payloadFormatVersion: publication.payloadFormatVersion,
    surfaceType: Surface.general,
    surfaceSlug: slug,
    version: publishedVersion,
    publishedAtMicros: publishedAtMicros,
    contentHash: payload.contentHash,
    artifactUrl: 'https://content.example/$slug',
    artifactPass: 'opaque.pass',
    payloadKind: payload.payloadKind,
  );
  final path = PublicDeliveryDecisionPathV1(
    steps: [
      PublicDeliveryDecisionStepV1(
        scope: DeliveryPolicyScopeV1(
          root: DeliveryRootIdentityV1.placement(descriptor.placement),
          family: const DeliveryFamilySelectorV1.none(),
        ),
        source: PublicDeliverySelectionSourceV1.ownerDefault,
      ),
      PublicDeliveryDecisionStepV1(
        scope: DeliveryPolicyScopeV1(
          root: DeliveryRootIdentityV1.surface(surface.surfaceIdentity),
          family: family,
        ),
        source: PublicDeliverySelectionSourceV1.ownerDefault,
      ),
    ],
    actualPublication: publication,
  );
  final delivery = PublicPlacementDeliveryV1(
    mount: descriptor,
    path: path,
    selectedSurface: surface,
    actualPublication: publication,
    fitRequirement: _fitRequirement(payload),
    cacheValidity: DeliveryCacheValidityV1(
      policySelections: const [],
      hostContractHash: mount.hostContractHash,
      installedCapabilityHash: (capability ?? _capability).contentHash,
      selectionIdentityDigest: path.selectionIdentityDigest,
    ),
    dependencyClosure: path.steps.map((step) => step.scope).toSet(),
  );
  return PlacementBatchAvailableV1(descriptor, delivery, [
    PlacementArtifactReferenceV1(
      publication: publication,
      descriptor: artifactDescriptor,
    ),
  ]);
}

FlowSurfacePayload _flowPayload(
  String name, {
  FlowSurfacePayload? child,
  int version = 1,
  int schemaVersion = 1,
  int minClient = 3,
  FlowDeliveryMode deliveryMode = FlowDeliveryMode.typed,
  String screenText = 'Welcome',
}) {
  final blob = _validPayload(text: screenText).blob;
  final document = FlowDocumentCodec.decodeJson(
    jsonEncode({
      'flow': name,
      'version': version,
      'schemaVersion': schemaVersion,
      'minClient': minClient,
      'deliveryMode': deliveryMode.wireName,
      'outbound': <String, Object?>{},
      'initial': 'screen',
      'screenArtifacts': {
        'screen': {
          'path': 'screen.rfw',
          'version': 1,
          'schemaVersion': 1,
          'minClient': 3,
          'contentHash': FlowContentHash.compute(blob).value,
        },
      },
      'states': {
        'screen': {
          'kind': 'screen',
          'screen': 'screen',
          'on': {
            'next': {
              'type': 'goto',
              'target': child == null ? 'done' : 'child',
            },
          },
        },
        if (child != null)
          'child': {
            'kind': 'subFlow',
            'flow': child.flowDocument.flow,
            'version': child.flowDocument.version,
            'schemaVersion': child.flowDocument.schemaVersion,
            'minClient': child.flowDocument.minClient,
            'contentHash':
                FlowDocumentCodec.canonicalJsonSha256(child.flowDocument),
            'input': <String, Object?>{},
            'onComplete': <Object?>[],
            'default': {'goto': 'done'},
          },
        'done': {'kind': 'end', 'result': <String, Object?>{}},
      },
    }),
  );
  return FlowSurfacePayload(
    flowDocument: document,
    screenBlobs: {'screen': blob},
  );
}

PlacementArtifactReferenceV1 _dependencyFor(
  FlowSurfacePayload payload, {
  int publishedAtMicros = 1791072000000000,
}) =>
    PlacementArtifactReferenceV1.dependency(
      descriptor: SurfaceArtifactDescriptor(
        payloadFormatVersion: surfaceArtifactPayloadFormatVersionFor(payload),
        surfaceType: Surface.general,
        surfaceSlug: payload.flowDocument.flow,
        version: payload.flowDocument.version,
        publishedAtMicros: publishedAtMicros,
        contentHash: payload.contentHash,
        artifactUrl: 'https://content.example/${payload.flowDocument.flow}',
        artifactPass: 'opaque.pass',
        payloadKind: payload.payloadKind,
      ),
    );

(
  PlacementBatchRequestV1,
  PlacementBatchResolvedV1,
  Map<String, FlowSurfacePayload>,
) _retainedFlowFixture() {
  final leaf = _flowPayload('shared_leaf', version: 11);
  final child = _flowPayload('shared_child', version: 7, child: leaf);
  final roots = [
    _flowPayload('first_root', version: 5, child: child),
    _flowPayload('second_root', version: 8, child: child),
  ];
  final host = SurfaceHostContractV1(
    hosting: const SurfaceHostingV1(
      contentKind: SurfaceContentKindV1.flow,
      presentation: SurfacePresentationV1.inline,
    ),
    providedContext: const SurfaceScreenHostDataSchema.empty(),
    handledEvents: SurfaceScreenEventSchema(events: const []),
    flowBoundary: _fitRequirement(roots.first).flowBoundary,
  );
  final mounts = [
    _mount(
      key: PlacementKeyV1.named(slug: 'first_root'),
      host: host,
    ),
    _mount(
      key: PlacementKeyV1.named(slug: 'second_root'),
      host: host,
    ),
  ];
  final capability = _installed(names: {'restage.core:Text'});
  final request = _batch(
    mounts: mounts,
    build: _build(
      mounts: mounts,
      contracts: {host.contentHash: host},
      capability: capability,
    ),
  );
  final decisions = <PlacementBatchAvailableV1>[];
  for (var index = 0; index < roots.length; index++) {
    final timestamp = 1791072000000000 + index * 1000000;
    final entry = _entryFor(
      mounts[index],
      roots[index],
      slug: roots[index].flowDocument.flow,
      family: DeliveryFamilySelectorV1.screenContract(contractVersion: 2),
      publishedVersion: index == 0 ? 29 : 41,
      publishedAtMicros: timestamp,
      capability: capability,
    );
    decisions.add(
      PlacementBatchAvailableV1(
        entry.descriptor,
        entry.publicDelivery,
        [
          entry.artifactClosure.single,
          _dependencyFor(child, publishedAtMicros: timestamp),
          _dependencyFor(leaf, publishedAtMicros: timestamp),
        ],
      ),
    );
  }
  final payloads = {
    for (final payload in [...roots, child, leaf])
      payload.flowDocument.flow: payload,
  };
  final response = PlacementBatchResponseV1(
    request: request,
    expectedTarget: _target,
    decisions: decisions,
    artifacts: payloads.values.map(_artifact).toList(),
  ) as PlacementBatchResolvedV1;
  return (request, response, payloads);
}
