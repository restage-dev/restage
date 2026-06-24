import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/deprecation_info.dart';
import 'package:rfw_catalog_schema/src/discriminator_spec.dart';
import 'package:rfw_catalog_schema/src/stability.dart';
import 'package:rfw_catalog_schema/src/widget_library.dart';
import 'package:rfw_catalog_schema/src/wire_id.dart';

/// One discriminated union entry in the catalog.
///
/// Examples: `Gradient` (members: `LinearGradient`, `RadialGradient`,
/// `SweepGradient`), `Decoration`, `ShapeBorder`, `BoxBorder`,
/// `InputBorder`. Members are structured types; the discriminator
/// selects which value type a blob slot carries.
@immutable
final class UnionEntry {
  /// Const constructor.
  const UnionEntry({
    required this.wireId,
    required this.name,
    required this.library,
    required this.description,
    required this.sourceType,
    required this.memberSourceTypes,
    required this.discriminator,
    required this.members,
    this.stability = Stability.volatile,
    this.deprecated,
  });

  /// Wire identity for this union.
  final WireId wireId;

  /// Advisory display name (`'Gradient'`). Identity is [wireId].
  final String name;

  /// Library this entry lives in.
  final WidgetLibrary library;

  /// Human-readable description.
  final String description;

  /// Fully-qualified name of the abstract base type this union models
  /// (`'package:flutter/src/painting/gradient.dart#Gradient'`).
  final String sourceType;

  /// Per-member source fully-qualified names, index-aligned with
  /// [members] — `members[i]` has source FQN `memberSourceTypes[i]`.
  /// Lets a later identity pass correlate each member reference back to
  /// the concrete type it stands for.
  final List<String> memberSourceTypes;

  /// On-wire discriminator metadata.
  final DiscriminatorSpec discriminator;

  /// Members of the union as cross-library references — built-in
  /// members and customer-extended members compose uniformly.
  final List<WireIdRef> members;

  /// Stability tier.
  final Stability stability;

  /// Lifecycle status.
  final DeprecationInfo? deprecated;
}
