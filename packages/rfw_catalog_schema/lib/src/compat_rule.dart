import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/wire_id.dart';

/// Compatibility classification for a catalog change. Determines how
/// the runtime / backend forwarding layer treats existing blob
/// references when the catalog version shifts.
enum CompatKind {
  /// The entry's wire-format type changed; existing references may not
  /// decode under the new schema.
  typeChange,

  /// The entry's type widened (e.g. `Color` → `Color?`). Additive;
  /// recorded for completeness.
  typeWiden,

  /// The entry was removed; existing references render an error
  /// placeholder or rewrite via a successor.
  removal,

  /// A new entry was added; recorded for completeness.
  addition,

  /// The entry's structural shape changed (e.g. children-slot moved
  /// from `single` to `list`).
  structuralShift,

  /// A union's member set changed (additions are additive; removals
  /// are breaking).
  unionMembershipChange,

  /// A structured type's variant set changed (additions are additive;
  /// removals are breaking).
  factoryVariantChange,
}

/// One compatibility rule emitted by the diff tool when a catalog
/// version changes. Consumed by the backend forwarding layer at blob
/// decode time.
@immutable
final class CompatRule {
  /// Const constructor.
  const CompatRule({
    required this.fromVersion,
    required this.toVersion,
    required this.kind,
    required this.affectedRef,
    this.successorRef,
    this.transitionId,
    this.note,
  });

  /// Catalog version this rule transitions from.
  final String fromVersion;

  /// Catalog version this rule transitions to.
  final String toVersion;

  /// The classification of the change.
  final CompatKind kind;

  /// Reference to the entry that changed.
  final WireIdRef affectedRef;

  /// For forwarding cases, the successor entry the old reference maps to.
  final WireIdRef? successorRef;

  /// When the change is part of a multi-event transition
  /// (deprecate + alloc + replace), the shared transition ID
  /// (`tx*`-prefixed).
  final String? transitionId;

  /// Human-readable migration guidance.
  final String? note;
}
