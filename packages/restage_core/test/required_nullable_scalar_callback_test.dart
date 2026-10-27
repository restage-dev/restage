import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

class _RequiredIndexProbe extends StatelessWidget {
  const _RequiredIndexProbe({required this.callback});
  final int? Function(Key)? callback;
  @override
  Widget build(BuildContext context) => Text(
      callback?.call(const ValueKey<int>(1))?.toString() ?? 'null supplied',
      textDirection: TextDirection.ltr);
}

void main() {
  testWidgets('required nullable scalar factory preserves supplied null',
      (tester) async {
    const program = ValueProgram(
        nodes: [ValueNode('literal', ValueType.integer, value: 7)], root: 0);
    final failures = <Object>[];
    final runtime = Runtime()
      ..update(
          const LibraryName(['probe']),
          LocalWidgetLibrary({
            kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
            'Probe': (context, source) {
              source = RestageValueBinding.dataSource(source, context);
              return RestageBuilderBinding.construct((bindings) {
                final presence =
                    RestageRfwConstructorPresence.read(source, ['callback']);
                final binding = RestageBuilderBinding.optional(
                    source, presence.valuePath,
                    scalarContract: const ScalarCallbackContract(
                        parameters: [ScalarCallbackParameter.valueKey]));
                if (binding != null) bindings.add(binding);
                try {
                  return Function.apply(
                      _RequiredIndexProbe.new, const <Object?>[], {
                    if (presence.supplied)
                      #callback: binding == null
                          ? null
                          : (Key key) =>
                              binding.evaluateKey(context, key) as int?,
                  }) as Widget;
                } catch (error) {
                  failures.add(error);
                  return const SizedBox();
                }
              });
            },
          }));
    final callback =
        '$kBuilderContinuationWidgetName(version:1,program:${jsonEncode(program.encode())},captures:{})';
    const marker = RfwConstructorPresenceProtocol.markerKey;
    const value = RfwConstructorPresenceProtocol.valueKey;
    for (final (argument, label) in [
      ("callback:{'$marker':1}", 'null supplied'),
      ("callback:{'$marker':1,'$value':$callback}", '7'),
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
    for (final argument in ['', 'callback:null']) {
      runtime.update(const LibraryName(['test']),
          rfw.parseLibraryFile('import probe;widget Root=Probe($argument);'));
      await tester.pump();
    }
    expect(failures, hasLength(2));
    expect(failures, everyElement(isA<NoSuchMethodError>()));
  });
}
