import 'package:flutter/widgets.dart';

/// A nullable integer controlled component used by the generated state-machine
/// proof.
class ControlledIntFixture extends StatelessWidget {
  const ControlledIntFixture({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('controlled-value:${value ?? 'null'}'),
        GestureDetector(
          key: const ValueKey('controlled-write-41'),
          onTap: () => onChanged(41),
          child: const Text('write-41'),
        ),
        GestureDetector(
          key: const ValueKey('controlled-write-null'),
          onTap: () => onChanged(null),
          child: const Text('write-null'),
        ),
      ],
    );
  }
}

/// Two independently controlled nullable integer fields for cross-talk proof.
class ControlledIntPairFixture extends StatelessWidget {
  const ControlledIntPairFixture({
    required this.first,
    required this.second,
    required this.onFirst,
    required this.onSecond,
    super.key,
  });

  final int? first;
  final int? second;
  final ValueChanged<int?> onFirst;
  final ValueChanged<int?> onSecond;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('pair-first:${first ?? 'null'}'),
        Text('pair-second:${second ?? 'null'}'),
        GestureDetector(
          key: const ValueKey('pair-write-first'),
          onTap: () => onFirst(11),
          child: const Text('write-first'),
        ),
        GestureDetector(
          key: const ValueKey('pair-write-second'),
          onTap: () => onSecond(22),
          child: const Text('write-second'),
        ),
      ],
    );
  }
}

/// The remaining controlled leaf families, kept in one widget so the generated
/// proof also exercises independent writers without duplicating state logic.
class ControlledLeafFamiliesFixture extends StatelessWidget {
  const ControlledLeafFamiliesFixture({
    required this.enabled,
    required this.label,
    required this.choice,
    required this.strings,
    required this.integers,
    required this.doubles,
    required this.numbers,
    required this.booleans,
    required this.maybeIntegers,
    required this.maybeNumbers,
    required this.fallbackIntegers,
    required this.onEnabled,
    required this.onLabel,
    required this.onChoice,
    required this.onStrings,
    required this.onIntegers,
    required this.onDoubles,
    required this.onNumbers,
    required this.onBooleans,
    required this.onMaybeIntegers,
    required this.onMaybeNumbers,
    required this.onFallbackIntegers,
    super.key,
  });

  final bool enabled;
  final String label;
  final ControlledChoice choice;
  final List<String> strings;
  final List<int> integers;
  final List<double> doubles;
  final List<num> numbers;
  final List<bool> booleans;
  final List<int>? maybeIntegers;
  final List<num?>? maybeNumbers;
  final List<int>? fallbackIntegers;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<String> onLabel;
  final ValueChanged<ControlledChoice> onChoice;
  final ValueChanged<List<String>> onStrings;
  final ValueChanged<List<int>> onIntegers;
  final ValueChanged<List<double>> onDoubles;
  final ValueChanged<List<num>> onNumbers;
  final ValueChanged<List<bool>> onBooleans;
  final ValueChanged<List<int>?> onMaybeIntegers;
  final ValueChanged<List<num?>?> onMaybeNumbers;
  final ValueChanged<List<int>?> onFallbackIntegers;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Text('families-enabled:$enabled'),
          Text('families-label:$label'),
          Text('families-choice:${choice.name}'),
          Text('families-strings:${strings.join(',')}'),
          Text('families-integers:${integers.join(',')}'),
          Text('families-doubles:${doubles.join(',')}'),
          Text('families-numbers:${numbers.join(',')}'),
          Text(
            'families-number-types:'
            '${numbers.map((value) => value.runtimeType).join(',')}',
          ),
          Text('families-booleans:${booleans.join(',')}'),
          Text('families-maybe-integers:${maybeIntegers?.join(',') ?? 'null'}'),
          Text(
            'families-maybe-numbers:'
            '${maybeNumbers?.map((value) => value ?? 'null').join(',') ?? 'null'}',
          ),
          Text(
            'families-fallback-integers:'
            '${fallbackIntegers?.join(',') ?? 'null'}',
          ),
          GestureDetector(
            key: const ValueKey('families-write-scalars'),
            onTap: () {
              onEnabled(!enabled);
              onLabel('local');
              onChoice(ControlledChoice.beta);
            },
            child: const Text('write-scalars'),
          ),
          GestureDetector(
            key: const ValueKey('families-write-lists'),
            onTap: () {
              onStrings(const <String>['local']);
              onIntegers(const <int>[41]);
              onDoubles(const <double>[4.5]);
              onNumbers(const <num>[4, 4.5]);
              onBooleans(const <bool>[false]);
              onMaybeNumbers(const <num?>[4, null, 4.5]);
              onFallbackIntegers(const <int>[9]);
            },
            child: const Text('write-lists'),
          ),
          GestureDetector(
            key: const ValueKey('families-write-null-list'),
            onTap: () => onMaybeIntegers(null),
            child: const Text('write-null-list'),
          ),
        ],
      ),
    );
  }
}

enum ControlledChoice { alpha, beta }

/// A stable root component whose child ID can change across Surface updates.
class ControlledScalarHostFixture extends StatelessWidget {
  const ControlledScalarHostFixture({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
