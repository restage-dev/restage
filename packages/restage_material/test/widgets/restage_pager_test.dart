import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:restage_material/restage_material_runtime.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch, WidgetLibrary;

void main() {
  group('RestagePager', () {
    test('asserts children is non-empty', () {
      expect(
        () => RestagePager(children: const []),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            'RestagePager.children must be non-empty.',
          ),
        ),
      );
    });

    test('asserts initialPage is non-negative', () {
      expect(
        () => RestagePager(
          initialPage: -1,
          children: const [SizedBox()],
        ),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            'RestagePager.initialPage must be non-negative.',
          ),
        ),
      );
    });

    test('asserts viewportFraction is in range', () {
      expect(
        () => RestagePager(
          viewportFraction: 0,
          children: const [SizedBox()],
        ),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            'RestagePager.viewportFraction must be in (0, 1].',
          ),
        ),
      );
      expect(
        () => RestagePager(
          viewportFraction: 1.1,
          children: const [SizedBox()],
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    testWidgets('works without a presentation sink', (tester) async {
      final pages = <int>[];
      await tester.pumpWidget(_pager(onPageChanged: pages.add));

      await _settleOnSecondPage(tester);

      expect(pages, <int>[1]);
    });

    testWidgets('delivers the sink before the author callback', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        RestagePagerEventScope(
          sink: RestagePagerEventSink(
            stageToken: Object(),
            isCurrent: (_) => true,
            onPageChanged: (index, count) => calls.add('sink:$index/$count'),
          ),
          child: _pager(
            onPageChanged: (index) => calls.add('author:$index'),
          ),
        ),
      );

      await _settleOnSecondPage(tester);

      expect(calls, <String>['sink:1/2', 'author:1']);
    });

    testWidgets('ignores a stale sink and still calls the author callback',
        (tester) async {
      var sinkCalls = 0;
      final pages = <int>[];
      await tester.pumpWidget(
        RestagePagerEventScope(
          sink: RestagePagerEventSink(
            stageToken: Object(),
            isCurrent: (_) => false,
            onPageChanged: (_, __) => sinkCalls += 1,
          ),
          child: _pager(onPageChanged: pages.add),
        ),
      );

      await _settleOnSecondPage(tester);

      expect(sinkCalls, 0);
      expect(pages, <int>[1]);
    });

    testWidgets('contains sink failures and preserves author failures',
        (tester) async {
      var authorCalls = 0;
      await tester.pumpWidget(
        RestagePagerEventScope(
          sink: RestagePagerEventSink(
            stageToken: Object(),
            isCurrent: (_) => true,
            onPageChanged: (_, __) => throw StateError('sink failure'),
          ),
          child: _pager(onPageChanged: (_) => authorCalls += 1),
        ),
      );

      await _settleOnSecondPage(tester);
      expect(authorCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        RestagePagerEventScope(
          sink: RestagePagerEventSink(
            stageToken: Object(),
            isCurrent: (_) => true,
            onPageChanged: (_, __) {},
          ),
          child: _pager(
            onPageChanged: (_) => throw StateError('author failure'),
          ),
        ),
      );

      await _settleOnSecondPage(tester);
      expect(tester.takeException(), isA<StateError>());
    });

    testWidgets('keeps author delivery after a sink-triggered dismissal',
        (tester) async {
      final visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);
      var authorCalls = 0;
      await tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, isVisible, _) {
            if (!isVisible) return const SizedBox.shrink();
            return RestagePagerEventScope(
              sink: RestagePagerEventSink(
                stageToken: Object(),
                isCurrent: (_) => true,
                onPageChanged: (_, __) => visible.value = false,
              ),
              child: _pager(onPageChanged: (_) => authorCalls += 1),
            );
          },
        ),
      );

      await _settleOnSecondPage(tester);

      expect(authorCalls, 1);
      expect(find.byType(RestagePager), findsNothing);
    });

    testWidgets('retains the generated author event payload', (tester) async {
      const rootLibrary = LibraryName(<String>['restage', 'paywall']);
      final events = <(String, Object?)>[];
      final runtime = Runtime()
        ..update(
          const LibraryName(<String>['restage', 'core']),
          core.buildCoreWidgetLibrary(),
        )
        ..update(
          const LibraryName(<String>['restage', 'material']),
          buildMaterialWidgetLibrary(),
        )
        ..update(
          rootLibrary,
          parseLibraryFile('''
            import restage.core;
            import restage.material;
            widget Paywall = SizedBox(
              width: 240.0,
              height: 160.0,
              child: RestagePager(
                onPageChanged: event "page_changed" { },
                children: [SizedBox(), SizedBox()],
              ),
            );
          '''),
        );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(rootLibrary, 'Paywall'),
            onEvent: (name, args) => events.add((name, args)),
          ),
        ),
      );

      await _settleOnSecondPage(tester);

      expect(events, hasLength(1));
      expect(events.single.$1, 'page_changed');
      expect(
        (events.single.$2! as Map).cast<String, Object?>(),
        <String, Object?>{'value': 1},
      );
    });
  });
}

Widget _pager({ValueChanged<int>? onPageChanged}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox(
      width: 240,
      height: 160,
      child: RestagePager(
        onPageChanged: onPageChanged,
        children: const <Widget>[SizedBox(), SizedBox()],
      ),
    ),
  );
}

Future<void> _settleOnSecondPage(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
  await tester.pumpAndSettle();
}
