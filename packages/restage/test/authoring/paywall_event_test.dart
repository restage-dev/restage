import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

final class _RebuildingPaywallProbe extends StatefulWidget {
  const _RebuildingPaywallProbe({
    super.key,
    required this.label,
    required this.onBuilt,
  });

  final String label;
  final void Function(int build, VoidCallback callback) onBuilt;

  @override
  State<_RebuildingPaywallProbe> createState() =>
      _RebuildingPaywallProbeState();
}

final class _RebuildingPaywallProbeState
    extends State<_RebuildingPaywallProbe> {
  var _build = 0;

  void rebuild() => setState(() => _build += 1);

  @override
  Widget build(BuildContext context) {
    widget.onBuilt(
      _build,
      paywallEvent(
        'selected_plan',
        args: <String, Object?>{
          'label': widget.label,
          'build': _build,
        },
      ),
    );
    return const SizedBox();
  }
}

void main() {
  testWidgets('paywallEvent without a dispatcher reports an error',
      (tester) async {
    final callback = paywallEvent(
      'subscribe',
      args: const <String, Object?>{'plan': 'monthly'},
    );

    expect(callback, throwsAssertionError);
  });

  testWidgets('paywallEvent preserves its name and arguments', (tester) async {
    String? receivedName;
    Map<String, Object?>? receivedArgs;
    VoidCallback? captured;
    await tester.pumpWidget(
      RestagePaywallEventDispatcher(
        onEvent: (name, args) {
          receivedName = name;
          receivedArgs = args;
        },
        child: Builder(
          builder: (_) {
            captured = paywallEvent(
              'subscribe',
              args: const <String, Object?>{'plan': 'monthly'},
            );
            return const SizedBox();
          },
        ),
      ),
    );

    captured!();

    expect(receivedName, 'subscribe');
    expect(receivedArgs, <String, Object?>{'plan': 'monthly'});
  });

  testWidgets('the dispatcher drops the reserved bare restore event',
      (tester) async {
    var received = false;
    VoidCallback? captured;
    await tester.pumpWidget(
      RestagePaywallEventDispatcher(
        onEvent: (_, __) => received = true,
        child: Builder(
          builder: (_) {
            captured = paywallEvent('restore');
            return const SizedBox();
          },
        ),
      ),
    );

    captured!();

    expect(received, isFalse);
  });

  testWidgets('retained callbacks refuse handler replacement', (tester) async {
    final received = <String>[];
    late StateSetter updateHost;
    PaywallEventHandler handler = (_, __) => received.add('first');
    VoidCallback? captured;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateHost = setState;
          return RestagePaywallEventDispatcher(
            onEvent: handler,
            child: Builder(
              builder: (_) {
                captured = paywallEvent('subscribe');
                return const SizedBox();
              },
            ),
          );
        },
      ),
    );
    final retained = captured!;

    updateHost(() {
      handler = (_, __) => received.add('second');
    });
    await tester.pump();
    final current = captured!;
    expect(retained, throwsAssertionError);
    current();

    expect(received, <String>['second']);
  });

  testWidgets('a scheduled descendant rebuild uses the current handler',
      (tester) async {
    final received = <Map<String, Object?>>[];
    final probeKey = GlobalKey<_RebuildingPaywallProbeState>();
    VoidCallback? captured;
    late StateSetter updateHost;
    PaywallEventHandler handler = (name, args) => received.add(
          <String, Object?>{
            'handler': 'first',
            'name': name,
            'args': Map<String, Object?>.of(args),
          },
        );
    final child = _RebuildingPaywallProbe(
      key: probeKey,
      label: 'updated-value',
      onBuilt: (_, callback) => captured = callback,
    );
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateHost = setState;
          return RestagePaywallEventDispatcher(
            onEvent: handler,
            child: child,
          );
        },
      ),
    );

    probeKey.currentState!.rebuild();
    updateHost(() {
      handler = (name, args) => received.add(<String, Object?>{
            'handler': 'second',
            'name': name,
            'args': Map<String, Object?>.of(args),
          });
    });
    await tester.pump();
    captured!();

    expect(received, <Map<String, Object?>>[
      <String, Object?>{
        'handler': 'second',
        'name': 'selected_plan',
        'args': <String, Object?>{'label': 'updated-value', 'build': 1},
      },
    ]);
  });

  testWidgets('removing a dispatcher cancels a pending descendant rebuild',
      (tester) async {
    final received = <Map<String, Object?>>[];
    final published = <({int build, VoidCallback callback})>[];
    final probeKey = GlobalKey<_RebuildingPaywallProbeState>();
    late StateSetter updateHost;
    var showDispatcher = true;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateHost = setState;
          if (!showDispatcher) return const SizedBox.shrink();
          return RestagePaywallEventDispatcher(
            onEvent: (name, args) => received.add(<String, Object?>{
              'name': name,
              'args': Map<String, Object?>.of(args),
            }),
            child: _RebuildingPaywallProbe(
              key: probeKey,
              label: 'removed-value',
              onBuilt: (build, callback) => published.add(
                (build: build, callback: callback),
              ),
            ),
          );
        },
      ),
    );
    expect(published.map((entry) => entry.build), <int>[0]);
    expect(activeDispatcher(), isNotNull);
    final retained = published.single.callback;

    probeKey.currentState!.rebuild();
    updateHost(() => showDispatcher = false);
    final pumpedFrames = await tester.pumpAndSettle();

    expect(pumpedFrames, greaterThanOrEqualTo(1));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(probeKey.currentState, isNull);
    expect(published.map((entry) => entry.build), <int>[0]);
    expect(received, isEmpty);
    expect(tester.takeException(), isNull);

    expect(retained, throwsAssertionError);

    expect(received, isEmpty);
    expect(tester.takeException(), isNull);
    expect(activeDispatcher(), isNull);
  });

  testWidgets('retained callbacks refuse disposal', (tester) async {
    final received = <String>[];
    VoidCallback? captured;
    await tester.pumpWidget(
      RestagePaywallEventDispatcher(
        onEvent: (_, __) => received.add('called'),
        child: Builder(
          builder: (_) {
            captured = paywallEvent('subscribe');
            return const SizedBox();
          },
        ),
      ),
    );
    final retained = captured!;

    await tester.pumpWidget(const SizedBox.shrink());
    expect(retained, throwsAssertionError);

    expect(received, isEmpty);
  });

  testWidgets('simultaneous dispatchers bind exact descendants',
      (tester) async {
    final received = <String>[];
    VoidCallback? first;
    VoidCallback? second;
    await tester.pumpWidget(
      Column(
        children: <Widget>[
          RestagePaywallEventDispatcher(
            onEvent: (_, __) => received.add('first'),
            child: Builder(
              builder: (_) {
                first = paywallEvent('subscribe');
                return const SizedBox();
              },
            ),
          ),
          RestagePaywallEventDispatcher(
            onEvent: (_, __) => received.add('second'),
            child: Builder(
              builder: (_) {
                second = paywallEvent('subscribe');
                return const SizedBox();
              },
            ),
          ),
        ],
      ),
    );

    first!();
    second!();

    expect(received, <String>['first', 'second']);
  });

  testWidgets(
      'independent descendant rebuilds keep simultaneous dispatchers exact',
      (tester) async {
    final received = <Map<String, Object?>>[];
    final firstKey = GlobalKey<_RebuildingPaywallProbeState>();
    VoidCallback? first;
    VoidCallback? second;
    await tester.pumpWidget(
      Column(
        children: <Widget>[
          RestagePaywallEventDispatcher(
            onEvent: (name, args) => received.add(<String, Object?>{
              'route': 'first',
              'name': name,
              'args': Map<String, Object?>.of(args),
            }),
            child: _RebuildingPaywallProbe(
              key: firstKey,
              label: 'first-value',
              onBuilt: (_, callback) => first = callback,
            ),
          ),
          RestagePaywallEventDispatcher(
            onEvent: (name, args) => received.add(<String, Object?>{
              'route': 'second',
              'name': name,
              'args': Map<String, Object?>.of(args),
            }),
            child: _RebuildingPaywallProbe(
              label: 'second-value',
              onBuilt: (_, callback) => second = callback,
            ),
          ),
        ],
      ),
    );

    firstKey.currentState!.rebuild();
    await tester.pump();
    first!();
    second!();

    expect(received, <Map<String, Object?>>[
      <String, Object?>{
        'route': 'first',
        'name': 'selected_plan',
        'args': <String, Object?>{'label': 'first-value', 'build': 1},
      },
      <String, Object?>{
        'route': 'second',
        'name': 'selected_plan',
        'args': <String, Object?>{'label': 'second-value', 'build': 0},
      },
    ]);
  });

  testWidgets('multiple mounted dispatchers refuse an unscoped lookup',
      (tester) async {
    final received = <String>[];
    await tester.pumpWidget(
      Column(
        children: <Widget>[
          RestagePaywallEventDispatcher(
            onEvent: (_, __) => received.add('first'),
            child: const SizedBox(),
          ),
          RestagePaywallEventDispatcher(
            onEvent: (_, __) => received.add('second'),
            child: const SizedBox(),
          ),
        ],
      ),
    );

    activeDispatcher()!('subscribe', const <String, Object?>{});

    expect(received, isEmpty);
  });

  testWidgets('nested dispatcher builds bind the inner descendant',
      (tester) async {
    final received = <String>[];
    VoidCallback? captured;
    await tester.pumpWidget(
      RestagePaywallEventDispatcher(
        onEvent: (_, __) => received.add('outer'),
        child: RestagePaywallEventDispatcher(
          onEvent: (_, __) => received.add('inner'),
          child: Builder(
            builder: (_) {
              captured = paywallEvent('subscribe');
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    captured!();

    expect(received, <String>['inner']);
  });

  testWidgets('independent descendant rebuilds keep nested dispatch exact',
      (tester) async {
    final received = <Map<String, Object?>>[];
    final probeKey = GlobalKey<_RebuildingPaywallProbeState>();
    VoidCallback? captured;
    await tester.pumpWidget(
      RestagePaywallEventDispatcher(
        onEvent: (name, args) => received.add(<String, Object?>{
          'route': 'outer',
          'name': name,
          'args': Map<String, Object?>.of(args),
        }),
        child: RestagePaywallEventDispatcher(
          onEvent: (name, args) => received.add(<String, Object?>{
            'route': 'inner',
            'name': name,
            'args': Map<String, Object?>.of(args),
          }),
          child: _RebuildingPaywallProbe(
            key: probeKey,
            label: 'nested-value',
            onBuilt: (_, callback) => captured = callback,
          ),
        ),
      ),
    );

    probeKey.currentState!.rebuild();
    await tester.pump();
    captured!();

    expect(received, <Map<String, Object?>>[
      <String, Object?>{
        'route': 'inner',
        'name': 'selected_plan',
        'args': <String, Object?>{'label': 'nested-value', 'build': 1},
      },
    ]);
  });
}
