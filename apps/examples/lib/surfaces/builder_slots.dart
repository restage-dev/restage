import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/builder_slots.restage.g.dart';

/// The count a builder slot shows.
final ValueNotifier<int> slotCount = ValueNotifier(1);

/// The plan a builder slot shows.
final ValueNotifier<SlotPlan> slotPlan = ValueNotifier(
    const SlotPlan('Monthly', 9, SlotTier.basic, ['Sync'], Color(0xFF2266AA)));

/// A plan's tier.
enum SlotTier {
  /// The basic tier.
  basic,

  /// The pro tier.
  pro,
}

/// A plan whose fields a delivered body reads.
final class SlotPlan {
  /// Creates a plan.
  const SlotPlan(this.name, this.price, this.tier, this.features, this.accent);

  /// The plan's name.
  final String name;

  /// The monthly price.
  final int price;

  /// The tier.
  final SlotTier tier;

  /// The features.
  final List<String> features;

  /// The accent color.
  final Color accent;
}

/// Shows a count through an app builder whose body is delivered.
@Paywall(id: 'slot_count')
final class SlotCount extends StatelessWidget {
  /// Creates the paywall.
  const SlotCount({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('header'),
        ValueListenableBuilder<int>(
          valueListenable: slotCount,
          builder: (context, count, child) => Text('count $count'),
        ),
      ]);
}

/// Shows a plan's fields through an app builder whose body is delivered.
@Paywall(id: 'slot_plan')
final class SlotPlanCard extends StatelessWidget {
  /// Creates the paywall.
  const SlotPlanCard({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('plans'),
        ValueListenableBuilder<SlotPlan>(
          valueListenable: slotPlan,
          builder: (context, plan, child) => Column(children: [
            Text('${plan.name} ${plan.price} ${plan.tier.name}',
                style: TextStyle(color: plan.accent)),
            Text('${plan.features.length} features'),
          ]),
        ),
      ]);
}

/// A builder whose body passes its child through keeps the whole builder.
@Paywall(id: 'slot_child')
final class SlotChild extends StatelessWidget {
  /// Creates the paywall.
  const SlotChild({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('child'),
        ValueListenableBuilder<int>(
          valueListenable: slotCount,
          builder: (context, count, child) =>
              Row(children: [Text('n $count'), child!]),
          child: const Text('kept'),
        ),
      ]);
}

/// A delivered body that reads a surface input beside the builder's value.
@Paywall(id: 'slot_mixed')
final class SlotMixed extends StatelessWidget {
  /// Creates the paywall.
  const SlotMixed({required this.label, super.key});

  /// The label shown beside the count.
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('mixed'),
        ValueListenableBuilder<int>(
          valueListenable: slotCount,
          builder: (context, count, child) => Text('$label $count'),
        ),
      ]);
}

String _shout(String text) => '${text.toUpperCase()}!';

/// A delivered body that reads a value the build computes in app code.
@Paywall(id: 'slot_local')
final class SlotLocal extends StatelessWidget {
  /// Creates the paywall.
  const SlotLocal({required this.label, super.key});

  /// The label the build shouts.
  final String label;

  @override
  Widget build(BuildContext context) {
    final shown = _shout(label);
    return Column(children: [
      const Text('local'),
      ValueListenableBuilder<int>(
        valueListenable: slotCount,
        builder: (context, count, child) => Text('$shown $count'),
      ),
    ]);
  }
}

/// Whether the slot condition examples show their row.
bool slotShown() => true;

/// A slot body that tests a value the build computes.
@Paywall(id: 'slot_flag')
final class SlotFlag extends StatelessWidget {
  /// Creates the paywall.
  const SlotFlag({super.key});

  @override
  Widget build(BuildContext context) {
    final shown = slotShown();
    return Column(children: [
      const Text('flag'),
      ValueListenableBuilder<int>(
        valueListenable: slotCount,
        builder: (context, count, child) =>
            Visibility(visible: shown, child: Text('f $count')),
      ),
    ]);
  }
}

/// A slot body with a collection `if` over a value the build computes.
@Paywall(id: 'slot_if')
final class SlotIf extends StatelessWidget {
  /// Creates the paywall.
  const SlotIf({super.key});

  @override
  Widget build(BuildContext context) {
    final shown = slotShown();
    return Column(children: [
      const Text('if'),
      ValueListenableBuilder<int>(
        valueListenable: slotCount,
        builder: (context, count, child) =>
            Column(children: [if (shown) Text('i $count')]),
      ),
    ]);
  }
}

/// A slot body whose condition combines a build value and a parameter.
@Paywall(id: 'slot_and')
final class SlotAnd extends StatelessWidget {
  /// Creates the paywall.
  const SlotAnd({super.key});

  @override
  Widget build(BuildContext context) {
    final shown = slotShown();
    return Column(children: [
      const Text('and'),
      ValueListenableBuilder<int>(
        valueListenable: slotCount,
        builder: (context, count, child) =>
            Column(children: [if (shown && count > 1) Text('a $count')]),
      ),
    ]);
  }
}

/// Each call of [slotEnd].
final slotEndCalls = <String>[];

/// The end of [SlotTweenEnd]'s tween, computed in app code.
double slotEnd() {
  slotEndCalls.add('end');
  return 100;
}

/// A tween whose end the app computes, through a builder whose body is
/// delivered.
@Paywall(id: 'slot_tween_end')
final class SlotTweenEnd extends StatelessWidget {
  /// Creates the paywall.
  const SlotTweenEnd({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('tween end'),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: slotEnd()),
          duration: const Duration(seconds: 1),
          builder: (context, value, child) => Text('t ${value.round()}'),
        ),
      ]);
}

/// Animates a count through an app builder whose body is delivered.
@Paywall(id: 'slot_tween')
final class SlotTween extends StatelessWidget {
  /// Creates the paywall.
  const SlotTween({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('tween'),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 100),
          duration: const Duration(seconds: 1),
          builder: (context, value, child) => Text('t ${value.round()}'),
        ),
      ]);
}
