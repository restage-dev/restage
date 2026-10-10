import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart' show encodeLibraryBlob, parseLibraryFile;

import 'flow_test_support.dart';

Uint8List _plansScreen() {
  const source = '''
    import restage.core;
    widget OnboardingScreen = Column(children: [
      ...for plan in data.context.plans:
        GestureDetector(
          onTap: event "pick" { plan: plan },
          child: Text(text: plan.__restage_index),
        ),
    ]);
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

void main() {
  testWidgets(
      'a screen view loop reads each position, and a tapped element still '
      'reaches the flow', (tester) async {
    final welcome = _plansScreen();
    final profile = screenBlob('Profile', 'finish');
    final events = <RestageEvent>[];
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(
        resolvedFlow(
          document: flowDocument(
            screenHashes: {
              'welcome': FlowContentHash.compute(welcome),
              'profile': FlowContentHash.compute(profile),
            },
            outbound: const FlowOutboundDeclarations(
              customEvents: {
                'pick': FlowOutboundPayloadDeclaration(fields: {
                  'id': FlowOutboundField(
                    type: FlowDataType.string,
                    ref: EventFlowOutboundRef(key: 'plan', path: ['id']),
                  ),
                }),
              },
            ),
          ),
          screenBlobs: <String, Uint8List>{
            'welcome': welcome,
            'profile': profile,
          },
        ),
      ),
      actions: null,
      onEvent: events.add,
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RestageScreenView<FirstRunResult>(
        controller: controller,
        context: const <String, Object?>{
          'plans': <Object?>[
            <String, Object?>{'id': 'monthly'},
            <String, Object?>{'id': 'annual'},
          ],
        },
      ),
    ));
    unawaited(controller.load());
    await tester.pumpAndSettle();
    final rendered = <int>[
      find.text('1').evaluate().length,
      find.text('2').evaluate().length,
    ];

    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    final picked = events
        .whereType<FlowCustomEvent>()
        .where((event) => event.eventName == 'pick')
        .map((event) => event.fields)
        .toList();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(rendered, <int>[1, 1]);
    expect(picked, <Map<String, Object?>>[
      <String, Object?>{'id': 'annual'},
    ]);
  });
}
