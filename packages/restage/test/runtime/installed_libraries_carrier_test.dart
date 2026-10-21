import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// ignore: implementation_imports
import 'package:restage/src/runtime/installed_libraries_carrier.dart';
// ignore: implementation_imports
import 'package:restage/src/runtime/library_runtime_registry.dart';
import 'package:restage/src/runtime/installed_widget_vocabulary.dart';
import 'package:restage_shared/restage_shared.dart'
    show InstalledCapability, InstalledLibrary;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show SdkInstalledLibrariesV1, sdkInstalledLibrariesMaximumLibraries;

Widget _stub(BuildContext context, DataSource source) => const SizedBox();

SdkInstalledLibrariesV1 _decode(String carrier) =>
    SdkInstalledLibrariesV1.fromCanonicalBytes(
      base64Url.decode(base64Url.normalize(carrier)),
    );

void _register(String namespace, {int? version, int? compatibleSince}) =>
    Restage.registerWidgetLibrary(
      WidgetLibrary.custom(namespace),
      widgets: [RestageWidgetFactory(name: 'W', builder: _stub)],
      capabilityVersion: version,
      compatibleSince: compatibleSince,
    );

void main() {
  setUp(LibraryRuntimeRegistry.clear);

  test('reports an empty registry as an empty list', () {
    expect(_decode(installedLibrariesCarrier()!).libraries, isEmpty);
  });

  test('reports the captured catalog and optional display version', () {
    final snapshot = InstalledCapability(
      builtInCatalogVersion: 7,
      installedLibraries: const [],
    );
    final report = _decode(installedLibrariesCarrier(
      snapshot: snapshot,
      appVersion: '2.4.1',
    )!);
    expect(report.builtInCatalogVersion, 7);
    expect(report.appVersion, '2.4.1');
    expect(_decode(installedLibrariesCarrier()!).builtInCatalogVersion,
        currentInstalledCapability().builtInCatalogVersion);
    expect(_decode(installedLibrariesCarrier()!).appVersion, isNull);
  });

  test('reports each registered library with its declared break', () {
    _register('zeta.widgets');
    _register('acme.widgets', version: 4, compatibleSince: 4);
    _register('app.widgets', version: 2);

    final carrier = installedLibrariesCarrier()!;
    expect(carrier, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    final libraries = _decode(carrier).libraries;
    expect(
      [
        for (final library in libraries)
          (library.namespace, library.version, library.compatibleSince),
      ],
      [
        ('acme.widgets', 4, 4),
        ('app.widgets', 2, null),
        ('zeta.widgets', null, null),
      ],
    );
  });

  test('a supplied snapshot keeps its libraries after the registry changes',
      () {
    _register('app.widgets', version: 2);
    final snapshot = currentInstalledCapability();
    _register('app.widgets', version: 3, compatibleSince: 3);
    _register('later.widgets', version: 1);

    final libraries =
        _decode(installedLibrariesCarrier(snapshot: snapshot)!).libraries;
    expect(libraries, hasLength(1));
    expect(libraries.single.namespace, 'app.widgets');
    expect(libraries.single.version, 2);
    expect(
        snapshot.contentHash, isNot(currentInstalledCapability().contentHash));
  });

  test('an invalid supplied snapshot is unknown even with an empty registry',
      () {
    expect(
      installedLibrariesCarrier(
        snapshot: InstalledCapability(
          builtInCatalogVersion: 1,
          installedLibraries: const [InstalledLibrary(namespace: 'has space')],
        ),
      ),
      isNull,
    );
  });

  test('omits the report when the build exceeds its bounds', () {
    for (var i = 0; i <= sdkInstalledLibrariesMaximumLibraries; i++) {
      _register('lib$i', version: 1);
    }
    expect(installedLibrariesCarrier(), isNull);

    LibraryRuntimeRegistry.clear();
    _register('has space', version: 1);
    expect(installedLibrariesCarrier(), isNull);
  });
}
