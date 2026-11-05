import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:restage/restage.dart';

part 'restage.generated/guarded_reads.restage.g.dart';

/// The app calls each surface below makes, in order.
final List<String> guardedCalls = [];

/// An offer whose features a paywall lists.
final class ReadOffer {
  /// Creates an offer.
  const ReadOffer(this.features);

  /// The features to list.
  final List<String> features;
}

/// A plan a paywall lists.
final class ReadPlan {
  /// Creates a plan.
  const ReadPlan(this.name);

  /// The plan's name.
  final String name;
}

List<ReadPlan> _loadPlans() {
  guardedCalls.add('load');
  return const [ReadPlan('Monthly'), ReadPlan('Yearly')];
}

bool _eligible() {
  guardedCalls.add('eligible');
  return true;
}

bool _hasFeatures(ReadOffer offer) {
  guardedCalls.add('has');
  return offer.features.isNotEmpty;
}

Widget _features(ReadOffer offer) =>
    Column(children: [for (final feature in offer.features) Text(feature)]);

Widget _plans() =>
    Column(children: [for (final plan in _loadPlans()) Text(plan.name)]);

/// Lists an offer's features after an early return for no offer.
@Paywall(id: 'read_early_return')
final class ReadEarlyReturn extends StatelessWidget {
  /// Creates the paywall.
  const ReadEarlyReturn({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer == null) return const Text('No offer');
    return Column(children: [for (final f in offer!.features) Text(f)]);
  }
}

/// Lists an offer's features through a helper called under a guard.
@Paywall(id: 'read_guarded_call')
final class ReadGuardedCall extends StatelessWidget {
  /// Creates the paywall.
  const ReadGuardedCall({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('Features'),
        if (offer != null) _features(offer!),
      ]);
}

/// Lists an offer's features under a guard that calls the app.
@Paywall(id: 'read_nested_guard')
final class ReadNestedGuard extends StatelessWidget {
  /// Creates the paywall.
  const ReadNestedGuard({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('Features'),
        if (offer != null)
          if (_hasFeatures(offer!))
            for (final f in offer!.features) Text(f),
      ]);
}

/// Lists plans under a flag and a check that calls the app.
@Paywall(id: 'read_flagged_check')
final class ReadFlaggedCheck extends StatelessWidget {
  /// Creates the paywall.
  const ReadFlaggedCheck({super.key, this.flag = false});

  /// Whether to show the plans.
  final bool flag;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('Plans'),
        if (flag)
          if (_eligible())
            for (final p in _loadPlans()) Text(p.name),
      ]);
}

/// Lists an offer's features through a helper in a conditional's arm.
@Paywall(id: 'read_conditional_call')
final class ReadConditionalCall extends StatelessWidget {
  /// Creates the paywall.
  const ReadConditionalCall({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) =>
      offer == null ? const Text('No offer') : _features(offer!);
}

/// Lists plans after an early return for no plans.
@Paywall(id: 'read_early_plans')
final class ReadEarlyPlans extends StatelessWidget {
  /// Creates the paywall.
  const ReadEarlyPlans({super.key, this.plans = const []});

  /// The plans the screen was given.
  final List<ReadPlan> plans;

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) return const Text('No plans');
    return Column(children: [for (final p in _loadPlans()) Text(p.name)]);
  }
}

/// Lists plans through a helper called under a flag.
@Paywall(id: 'read_flagged_call')
final class ReadFlaggedCall extends StatelessWidget {
  /// Creates the paywall.
  const ReadFlaggedCall({super.key, this.flag = false});

  /// Whether to show the plans.
  final bool flag;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('Plans'),
        if (flag) _plans(),
      ]);
}

/// Shows a line only for a title that is present and not empty.
@Paywall(id: 'read_null_check')
final class ReadNullCheck extends StatelessWidget {
  /// Creates the paywall.
  const ReadNullCheck({super.key, this.title});

  /// The title, when there is one.
  final String? title;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('Title'),
        if (title != null && title!.isNotEmpty) Text(title!),
      ]);
}

/// A plan that may carry an offer.
final class ReadHolder {
  /// Creates a holder.
  const ReadHolder(this.offer);

  /// The holder's offer, when it has one.
  final ReadOffer? offer;
}

String _describe(ReadOffer offer) {
  guardedCalls.add('describe');
  return offer.features.join(', ');
}

/// Describes each holder's offer, only for holders with an offer that has
/// features.
@Paywall(id: 'read_item_check')
final class ReadItemCheck extends StatelessWidget {
  /// Creates the paywall.
  const ReadItemCheck({super.key, this.holders = const []});

  /// The holders to describe.
  final List<ReadHolder> holders;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('Offers'),
        for (final h in holders)
          if (h.offer != null && _hasFeatures(h.offer!))
            Text(_describe(h.offer!)),
      ]);
}

/// Describes each holder's offer when the reader is eligible.
@Paywall(id: 'read_item_eligible')
final class ReadItemEligible extends StatelessWidget {
  /// Creates the paywall.
  const ReadItemEligible({super.key, this.holders = const []});

  /// The holders to describe.
  final List<ReadHolder> holders;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('Offers'),
        for (final h in holders)
          if (_eligible() && h.offer != null) Text(_describe(h.offer!)),
      ]);
}

/// Lists the offer's features from a return inside an `if` block.
@Paywall(id: 'read_return_in_if')
final class ReadReturnInIf extends StatelessWidget {
  /// Creates the paywall.
  const ReadReturnInIf({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer != null) {
      return Column(children: [for (final f in offer!.features) Text(f)]);
    }
    return const Text('none');
  }
}

/// Lists the offer's features from a return inside an `if` without braces.
@Paywall(id: 'read_return_no_braces')
final class ReadReturnNoBraces extends StatelessWidget {
  /// Creates the paywall.
  const ReadReturnNoBraces({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer != null)
      return Column(children: [for (final f in offer!.features) Text(f)]);
    return const Text('none');
  }
}

/// Lists the offer's features from a return two `if`s deep.
@Paywall(id: 'read_return_nested')
final class ReadReturnNested extends StatelessWidget {
  /// Creates the paywall.
  const ReadReturnNested({super.key, this.flag = false, this.offer});

  /// Whether to look at the offer.
  final bool flag;

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (flag) {
      if (offer != null) {
        return Column(children: [for (final f in offer!.features) Text(f)]);
      }
    }
    return const Text('none');
  }
}

/// Lists the offer's features under each named plan.
@Paywall(id: 'read_plan_features')
final class ReadPlanFeatures extends StatelessWidget {
  /// Creates the paywall.
  const ReadPlanFeatures({super.key, this.plans = const [], this.offer});

  /// The plans to list.
  final List<ReadPlan> plans;

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('Plans'),
        for (final p in plans)
          if (p.name.isNotEmpty)
            for (final f in offer!.features) Text(f),
      ]);
}

/// Describes the offer once per plan, when the offer has features.
@Paywall(id: 'read_loop_check')
final class ReadLoopCheck extends StatelessWidget {
  /// Creates the paywall.
  const ReadLoopCheck({super.key, this.plans = const [], this.offer});

  /// The plans to list.
  final List<ReadPlan> plans;

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) => Column(children: [
        // ignore: unused_local_variable
        for (final p in plans)
          if (offer!.features.isNotEmpty) Text(_describe(offer!)),
      ]);
}

/// Describes the offer once per plan, when a check that calls code holds.
@Paywall(id: 'read_loop_call')
final class ReadLoopCall extends StatelessWidget {
  /// Creates the paywall.
  const ReadLoopCall({super.key, this.plans = const [], this.offer});

  /// The plans to list.
  final List<ReadPlan> plans;

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) => Column(children: [
        // ignore: unused_local_variable
        for (final p in plans)
          if (_hasFeatures(offer!)) Text(_describe(offer!)),
      ]);
}

/// Lists the offer's features once per plan, when a check that calls code
/// holds.
@Paywall(id: 'read_loop_list')
final class ReadLoopList extends StatelessWidget {
  /// Creates the paywall.
  const ReadLoopList({super.key, this.plans = const [], this.offer});

  /// The plans to list.
  final List<ReadPlan> plans;

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) => Column(children: [
        // ignore: unused_local_variable
        for (final p in plans)
          if (_hasFeatures(offer!))
            for (final f in offer!.features) Text(f),
      ]);
}

/// Lists each holder's offer features, for holders whose offer has features.
@Paywall(id: 'read_item_list')
final class ReadItemList extends StatelessWidget {
  /// Creates the paywall.
  const ReadItemList({super.key, this.holders = const []});

  /// The holders to list.
  final List<ReadHolder> holders;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('Offers'),
        for (final h in holders)
          if (h.offer != null && _hasFeatures(h.offer!))
            for (final f in h.offer!.features) Text(f),
      ]);
}

/// One keyed button per plan, and per feature of the offer when there is one.
@Paywall(id: 'read_item_keys')
final class ReadItemKeys extends StatelessWidget {
  /// Creates the paywall.
  const ReadItemKeys({super.key, this.plans = const [], this.offer});

  /// The plans to list.
  final List<ReadPlan> plans;

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final p in plans)
          ElevatedButton(
              key: ValueKey(p.name), onPressed: null, child: Text(p.name)),
        if (offer != null)
          for (final f in offer!.features)
            ElevatedButton(key: ValueKey(f), onPressed: null, child: Text(f)),
      ]);
}

class _Framed extends StatelessWidget {
  const _Framed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(4), child: child);
}

String _fallbackLabel() {
  guardedCalls.add('label');
  return 'All plans';
}

/// Shows the offer's first feature in a frame, from a local of the branch.
@Paywall(id: 'read_block_framed')
final class ReadBlockFramed extends StatelessWidget {
  /// Creates the paywall.
  const ReadBlockFramed({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer != null) {
      final features = offer!.features;
      return _Framed(child: Text(features.first));
    }
    return const Text('none');
  }
}

/// Lists the offer's features from a local of the branch.
@Paywall(id: 'read_block_loop')
final class ReadBlockLoop extends StatelessWidget {
  /// Creates the paywall.
  const ReadBlockLoop({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer != null) {
      final features = offer!.features;
      return Column(children: [for (final f in features) Text(f)]);
    }
    return const Text('none');
  }
}

/// Shows the offer's first feature from a local of the branch.
@Paywall(id: 'read_block_text')
final class ReadBlockText extends StatelessWidget {
  /// Creates the paywall.
  const ReadBlockText({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer != null) {
      final features = offer!.features;
      return Text(features.first);
    }
    return const Text('none');
  }
}

/// Two branches that each declare a local named `label`.
@Paywall(id: 'read_block_same_name')
final class ReadBlockSameName extends StatelessWidget {
  /// Creates the paywall.
  const ReadBlockSameName({super.key, this.offer, this.title});

  /// The offer, when there is one.
  final ReadOffer? offer;

  /// The title, when there is one.
  final String? title;

  @override
  Widget build(BuildContext context) {
    if (offer != null) {
      final label = offer!.features.first;
      return Text(label);
    }
    if (title != null) {
      final label = title!;
      return Text(label);
    }
    return const Text('none');
  }
}

/// A branch local that shadows the build's own local of the same name.
@Paywall(id: 'read_block_shadow')
final class ReadBlockShadow extends StatelessWidget {
  /// Creates the paywall.
  const ReadBlockShadow({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    final label = _fallbackLabel();
    if (offer != null) {
      final label = offer!.features.first;
      return Text(label);
    }
    return Text(label);
  }
}

/// Shows the offer's first feature from an if-case pattern variable.
@Paywall(id: 'read_case_text')
final class ReadCaseText extends StatelessWidget {
  /// Creates the paywall.
  const ReadCaseText({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer case final o?) {
      return Text(o.features.first);
    }
    return const Text('none');
  }
}

/// Shows the offer's first feature in a frame from an if-case variable.
@Paywall(id: 'read_case_framed')
final class ReadCaseFramed extends StatelessWidget {
  /// Creates the paywall.
  const ReadCaseFramed({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer case final o?) {
      return _Framed(child: Text(o.features.first));
    }
    return const Text('none');
  }
}

/// Lists the offer's features from an if-case variable.
@Paywall(id: 'read_case_loop')
final class ReadCaseLoop extends StatelessWidget {
  /// Creates the paywall.
  const ReadCaseLoop({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer case final o?) {
      return Column(children: [for (final f in o.features) Text(f)]);
    }
    return const Text('none');
  }
}

/// Shows the second feature when the matched offer has more than one.
@Paywall(id: 'read_case_when')
final class ReadCaseWhen extends StatelessWidget {
  /// Creates the paywall.
  const ReadCaseWhen({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer case final o? when o.features.length > 1) {
      return Text(o.features[1]);
    }
    return const Text('none');
  }
}

/// Shows the first plan whose name starts with `Y`, from a local the loop
/// assigns on each pass.
@Paywall(id: 'read_loop_local')
final class ReadLoopLocal extends StatelessWidget {
  /// Creates the paywall.
  const ReadLoopLocal({super.key, this.plans = const []});

  /// The plans to search.
  final List<ReadPlan> plans;

  @override
  Widget build(BuildContext context) {
    for (final p in plans) {
      final n = p.name;
      if (n.startsWith('Y')) return Text(n);
    }
    return const Text('none');
  }
}

/// Shows the first plan with a name, from the loop's variable.
@Paywall(id: 'read_loop_variable')
final class ReadLoopVariable extends StatelessWidget {
  /// Creates the paywall.
  const ReadLoopVariable({super.key, this.plans = const []});

  /// The plans to search.
  final List<ReadPlan> plans;

  @override
  Widget build(BuildContext context) {
    for (final p in plans) {
      if (p.name.isNotEmpty) return Text(p.name);
    }
    return const Text('none');
  }
}

/// Shows the offer's first feature in a frame from a branch local named
/// `context`.
@Paywall(id: 'read_block_context')
final class ReadBlockContext extends StatelessWidget {
  /// Creates the paywall.
  const ReadBlockContext({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer != null) {
      final context = offer!.features.first;
      return _Framed(child: Text(context));
    }
    return const Text('none');
  }
}

/// Shows the title in a frame from a build local named `context`.
@Paywall(id: 'read_build_context')
final class ReadBuildContext extends StatelessWidget {
  /// Creates the paywall.
  const ReadBuildContext({super.key, this.title, this.flag = false});

  /// The title, when there is one.
  final String? title;

  /// Whether to show the title.
  final bool flag;

  @override
  Widget build(BuildContext buildContext) {
    final context = title ?? 'Untitled';
    if (flag) {
      return _Framed(child: Text(context));
    }
    return const Text('none');
  }
}

String _readHeadline() {
  guardedCalls.add('headline');
  return 'Top';
}

final _banner = 'Top banner';

const _bannerConst = 'Top const';

/// A branch local named like a top-level function the build calls.
@Paywall(id: 'read_shadow_function')
final class ReadShadowFunction extends StatelessWidget {
  /// Creates the paywall.
  const ReadShadowFunction({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer != null) {
      // ignore: no_leading_underscores_for_local_identifiers
      final _readHeadline = offer!.features.first;
      return Text(_readHeadline);
    }
    return Text(_readHeadline());
  }
}

/// A branch local named like a top-level final the build reads.
@Paywall(id: 'read_shadow_final')
final class ReadShadowFinal extends StatelessWidget {
  /// Creates the paywall.
  const ReadShadowFinal({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer != null) {
      // ignore: no_leading_underscores_for_local_identifiers
      final _banner = offer!.features.first;
      return Text(_banner);
    }
    return Text(_banner);
  }
}

/// A branch local named like a top-level const the build reads.
@Paywall(id: 'read_shadow_const')
final class ReadShadowConst extends StatelessWidget {
  /// Creates the paywall.
  const ReadShadowConst({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer != null) {
      // ignore: no_leading_underscores_for_local_identifiers
      final _bannerConst = offer!.features.first;
      return Text(_bannerConst);
    }
    return const Text(_bannerConst);
  }
}

/// A section of named tags.
final class ReadSection {
  /// Creates a section.
  const ReadSection(this.name, this.tags);

  /// The section's name.
  final String name;

  /// The section's tags.
  final List<String> tags;
}

/// One keyed button per tag of each section, keyed by the tag and by both.
@Paywall(id: 'read_nested_keys')
final class ReadNestedKeys extends StatelessWidget {
  /// Creates the paywall.
  const ReadNestedKeys({super.key, this.sections = const []});

  /// The sections to list.
  final List<ReadSection> sections;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final s in sections)
          for (final t in s.tags)
            ElevatedButton(key: ValueKey(t), onPressed: null, child: Text(t)),
        for (final s in sections)
          for (final t in s.tags)
            ElevatedButton(
                key: ValueKey('${s.name}/$t'),
                onPressed: null,
                child: Text('${s.name}/$t')),
      ]);
}

/// Shows a count and the first feature from a destructuring declaration.
@Paywall(id: 'read_block_destructure')
final class ReadBlockDestructure extends StatelessWidget {
  /// Creates the paywall.
  const ReadBlockDestructure({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer != null) {
      final (count, first) = (offer!.features.length, offer!.features.first);
      return Text('$count $first');
    }
    return const Text('none');
  }
}

/// Shows the score an if-case matches, NaN included.
@Paywall(id: 'read_case_score')
final class ReadCaseScore extends StatelessWidget {
  /// Creates the paywall.
  const ReadCaseScore({super.key, this.score});

  /// The score as written, when there is one.
  final String? score;

  @override
  Widget build(BuildContext context) {
    if (double.tryParse(score ?? '') case final s?) {
      return Text('$s');
    }
    return const Text('none');
  }
}

/// Shows the first plan whose name starts with `Y`, found by index.
@Paywall(id: 'read_classic_loop')
final class ReadClassicLoop extends StatelessWidget {
  /// Creates the paywall.
  const ReadClassicLoop({super.key, this.plans = const []});

  /// The plans to search.
  final List<ReadPlan> plans;

  @override
  Widget build(BuildContext context) {
    for (var i = 0; i < plans.length; i++) {
      if (plans[i].name.startsWith('Y')) return Text(plans[i].name);
    }
    return const Text('none');
  }
}

/// Describes the offer from a local of a `try` block.
@Paywall(id: 'read_try_local')
final class ReadTryLocal extends StatelessWidget {
  /// Creates the paywall.
  const ReadTryLocal({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    try {
      final t = _describe(offer!);
      return Text(t);
    } on Object {
      // Without an offer there is nothing to describe.
    }
    return const Text('none');
  }
}

/// Lists the offer's features from a switch on the offer.
@Paywall(id: 'read_switch_offer')
final class ReadSwitchOffer extends StatelessWidget {
  /// Creates the paywall.
  const ReadSwitchOffer({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) => switch (offer) {
        ReadOffer(:final features) =>
          Column(children: [for (final f in features) Text(f)]),
        _ => const Text('none'),
      };
}

/// Shows on or off from a switch statement whose cases return.
@Paywall(id: 'read_switch_flag')
final class ReadSwitchFlag extends StatelessWidget {
  /// Creates the paywall.
  const ReadSwitchFlag({super.key, this.flag = false});

  /// Whether it is on.
  final bool flag;

  @override
  Widget build(BuildContext context) {
    switch (flag) {
      case true:
        return const Text('on');
      case false:
        return const Text('off');
    }
  }
}

/// A plan's tier.
sealed class ReadTier {
  const ReadTier();
}

/// A free tier.
final class ReadFree extends ReadTier {
  /// Creates the tier.
  const ReadFree();
}

/// A paid tier with its plan's name.
final class ReadPaid extends ReadTier {
  /// Creates the tier.
  const ReadPaid(this.name);

  /// The plan's name.
  final String name;
}

ReadTier _tierOf(String? plan) {
  guardedCalls.add('tier');
  return plan == null ? const ReadFree() : ReadPaid(plan);
}

/// Shows the tier from a switch over a sealed type, with a guard.
@Paywall(id: 'read_switch_tier')
final class ReadSwitchTier extends StatelessWidget {
  /// Creates the paywall.
  const ReadSwitchTier({super.key, this.plan});

  /// The plan, when there is one.
  final String? plan;

  @override
  Widget build(BuildContext context) => switch (_tierOf(plan)) {
        ReadPaid(:final name) when name.length > 3 => Text(name),
        ReadPaid() => const Text('paid'),
        ReadFree() => const Text('free'),
      };
}

/// Shows the tier from a switch statement over a sealed type.
@Paywall(id: 'read_switch_tier_statement')
final class ReadSwitchTierStatement extends StatelessWidget {
  /// Creates the paywall.
  const ReadSwitchTierStatement({super.key, this.plan});

  /// The plan, when there is one.
  final String? plan;

  @override
  Widget build(BuildContext context) {
    switch (_tierOf(plan)) {
      case ReadPaid(:final name):
        return Text(name);
      case ReadFree():
        return const Text('free');
    }
  }
}

/// Shows the second plan, from a loop over indexed plans.
@Paywall(id: 'read_loop_indexed')
final class ReadLoopIndexed extends StatelessWidget {
  /// Creates the paywall.
  const ReadLoopIndexed({super.key, this.plans = const []});

  /// The plans to search.
  final List<ReadPlan> plans;

  @override
  Widget build(BuildContext context) {
    for (final (i, p) in plans.indexed) {
      if (i == 1) return Text(p.name);
    }
    return const Text('none');
  }
}

/// Describes the offer, or what was caught without one.
@Paywall(id: 'read_catch_parameter')
final class ReadCatchParameter extends StatelessWidget {
  /// Creates the paywall.
  const ReadCatchParameter({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    try {
      final d = _describe(offer!);
      return Text(d);
    } on TypeError catch (e, s) {
      return Text('caught ${e.runtimeType} ${s.toString().isNotEmpty}');
    }
  }
}

/// Describes the offer from a return inside a try block.
@Paywall(id: 'read_try_return')
final class ReadTryReturn extends StatelessWidget {
  /// Creates the paywall.
  const ReadTryReturn({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    try {
      return Text(_describe(offer!));
    } on TypeError {
      return const Text('caught');
    }
  }
}

/// An app value spelled like a name a generated mount once declared.
int restageBranch = 5;

/// Reads an app value whose name a generated mount once declared.
@Paywall(id: 'read_cx1')
final class ReadCx1 extends StatelessWidget {
  /// Creates the paywall.
  const ReadCx1({super.key, this.flag = false});

  /// Whether to show the value.
  final bool flag;

  @override
  Widget build(BuildContext context) {
    if (flag) return Text('$restageBranch');
    return const Text('none');
  }
}

/// Two cases share one body; the first has a guard.
@Paywall(id: 'read_s11')
final class ReadS11 extends StatelessWidget {
  /// Creates the paywall.
  const ReadS11({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    switch (offer) {
      case ReadOffer(features: [final first, ...]) when first.isEmpty:
      case ReadOffer(features: [final first, ...]):
        return Text('first $first');
      default:
        return const Text('none');
    }
  }
}

/// Two cases share one body without a guard.
@Paywall(id: 'read_sx9')
final class ReadSx9 extends StatelessWidget {
  /// Creates the paywall.
  const ReadSx9({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    switch (offer) {
      case ReadOffer(features: [final name]):
      case ReadOffer(features: [final name, _, ...]):
        return Text(name);
      default:
        return const Text('none');
    }
  }
}

/// An `||` pattern binds one variable in an if-case.
@Paywall(id: 'read_s24')
final class ReadS24 extends StatelessWidget {
  /// Creates the paywall.
  const ReadS24({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    if (offer
        case ReadOffer(features: [final f]) ||
            ReadOffer(features: [final f, _, ...])) {
      return Text(f);
    }
    return const Text('none');
  }
}

/// An `||` pattern binds one variable in a root switch expression.
@Paywall(id: 'read_sx10')
final class ReadSx10 extends StatelessWidget {
  /// Creates the paywall.
  const ReadSx10({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) => switch (offer) {
        ReadOffer(features: [final f]) ||
        ReadOffer(features: [final f, _, ...]) =>
          Text(f),
        _ => const Text('none'),
      };
}

/// A root switch expression with an arm that throws.
@Paywall(id: 'read_s18')
final class ReadS18 extends StatelessWidget {
  /// Creates the paywall.
  const ReadS18({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) => switch (offer) {
        null => const Text('none'),
        ReadOffer(features: []) => throw StateError('empty'),
        final o => Text(o.features.first),
      };
}

/// A classic loop whose body moves its own index, read interpolated.
@Paywall(id: 'read_u1')
final class ReadU1 extends StatelessWidget {
  /// Creates the paywall.
  const ReadU1({super.key, this.plans = const []});

  /// The plans to list.
  final List<ReadPlan> plans;

  @override
  Widget build(BuildContext context) {
    for (var i = 0; i < plans.length; i++) {
      if (plans[i].name.isEmpty) i++;
      if (plans[i].name == 'Yearly') return Text('at $i');
    }
    return const Text('none');
  }
}

/// A return in a try block whose value throws where the app catches it.
@Paywall(id: 'read_j3')
final class ReadJ3 extends StatelessWidget {
  /// Creates the paywall.
  const ReadJ3({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    try {
      return _Framed(child: Text(_describe(offer!)));
    } catch (e) {
      return const Text('error');
    }
  }
}

/// Tests a local under `&&` before a return reads it.
@Paywall(id: 'read_and_local')
final class ReadAndLocal extends StatelessWidget {
  /// Creates the paywall.
  const ReadAndLocal({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    if (o != null && o.features.isNotEmpty) return Text(o.features.first);
    return const Text('none');
  }
}

/// Tests a local under `||` before an else arm reads it.
@Paywall(id: 'read_or_local')
final class ReadOrLocal extends StatelessWidget {
  /// Creates the paywall.
  const ReadOrLocal({super.key, this.offer});

  /// The offer, when there is one.
  final ReadOffer? offer;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    return Column(children: [
      if (o == null || o.features.isEmpty)
        const Text('none')
      else
        Text(o.features.first),
    ]);
  }
}

/// A root switch expression after an early return.
@Paywall(id: 'read_sx2')
final class ReadSx2 extends StatelessWidget {
  /// Creates the paywall.
  const ReadSx2({super.key, this.offer, this.flag = false});

  /// The offer, when there is one.
  final ReadOffer? offer;

  /// Whether to show the offer.
  final bool flag;

  @override
  Widget build(BuildContext context) {
    if (offer == null) return const Text('none');
    return switch (flag) {
      true => Text(offer!.features.first),
      false => const Text('off'),
    };
  }
}

/// A switch expression as another switch's arm.
@Paywall(id: 'read_sx8')
final class ReadSx8 extends StatelessWidget {
  /// Creates the paywall.
  const ReadSx8({super.key, this.offer, this.flag = false});

  /// The offer, when there is one.
  final ReadOffer? offer;

  /// Whether to show the offer.
  final bool flag;

  @override
  Widget build(BuildContext context) => switch (flag) {
        true => switch (offer) {
            null => const Text('none'),
            final o => Text(o.features.first),
          },
        false => const Text('off'),
      };
}

/// How many tallies have been created.
int tallyStates = 0;

/// An app widget with State of its own.
class _Tally extends StatefulWidget {
  const _Tally();

  @override
  State<_Tally> createState() => _TallyState();
}

class _TallyState extends State<_Tally> {
  late final int id = ++tallyStates;

  @override
  Widget build(BuildContext context) => Text('tally $id');
}

Widget _twice(Widget w) => Row(children: [w, w]);

/// Places an app widget with State of its own.
@Paywall(id: 'read_kept_state')
final class ReadKeptState extends StatelessWidget {
  /// Creates the paywall.
  const ReadKeptState({super.key});

  @override
  Widget build(BuildContext context) =>
      const Column(children: [Text('kept'), _Tally()]);
}

/// Places an app widget twice through a helper.
@Paywall(id: 'read_twice')
final class ReadTwice extends StatelessWidget {
  /// Creates the paywall.
  const ReadTwice({super.key});

  @override
  Widget build(BuildContext context) =>
      Column(children: [const Text('twice'), _twice(const _Tally())]);
}

/// Places an app widget twice inside a value a helper places.
@Paywall(id: 'read_twice_framed')
final class ReadTwiceFramed extends StatelessWidget {
  /// Creates the paywall.
  const ReadTwiceFramed({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('framed'),
        _twice(const Padding(padding: EdgeInsets.zero, child: _Tally())),
      ]);
}

/// Strings an app reads through its context, as generated localizations do.
final class ReadStrings {
  const ReadStrings._();

  /// The strings for [context].
  static ReadStrings of(BuildContext context) {
    guardedCalls.add('of');
    return const ReadStrings._();
  }

  /// The title.
  String get title {
    guardedCalls.add('title');
    return 'Localized';
  }
}

String _greeting() {
  guardedCalls.add('greeting');
  return Intl.message('Hello', name: '_greeting');
}

/// Shows strings from a localization lookup and an `Intl.message`.
@Paywall(id: 'read_localized')
final class ReadLocalized extends StatelessWidget {
  /// Creates the paywall.
  const ReadLocalized({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(ReadStrings.of(context).title),
        Text(_greeting()),
      ]);
}

/// A button whose action calls an app function.
@Paywall(id: 'read_print_action')
final class ReadPrintAction extends StatelessWidget {
  /// Creates the paywall.
  const ReadPrintAction({super.key, this.label = 'Hi'});

  /// The button label.
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        TextButton(
            onPressed: () => debugPrint('pressed $label'), child: Text(label)),
      ]);
}

/// Each offset the scrolled list reported, frame by frame.
final List<double> scrolledOffsets = [];

/// A list scrolled through a controller its State holds.
@Paywall(id: 'read_scrolled')
final class ReadScrolled extends StatefulWidget {
  /// Creates the paywall.
  const ReadScrolled({super.key});

  @override
  State<ReadScrolled> createState() => _ReadScrolledState();
}

class _ReadScrolledState extends State<ReadScrolled> {
  final ScrollController _scroll = ScrollController();
  bool _listening = true;

  @override
  void initState() {
    super.initState();
    // The app reads its controller's offset every frame it has a list.
    void read(Duration _) {
      if (!_listening) return;
      if (_scroll.hasClients) scrolledOffsets.add(_scroll.offset);
      WidgetsBinding.instance.addPostFrameCallback(read);
    }

    WidgetsBinding.instance.addPostFrameCallback(read);
  }

  @override
  void dispose() {
    _listening = false;
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 200,
        child: ListView(controller: _scroll, children: const [
          Text('row a'),
          Text('row b'),
        ]),
      );
}

int _inset() {
  guardedCalls.add('inset');
  return 4;
}

class _Inset extends StatelessWidget {
  const _Inset({required this.inset, required this.child});

  final int inset;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.all(inset.toDouble()), child: child);
}

class _InsetBuilder extends StatelessWidget {
  const _InsetBuilder({required this.inset, required this.builder});

  final int inset;
  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.all(inset.toDouble()), child: builder(context));
}

/// An app widget with delivered content and an argument that calls the app.
@Paywall(id: 'read_island_args')
final class ReadIslandArgs extends StatelessWidget {
  /// Creates the paywall.
  const ReadIslandArgs({super.key, this.label = 'Pro'});

  /// The label.
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        _Inset(inset: _inset(), child: Text(label)),
      ]);
}

/// A name whose `toString` the app declares.
final class ReadNamed {
  /// Creates a name.
  const ReadNamed(this.name);

  /// The name.
  final String name;

  @override
  String toString() {
    guardedCalls.add('toString');
    return name;
  }
}

/// Names whose iterator the app declares.
final class ReadNames extends Iterable<String> {
  /// Creates the names.
  const ReadNames();

  @override
  Iterator<String> get iterator {
    guardedCalls.add('iterator');
    return const ['x', 'y'].iterator;
  }
}

class _Titled extends StatelessWidget {
  const _Titled(
      {required this.title, required this.names, required this.child});

  final String title;
  final List<String> names;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.all(title.length.toDouble()),
        child: Column(children: [Text('$title ${names.join(',')}'), child]),
      );
}

/// An island whose arguments call the app implicitly.
@Paywall(id: 'read_island_implicit')
final class ReadIslandImplicit extends StatelessWidget {
  /// Creates the paywall.
  const ReadIslandImplicit({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
        _Titled(
          title: '${const ReadNamed('n')}',
          names: [...const ReadNames()],
          child: const Text('body'),
        ),
      ]);
}

/// A stateful island the app gives a new identity on every build.
@Paywall(id: 'read_unique_keyed')
final class ReadUniqueKeyed extends StatelessWidget {
  /// Creates the paywall.
  const ReadUniqueKeyed({super.key});

  @override
  Widget build(BuildContext context) =>
      Column(children: [_Counted(key: UniqueKey(), label: 'u')]);
}

String _tick() {
  guardedCalls.add('tick');
  return '${guardedCalls.where((call) => call == 'tick').length}';
}

/// The same expression, which runs code, written twice.
@Paywall(id: 'read_impure_twice')
final class ReadImpureTwice extends StatelessWidget {
  /// Creates the paywall.
  const ReadImpureTwice({super.key});

  @override
  Widget build(BuildContext context) =>
      Column(children: [Text('${_tick()}'), Text('${_tick()}')]);
}

/// The names a kept builder lists.
final readNames = ValueNotifier<List<String>>(['a', 'b', 'c']);

String _shoutName(String name) {
  guardedCalls.add('shout $name');
  return '${name.toUpperCase()}!';
}

/// A root builder that runs again without its mount.
@Paywall(id: 'read_builder_rerun')
final class ReadBuilderRerun extends StatelessWidget {
  /// Creates the paywall.
  const ReadBuilderRerun({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
        valueListenable: readNames,
        builder: (context, names, child) => Column(children: [
          for (final name in names) Text(_shoutName(name)),
        ]),
      );
}

class _Counted extends StatefulWidget {
  const _Counted({required this.label, super.key});

  final String label;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    guardedCalls.add('init ${widget.label}');
  }

  @override
  void dispose() {
    guardedCalls.add('dispose ${widget.label}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

/// Stateful app widgets the app keys by value, in a loop.
@Paywall(id: 'read_keyed_loop')
final class ReadKeyedLoop extends StatelessWidget {
  /// Creates the paywall.
  const ReadKeyedLoop({super.key, this.names = const ['a', 'b']});

  /// The names listed.
  final List<String> names;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final name in names) _Counted(key: ValueKey(name), label: name),
      ]);
}

Widget _insetCard(String label) =>
    _Inset(inset: label.length, child: Text(label));

/// A helper whose island has delivered content, called at two sites.
@Paywall(id: 'read_helper_twice')
final class ReadHelperTwice extends StatelessWidget {
  /// Creates the paywall.
  const ReadHelperTwice({super.key});

  @override
  Widget build(BuildContext context) =>
      Column(children: [_insetCard('monthly'), _insetCard('yearly')]);
}

/// An app widget with a builder slot and an argument that calls the app.
@Paywall(id: 'read_island_builder_args')
final class ReadIslandBuilderArgs extends StatelessWidget {
  /// Creates the paywall.
  const ReadIslandBuilderArgs({super.key, this.label = 'Pro'});

  /// The label.
  final String label;

  @override
  Widget build(BuildContext context) => Column(children: [
        _InsetBuilder(inset: _inset(), builder: (context) => Text(label)),
      ]);
}

class _Signal extends StatelessWidget {
  const _Signal({required this.builder});

  final Widget Function(BuildContext context, int count) builder;

  @override
  Widget build(BuildContext context) => builder(context, 2);
}

class _Listen extends StatelessWidget {
  const _Listen({required this.listener, required this.child});

  final void Function(BuildContext context, int count) listener;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _Repeat extends StatelessWidget {
  const _Repeat({required this.builder});

  final Widget Function(BuildContext context, int index) builder;

  @override
  Widget build(BuildContext context) =>
      Column(children: [for (var i = 0; i < 3; i++) builder(context, i)]);
}

Color _ink() {
  guardedCalls.add('ink');
  return const Color(0xFF112233);
}

Color _muted() {
  guardedCalls.add('muted');
  return const Color(0xFF445566);
}

String _labelFor(int index) {
  guardedCalls.add('label $index');
  return 'row $index';
}

/// A builder whose body reads a controller and a color the app computes.
@Paywall(id: 'read_builder_values')
final class ReadBuilderValues extends StatefulWidget {
  /// Creates the paywall.
  const ReadBuilderValues({super.key});

  @override
  State<ReadBuilderValues> createState() => _ReadBuilderValuesState();
}

class _ReadBuilderValuesState extends State<ReadBuilderValues> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: _Listen(
          listener: (context, count) => guardedCalls.add('listen $count'),
          child: _Signal(builder: (context, count) {
            final ink = _ink();
            final muted = _muted();
            return Padding(
              padding: const EdgeInsets.all(8),
              child: ListView(controller: _scroll, children: [
                Text('count $count', style: TextStyle(color: ink)),
                Text('muted', style: TextStyle(color: muted)),
              ]),
            );
          }),
        ),
      );
}

/// A builder below delivered content, reading a controller and a color.
@Paywall(id: 'read_builder_slot')
final class ReadBuilderSlot extends StatefulWidget {
  /// Creates the paywall.
  const ReadBuilderSlot({super.key});

  @override
  State<ReadBuilderSlot> createState() => _ReadBuilderSlotState();
}

class _ReadBuilderSlotState extends State<ReadBuilderSlot> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('head'),
        Expanded(
          child: _Signal(builder: (context, count) {
            final ink = _ink();
            return ListView(controller: _scroll, children: [
              Text('count $count', style: TextStyle(color: ink)),
            ]);
          }),
        ),
      ]);
}

/// A builder the app calls once per row, whose body calls the app.
@Paywall(id: 'read_builder_rows')
final class ReadBuilderRows extends StatelessWidget {
  /// Creates the paywall.
  const ReadBuilderRows({super.key});

  @override
  Widget build(BuildContext context) =>
      _Repeat(builder: (context, index) => Text(_labelFor(index)));
}
