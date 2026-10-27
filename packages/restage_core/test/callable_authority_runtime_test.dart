import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';

import 'fixtures/callable_authority_source.dart';

void main() {
  test('installed constant lookup aliases preserve thrown metadata identity',
      () {
    final adapter = aliasedLookupAdapter();
    expect(
        () => authoredAliasedLookup(), throwsA(same(callableMetadataFailure)));
    expect(
        () => adapter.invoke([], {}), throwsA(same(callableMetadataFailure)));
  });

  testWidgets(
      'nullable callable assignment preserves lazy acquisition and identity',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(Builder(builder: (value) {
      context = value;
      return const SizedBox();
    }));
    final trace = <String>[];
    void first(BuildContext value) {
      expect(value, same(context));
      trace.add('first');
    }

    void replacement(BuildContext value) {
      expect(value, same(context));
      trace.add('replacement');
    }

    bool acquire() {
      trace.add('acquire');
      return true;
    }

    NativeBinding<Object> binding(Object value, String type) => NativeBinding(
        contract: NativeBindingContract(type: type), value: value);
    const type = ValueType.native('callback.context', nullable: true);
    final adapter = nullableCallableAdapter();
    for (final initial in [null, first]) {
      final frame = ValueLocalFrame({nullableCallableSlot: type})
        ..write(nullableCallableSlot,
            initial == null ? null : binding(initial, 'callback.context'));
      final callback = (adapter.invoke([
        binding(acquire, 'callback.acquire'),
        binding(replacement, 'callback.context')
      ], {
        adapter.contract.call!.captures.keys.single:
            NativeCapture<Object?>(frame, nullableCallableSlot, type),
      }) as ValueNative)
          .value as void Function(BuildContext);
      expect(trace, isEmpty);
      callback(context);
      callback(context);
      final actual = [...trace];
      expect((frame.read(nullableCallableSlot) as ValueNative).value,
          same(initial ?? replacement));
      trace.clear();
      final native = authoredNullableCallable(initial, replacement, acquire);
      native(context);
      native(context);
      expect(actual, trace);
      expect(
          actual,
          initial == null
              ? ['acquire', 'replacement', 'replacement']
              : ['first', 'first']);
      trace.clear();
    }
    final failure = StateError('acquisition failed');
    bool fail() => throw failure;
    for (final initial in [null, first]) {
      final frame = ValueLocalFrame({nullableCallableSlot: type})
        ..write(nullableCallableSlot,
            initial == null ? null : binding(initial, 'callback.context'));
      final callback = (adapter.invoke([
        binding(fail, 'callback.acquire'),
        binding(replacement, 'callback.context')
      ], {
        adapter.contract.call!.captures.keys.single:
            NativeCapture<Object?>(frame, nullableCallableSlot, type),
      }) as ValueNative)
          .value as void Function(BuildContext);
      if (initial == null) {
        expect(() => callback(context), throwsA(same(failure)));
        expect(frame.read(nullableCallableSlot), isNull);
      } else {
        callback(context);
        expect(trace, ['first']);
        expect((frame.read(nullableCallableSlot) as ValueNative).value,
            same(first));
      }
    }
  });

  testWidgets(
      'installed callbacks retain live function cells and actual context',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(Builder(builder: (value) {
      context = value;
      return const SizedBox();
    }));
    final trace = <(String, BuildContext)>[];
    void first(BuildContext value) => trace.add(('first', value));
    void second(BuildContext value) => trace.add(('second', value));
    const type = ValueType.native('callback.context');
    NativeBinding<Object> binding(Object value) => NativeBinding(
        contract: const NativeBindingContract(type: 'callback.context'),
        value: value);
    final frame = ValueLocalFrame({'callback': type})
      ..write('callback', binding(first));
    final adapter = callableAuthorityAdapter();
    void Function(BuildContext) make() => (adapter.invoke([
          binding(second)
        ], {
          adapter.contract.call!.captures.keys.single:
              NativeCapture<Object?>(frame, 'callback', type),
        }) as ValueNative)
            .value as void Function(BuildContext);
    final generated = make();
    final retained = make();
    expect(trace, isEmpty);
    expect((frame.read('callback') as ValueNative).value, same(first));
    generated(context);
    expect(trace.single, ('first', context));
    expect((frame.read('callback') as ValueNative).value, same(second));
    retained(context);
    expect(trace.last, ('second', context));
    trace.clear();
    final native = authoredCallable(first, second);
    native(context);
    native(context);
    expect(trace, [('first', context), ('second', context)]);

    final failure = StateError('callback failure');
    void throwsFailure(BuildContext value) {
      expect(value, same(context));
      throw failure;
    }

    frame.write('callback', binding(throwsFailure));
    expect(() => generated(context), throwsA(same(failure)));
    expect((frame.read('callback') as ValueNative).value, same(throwsFailure));
    frame.write('callback', binding(first));
    retained(context);
    expect(trace.last, ('first', context));
  });
}
