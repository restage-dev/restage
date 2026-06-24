// A real, hand-written customer widget library — the kind a developer writes
// and annotates with `@RestageWidget`. The data-shape fidelity proof resolves
// THIS source with the analyzer, reflects each widget's constructor parameters
// into rich data-shape nodes, runs them through the production A2UI emitter,
// and renders the generated catalog against real genui. The widgets render
// their reconstructed data as text so the render assertions can read the values
// that arrived. (The `@RestageWidget` annotation itself is build-phase discovery
// — a tracked follow-up — and is not needed to reflect the parameter types.)
import 'package:flutter/widgets.dart';

/// A nullable enum field inside a nested data class.
enum PlanBadge { none, popular, bestValue }

/// A nested data class: required scalars + a nullable enum + a nullable string.
class PlanTier {
  const PlanTier({
    required this.name,
    required this.price,
    this.badge,
    this.tagline,
  });

  final String name;
  final double price;
  final PlanBadge? badge;
  final String? tagline;
}

/// A list-of-objects element.
class PlanFeature {
  const PlanFeature({required this.label, required this.included});

  final String label;
  final bool included;
}

/// A nested object whose own field is named `path` — the exact shape genui's
/// BoundObject would have misread as a `{path: ...}` binding. Direct
/// reconstruction reads the field by name, so it renders correctly.
class LinkData {
  const LinkData({required this.path, required this.label});

  final String path;
  final String label;
}

/// Renders a required nested data class — the nested-data-class + nullable-field
/// proof, and the required-null fail-safe target.
class PlanCardFixture extends StatelessWidget {
  const PlanCardFixture({required this.plan, super.key});

  final PlanTier plan;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('plan-name:${plan.name}'),
        Text('plan-price:${plan.price}'),
        Text('plan-badge:${plan.badge?.name ?? 'none'}'),
        Text('plan-tagline:${plan.tagline ?? '-'}'),
      ],
    );
  }
}

/// Renders a required list-of-objects — the list-of-objects proof.
class FeatureGridFixture extends StatelessWidget {
  const FeatureGridFixture({required this.features, super.key});

  final List<PlanFeature> features;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final feature in features)
          Text('feature:${feature.label}:${feature.included}'),
      ],
    );
  }
}

/// Renders a required String-keyed map — the open-dictionary proof.
class GlossaryFixture extends StatelessWidget {
  const GlossaryFixture({required this.terms, super.key});

  final Map<String, String> terms;

  @override
  Widget build(BuildContext context) {
    final entries = terms.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Column(
      children: [
        for (final entry in entries) Text('term:${entry.key}=${entry.value}'),
      ],
    );
  }
}

/// Renders a required named record — the named-record proof.
class MetaBarFixture extends StatelessWidget {
  const MetaBarFixture({required this.meta, super.key});

  final ({String title, int count}) meta;

  @override
  Widget build(BuildContext context) {
    return Text('meta:${meta.title}:${meta.count}');
  }
}

/// Renders a required nested object whose field is named `path` — the
/// binding-sentinel hazard proof (BoundObject would have misread it).
class LinkCardFixture extends StatelessWidget {
  const LinkCardFixture({required this.link, super.key});

  final LinkData link;

  @override
  Widget build(BuildContext context) {
    return Text('link:${link.label}:${link.path}');
  }
}

/// A self-recursive data class with a DIRECT nested-class field (`reply`, of its
/// own type) that is also nullable — the recursion proof (`$defs`/`$ref` schema
/// + a depth-bounded recursive reconstruction helper).
class Comment {
  const Comment({required this.text, this.reply});

  final String text;
  final Comment? reply;
}

/// Renders a required recursive nested object — render-proves the `$ref`-rooted
/// data schema, the depth-bounded recursive reconstruction, and a direct
/// nullable nested-class field.
class CommentThreadFixture extends StatelessWidget {
  const CommentThreadFixture({required this.root, super.key});

  final Comment root;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('comment:${root.text}'),
        if (root.reply != null) Text('reply:${root.reply!.text}'),
      ],
    );
  }
}
