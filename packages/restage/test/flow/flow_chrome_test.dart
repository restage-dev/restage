import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  group('FlowChromeTheme', () {
    test('value-equal themes are == and share a hashCode', () {
      const a = FlowChromeTheme(
        backIcon: IconData(0xe5c4, fontFamily: 'MaterialIcons'),
        color: Color(0xFF112233),
        size: 30,
        padding: EdgeInsets.all(10),
        skipLabel: 'Later',
        skipTextStyle: TextStyle(fontSize: 18),
      );
      const b = FlowChromeTheme(
        backIcon: IconData(0xe5c4, fontFamily: 'MaterialIcons'),
        color: Color(0xFF112233),
        size: 30,
        padding: EdgeInsets.all(10),
        skipLabel: 'Later',
        skipTextStyle: TextStyle(fontSize: 18),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing themes are not ==', () {
      const a = FlowChromeTheme(color: Color(0xFF112233));
      const b = FlowChromeTheme(color: Color(0xFF445566));
      expect(a, isNot(equals(b)));
    });

    test('copyWith overrides one field and leaves the rest', () {
      const base = FlowChromeTheme(
        color: Color(0xFF112233),
        size: 30,
        skipLabel: 'Later',
      );
      final next = base.copyWith(size: 44);
      expect(next.size, 44);
      expect(next.color, const Color(0xFF112233));
      expect(next.skipLabel, 'Later');
      expect(next, isNot(equals(base)));
    });

    test('copyWith with no overrides equals the original', () {
      const base = FlowChromeTheme(color: Color(0xFF112233), size: 30);
      expect(base.copyWith(), equals(base));
    });

    test('an empty theme has all-null tokens (defaults applied by the view)',
        () {
      const theme = FlowChromeTheme();
      expect(theme.backIcon, isNull);
      expect(theme.color, isNull);
      expect(theme.size, isNull);
      expect(theme.padding, isNull);
      expect(theme.skipLabel, isNull);
      expect(theme.skipTextStyle, isNull);
    });
  });

  group('FlowChromeState', () {
    void noop() {}

    FlowChromeState state({
      VoidCallback? onBack,
      VoidCallback? onSkip,
      bool canBack = true,
      bool canSkip = false,
      bool isForward = true,
      String? screenId = 'welcome',
      bool isComplete = false,
      bool isBusy = false,
    }) {
      return FlowChromeState(
        onBack: onBack ?? noop,
        onSkip: onSkip ?? noop,
        canBack: canBack,
        canSkip: canSkip,
        isForward: isForward,
        screenId: screenId,
        isComplete: isComplete,
        isBusy: isBusy,
      );
    }

    test('exposes the runtime-honest signals (no step index/count)', () {
      final s = state();
      expect(s.canBack, isTrue);
      expect(s.canSkip, isFalse);
      expect(s.isForward, isTrue);
      expect(s.screenId, 'welcome');
      expect(s.isComplete, isFalse);
      expect(s.isBusy, isFalse);
      expect(s.onBack, isA<VoidCallback>());
      expect(s.onSkip, isA<VoidCallback>());
    });

    test('value-equal states are == and hash equal', () {
      expect(state(), equals(state()));
      expect(state().hashCode, equals(state().hashCode));
    });

    test(
        'the callbacks are excluded from equality — distinct closures with '
        'identical value fields are == and hash equal', () {
      void otherBack() {}
      void otherSkip() {}
      expect(
        state(onBack: noop, onSkip: noop),
        equals(state(onBack: otherBack, onSkip: otherSkip)),
      );
      expect(
        state(onBack: noop, onSkip: noop).hashCode,
        equals(state(onBack: otherBack, onSkip: otherSkip).hashCode),
      );
    });

    test('states differing in any field are not ==', () {
      expect(state(canBack: true), isNot(equals(state(canBack: false))));
      expect(state(isBusy: false), isNot(equals(state(isBusy: true))));
      expect(state(isComplete: false), isNot(equals(state(isComplete: true))));
      expect(state(screenId: 'a'), isNot(equals(state(screenId: 'b'))));
    });
  });
}
