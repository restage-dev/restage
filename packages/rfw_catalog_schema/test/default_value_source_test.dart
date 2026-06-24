import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('DefaultValueSource sealed hierarchy', () {
    test('literal compares structurally', () {
      const a = LiteralDefault([0, 0, 0, 0]);
      const b = LiteralDefault([0, 0, 0, 0]);
      const c = LiteralDefault([1, 1, 1, 1]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('literal compares structurally across map shapes', () {
      const a = LiteralDefault({'x': 1, 'y': 2});
      const b = LiteralDefault({'y': 2, 'x': 1});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('tokenRef equality uses cross-library reference', () {
      final a = TokenRefDefault(
        WireIdRef(library: 'restage.core', wireId: WireId('t0005')),
      );
      final b = TokenRefDefault(
        WireIdRef(library: 'restage.core', wireId: WireId('t0005')),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('themeBindingDefault equality follows the underlying path', () {
      const a = ThemeBindingDefault(
        ThemeBindingPath.path('colorScheme.primary'),
      );
      const b = ThemeBindingDefault(
        ThemeBindingPath.path('colorScheme.primary'),
      );
      const c = ThemeBindingDefault(
        ThemeBindingPath.path('colorScheme.surface'),
      );
      expect(a, b);
      expect(a, isNot(c));
    });

    test('flutterCtorDefault is a marker singleton in equality terms', () {
      const a = FlutterCtorDefault();
      const b = FlutterCtorDefault();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different subtypes never compare equal even when content overlaps',
        () {
      const literal = LiteralDefault('primary');
      final tokenRef = TokenRefDefault(
        WireIdRef(library: 'restage.core', wireId: WireId('t0003')),
      );
      expect(literal, isNot(tokenRef));
    });

    test('sealed hierarchy supports exhaustive switching', () {
      String describe(DefaultValueSource s) => switch (s) {
            LiteralDefault() => 'literal',
            TokenRefDefault() => 'tokenRef',
            ThemeBindingDefault() => 'themeBinding',
            FlutterCtorDefault() => 'flutterCtorDefault',
          };
      expect(describe(const LiteralDefault(1)), 'literal');
      expect(
        describe(
          TokenRefDefault(
            WireIdRef(library: 'restage.core', wireId: WireId('t0001')),
          ),
        ),
        'tokenRef',
      );
      expect(
        describe(const ThemeBindingDefault(ThemeBindingPath.path('x'))),
        'themeBinding',
      );
      expect(describe(const FlutterCtorDefault()), 'flutterCtorDefault');
    });
  });

  group('ThemeBindingPath', () {
    test('.path sets path only, resolverName null', () {
      const binding = ThemeBindingPath.path('colorScheme.primary');
      expect(binding.path, 'colorScheme.primary');
      expect(binding.resolverName, isNull);
    });

    test('.resolver sets resolverName only, path null', () {
      const binding = ThemeBindingPath.resolver('elevationOverlay');
      expect(binding.path, isNull);
      expect(binding.resolverName, 'elevationOverlay');
    });

    test('.both sets path and resolverName', () {
      const binding = ThemeBindingPath.both(
        path: 'colorScheme.surface',
        resolverName: 'elevationOverlay',
      );
      expect(binding.path, 'colorScheme.surface');
      expect(binding.resolverName, 'elevationOverlay');
    });

    test('equality compares path + resolverName across the named ctors', () {
      const a = ThemeBindingPath.path('colorScheme.primary');
      const b = ThemeBindingPath.path('colorScheme.primary');
      const c = ThemeBindingPath.resolver('colorScheme.primary');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
