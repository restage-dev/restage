# Changelog

## 2.0.0

- Breaking: the registry and catalog use catalog schema v5 from
  `rfw_catalog_schema` 2.0.0. The closed event-name list is gone; a callback's
  constructor property name is its event identity, and a 1.x runtime or
  toolchain does not read this catalog.
- `CupertinoNavigationBar` admits `automaticallyImplyLeading`,
  `automaticallyImplyMiddle`, `previousPageTitle`,
  `automaticBackgroundVisibility`, `enableBackgroundFilterBlur` and
  `brightness`.
- Regenerate the catalog as schema v5. Picker callbacks retain their precise
  Flutter constructor names as open event identities.

## 1.0.2

- Documentation and build-configuration refresh.

## 1.0.1

- Add a usage example and shorten the package description.

## 1.0.0

- Initial release of the `restage.cupertino` RFW catalog: 16 Cupertino
  (Apple HIG) widgets with per-widget metadata and the committed catalog JSON.
