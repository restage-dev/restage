import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/deprecation_info.dart';
import 'package:rfw_catalog_schema/src/stability.dart';
import 'package:rfw_catalog_schema/src/theme_binding.dart';
import 'package:rfw_catalog_schema/src/widget_library.dart';
import 'package:rfw_catalog_schema/src/wire_id.dart';

/// What kind of value a design token resolves to. Determines which
/// `PropertyType` slots can reference the token and how the runtime
/// interprets the resolved value.
enum DesignTokenType {
  /// Encoded as a 32-bit ARGB integer.
  color,

  /// A length / dimension (`double`).
  length,

  /// A `Duration` (milliseconds on the wire).
  duration,

  /// A `FontWeight` value.
  fontWeight,

  /// A font size (`double`).
  fontSize,
}

/// One design token entry in the catalog.
///
/// Design tokens are durable named values that paywall blobs may reference
/// for color, length, typography, radius, etc. The runtime resolves the
/// wire-ID reference at render time via the token's [resolver] (a theme
/// binding) or a [literalFallback].
///
/// Design tokens have stable wire identity. Renames are zero-cost. At
/// least one of [resolver] and [literalFallback] is required after
/// replay — a token with neither cannot produce a value at render time.
@immutable
final class DesignTokenEntry {
  /// Const constructor.
  const DesignTokenEntry({
    required this.wireId,
    required this.name,
    required this.library,
    required this.type,
    this.description,
    this.resolver,
    this.literalFallback,
    this.stability = Stability.volatile,
    this.deprecated,
  });

  /// Wire identity for this token.
  final WireId wireId;

  /// Advisory display label (e.g. `'background'`,
  /// `'acme.semantic.success'`). Identity is [wireId]; this name may
  /// shift via `rename` events.
  final String name;

  /// Library this token lives in.
  final WidgetLibrary library;

  /// What kind of value the token resolves to.
  final DesignTokenType type;

  /// Human-readable purpose of the token, surfaced in the editor.
  final String? description;

  /// Where the runtime resolves the value when no [literalFallback]
  /// applies (or as the canonical resolution path). Typically a path
  /// into the active theme.
  final ThemeBindingPath? resolver;

  /// Canonical literal value when no theme resolution is available
  /// (e.g. the host app hasn't wired a custom theme). The literal's
  /// type matches [type]: `int` for color (0xAARRGGBB), `double` for
  /// length / fontSize, etc.
  final Object? literalFallback;

  /// Stability tier. [Stability.volatile] for tokens that may change
  /// shape / resolution in any release; [Stability.stable] for tokens
  /// promoted via a maintainer commitment.
  final Stability stability;

  /// Lifecycle status for this token.
  final DeprecationInfo? deprecated;
}
