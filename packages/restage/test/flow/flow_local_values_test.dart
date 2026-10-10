import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_sections_carrier.dart';
import 'package:restage/src/runtime/local_values.dart';
import 'package:restage_shared/restage_shared.dart'
    show EndFlowState, FlowContentHash, FlowTransition, ScreenFlowState;
import 'package:rfw/formats.dart' show encodeLibraryBlob, parseLibraryFile;

import 'flow_test_support.dart';

Uint8List _answerScreenBlob() {
  const source = '''
    import restage.core;
    import restage.material;
    widget OnboardingScreen = Column(children: [
      TextField(onChanged: event "restage.local.set" { key: "name" }),
      switch data.local.name {
        "Ada": Text(text: "Hello Ada"),
        "Grace": Text(text: "Hello Grace"),
        default: Text(text: "Hello"),
      },
      GestureDetector(onTap: event "next" { }, child: Text(text: "Next")),
    ]);
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

void main() {
  testWidgets(
      'a flow screen keeps its own local values, and the write never reaches '
      'the flow or the host', (tester) async {
    final hostEvents = <Object?>[];
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(
        resolvedFlow(screenBlobs: <String, Uint8List>{
          'welcome': _answerScreenBlob(),
        }),
      ),
      actions: null,
      onEvent: hostEvents.add,
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
          home: Scaffold(body: RestageFlowView(controller: controller))),
    );
    unawaited(controller.load());
    await tester.pumpAndSettle();
    final before = find.text('Hello').evaluate().length;
    final eventsBeforeWrite = List<Object?>.of(hostEvents);

    tester.widget<TextField>(find.byType(TextField)).onChanged!('Ada');
    await tester.pump();
    final greeted = find.text('Hello Ada').evaluate().length;
    final screenAfterWrite = controller.currentScreenId;
    final unavailable = controller.isUnavailable;
    final eventsAfterWrite = List<Object?>.of(hostEvents);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    final screenAfterNext = controller.currentScreenId;

    // Unmount first so a failing expectation is reported, not swallowed.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(before, 1);
    expect(greeted, 1);
    expect(screenAfterWrite, 'welcome');
    expect(unavailable, isFalse);
    expect(eventsAfterWrite, eventsBeforeWrite);
    expect(screenAfterNext, 'profile');
  });

  testWidgets('a flow screen is seeded by its screen id', (tester) async {
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(
        attachSurfaceSections(
          resolvedFlow(screenBlobs: <String, Uint8List>{
            'welcome': _answerScreenBlob(),
          }),
          const SurfaceSections(localSeeds: <String, Map<String, Object>>{
            'welcome': <String, Object>{'name': 'Grace'},
          }),
        ),
      ),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
          home: Scaffold(body: RestageFlowView(controller: controller))),
    );
    unawaited(controller.load());
    await tester.pumpAndSettle();
    final seeded = find.text('Hello Grace').evaluate().length;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(seeded, 1);
  });

  testWidgets('a state showing another screen is seeded by that screen',
      (tester) async {
    final blob = _answerScreenBlob();
    final hash = FlowContentHash.compute(blob);
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(
        attachSurfaceSections(
          resolvedFlow(
            document: flowDocument(
              screenHashes: {'welcome': hash, 'profile': hash},
              states: const {
                'welcome': ScreenFlowState(
                  screen: 'profile',
                  on: {'next': FlowTransition.goto('profile')},
                ),
                'profile': ScreenFlowState(
                  screen: 'welcome',
                  on: {'next': FlowTransition.goto('done')},
                ),
                'done': EndFlowState(result: {'completed': true}),
              },
            ),
            screenBlobs: <String, Uint8List>{'welcome': blob, 'profile': blob},
          ),
          const SurfaceSections(localSeeds: <String, Map<String, Object>>{
            'welcome': <String, Object>{'name': 'Ada'},
            'profile': <String, Object>{'name': 'Grace'},
          }),
        ),
      ),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
          home: Scaffold(body: RestageFlowView(controller: controller))),
    );
    unawaited(controller.load());
    await tester.pumpAndSettle();
    final grace = find.text('Hello Grace').evaluate().length;
    final ada = find.text('Hello Ada').evaluate().length;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect((grace: grace, ada: ada), (grace: 1, ada: 0));
  });

  testWidgets('a local write notifies the listener above the view',
      (tester) async {
    var writes = 0;
    final controller = RestageFlowController<FirstRunResult>(
      flow: firstRunFlowRef,
      resolver: StaticFlowResolver(
        resolvedFlow(screenBlobs: <String, Uint8List>{
          'welcome': _answerScreenBlob(),
        }),
      ),
      actions: null,
      onEvent: (_) {},
      onComplete: (_) {},
      onUnavailable: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalWriteListener(
            onWrite: () => writes += 1,
            child: RestageFlowView(controller: controller),
          ),
        ),
      ),
    );
    unawaited(controller.load());
    await tester.pumpAndSettle();

    tester.widget<TextField>(find.byType(TextField)).onChanged!('Ada');
    await tester.pump();
    final afterWrite = writes;
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    final afterTap = writes;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(afterWrite, 1);
    expect(afterTap, 1);
  });
}
