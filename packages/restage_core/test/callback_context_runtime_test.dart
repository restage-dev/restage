import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

import 'fixtures/callback_context_source.dart';

void main() {
  for (final (name, native, dsl, bindings) in [
    ('direct', authoredDirect, contextDirectDsl, contextDirectBindings),
    ('alias', authoredAlias, contextAliasDsl, contextAliasBindings),
    ('helper', authoredHelper, contextHelperDsl, contextHelperBindings),
    ('nested', authoredNested, contextNestedDsl, contextNestedBindings),
  ]) {
    for (final generated in [false, true]) {
      testWidgets(
          '$name ${generated ? 'generated' : 'native'} retains exact callback context',
          (tester) async {
        contextCallbacks.clear();
        final runtime = Runtime()
          ..update(
              const LibraryName(['restage', 'core']),
              LocalWidgetLibrary({
                ...kCoreLibraryFactories,
                // Secondary one-context contract caller; Builder is not catalog registered.
                'Builder': (context, source) {
                  source = RestageValueBinding.dataSource(source, context);
                  return RestageBuilderBinding.construct((bindings) {
                    final binding = RestageBuilderBinding(source, ['builder'],
                        contract: const WidgetBuilderContract(
                            parameters: [WidgetBuilderParameter.buildContext]));
                    bindings.add(binding);
                    return Builder(
                        builder: (context) => binding.build(context, {}));
                  });
                },
                'ContextProbe': (context, source) => ContextProbe(
                    source.v<String>(['name'])!,
                    RestageValueBinding.readNative<BuildContext Function()>(
                        source, ['callback'], context,
                        type: 'context.callback')!,
                    child: source.optionalChild(['child'])),
              }))
          ..update(const LibraryName(['context']), rfw.parseLibraryFile(dsl));
        addTearDown(runtime.dispose);
        final data = DynamicContent();
        Widget tree(String key) => generated
            ? RestageNativeValues(
                bindings: bindings(),
                child: RemoteWidget(
                    key: ValueKey(key),
                    runtime: runtime,
                    data: data,
                    widget: const FullyQualifiedWidgetName(
                        LibraryName(['context']), 'Root')))
            : KeyedSubtree(key: ValueKey(key), child: native());
        await tester.pumpWidget(tree('first'));
        expect(tester.takeException(), isNull);
        final elements = tester
            .elementList(find.byType(name == 'alias' ? Builder : LayoutBuilder))
            .toList();
        final outer = elements.first;
        final inner = elements.last;
        final saved = Map.of(contextCallbacks);
        for (final entry in saved.entries) {
          expect(identical(entry.value(), entry.key == 'inner' ? inner : outer),
              isTrue,
              reason: entry.key);
          expect(entry.value().mounted, isTrue);
        }
        if (name == 'nested') expect(identical(inner, outer), isFalse);
        // A second native invocation/Element must not replace a saved closure's input.
        await tester.pumpWidget(tree('second'));
        expect(tester.takeException(), isNull);
        final replacement = contextCallbacks.values.first();
        expect(identical(replacement, outer), isFalse);
        for (final entry in saved.entries) {
          expect(identical(entry.value(), entry.key == 'inner' ? inner : outer),
              isTrue);
          expect(entry.value().mounted, isFalse);
        }
        final second = Map.of(contextCallbacks);
        await tester.pumpWidget(const SizedBox());
        for (final callback in second.values) {
          expect(callback().mounted, isFalse);
        }
      });
    }
  }

  test('only the actual supported widget contract admits nominal arg0', () {
    BuilderProgram program(ValueType type) => BuilderProgram(
        values: ValueProgram(
            nodes: [ValueNode('parameter', type, name: 'arg0')],
            root: 0,
            parameters: {'arg0': type}),
        result: const BuilderResult.body(0),
        bodyCount: 1);
    const builder = WidgetBuilderContract(
        parameters: [WidgetBuilderParameter.buildContext]);
    validateBuilderProgramContract(
        program(builderContextNativeValueType), builder);
    for (final type in [
      ValueType.string,
      const ValueType.native('forged'),
      ValueType.native(builderContextNativeValueType.nativeType!,
          nullable: true)
    ]) {
      expect(() => validateBuilderProgramContract(program(type), builder),
          throwsFormatException);
    }
    expect(
        () => validateBuilderProgramContract(
            program(builderContextNativeValueType),
            const WidgetBuilderContract(
                parameters: [WidgetBuilderParameter.itemIndex])),
        throwsFormatException);
    expect(
        () => validateScalarCallbackProgramContract(
            program(builderContextNativeValueType).values,
            const ScalarCallbackContract(
                parameters: [ScalarCallbackParameter.valueKey])),
        throwsFormatException);
  });

  testWidgets('native arg0 cannot enter a builder without its native contract',
      (tester) async {
    const program = BuilderProgram(
        values: ValueProgram(
            nodes: [
              ValueNode('parameter', builderContextNativeValueType,
                  name: 'arg0')
            ],
            root: 0,
            parameters: {'arg0': builderContextNativeValueType}),
        result: BuilderResult.body(0),
        bodyCount: 1);
    late RestageBuilderBinding binding;
    late BuildContext host;
    final runtime = Runtime()
      ..update(
          const LibraryName(['probe']),
          LocalWidgetLibrary({
            kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
            'Host': (context, source) {
              host = context;
              binding =
                  RestageBuilderBinding(source, ['slot'], context: context);
              return const SizedBox();
            },
            'Empty': (context, source) => const SizedBox(),
          }))
      ..update(
          const LibraryName(['missing']),
          rfw.parseLibraryFile(
              'import probe; widget Root = Host(slot: $kBuilderContinuationWidgetName(version: 1, program: ${jsonEncode(program.encode())}, captures: {}, bodies: [(frame) => Empty()]));'));
    addTearDown(runtime.dispose);
    await tester.pumpWidget(RemoteWidget(
        runtime: runtime,
        data: DynamicContent(),
        widget:
            const FullyQualifiedWidgetName(LibraryName(['missing']), 'Root')));
    expect(() => binding.build(host, {}), throwsFormatException);
    binding.dispose();
  });

  testWidgets('scalar key arg0 remains the supplied ValueKey projection',
      (tester) async {
    const keyType = ValueType('record', fields: {'value': ValueType.integer});
    const program = ValueProgram(
        nodes: [
          ValueNode('parameter', keyType, name: 'arg0'),
          ValueNode('field', ValueType.integer, inputs: [0], name: 'value'),
        ],
        root: 1,
        parameters: {'arg0': keyType});
    late RestageBuilderBinding binding;
    late BuildContext host;
    final runtime = Runtime()
      ..update(
          const LibraryName(['probe']),
          LocalWidgetLibrary({
            kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
            'Host': (context, source) {
              host = context;
              binding = RestageBuilderBinding(source, ['slot'],
                  context: context,
                  scalarContract: const ScalarCallbackContract(
                      parameters: [ScalarCallbackParameter.valueKey]));
              return const SizedBox();
            },
          }))
      ..update(
          const LibraryName(['scalar']),
          rfw.parseLibraryFile(
              'import probe; widget Root = Host(slot: $kBuilderContinuationWidgetName(version: 1, program: ${jsonEncode(program.encode())}, captures: {}));'));
    addTearDown(runtime.dispose);
    await tester.pumpWidget(RemoteWidget(
        runtime: runtime,
        data: DynamicContent(),
        widget:
            const FullyQualifiedWidgetName(LibraryName(['scalar']), 'Root')));
    expect(binding.evaluateKey(host, const ValueKey<int>(73)), 73);
    binding.dispose();
  });
}
