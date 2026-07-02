import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/flow/flow_runtime_support.dart'
    show populateFlowScreenData;
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

  // Event-closure guard: the `EventFlowValueSource` / `onEvent` → analytics
  // channel is safe ONLY because flow-state never reaches a screen — so no
  // screen-fired event can carry app-supplied (incl. host-seeded) flow-state to
  // analytics. That closure holds by construction because `populateFlowScreenData`
  // projects ONLY product / device / theme onto a screen's `DynamicContent`. This
  // test locks that: a future prefill-from-flow-state or `data.context.*`-into-
  // screen change would silently reopen the Event→analytics path and MUST turn
  // this red.
  testWidgets(
      'populateFlowScreenData projects only product/device/theme onto a screen '
      '— never flow-state or data.context', (tester) async {
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
      priceQueries: const {},
      includeInheritedData: true,
    );

    // The three projected namespaces are present.
    expect(_read(dc, 'products'), isA<Map<Object?, Object?>>());
    expect(_read(dc, 'device'), isA<Map<Object?, Object?>>());
    expect(_read(dc, 'theme'), isA<Map<Object?, Object?>>());

    // Flow-state (incl. host-seeded) and host-context are NEVER projected onto a
    // screen — absent keys read back as the RFW `missing` sentinel.
    expect(_read(dc, 'flowState'), same(missing));
    expect(_read(dc, 'state'), same(missing));
    expect(_read(dc, 'context'), same(missing));
  });
}
