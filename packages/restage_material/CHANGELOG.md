# Changelog

## 2.0.0

- `Scaffold` admits `appBar`, so a screen composes its bar in the
  scaffold's own slot and the bar sits below the status bar inset. A bar that
  sets its own `toolbarHeight` is laid out at that height.
- `AppBar` admits `bottom`, and `TabBar`, `DefaultTabController` and
  `PreferredSize` join the catalog, so a tabbed bar is authored in plain
  Flutter without host code owning a tab controller.
- `AppBar` admits `leading`, `actions`, `automaticallyImplyLeading`,
  `toolbarHeight`, `titleSpacing`, `leadingWidth`, `scrolledUnderElevation`,
  `shadowColor`, `surfaceTintColor`, `primary`, `forceMaterialTransparency`
  and `actionsPadding`. A delivered screen can place its own controls in the
  bar, and the bar's back control follows the host route.
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
