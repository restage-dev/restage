import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../policy/fakes/fake_dart_types.dart' as fakes;

/// The library a real Flutter `WidgetStateProperty` is declared in. The
/// state-property unwrap is gated on this canonical identity so a lookalike
/// type merely *named* `WidgetStateProperty` is not mis-shaped as the Flutter
/// carrier.
const _flutterWidgetStateLibrary =
    'package:flutter/src/widgets/widget_state.dart';

void main() {
  group('resolveValueShape — WidgetStateProperty unwrap is FQN-gated', () {
    const policy = PolicyLedger.builtIn();

    test(
        'a real Flutter WidgetStateProperty<Color> unwraps to its value shape '
        '(Color lowers to a color scalar)', () {
      final type = fakes.fakeInterfaceType(
        'WidgetStateProperty',
        libraryIdentifier: _flutterWidgetStateLibrary,
        typeArguments: [
          fakes.fakeInterfaceType('Color', libraryIdentifier: 'dart:ui'),
        ],
      );

      final shape = resolveValueShape(
        type,
        library: WidgetLibrary.material,
        policy: policy,
      );

      // The carrier is unwrapped to `Color`, a recognized scalar → a
      // ScalarShape carrying PropertyType.color (not null).
      expect(shape, isA<ScalarShape>());
      expect(shape?.propertyType, PropertyType.color);
    });

    test(
        'a lookalike WidgetStateProperty<Color> from a non-Flutter library is '
        'NOT unwrapped (the lookalike resolves to no catalog shape)', () {
      final type = fakes.fakeInterfaceType(
        'WidgetStateProperty',
        // A project type that merely shares the name — different library.
        libraryIdentifier: 'package:my_app/widget_state.dart',
        typeArguments: [
          fakes.fakeInterfaceType('Color', libraryIdentifier: 'dart:ui'),
        ],
      );

      final shape = resolveValueShape(
        type,
        library: WidgetLibrary.material,
        policy: policy,
      );

      // No unwrap: the lookalike outer type is not an enum / scalar / union /
      // list / known recipe structured type, so the resolver maps it to
      // nothing — the inner `Color` is never reached.
      expect(shape, isNull);
    });
  });
}
