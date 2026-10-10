import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
// ignore: implementation_imports
import 'package:restage/src/runtime/installed_libraries_carrier.dart';
// ignore: implementation_imports
import 'package:restage/src/runtime/library_runtime_registry.dart';
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
