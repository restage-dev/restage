# Changelog

## 2.0.0

- Add `RestageDecoders.preferredSize` / `optionalPreferredSize`, which adapt a
  rendered slot value to a `PreferredSizeWidget` argument at the height carried
  beside it.
- Breaking: the registry and catalog use catalog schema v5 from
  `rfw_catalog_schema` 2.0.0. The closed event-name list is gone; a callback's
  constructor property name is its event identity, and a 1.x runtime or
  toolchain does not read this catalog.
- Regenerate the catalog as schema v5 with callback property names serving as
  open event identities.

## 1.0.2

- Documentation and build-configuration refresh.

## 1.0.1

- Add a usage example and shorten the package description.

## 1.0.0

- Initial release of the `restage.core` RFW catalog: 54 cross-platform widget
  primitives with per-widget metadata and the committed catalog JSON, plus the
  compiled-in motion (`RestageMotion`/`RestageFadeIn`/`RestagePulse`/
  `RestageStagger`/`RestageSpring`) and number/price formatter widgets.
