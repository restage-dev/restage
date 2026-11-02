import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:restage_a2ui/restage_a2ui.dart';
import 'package:restage_a2ui_example/generated/restage_a2ui_catalog.g.dart';
import 'package:restage_shared/restage_shared.dart'
    show CapabilityManifest, LibraryRequirement;

import 'a2ui_proof_support.dart';

/// Missing types fail preflight and the strict upstream runtime.
/// A payload whose root references a component absent from the catalog.
List<Object?> _ghostMessages(String surfaceId, String catalogId) =>
    sidecarMessages(surfaceId, catalogId, const [
      {'id': 'root', 'component': 'GhostWidget', 'props_title': 'nope'},
    ]);

/// A valid single-component payload (every referenced type EXISTS), so only the
/// capability axis can reject it.
List<Object?> _validMessages(String surfaceId, String catalogId) =>
    sidecarMessages(surfaceId, catalogId, const [
      {'id': 'root', 'component': 'SectionHeader', 'props_title': 'ok'},
    ]);

/// A mixed graph must be rejected as a whole, even when its other nodes exist.
/// Strict v1 processing rejects the same graph before any components commit.
List<Object?> _mixedMessages(String surfaceId, String catalogId) =>
    sidecarMessages(surfaceId, catalogId, const [
      {
        'id': 'root',
        'component': 'ComparisonPanel',

        'props_heading': 'Mixed',
        'props_examples': ['ok', 'ghost'],
      },
      {'id': 'ok', 'component': 'SectionHeader', 'props_title': 'I render'},
      {
        'id': 'ghost',
        'component': 'GhostWidget',
        'props_title': 'I do not exist',
      },
    ]);

void main() {
  late final CatalogImplementation catalog;
  late final A2uiInstalledCapability installed;

  setUpAll(() {
    catalog = CatalogImplementation(
      id: 'test_catalog',
      components: buildRestageCatalogItems(),
      definitions: buildRestageCatalogDefinitions(),
      protocolVersion: A2uiProtocolVersion.v1_0,
    );
    installed = A2uiInstalledCapability.fromStampJson(
      readStamp()['restageCapability'] as Map<String, Object?>,
    );
  });

  test('the pre-render check REJECTS a missing component, naming it', () {
    final sidecar = RestageA2uiSidecar(
      capability: CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const [],
      ),
      perItemSinceVersion: const {},
      a2ui: _ghostMessages('s', 'test_catalog'),
    );
    final check = RestageA2uiPreRenderCheck(
      catalogs: [catalog],
      installed: installed,
      validationConfig: ValidationConfig.strict,
    );
    final result = check.check(sidecar.toJson());
    expect(result, isA<A2uiRejected>());
    expect((result as A2uiRejected).diagnostic, contains('GhostWidget'));
  });

  for (final pair in [
    ('missing root', _ghostMessages),
    ('mixed children', _mixedMessages),
  ]) {
    test(
      '${pair.$1} rejected by preflight and strict processor before components commit',
      () {
        final messages = pair.$2('s', 'test_catalog');
        final result = RestageA2uiPreRenderCheck(
          catalogs: [catalog],
          installed: installed,
          validationConfig: ValidationConfig.strict,
        ).check(messages);
        expect(result, isA<A2uiRejected>());
        expect((result as A2uiRejected).diagnostic, contains('GhostWidget'));
        final processor = MessageProcessor<ComponentImplementation>(
          catalogs: [catalog],
          defaultVersion: A2uiProtocolVersion.v1_0,
          validationConfig: ValidationConfig.strict,
        );
        addTearDown(processor.dispose);
        expect(
          () => processor.processMessages(messages),
          throwsA(isA<A2uiError>()),
        );
        expect(
          processor.model.getSurface('s')?.componentsModel.keys ?? {},
          isEmpty,
        );
      },
    );
  }

  test('a stamped payload with NO installed descriptor fails closed', () {
    final sidecar = RestageA2uiSidecar(
      capability: CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const [
          LibraryRequirement(namespace: 'acme.lessons', minVersion: 1),
        ],
      ),
      perItemSinceVersion: const {},
      a2ui: _validMessages('s', 'test_catalog'),
    );
    // No `installed:` supplied → a stamped requirement cannot be verified.
    final check = RestageA2uiPreRenderCheck(
      catalogs: [catalog],
      validationConfig: ValidationConfig.strict,
    );
    final result = check.check(sidecar.toJson());
    expect(result, isA<A2uiRejected>());
    expect((result as A2uiRejected).diagnostic, contains('cannot be verified'));
  });
}
