import 'package:flutter_test/flutter_test.dart';
import 'package:restage_a2ui/restage_a2ui.dart';

void main() {
  test('catalog capability is a compact const runtime value', () {
    const capability = RestageA2uiCapability(
      schemaDialect: 'https://json-schema.org/draft/2020-12/schema',
      a2uiProtocolVersion: '0.9.1',
      catalogId: 'restage:catalog/sha256/abc',
      fingerprint: 'sha256/abc',
      catalogContentVersion: 2,
      availableLibraries: [
        A2uiAvailableLibrary(namespace: 'acme.widgets', version: 3),
      ],
      perItemSinceVersion: {'Card': 2},
    );

    expect(capability.schemaVersion, capability.a2uiProtocolVersion);
    expect(capability.catalogFingerprint, capability.fingerprint);
    expect(capability.catalogId, 'restage:catalog/sha256/abc');
    expect(capability.availableLibraries, [
      const A2uiAvailableLibrary(namespace: 'acme.widgets', version: 3),
    ]);
    expect(capability.perItemSinceVersion, {'Card': 2});
  });

  test('available axes adapt to the existing fail-closed pre-render value', () {
    const capability = RestageA2uiCapability(
      schemaDialect: 'dialect',
      a2uiProtocolVersion: 'version',
      catalogId: 'catalog',
      fingerprint: 'fingerprint',
      catalogContentVersion: 2,
      availableLibraries: [
        A2uiAvailableLibrary(namespace: 'zed.widgets', version: 1),
        A2uiAvailableLibrary(namespace: 'acme.widgets', version: 3),
      ],
      perItemSinceVersion: {},
    );

    final installed = capability.installedCapability;
    expect(installed.catalogContentVersion, 2);
    expect(installed.availableLibraries.map((entry) => entry.namespace), [
      'acme.widgets',
      'zed.widgets',
    ]);
  });
}
