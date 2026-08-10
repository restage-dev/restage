# Changelog

## Unreleased — coordinated breaking release

This section records the package side of a coordinated breaking release. The
release version and publication timing are assigned separately.

- Make the unnamed generative constructor the source of truth for customer
  widget inputs, requiredness, positionalness, and order; descriptions may come
  from Dartdoc and `RestageProperty` becomes an optional metadata overlay.
- Emit canonical catalog schema v5 while continuing to decode schema v4 at the
  catalog boundary.
- Remove the closed event-name enum and event rename/declaration fields. An
  event's identity is now the exact callback constructor property name.
- Add pure-Dart target configuration annotations with aggregate and composable
  shorthand constructors for A2UI, RFW, and Widgetbook.
- Add `EmitTarget` and target-selective `@Ignore` authoring. Bare `@ignore` and
  `@Ignore()` retain their all-target behavior.
- Add class-level `enabled` configuration and a composable `Config.enabled`
  shorthand for RFW, A2UI, and Widgetbook customer-widget targets.
- Remove the deprecated target fields from `RestageWidget` and
  `RestageProperty`.
- Remove public `RestageWidget.childrenSlot`. Customer child-bearing properties
  are derived from every exact `Widget` and `List<Widget>` constructor input;
  the `ChildrenSlot` enum and `WidgetEntry.childrenSlot` wire field remain for
  curated built-ins and backwards-compatible decoding.

## 1.2.0

- Add typed `RestageConstraints` to property annotations and catalog entries,
  with deterministic schema-v4 encoding and structural preservation of unknown
  constraint keywords.
- Add `RestageDataField` for nested data documentation.

## 1.1.0

- Add the optional `usage` parameter to `@RestageWidget`: producer-facing
  guidance for when and how to use a widget. It emits into the generated A2UI
  catalog's system-prompt fragments, falling back to the widget description.
- Add the opaque list-of-structured wire shape (`ListShape.opaqueStructured`
  and `ListShape.isOpaqueStructuredList`) for a property typed as a list of
  structured values, where the item shape carries the structured reference.

## 1.0.3

- Documentation: README refresh.

## 1.0.2

- Add the optional `writeBackValue` parameter to `@RestageProperty`, pairing a
  callback property with the field whose value it writes back.

## 1.0.1

- Add a usage example and shorten the package description.

## 1.0.0

- Initial release. Catalog data types, wire identity (`WireId`,
  `WireIdRef`, `WireIdKind`), annotations, hand-written JSON codecs,
  and the supporting metadata, default-value, lifecycle, and
  compatibility-rule types.
