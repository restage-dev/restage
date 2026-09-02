import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/flow/flow_runtime_support.dart'
    show populateFlowScreenData;
import 'package:restage/src/runtime/context_data.dart'
    show ContextPublisher, ContextSnapshot;
import 'package:rfw/rfw.dart';

/// Reads a top-level key from [DynamicContent] via its public `subscribe` API,
/// which returns the RFW `missing` sentinel when the key is absent.
Object _read(DynamicContent dc, String key) {
  void noop(Object _) {}
  final value = dc.subscribe(<Object>[key], noop);
  dc.unsubscribe(<Object>[key], noop);
  return value;
}

void main() {
  setUp(Restage.debugReset);

  testWidgets('omitting context arguments preserves the existing namespace set',
      (tester) async {
    late final BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final dc = DynamicContent();
    populateFlowScreenData(
      ctx,
      dc,
      includeInheritedData: true,
    );

    // The projected namespaces are present.
    expect(_read(dc, 'device'), isA<Map<Object?, Object?>>());
    expect(_read(dc, 'theme'), isA<Map<Object?, Object?>>());

    expect(_read(dc, 'products'), same(missing));
    expect(_read(dc, 'flowState'), same(missing));
    expect(_read(dc, 'state'), same(missing));
    expect(_read(dc, 'context'), same(missing));
  });

  // The screen-event to analytics channel is safe only while flow state and
  // products never reach a screen's data. Host context is the one deliberately
  // projected namespace; admitting any other must turn this red.
  testWidgets('projects host context without admitting products or flow state',
      (tester) async {
    late final BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final dc = DynamicContent();
    populateFlowScreenData(
      ctx,
      dc,
      includeInheritedData: true,
      contextPublisher: ContextPublisher(dc),
      hostContext: ContextSnapshot.of(const <String, Object?>{'plan': 'pro'}),
    );

    expect(_read(dc, 'context'), <Object?, Object?>{'plan': 'pro'});
    expect(_read(dc, 'device'), isA<Map<Object?, Object?>>());
    expect(_read(dc, 'theme'), isA<Map<Object?, Object?>>());

    expect(_read(dc, 'products'), same(missing));
    expect(_read(dc, 'flowState'), same(missing));
    expect(_read(dc, 'state'), same(missing));
  });

  testWidgets('publishes context before inherited data is available',
      (tester) async {
    late final BuildContext ctx;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ),
    );

    final dc = DynamicContent();
    populateFlowScreenData(
      ctx,
      dc,
      includeInheritedData: false,
      contextPublisher: ContextPublisher(dc),
      hostContext: ContextSnapshot.of(
        const <String, Object?>{'status': 'ready'},
      ),
    );

    expect(_read(dc, 'context'), <Object?, Object?>{'status': 'ready'});
    expect(_read(dc, 'device'), same(missing));
    expect(_read(dc, 'theme'), same(missing));
  });

  testWidgets('rejects a context snapshot without a target publisher',
      (tester) async {
    late final BuildContext ctx;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ),
    );

    expect(
      () => populateFlowScreenData(
        ctx,
        DynamicContent(),
        includeInheritedData: false,
        hostContext: ContextSnapshot.of(
          const <String, Object?>{'status': 'ready'},
        ),
      ),
      throwsAssertionError,
    );
  });
}
