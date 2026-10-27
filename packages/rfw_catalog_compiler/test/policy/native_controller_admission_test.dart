import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:test/test.dart';

import 'fakes/fake_dart_types.dart' as fakes;

void main() {
  const policy = PolicyLedger.builtIn();
  for (final (name, library) in [
    ('ScrollController', 'package:flutter/src/widgets/scroll_controller.dart'),
    ('TabController', 'package:flutter/src/material/tab_controller.dart'),
  ]) {
    for (final target in [name, '$library#$name']) {
      test('explicit policy denial wins for $target', () {
        final denied =
            policy.extend(denylist: policy.denylist.extend(types: {target}));
        for (final nullable in [false, true]) {
          final match = DenylistFilter.match(
              fakes.fakeInterfaceType(name,
                  libraryIdentifier: library, isNullable: nullable),
              denied);
          expect(match, isNotNull);
          expect(match!.policy, 'denylist.types');
          expect(match.target, target);
        }
      });
    }
  }
  test('unrelated exact policy denials remain effective', () {
    const target = 'package:app/secret.dart#SecretSurface';
    final denied =
        policy.extend(denylist: policy.denylist.extend(types: {target}));
    final match = DenylistFilter.match(
        fakes.fakeInterfaceType('SecretSurface',
            libraryIdentifier: 'package:app/secret.dart'),
        denied);
    expect(match!.target, target);
    expect(match.policy, 'denylist.types');
  });
  test('only the installed framework controller types bypass the default deny',
      () {
    for (final (name, library) in [
      (
        'ScrollController',
        'package:flutter/src/widgets/scroll_controller.dart'
      ),
      ('TabController', 'package:flutter/src/material/tab_controller.dart'),
    ]) {
      for (final nullable in [false, true]) {
        expect(
            DenylistFilter.match(
                fakes.fakeInterfaceType(name,
                    libraryIdentifier: library, isNullable: nullable),
                policy),
            isNull);
        expect(
            DenylistFilter.match(
                fakes.fakeInterfaceType(name,
                    libraryIdentifier: 'package:app/controllers.dart',
                    isNullable: nullable),
                policy),
            isNotNull);
      }
    }
    for (final name in [
      'TextEditingController',
      'PageController',
      'CustomController'
    ]) {
      expect(DenylistFilter.match(fakes.fakeInterfaceType(name), policy),
          isNotNull);
    }
  });
}
