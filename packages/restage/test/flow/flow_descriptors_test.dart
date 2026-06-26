import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart' show kCapturedEventValueKey;

OnboardingScreenRef _screen(String id) => OnboardingScreenRef(
      id: id,
      artifactPath: '$id.rfw',
      version: 1,
      minClient: 3,
    );

void main() {
  group('ScreenNodeDef chained .on()', () {
    test('chaining .on() after .goTo() accumulates transitions in order', () {
      final a = _screen('a');
      final b = _screen('b');
      final c = _screen('c');
      const eventX = OnboardingEvent<void>('x');
      const eventY = OnboardingEvent<void>('y');

      final node = screen(a).on(eventX).goTo(b).on(eventY).goTo(c);

      expect(node.ref.id, 'a');
      expect(node.transitions, hasLength(2));
      expect(node.transitions[0].event.id, 'x');
      expect((node.transitions[0].target as OnboardingScreenRef).id, 'b');
      expect(node.transitions[1].event.id, 'y');
      expect((node.transitions[1].target as OnboardingScreenRef).id, 'c');
    });

    test('three-way fork accumulates three transitions', () {
      final a = _screen('a');
      final node = screen(a)
          .on(const OnboardingEvent<void>('x'))
          .goTo(_screen('x'))
          .on(const OnboardingEvent<void>('y'))
          .goTo(_screen('y'))
          .on(const OnboardingEvent<void>('z'))
          .goTo(_screen('z'));

      expect(node.transitions.map((t) => t.event.id), ['x', 'y', 'z']);
    });

    test('single .on().goTo() yields one transition with empty stateWrites',
        () {
      final a = _screen('a');
      final b = _screen('b');
      const eventX = OnboardingEvent<void>('x');

      final node = screen(a).on(eventX).goTo(b);

      expect(node.transitions, hasLength(1));
      expect(node.transitions.single.stateWrites, isEmpty);
      expect(node.transitions.single.action, isNull);
    });
  });

  group('.capture()', () {
    test('captures an int event value into the named flow-state write', () {
      final a = _screen('a');
      final b = _screen('b');
      const rating = OnboardingEvent<int>('rating');

      final node = screen(a).on(rating).capture('rating').goTo(b);

      final write = node.transitions.single.stateWrites['rating'];
      expect(write, isNotNull);
      expect(write!.type, FlowDataType.int);
      final value = write.value;
      expect(value, isA<EventFlowValueSource>());
      // The capture reads the reserved event-value key; 'rating' names only the
      // flow-state slot written.
      expect((value as EventFlowValueSource).key, kCapturedEventValueKey);
      expect(value.path, isEmpty);
    });

    test('infers string and bool flow-data types from the event T', () {
      final a = _screen('a');
      final b = _screen('b');

      final s = screen(a)
          .on(const OnboardingEvent<String>('goal'))
          .capture('goal')
          .goTo(b)
          .transitions
          .single
          .stateWrites['goal']!;
      expect(s.type, FlowDataType.string);

      final f = screen(a)
          .on(const OnboardingEvent<bool>('flag'))
          .capture('flag')
          .goTo(b)
          .transitions
          .single
          .stateWrites['flag']!;
      expect(f.type, FlowDataType.bool);
    });

    test('non-scalar capture (void event) is a loud error', () {
      final a = _screen('a');
      final b = _screen('b');
      const voidEvent = OnboardingEvent<void>('v');

      expect(
        () => screen(a).on(voidEvent).capture('k').goTo(b),
        throwsArgumentError,
      );
    });
  });

  group('.write()', () {
    test('writes a bool literal', () {
      final a = _screen('a');
      final b = _screen('b');
      const e = OnboardingEvent<void>('e');

      final write = screen(a)
          .on(e)
          .write('wantsReminders', true)
          .goTo(b)
          .transitions
          .single
          .stateWrites['wantsReminders']!;
      expect(write.type, FlowDataType.bool);
      final value = write.value;
      expect(value, isA<LiteralFlowValueSource>());
      expect((value as LiteralFlowValueSource).type, FlowDataType.bool);
      expect(value.value, true);
    });

    test('writes string and int literals with inferred types', () {
      final a = _screen('a');
      final b = _screen('b');
      const e = OnboardingEvent<void>('e');

      final s = screen(a)
          .on(e)
          .write('goal', 'sleep')
          .goTo(b)
          .transitions
          .single
          .stateWrites['goal']!;
      expect(s.type, FlowDataType.string);
      expect((s.value as LiteralFlowValueSource).value, 'sleep');

      final i = screen(a)
          .on(e)
          .write('count', 3)
          .goTo(b)
          .transitions
          .single
          .stateWrites['count']!;
      expect(i.type, FlowDataType.int);
      expect((i.value as LiteralFlowValueSource).value, 3);
    });

    test('unsupported literal type (double) is a loud error', () {
      final a = _screen('a');
      final b = _screen('b');
      const e = OnboardingEvent<void>('e');

      expect(
        () => screen(a).on(e).write('x', 3.14).goTo(b),
        throwsArgumentError,
      );
    });

    test('duplicate write key on one transition is a loud error', () {
      final a = _screen('a');
      final b = _screen('b');
      const e = OnboardingEvent<void>('e');

      expect(
        () => screen(a).on(e).write('k', true).write('k', false).goTo(b),
        throwsArgumentError,
      );
    });
  });

  group('action-gate + writes', () {
    test('write after .result() carries both action and write', () {
      final a = _screen('a');
      final b = _screen('b');
      const e = OnboardingEvent<void>('e');
      const action = FlowActionRef<void, bool>('act');

      final node = screen(a)
          .on(e)
          .run(action)
          .result((r) => r)
          .write('granted', true)
          .goTo(b);

      final t = node.transitions.single;
      expect(t.action, isNotNull);
      expect(t.stateWrites['granted'], isNotNull);
      expect(t.stateWrites['granted']!.type, FlowDataType.bool);
    });

    test('a write removes the action gate so write-before-run cannot compile',
        () {
      final a = _screen('a');
      const e = OnboardingEvent<void>('e');

      // `.on()` returns the run-capable builder; once a write is added the
      // builder is a plain write-builder with no `.run()`, so a
      // write-before-`.run()` chain is unconstructable (enforced by the static
      // return types below — there is no runtime path to assert).
      final entry = screen(a).on(e);
      expect(entry, isA<ScreenEventTransitionBuilder<void>>());
      final afterWrite = entry.write('k', true);
      expect(afterWrite, isA<ScreenEventWriteBuilder<void>>());
      expect(afterWrite, isNot(isA<ScreenEventTransitionBuilder<void>>()));
    });
  });

  group('fork + per-branch writes combined', () {
    test('two .on() branches each carry their own literal write', () {
      final a = _screen('a');
      final b = _screen('b');
      final c = _screen('c');
      const enable = OnboardingEvent<void>('enable');
      const skip = OnboardingEvent<void>('skip');

      final node = screen(a)
          .on(enable)
          .write('wantsReminders', true)
          .goTo(b)
          .on(skip)
          .write('wantsReminders', false)
          .goTo(c);

      expect(node.transitions, hasLength(2));
      expect(node.transitions[0].event.id, 'enable');
      expect(
        (node.transitions[0].stateWrites['wantsReminders']!.value
                as LiteralFlowValueSource)
            .value,
        true,
      );
      expect(node.transitions[1].event.id, 'skip');
      expect(
        (node.transitions[1].stateWrites['wantsReminders']!.value
                as LiteralFlowValueSource)
            .value,
        false,
      );
    });
  });
}
