import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/diff/catalog_change.dart';
import 'package:rfw_catalog_compiler/src/diff/compat_classifier.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Emits a [CompatRule] for every `forwarding` and `breaking` change in
/// [changes], in input order.
///
/// `free` and `additive` changes need no decode-time mediation and produce
/// no rule. [fromVersion] / [toVersion] identify the two catalog versions
/// being compared and are stamped on every emitted rule; this emitter does not
/// define the version-string scheme — the caller supplies it.
///
/// Infrastructure ahead of application: this emission path has no production
/// consumer yet (the `CompatRule` type it returns is production; the diff that
/// drives it is not wired in).
@experimental
List<CompatRule> emitCompatRules(
  List<CatalogChange> changes, {
  required String fromVersion,
  required String toVersion,
}) {
  final rules = <CompatRule>[];
  for (final change in changes) {
    final classification = classifyCatalogChange(change);
    if (classification == CompatClassification.forwarding ||
        classification == CompatClassification.breaking) {
      rules.add(_buildRule(change, fromVersion, toVersion));
    }
  }
  return rules;
}

/// Builds the [CompatRule] for one `forwarding` / `breaking` [change].
///
/// `emitCompatRules` gates this on the classifier, so only forwarding and
/// breaking changes reach it. The `free` / `additive` arms throw: they are
/// unreachable, and the throw guards against classifier/emitter drift — if
/// the classifier ever marked one of them breaking, this surfaces the
/// inconsistency loudly rather than emitting a wrong rule.
CompatRule _buildRule(
  CatalogChange change,
  String fromVersion,
  String toVersion,
) {
  final (CompatKind kind, String note) = switch (change) {
    EntryReplaced() => (
        CompatKind.removal,
        '${_kindLabel(change.kind)} ${change.affected} was replaced by '
            '${change.successor}; the decoder forwards old references to '
            'the successor',
      ),
    EntryRemoved() => (
        change.kind == WireIdKind.variant
            ? CompatKind.factoryVariantChange
            : CompatKind.removal,
        '${_kindLabel(change.kind)} ${change.affected} was removed; blobs '
            'referencing it render an error placeholder',
      ),
    PropertyTypeChanged() => (
        CompatKind.typeChange,
        'property ${change.affected} changed type from ${change.from.name} '
            'to ${change.to.name}; existing values may not decode',
      ),
    RequiredFlagChanged(direction: RequiredFlagDirection.tightened) => (
        CompatKind.structuralShift,
        'property ${change.affected} became required; blobs that omit it '
            'fail to decode',
      ),
    SyntheticStrategyChanged() => (
        CompatKind.structuralShift,
        'property ${change.affected} changed its synthetic codegen '
            'strategy; the decoder semantics for the slot shift',
      ),
    WidgetChildrenSlotChanged() => (
        CompatKind.structuralShift,
        'widget ${change.affected} changed its children slot from '
            '${change.from.name} to ${change.to.name}; a structural blob '
            'change is required',
      ),
    UnionMemberRemoved() => (
        CompatKind.unionMembershipChange,
        'union ${change.affected} lost member ${change.member}; blobs '
            'carrying that discriminator value fail to decode',
      ),
    UnionDiscriminatorChanged() => (
        CompatKind.structuralShift,
        'union ${change.affected} changed its discriminator field; the '
            'on-wire union format shifts',
      ),
    VariantArgumentsChanged() => (
        CompatKind.factoryVariantChange,
        'variant ${change.affected} changed its argument shape; the '
            'decoder semantics for the variant shift',
      ),
    TokenTypeChanged() => (
        CompatKind.typeChange,
        'design token ${change.affected} changed type from '
            '${change.from.name} to ${change.to.name}; referencing '
            'defaults may mismatch',
      ),
    EntryAdded() ||
    EntryRenamed() ||
    EntryDeprecated() ||
    RequiredFlagChanged() ||
    PropertyDefaultChanged() ||
    PropertyMetadataChanged() ||
    UnionMemberAdded() ||
    TokenResolverChanged() ||
    TokenFallbackChanged() =>
      throw StateError(
        'emitCompatRules reached _buildRule for a non-breaking, '
        'non-forwarding change: ${change.runtimeType}',
      ),
  };
  return CompatRule(
    fromVersion: fromVersion,
    toVersion: toVersion,
    kind: kind,
    affectedRef: change.affected,
    successorRef: change is EntryReplaced ? change.successor : null,
    transitionId: change is EntryReplaced ? change.transitionId : null,
    note: note,
  );
}

/// A human-readable label for [kind], used in rule notes.
String _kindLabel(WireIdKind kind) {
  return switch (kind) {
    WireIdKind.widget => 'widget',
    WireIdKind.property => 'property',
    WireIdKind.structured => 'structured type',
    WireIdKind.variant => 'variant',
    WireIdKind.parameter => 'factory parameter',
    WireIdKind.union => 'union',
    WireIdKind.designToken => 'design token',
  };
}
