import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

class _RequiredBuilderProbe extends StatelessWidget {
  const _RequiredBuilderProbe({required this.builder});
  final WidgetBuilder? builder;
  @override
  Widget build(BuildContext context) =>
      builder?.call(context) ??
      const Text('null supplied', textDirection: TextDirection.ltr);
}

void main() {
  testWidgets(
      'required nullable factory distinguishes null callback and omission',
      (tester) async {
    const contract = WidgetBuilderContract(
        parameters: [WidgetBuilderParameter.buildContext]);
    const program = BuilderProgram(
        values: ValueProgram(
            nodes: [ValueNode('literal', ValueType.integer, value: 0)],
            root: 0),
        result: BuilderResult.body(0),
        bodyCount: 1);
    final failures = <Object>[];
    final runtime = Runtime()
      ..update(
          const LibraryName(['probe']),
          LocalWidgetLibrary({
            kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
            'Body': (context, source) => const Text('callback supplied',
                textDirection: TextDirection.ltr),
            'Probe': (context, source) {
              source = RestageValueBinding.dataSource(source, context);
              return RestageBuilderBinding.construct((bindings) {
                final presence =
                    RestageRfwConstructorPresence.read(source, ['builder']);
                final binding = RestageBuilderBinding.optional(
                    source, presence.valuePath,
                    contract: contract);
                if (binding != null) bindings.add(binding);
                try {
                  return Function.apply(
                      _RequiredBuilderProbe.new,
                      const <Object?>[],
                      <Symbol, Object?>{
                        if (presence.supplied)
                          #builder: binding == null
                              ? null
                              : (BuildContext context) =>
                                  binding.build(context, const {}),
                      }) as Widget;
                } catch (error) {
                  failures.add(error);
                  return const SizedBox();
                }
              });
            },
          }));
    final callback =
        '$kBuilderContinuationWidgetName(version:1,program:${jsonEncode(program.encode())},captures:{},bodies:[(frame)=>Body()])';
    final marker = RfwConstructorPresenceProtocol.markerKey;
    final value = RfwConstructorPresenceProtocol.valueKey;
    for (final (argument, label) in [
      ("builder:{'$marker':1}", 'null supplied'),
      ("builder:{'$marker':1,'$value':$callback}", 'callback supplied'),
    ]) {
      runtime.update(const LibraryName(['test']),
          rfw.parseLibraryFile('import probe;widget Root=Probe($argument);'));
      await tester.pumpWidget(RemoteWidget(
          runtime: runtime,
          data: DynamicContent(),
          widget:
              const FullyQualifiedWidgetName(LibraryName(['test']), 'Root')));
      expect(tester.takeException(), isNull);
      expect(failures, isEmpty);
      expect(find.text(label), findsOneWidget);
    }
    runtime.update(const LibraryName(['test']),
        rfw.parseLibraryFile('import probe;widget Root=Probe();'));
    await tester.pump();
    expect(failures, hasLength(1));
    expect(failures.single, isA<NoSuchMethodError>());
  });
}
