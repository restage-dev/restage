import 'package:meta/meta.dart';

import 'package:rfw_catalog_schema/src/wire_id.dart';

/// Two-layer deprecation metadata for a catalog entry.
///
/// Catalog entries can be deprecated at two independent layers:
///
/// * **Source-level** — the underlying Dart class / field / parameter
///   carries an `@Deprecated('...')` annotation. The analyzer captures
///   this at compile time and surfaces it via [source].
/// * **Catalog lifecycle** — the catalog's maintainer issued a
///   `deprecate` event against the entry's wire ID, marking it as no
///   longer recommended for new authoring while continuing to honor
///   existing blob references. Surfaced via [catalog].
///
/// Both layers can coexist or apply independently. A widget that's
/// `@Deprecated` upstream may stay live in the catalog for as long as
/// the maintainer wants to keep supporting existing blobs; a widget the
/// maintainer retires may be catalog-deprecated while still active
/// upstream. The runtime honors the catalog lifecycle; the editor surfaces
/// both.
@immutable
final class DeprecationInfo {
  /// Const constructor.
  const DeprecationInfo({this.source, this.catalog});

  /// Upstream `@Deprecated` annotation, captured at compile time. The
  /// editor surfaces as "deprecated upstream" without blocking authoring.
  final SourceDeprecationInfo? source;

  /// Catalog-lifecycle deprecation, derived from a `deprecate` event
  /// in the wire ID event log. The editor surfaces as "deprecated in
  /// the catalog" without blocking authoring. Existing blobs continue
  /// to honor the entry; removal happens via an explicit `replace`
  /// event with a successor.
  final CatalogDeprecationInfo? catalog;

  @override
  bool operator ==(Object other) =>
      other is DeprecationInfo &&
      other.source == source &&
      other.catalog == catalog;

  @override
  int get hashCode => Object.hash(source, catalog);
}

/// Source-side deprecation captured from an upstream `@Deprecated`
/// annotation on the underlying Dart element.
@immutable
final class SourceDeprecationInfo {
  /// Const constructor.
  const SourceDeprecationInfo({required this.message, this.since});

  /// The `@Deprecated('message')` message captured from source.
  final String message;

  /// When the source version applied the deprecation, if recorded in
  /// the annotation or extractable from version control.
  final String? since;

  @override
  bool operator ==(Object other) =>
      other is SourceDeprecationInfo &&
      other.message == message &&
      other.since == since;

  @override
  int get hashCode => Object.hash(message, since);
}

/// Catalog-side deprecation derived from a `deprecate` event in the
/// wire ID event log.
@immutable
final class CatalogDeprecationInfo {
  /// Const constructor.
  const CatalogDeprecationInfo({
    required this.reason,
    required this.at,
    this.transitionId,
    this.replaceWith,
  });

  /// Maintainer-supplied reason from the `deprecate` event.
  final String reason;

  /// Event timestamp (ISO-8601 UTC).
  final String at;

  /// When the deprecation participates in a multi-event transition
  /// (deprecate + alloc + replace), the shared transition ID
  /// (`tx*`-prefixed; distinct from the design-token `t*` prefix).
  final String? transitionId;

  /// Successor entry, if one was registered via a `replace` event.
  final WireIdRef? replaceWith;

  @override
  bool operator ==(Object other) =>
      other is CatalogDeprecationInfo &&
      other.reason == reason &&
      other.at == at &&
      other.transitionId == transitionId &&
      other.replaceWith == replaceWith;

  @override
  int get hashCode => Object.hash(reason, at, transitionId, replaceWith);
}
