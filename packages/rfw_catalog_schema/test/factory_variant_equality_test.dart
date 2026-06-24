import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

/// Value-equality for the sealed [FactoryVariant] subtypes, [ArgMapping], and
/// the [FactoryParameter] they carry.
///
/// The sealed swap (the prior milestone) was behavior-neutral and left the
/// variant types on identity equality. This locks the value-`==`/`hashCode`
/// the subtypes need to be usable in value contexts (set membership, dedup,
/// `expect(decoded, original)` round-trips). Deep on the collection fields:
/// two structurally-equal variants compare equal even when their
/// `argMappings` / `parameters` are distinct instances; a variant's parameters
/// are part of its value, so [FactoryParameter] is compared by value too.
void main() {
  ArgMapping argMapping(List<String> targets) =>
      ArgMapping(targetFields: [for (final id in targets) WireId(id)]);

  FactoryParameter param({String name = 'edge'}) => FactoryParameter(
        wireId: WireId('a0001'),
        name: name,
        kind: FactoryParameterKind.named,
        required: false,
        nullable: false,
        defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
        valueShape: const ScalarShape(propertyType: PropertyType.string),
      );

  ConstructorVariant ctor({
    String wireId = 'v0001',
    String? namedConstructor = 'only',
    List<String> argTargets = const ['p0501'],
    List<FactoryParameter> parameters = const [],
    String? description = 'A constructor.',
  }) =>
      ConstructorVariant(
        wireId: WireId(wireId),
        namedConstructor: namedConstructor,
        argMappings: {'edge': argMapping(argTargets)},
        parameters: parameters,
        description: description,
      );

  StaticMethodVariant method(String accessor) =>
      StaticMethodVariant(wireId: WireId('v0001'), staticAccessor: accessor);

  StaticGetterVariant getter(String accessor) =>
      StaticGetterVariant(wireId: WireId('v0001'), staticAccessor: accessor);

  ConstValueVariant constValue(String accessor) =>
      ConstValueVariant(wireId: WireId('v0001'), staticAccessor: accessor);

  group('ArgMapping value-equality', () {
    test('equal target-field lists compare equal with equal hashCodes', () {
      final a = argMapping(['p0501', 'p0502']);
      final b = argMapping(['p0501', 'p0502']);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different target fields compare unequal', () {
      expect(argMapping(['p0501']), isNot(equals(argMapping(['p0502']))));
    });

    test('order-sensitive', () {
      expect(
        argMapping(['p0501', 'p0502']),
        isNot(equals(argMapping(['p0502', 'p0501']))),
      );
    });
  });

  group('FactoryParameter value-equality', () {
    test('structurally-equal parameters compare equal', () {
      expect(param(), equals(param()));
      expect(param().hashCode, equals(param().hashCode));
    });

    test('a differing field compares unequal', () {
      expect(param(), isNot(equals(param(name: 'corner'))));
    });
  });

  group('ConstructorVariant value-equality', () {
    test('structurally equal (distinct argMappings + parameters) are equal',
        () {
      final a = ctor(parameters: [param()]);
      final b = ctor(parameters: [param()]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs by namedConstructor', () {
      expect(ctor(), isNot(equals(ctor(namedConstructor: 'all'))));
    });

    test('differs by argMappings', () {
      expect(ctor(), isNot(equals(ctor(argTargets: ['p0502']))));
    });

    test('differs by parameters', () {
      expect(ctor(parameters: [param()]), isNot(equals(ctor())));
    });

    test('differs by wireId / description', () {
      expect(ctor(), isNot(equals(ctor(wireId: 'v0002'))));
      expect(ctor(), isNot(equals(ctor(description: 'B'))));
    });
  });

  group('accessor-kind value-equality', () {
    test('StaticMethodVariant equal/unequal', () {
      expect(method('lerp'), equals(method('lerp')));
      expect(method('lerp').hashCode, equals(method('lerp').hashCode));
      expect(method('lerp'), isNot(equals(method('of'))));
    });

    test('StaticGetterVariant equal/unequal', () {
      expect(getter('instance'), equals(getter('instance')));
      expect(getter('instance').hashCode, equals(getter('instance').hashCode));
      expect(getter('instance'), isNot(equals(getter('shared'))));
    });

    test('ConstValueVariant equal/unequal', () {
      expect(constValue('zero'), equals(constValue('zero')));
      expect(constValue('zero'), isNot(equals(constValue('one'))));
    });
  });

  group('cross-subtype inequality', () {
    test('different subtypes with the same wireId are unequal', () {
      expect(getter('instance'), isNot(equals(constValue('instance'))));
    });
  });
}
