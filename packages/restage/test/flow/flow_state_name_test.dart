import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

// A state holder that exposes `state` and `emit` the way a Cubit or a
// Notifier does; subclasses read the inherited `state`.
abstract class _Cubit<T> {
  _Cubit(this._state);
  T _state;
  T get state => _state;
  void emit(T next) => _state = next;
}

final class _Counter extends _Cubit<int> {
  _Counter() : super(0);
  void increment() => emit(state + 1);
}

void main() {
  test('a Cubit in a file that imports Restage reads its own state', () {
    final counter = _Counter()
      ..increment()
      ..increment();
    expect(counter.state, 2);
    final predicate = flowState('goal').equals('sleep');
    final value = (predicate.fields['goal']! as EqualsFlowPredicateCondition)
        .value as LiteralFlowValueSource;
    expect(value.value, 'sleep');
  });
}
