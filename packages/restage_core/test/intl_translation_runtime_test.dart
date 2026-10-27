import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as i;
import 'package:intl/message_lookup_by_library.dart';
import 'package:intl/src/intl_helpers.dart' as intl_helpers;
import 'package:restage_core/restage_core.dart';
import 'package:restage_core/src/runtime/intl_value_operations.dart';
import 'package:restage_shared/restage_shared.dart';

import 'fixtures/intl_translation_source.dart';

final _received = <List<Object>>[];
final _lookups = <String?>[];
final _meaningCalls = <String>[];

class _Messages extends MessageLookupByLibrary {
  _Messages(this.localeName);
  @override
  final String localeName;
  @override
  String? lookupMessage(String? messageText, String? locale, String? name,
      List<Object>? args, String? meaning,
      {intl_helpers.MessageIfAbsent? ifAbsent}) {
    _lookups.add(name);
    return super.lookupMessage(messageText, locale, name, args, meaning,
        ifAbsent: ifAbsent);
  }

  @override
  Map<String, Object?> get messages => {
        'welcome': (String user, DateTime date, TranslationToken token) {
          _received.add([user, date, token]);
          return '$localeName welcome $user ${date.microsecondsSinceEpoch}';
        },
        'items': (int count) => '$localeName items $count',
        'person': (String gender) => '$localeName person $gender',
        'status': (String first, String second, TranslationToken token) {
          _received.add([first, second, token]);
          return '$localeName status $first $second';
        },
        'noArgs': () => '$localeName translated',
        'implicit': () => '$localeName implicit',
        'implicit_context': () => '$localeName contextual',
        'null_secret': () {
          _meaningCalls.add('secret');
          return '$localeName secret';
        },
        'null_other': () {
          _meaningCalls.add('other');
          return '$localeName other';
        },
        'null_': () {
          _meaningCalls.add('');
          return '$localeName ';
        },
        'null_remoteSelected': () {
          _meaningCalls.add('remoteSelected');
          return '$localeName remoteSelected';
        },
        'wrongArity': (int first, int second) => '$first $second',
        'wrongType': (int count) => '$count',
        'unrelated': () => throw StateError('undeclared message invoked'),
      };
}

class _NoCaptures implements ValueReader {
  @override
  Object? read(List<Object> path, ValueType type) => throw StateError('$path');
  @override
  int length(List<Object> path) => throw StateError('$path');
}

NativeBinding<Object> _native(String type, Object value) =>
    NativeBinding(contract: NativeBindingContract(type: type), value: value);

Object _failure(Object? Function() action) {
  try {
    action();
  } catch (error) {
    return error;
  }
  throw StateError('Expected native failure');
}

void main() {
  setUp(() {
    final previous = intl_helpers.messageLookup;
    final previousLocale = i.Intl.defaultLocale;
    final lookup = CompositeMessageLookup();
    lookup.addLocale('en', (_) => _Messages('en'));
    lookup.addLocale('fr', (_) => _Messages('fr'));
    intl_helpers.messageLookup = lookup;
    i.Intl.defaultLocale = 'en';
    _received.clear();
    _lookups.clear();
    _meaningCalls.clear();
    translationEffects.clear();
    addTearDown(() {
      intl_helpers.messageLookup = previous;
      i.Intl.defaultLocale = previousLocale;
    });
  });

  testWidgets(
      'generated native translations preserve locale, types and identity',
      (tester) async {
    final adapters = {
      intlMessageBinding: intlMessageAdapter(),
      intlPluralBinding: intlPluralAdapter(),
      intlGenderBinding: intlGenderAdapter(),
      intlSelectBinding: intlSelectAdapter(),
      intlAbsentArgsBinding: intlAbsentArgsAdapter(),
      intlNullArgsBinding: intlNullArgsAdapter(),
      intlEmptyArgsBinding: intlEmptyArgsAdapter(),
      intlMissingBinding: intlMissingAdapter(),
      intlNullNameBinding: intlNullNameAdapter(),
      intlImplicitNameBinding: intlImplicitNameAdapter(),
      intlEmptyNameBinding: intlEmptyNameAdapter(),
      intlMeaningBinding: intlMeaningAdapter(),
    };
    adapters[intlWidgetBinding] = intlWidgetAdapter();
    late Map<String, ValueOperation> operations;
    late BuildContext host;
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          for (final entry in adapters.entries)
            entry.key: NativeBinding(
                contract: entry.value.contract, value: entry.value),
        },
        child: Builder(builder: (context) {
          host = context;
          operations = RestageNativeValues.operationsOf(context, {});
          return const SizedBox();
        })));
    Object? evaluate(ValueProgram program,
            [Map<String, Object?> parameters = const {}]) =>
        ValueEvaluator(program,
                captures: _NoCaptures(),
                parameters: parameters,
                operations: operations)
            .evaluate();
    final date = DateTime.fromMicrosecondsSinceEpoch(-1234567, isUtc: true);
    final token = TranslationToken();
    final message = intlMessageProgram(operations);
    final select = intlSelectProgram(operations);
    const constraints = BoxConstraints(maxWidth: 300, maxHeight: 100);
    for (final locale in ['en', 'fr', 'de']) {
      i.Intl.withLocale(locale, () {
        final widgetInvocation = intlWidgetProgram(operations).invoke(
            captures: _NoCaptures(),
            parameters: {
              'arg1': RestageBuilderBinding.constraints(constraints),
            },
            operations: operations);
        expect(
            widgetInvocation.values.values.single,
            ((authoredTranslatedWidget() as LayoutBuilder)
                    .builder(host, constraints) as Text)
                .data);
        final translated = evaluate(message, {
          'user': 'Ada',
          'date': _native('dart.DateTime', date),
          'token': _native('translation.Token', token),
        });
        if (locale != 'de') {
          expect(translated, startsWith('$locale welcome'));
          expect(_received.last[1], same(date));
          expect(_received.last[2], same(token));
        } else {
          expect(translated, 'Hello Ada');
        }
        expect(translated, authoredMessage('Ada', date, token));
        expect(evaluate(intlPluralProgram(operations), {'count': 2}),
            authoredPlural(2));
        expect(evaluate(intlGenderProgram(operations), {'gender': 'female'}),
            authoredGender('female'));
        final selected = evaluate(select, {
          'choice': _native('translation.Status', TranslationStatus.active),
          'token': _native('translation.Token', token),
        });
        if (locale != 'de') {
          expect(selected, '$locale status active active');
          expect(_received.last.take(2), ['active', 'active']);
          expect(_received.last.last, same(token));
        }
        expect(selected, authoredSelect(TranslationStatus.active, token));
        for (final (program, native) in [
          (intlAbsentArgsProgram(operations), authoredAbsentArgs),
          (intlNullArgsProgram(operations), authoredNullArgs),
          (intlEmptyArgsProgram(operations), authoredEmptyArgs),
          (intlMissingProgram(operations), authoredMissing),
          (intlNullNameProgram(operations), authoredNullName),
          (intlImplicitNameProgram(operations), authoredImplicitName),
          (intlEmptyNameProgram(operations), authoredEmptyName),
          (intlMeaningProgram(operations), authoredMeaning),
        ]) {
          expect(evaluate(program), native());
        }
      });
    }
    expect(evaluate(intlAbsentArgsProgram(operations)), 'en translated');
  });

  testWidgets('all supplied arguments execute in source order before lookup',
      (tester) async {
    final adapters = {
      intlOrderedBinding: intlOrderedAdapter(),
      intlUnusedFallbackBinding: intlUnusedFallbackAdapter(),
      intlMetadataFailureBinding: intlMetadataFailureAdapter(),
      intlWrongArityBinding: intlWrongArityAdapter(),
      intlWrongTypeBinding: intlWrongTypeAdapter(),
    };
    late Map<String, ValueOperation> operations;
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          for (final entry in adapters.entries)
            entry.key: NativeBinding(
                contract: entry.value.contract, value: entry.value),
        },
        child: Builder(builder: (context) {
          operations = RestageNativeValues.operationsOf(context, {});
          return const SizedBox();
        })));
    Object? evaluate(ValueProgram program) => ValueEvaluator(program,
            captures: _NoCaptures(), parameters: {}, operations: operations)
        .evaluate();
    final value = evaluate(intlOrderedProgram(operations));
    final effects = List<String>.of(translationEffects);
    translationEffects.clear();
    expect(value, authoredOrdered());
    expect(value, 'fr items 1');
    expect(effects, translationEffects);
    expect(effects,
        ['other', 'count', 'args', 'locale', 'desc', 'examples', 'skip']);
    for (final (program, native, expectedLookups) in [
      (intlUnusedFallbackProgram(operations), authoredUnusedFallback, 0),
      (intlMetadataFailureProgram(operations), authoredMetadataFailure, 0),
      (intlWrongArityProgram(operations), authoredWrongArity, 1),
      (intlWrongTypeProgram(operations), authoredWrongType, 1),
    ]) {
      _lookups.clear();
      final expected = _failure(native);
      expect(_lookups, hasLength(expectedLookups));
      _lookups.clear();
      final actual = _failure(() => evaluate(program));
      expect(_lookups, hasLength(expectedLookups));
      expect(actual.runtimeType, expected.runtimeType);
      if (expected is StateError || expected is ArgumentError) {
        expect(actual.toString(), expected.toString());
      }
    }
  });

  testWidgets('translated args read and update the existing live lexical cell',
      (tester) async {
    final adapter = intlLiveCountAdapter();
    late Map<String, ValueOperation> operations;
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          intlLiveCountBinding:
              NativeBinding(contract: adapter.contract, value: adapter)
        },
        child: Builder(builder: (context) {
          operations = RestageNativeValues.operationsOf(context, {});
          return const SizedBox();
        })));
    final frame = ValueLocalFrame({'count': ValueType.integer})
      ..write('count', 1);
    final program = intlLiveCountProgram(operations,
        context:
            ValueOperationContext(frame: frame, locals: frame.visibleTypes));
    Object? evaluate() => ValueEvaluator(program,
            captures: _NoCaptures(),
            parameters: {},
            operations: operations,
            parentFrame: frame)
        .evaluate();
    expect(evaluate(), authoredLiveCount(1));
    expect(frame.read('count'), 2);
    frame.write('count', 9);
    expect(evaluate(), authoredLiveCount(9));
    expect(frame.read('count'), 10);
  });

  test('missing and forged translation declarations fail closed', () {
    final adapter = intlAbsentArgsAdapter();
    final operations = {
      'native.call':
          NativeCallValueOperation({intlAbsentArgsBinding: adapter.contract}),
    };
    final program = intlAbsentArgsProgram(operations);
    final call = program.nodes.single;
    final original = call.value! as Map;
    for (final options in [
      {...original, 'binding': 'unrelated'},
      {...original, 'binding': intlMessageBinding},
      {...original, 'contract': intlMessageAdapter().contract.toJson()},
    ]) {
      final forged = ValueProgram(
          nodes: [ValueNode('native.call', ValueType.string, value: options)],
          root: 0);
      expect(
          () => forged.validate(operations: operations), throwsFormatException);
      expect(
          () => ValueEvaluator(forged,
                  captures: _NoCaptures(),
                  parameters: {},
                  operations: operations)
              .evaluate(),
          throwsFormatException);
    }
    expect(
        () => program.validate(operations: {
              'native.call': NativeCallValueOperation({}),
            }),
        throwsFormatException);
    expect(
        () => ValueEvaluator(program,
                captures: _NoCaptures(), parameters: {}, operations: operations)
            .evaluate(),
        throwsStateError);
  });

  testWidgets('fixed meaning-only adapters use actual native lookup keys',
      (tester) async {
    final cases = [
      (
        intlPluralMeaningBinding,
        intlPluralMeaningAdapter(),
        intlPluralMeaningProgram,
        authoredPluralMeaning
      ),
      (
        intlGenderMeaningBinding,
        intlGenderMeaningAdapter(),
        intlGenderMeaningProgram,
        authoredGenderMeaning
      ),
      (
        intlSelectMeaningBinding,
        intlSelectMeaningAdapter(),
        intlSelectMeaningProgram,
        authoredSelectMeaning
      ),
      (
        intlPluralNullMeaningNameBinding,
        intlPluralNullMeaningNameAdapter(),
        intlPluralNullMeaningNameProgram,
        authoredPluralNullMeaningName
      ),
      (
        intlGenderNullMeaningNameBinding,
        intlGenderNullMeaningNameAdapter(),
        intlGenderNullMeaningNameProgram,
        authoredGenderNullMeaningName
      ),
      (
        intlSelectNullMeaningNameBinding,
        intlSelectNullMeaningNameAdapter(),
        intlSelectNullMeaningNameProgram,
        authoredSelectNullMeaningName
      ),
      (
        intlNestedPluralMeaningBinding,
        intlNestedPluralMeaningAdapter(),
        intlNestedPluralMeaningProgram,
        authoredNestedPluralMeaning
      ),
      (
        intlNestedGenderMeaningBinding,
        intlNestedGenderMeaningAdapter(),
        intlNestedGenderMeaningProgram,
        authoredNestedGenderMeaning
      ),
      (
        intlNestedSelectMeaningBinding,
        intlNestedSelectMeaningAdapter(),
        intlNestedSelectMeaningProgram,
        authoredNestedSelectMeaning
      ),
    ];
    late Map<String, ValueOperation> operations;
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          for (final (key, adapter, _, _) in cases)
            key: NativeBinding(contract: adapter.contract, value: adapter),
        },
        child: Builder(builder: (context) {
          operations = RestageNativeValues.operationsOf(context, {});
          return const SizedBox();
        })));
    for (final locale in ['en', 'fr']) {
      i.Intl.withLocale(locale, () {
        for (var index = 0; index < cases.length; index++) {
          final (_, _, decode, native) = cases[index];
          _meaningCalls.clear();
          final value = ValueEvaluator(decode(operations),
                  captures: _NoCaptures(),
                  parameters: {},
                  operations: operations)
              .evaluate();
          expect(_meaningCalls, ['secret']);
          expect(value, index < 6 ? '$locale secret' : '$locale translated');
          _meaningCalls.clear();
          expect(value, native());
          expect(_meaningCalls, ['secret']);
        }
      });
    }
  });

  test('legacy formatting cannot dispatch meaning-selected translations', () {
    for (final family in ['plural', 'gender', 'select']) {
      final choice = family == 'plural' ? 1 : 'active';
      final choiceType =
          family == 'plural' ? ValueType.integer : ValueType.string;
      final options = <String, Object?>{
        'arguments': family == 'select' ? ['meaning'] : ['other', 'meaning'],
        if (family == 'select') 'keys': ['other'],
      };
      final operation = kNativeIntlValueOperations['intl.$family']!;
      for (final meaning in ['secret', 'other', '', null]) {
        final inputs = <Object?>[choice, 'fallback', meaning];
        final node = ValueNode('intl.$family', ValueType.string,
            inputs: [0, 1, 2], value: options);
        final types = [
          choiceType,
          ValueType.string,
          meaning == null ? ValueType.nullType : ValueType.string
        ];
        _meaningCalls.clear();
        if (meaning == null) {
          kIntlValueOperations['intl.$family']!.validate(node, types);
          final native = switch (family) {
            'plural' => i.Intl.plural(1, other: 'fallback', meaning: null),
            'gender' =>
              i.Intl.gender('active', other: 'fallback', meaning: null),
            _ => i.Intl.select('active', {'other': 'fallback'}, meaning: null),
          };
          expect(operation.evaluate(inputs, options), native);
          expect(_meaningCalls, isEmpty);
        } else {
          final native = switch (family) {
            'plural' => i.Intl.plural(1, other: 'fallback', meaning: meaning),
            'gender' =>
              i.Intl.gender('active', other: 'fallback', meaning: meaning),
            _ =>
              i.Intl.select('active', {'other': 'fallback'}, meaning: meaning),
          };
          expect(native, 'en $meaning');
          expect(_meaningCalls, [meaning]);
          _meaningCalls.clear();
          expect(
              () => kIntlValueOperations['intl.$family']!.validate(node, types),
              throwsFormatException);
          expect(
              () => operation.evaluate(inputs, options), throwsFormatException);
          expect(_meaningCalls, isEmpty);
        }
      }
    }
  });

  for (final (family, key, create, decode, native) in [
    (
      'plural',
      intlNullPluralBinding,
      intlNullPluralAdapter,
      intlNullPluralProgram,
      authoredNullPluralWidget
    ),
    (
      'gender',
      intlNullGenderBinding,
      intlNullGenderAdapter,
      intlNullGenderProgram,
      authoredNullGenderWidget
    ),
    (
      'select',
      intlNullSelectBinding,
      intlNullSelectAdapter,
      intlNullSelectProgram,
      authoredNullSelectWidget
    ),
    (
      'aliased plural',
      intlAliasNullPluralBinding,
      intlAliasNullPluralAdapter,
      intlAliasNullPluralProgram,
      authoredAliasNullPluralWidget
    ),
    (
      'aliased gender',
      intlAliasNullGenderBinding,
      intlAliasNullGenderAdapter,
      intlAliasNullGenderProgram,
      authoredAliasNullGenderWidget
    ),
    (
      'aliased select',
      intlAliasNullSelectBinding,
      intlAliasNullSelectAdapter,
      intlAliasNullSelectProgram,
      authoredAliasNullSelectWidget
    ),
  ]) {
    testWidgets(
        'generated constant-null $family metadata cannot acquire remote lookup authority',
        (tester) async {
      final adapter = create();
      late Map<String, ValueOperation> operations;
      late BuildContext host;
      await tester.pumpWidget(RestageNativeValues(
          bindings: {
            key: NativeBinding(contract: adapter.contract, value: adapter),
          },
          child: Builder(builder: (context) {
            host = context;
            operations = RestageNativeValues.operationsOf(context, {});
            return const SizedBox();
          })));
      const constraints = BoxConstraints(maxWidth: 300, maxHeight: 100);
      for (final locale in ['en', 'fr']) {
        i.Intl.withLocale(locale, () {
          final producer = decode(operations);
          _meaningCalls.clear();
          final value = producer
              .invoke(
                  captures: _NoCaptures(),
                  parameters: {
                    'arg1': RestageBuilderBinding.constraints(constraints),
                  },
                  operations: operations)
              .values
              .values
              .single;
          expect(_meaningCalls, isEmpty);
          expect(
              value,
              ((native() as LayoutBuilder).builder(host, constraints) as Text)
                  .data);
          expect(_meaningCalls, isEmpty);

          // Exercise exactly the producer's installed signature. A widened
          // nullable String input would let this accepted payload choose an
          // unauthored lookup key; a closed constant leaves no such operand.
          final call = producer.values.nodes
              .singleWhere((node) => node.op == 'native.call');
          final operands = <ValueNode>[
            for (final type in adapter.contract.call!.inputs)
              ValueNode('literal', type, value: 'remoteSelected'),
          ];
          final remote = ValueProgram(nodes: [
            ...operands,
            ValueNode('native.call', call.type,
                inputs: List.generate(operands.length, (index) => index),
                value: call.value),
          ], root: operands.length);
          remote.validate(operations: operations);
          _meaningCalls.clear();
          expect(
              ValueEvaluator(remote,
                      captures: _NoCaptures(),
                      parameters: {},
                      operations: operations)
                  .evaluate(),
              '$locale translated');
          expect(_meaningCalls, isEmpty);
          expect(adapter.contract.call!.inputs, isEmpty);
          expect(adapter.contract.call!.captures, isEmpty);
        });
      }
    });
  }
}
