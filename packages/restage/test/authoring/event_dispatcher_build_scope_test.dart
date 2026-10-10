import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

final class _Value extends InheritedWidget {
  const _Value({required this.value, required super.child});

  final int value;

  @override
  bool updateShouldNotify(_Value oldWidget) => value != oldWidget.value;
}

final class _Dependent extends StatelessWidget {
  const _Dependent({required this.onBuilt});

  final void Function(VoidCallback callback) onBuilt;

  @override
  Widget build(BuildContext context) {
    final value = context.dependOnInheritedWidgetOfExactType<_Value>()!.value;
    onBuilt(paywallEvent('value', args: <String, Object?>{'value': value}));
    return Text('$value', textDirection: TextDirection.ltr);
  }
}

final class _Host extends StatefulWidget {
  const _Host({required this.onEvent, required this.onBuilt});

  final PaywallEventHandler onEvent;
  final void Function(VoidCallback callback) onBuilt;

  @override
  State<_Host> createState() => _HostState();
}

final class _HostState extends State<_Host> {
  var value = 0;
  var showDependent = true;

  void update({required int value, required bool showDependent}) =>
      setState(() {
        this.value = value;
        this.showDependent = showDependent;
      });

  @override
  Widget build(BuildContext context) => _Value(
        value: value,
        child: RestagePaywallEventDispatcher(
          onEvent: widget.onEvent,
          child: showDependent
              ? _Dependent(onBuilt: widget.onBuilt)
              : const SizedBox.shrink(),
        ),
      );
}

void main() {
  testWidgets('a dependent removed in the frame it was dirtied does not throw',
      (tester) async {
    await tester.pumpWidget(_Host(onEvent: (_, __) {}, onBuilt: (_) {}));

    tester
        .state<_HostState>(find.byType(_Host))
        .update(value: 1, showDependent: false);
    await tester.pump();
    await tester.pump();
    await tester.idle();

    expect(tester.takeException(), isNull);
    expect(find.byType(_Dependent), findsNothing);
  });

  testWidgets('a dependent removed while covered does not throw when shown',
      (tester) async {
    final cover = OverlayEntry(
      opaque: true,
      builder: (_) => const SizedBox.expand(),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              maintainState: true,
              builder: (_) => _Host(onEvent: (_, __) {}, onBuilt: (_) {}),
            ),
            cover,
          ],
        ),
      ),
    );

    tester
        .state<_HostState>(find.byType(_Host, skipOffstage: false))
        .update(value: 1, showDependent: false);
    await tester.pump();
    await tester.pump();
    cover.remove();
    await tester.pump();
    await tester.idle();

    expect(tester.takeException(), isNull);
    expect(find.byType(_Dependent), findsNothing);
    cover.dispose();
  });

  testWidgets('a dependent rebuilt by the scope binds to the dispatcher',
      (tester) async {
    final received = <Object?>[];
    VoidCallback? latest;
    await tester.pumpWidget(
      _Host(
        onEvent: (_, args) => received.add(args['value']),
        onBuilt: (callback) => latest = callback,
      ),
    );

    tester
        .state<_HostState>(find.byType(_Host))
        .update(value: 2, showDependent: true);
    await tester.pump();

    expect(find.text('2'), findsOneWidget);
    latest!();
    expect(received, <Object?>[2]);
  });
}
