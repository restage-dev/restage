import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/rfw_constructor_presence_protocol.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _nonNullDefault = DartConstScalar('constructor default');

PropertyEntry _property({
  String name = 'label',
  bool required = false,
  bool constructorNullable = true,
  DartConstValue? constructorDefault = _nonNullDefault,
}) =>
    PropertyEntry(
      wireId: WireId.unallocatedProperty,
      name: name,
      type: PropertyType.string,
      description: 'Optional label.',
      required: required,
      constructorNullable: constructorNullable,
      constructorDefault: constructorDefault,
    );

Catalog _catalog() => catalogWith([
      entry(
        name: 'Probe',
        category: WidgetCategory.input,
        properties: [_property()],
      ),
    ]);

Future<String> _translate(String argument) async {
  final expression = await parseExpressionFromSourceForTest('''
Object x() => Probe(label: $argument);
''');
  final result = ExpressionTranslator(
    catalog: _catalog(),
    helpers: HelperRegistry(),
  ).translate(expression);
  expect(result.issues, isEmpty);
  return result.dsl;
}

void main() {
  group('RFW constructor presence encoder', () {
    test('applies to every optional constructor property with a default', () {
      expect(RfwConstructorPresenceEncoder.appliesTo(_property()), isTrue);
      expect(
        RfwConstructorPresenceEncoder.appliesTo(
          _property(constructorNullable: false),
        ),
        isTrue,
      );
      expect(
        RfwConstructorPresenceEncoder.appliesTo(
          _property(constructorDefault: const DartConstNull()),
        ),
        isTrue,
      );
    });

    test('does not apply to required or no-default properties', () {
      expect(
        RfwConstructorPresenceEncoder.appliesTo(_property(required: true)),
        isFalse,
      );
      expect(
        RfwConstructorPresenceEncoder.appliesTo(
          _property(constructorDefault: null),
        ),
        isFalse,
      );
    });

    test('wraps a supplied non-null value in the named versioned envelope',
        () async {
      expect(
        await _translate("'authored'"),
        'Probe(label: ${RfwConstructorPresenceEncoder.supplied('"authored"')})',
      );
    });

    test('keeps the envelope but omits its nested value for explicit null',
        () async {
      final dsl = await _translate('null');

      expect(
        dsl,
        'Probe(label: ${RfwConstructorPresenceEncoder.supplied('null')})',
      );
      expect(dsl, contains(RfwConstructorPresenceProtocol.markerKey));
      expect(
        dsl,
        isNot(contains('${RfwConstructorPresenceProtocol.valueKey}:')),
      );
    });
  });

  test('generated factory conditionally supplies the Dart constructor argument',
      () {
    final widget = WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: 'Probe',
      library: const WidgetLibrary.custom('acme.widgets'),
      category: WidgetCategory.input,
      description: 'A probe.',
      flutterType: 'package:acme/widgets/probe.dart#Probe',
      childrenSlot: ChildrenSlot.none,
      properties: [_property()],
    );

    final source = emitFactoryFunction(
      widget,
      aliases: const {'package:acme/widgets/probe.dart': 's0'},
    )!;

    expect(source, contains('RestageRfwConstructorPresence.read('));
    expect(source, contains('Function.apply(s0.Probe.new'));
    expect(source, contains('if (_restagePresenceLabel.supplied)'));
    expect(source, contains('#label:'));
    expect(source, isNot(contains("source.v<String>(<Object>['label']) ??")));
  });

  test('generated factory allocates deterministic unique presence locals', () {
    WidgetEntry widget() => WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'Probe',
          library: const WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.input,
          description: 'A probe.',
          flutterType: 'package:acme/widgets/probe.dart#Probe',
          childrenSlot: ChildrenSlot.none,
          properties: [
            _property(name: 'foo'),
            _property(name: 'Foo'),
            _property(name: r'foo$'),
            _property(name: r'Foo$'),
            _property(),
          ],
        );

    final first = emitFactoryFunction(
      widget(),
      aliases: const {'package:acme/widgets/probe.dart': 's0'},
    )!;
    final second = emitFactoryFunction(
      widget(),
      aliases: const {'package:acme/widgets/probe.dart': 's0'},
    )!;
    final locals = RegExp(
      'final (_restagePresence[^ ]+) = RestageRfwConstructorPresence',
    ).allMatches(first).map((match) => match.group(1)!).toList();

    expect(second, first, reason: 'the generated bytes must be deterministic');
    expect(locals, [
      '_restagePresenceFoo',
      '_restagePresence1_Foo',
      r'_restagePresenceFoo$',
      r'_restagePresence3_Foo$',
      '_restagePresenceLabel',
    ]);
    expect(locals.toSet(), hasLength(locals.length));
    expect(first, contains("<Object>['foo']"));
    expect(first, contains("<Object>['Foo']"));
    expect(first, contains(r"<Object>['foo\$']"));
    expect(first, contains(r"<Object>['Foo\$']"));
    expect(first, contains('_restagePresenceLabel'));
    expect(first, contains('if (_restagePresenceFoo.supplied)'));
    expect(first, contains('#foo:'));
    expect(first, contains('if (_restagePresence1_Foo.supplied)'));
    expect(first, contains('#Foo:'));
  });
}
