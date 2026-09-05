---
title: Restage 2.0
headline_tag: restage-v2.0.0
packages:
  - restage
  - restage_core
  - restage_material
  - restage_cupertino
  - restage_codegen
  - restage_shared
  - rfw_catalog_schema
  - rfw_catalog_compiler
  - restage_measurement_schema
  - restage_a2ui
---
A breaking release. The migration table is at the end; everything not listed there is additive.

## Screens take data from your app

A screen's constructor parameters are now inputs the build understands. Pass values through `context:` on any mount, or let the build generate a typed `<Screen>Surface` widget that mirrors the authored constructor, serializes the values, and shows the compiled-in authored widget when delivery is unavailable.

```dart
StarterChecklistSurface(items: items, onToggle: (id) => setState(() => toggle(id)));
```

The ambient theme's brightness is published too, so `Theme.of(context).brightness == Brightness.dark ? a : b` inside a screen compiles and the delivered surface picks its own palette per mode. The app's text theme is published the same way, so `Theme.of(context).textTheme.titleLarge?.fontSize` and its sibling fields resolve against the running app's type scale. A whole style handed to a `style:` slot compiles too, binding each of its published fields — every `TextStyle` field a slot holds as a scalar or a list of scalars, the font family and its fallbacks, the posture, the spacing and the decoration group among them — so a branded app's display face, its italics and its underlines follow the surface.

Screens also read the device the surface is rendering on. `MediaQuery.sizeOf(context)`, `MediaQuery.paddingOf(context)`, `MediaQuery.devicePixelRatioOf(context)`, `MediaQuery.orientationOf(context)`, `defaultTargetPlatform`, and `Localizations.localeOf(context).languageCode` lower to the device data the runtime publishes on every mount, and a platform, orientation or language comparison in a ternary becomes a match in the artifact. `shortestSide` and `longestSide` are published for layout that keys on the smaller edge. The artifact's data language has no comparison operators, so a numeric breakpoint such as `width > 600` is refused rather than lowered.

Inside a screen, a `for` over a list becomes a loop in the artifact, a `final` or `const` local before the `return` is accepted, a named constant resolves through its declaration, and a closure passed to a callback parameter lowers to its event. A condition may negate with `!`, combine with `&&` and `||`, and compare a String state field, parameter, context value, the theme's brightness, or the device's platform or language to a literal, whether it selects between two values or is bound straight to a boolean input; a collection-`if` on a runtime value keeps its element conditional in the artifact, in a list input of any type, with `else` and nesting; an element whose condition does not hold is absent from its parent, not an empty box, so spacing, runs and indices count what Flutter would count. Both hold inside a custom widget as well as at the screen root. Shapes that depend on runtime values are refused with a diagnostic that names the line.

A screen also reads the host it renders on: the theme's brightness and text styles, the screen size, safe areas and orientation, the platform, and the locale, and a comparison on any of them lowers to a branch in the artifact. `Scaffold` takes its `AppBar` in its own slot.

## Flow screens are routes

Each flow screen is a route on the surface's own `Navigator`. An `AppBar` or `CupertinoNavigationBar` in the screen shows the platform back control whenever there is a screen behind it, and the bar's control, `Navigator.maybePop`, and system back each pop one screen. Screens move with the app's `pageTransitionsTheme`, `Hero` flies between them, and the iOS edge swipe and Android predictive back work as they do anywhere else. The runtime draws no back or skip controls of its own; skip is an action you place in the bar.

## Custom widgets are described by their constructor

The unnamed constructor of a `@RestageWidget` is the source of truth for its inputs, requiredness, and order, with descriptions from Dartdoc. A callback parameter's name is its event identity; there is no event enum to declare. The catalog is schema v5, and v4 catalogs still decode. Every `Widget` and `List<Widget>` input is a child-bearing property, `AppBar.actions` included, and per-target configuration is authored in Dart for RFW, A2UI, and Widgetbook.

## Commerce and measurement are contracts

Legacy billing gateways, products, purchase helpers, and the authored commerce widgets are removed. `package:restage/commerce.dart` is a provider-neutral typed request and response surface that is inert in 2.0; nothing purchases until a host opts in. The measurement contracts the SDK compiles against are published as `restage_measurement_schema`: inert data types that compute nothing and reach no network. `Restage.measurement` and `Restage.privacy` carry the explicit subject operations and return `temporarilyUnavailable` until the service serves measurement for your app.

## Migrating from 1.x

Renamed, with `@Deprecated` aliases that keep working through 2.x:

| 1.x | 2.0 |
|---|---|
| `RestageSurfaceScreen<E>` | `RestageScreen<E>` |
| `RestageSurfaceFlow<R>` | `RestageFlowGraph<R>` |
| `RestageSurfaceScreenResolver` | `RestageScreenResolver` |
| `RestageSurfaceEventDispatcher` | `RestageEventDispatcher` |
| `WelcomeScreenDescriptor.ref` | `welcomeScreenRef` |
| `registerRestageCustomerWidgets()` | `registerRestageWidgets()` |

Removed, with no alias:

- the flow chrome parameters (`enableSkip`, `chromeTheme`, `persistentChrome`, `backBuilder`, `skipBuilder`, `chromeBuilder`, `persistentChromeBuilder`) and the `FlowChrome*` types; place an `AppBar` or `CupertinoNavigationBar` in the screen instead
- `defaultFlowTransitionBuilder`; screens follow `pageTransitionsTheme`, and `transition:` replaces the motion for one flow
- `Restage.identify`, `Restage.track`, `Restage.beginSurfaceSession`, `Restage.endSurfaceSession`, `Restage.sdkVersion`
- `Restage.configure(products:, billingGateway:)`, the `Package` and `ExpressCheckoutButton` catalog widgets, and the `paywallPurchase` and `paywallPriceFor` authoring forms
- experiment assignment metadata on delivery types and events
- the closed event-name enum; a callback's constructor name is its event identity
- `CommerceCustomerState` and `CommerceCustomerStateStatusCode` are `CommercePurchaserState` and `CommercePurchaserStateStatusCode`

Generated Dart changes; delivery artifacts do not. The `.rfw` bytes, event-contract hashes, and published identities are unchanged across this release.

**Versions:** `restage`, `restage_core`, `restage_material`, `restage_cupertino`, `restage_codegen`, `restage_shared`, `rfw_catalog_schema`, `rfw_catalog_compiler` 2.0.0 · `restage_measurement_schema` 0.1.0 · `restage_a2ui` 0.2.0
