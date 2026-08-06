# Changelog

## 1.2.0

- Add typed `RestageConstraints` to property annotations and catalog entries,
  with deterministic schema-v4 encoding and structural preservation of unknown
  constraint keywords.
- Add `RestageDataField` for nested data documentation and the repeatable
  `RestageA2uiExample` annotation for canonical A2UI examples.

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
