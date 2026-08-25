# Changelog

## 2.0.0

- Remove the authored commerce widgets `Package` and
  `ExpressCheckoutButton`. Authored surfaces do not initiate purchases or
  restores; host code decides how to handle UI intent.

## 1.1.0

- Regenerate the catalog as schema v5 with callback property names serving as
  open event identities.
- Add an `@nodoc` runtime bridge used by the SDK to observe settled pager page
  changes without changing authored callback delivery.

## 1.0.2

- Documentation and build-configuration refresh.

## 1.0.1

- Add a usage example and shorten the package description.
- Silence a generated icon-factory analyzer warning.

## 1.0.0

- Initial release of the `restage.material` RFW catalog: 45 Material widgets
  with per-widget metadata and the committed catalog JSON, plus the compiled-in
  interactive composites (`RestageModalSheet`/`RestageDraggableSheet`/
  `RestagePager` and the selection controls) and the `Package` /
  `ExpressCheckoutButton` domain widgets.
