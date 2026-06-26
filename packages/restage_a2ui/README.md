# restage_a2ui

[![pub package](https://img.shields.io/pub/v/restage_a2ui.svg)](https://pub.dev/packages/restage_a2ui) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

The app-side half of Restage's [A2UI](https://github.com/google/genui) emit target: a fail-closed,
**pre-render capability check** plus a **capability sidecar** for cached A2UI payloads.

Restage's build-time toolchain can emit your widget catalog as an A2UI component catalog (a catalog of
widget schemas a generative-UI model renders against, via Google's [`genui`](https://pub.dev/packages/genui)
SDK). `restage_a2ui` is what an app uses on the *other* end: it checks an A2UI payload against the catalog
the app actually registered **before** handing it to genui, so a payload your build can't render faithfully
fails with a clean, actionable diagnostic instead of throwing mid-render.

## What this is — and is not

- **It is** an app-side safety wrapper: a pre-render check + a capability sidecar you can wrap your cached
  payloads in.
- **It is not** an A2UI delivery mechanism. It does not fetch, host, or stream A2UI — your app (or your
  model session) owns that. It does not generate the catalog either; that is the build-time toolchain.
- It depends on `genui`. Your app already depends on `genui` to render A2UI, so this adds no new render
  stack — only the check.

## Generate an A2UI catalog from your widgets — step by step

This is the whole loop: write a normal Flutter widget, annotate it, run `build_runner`, and get a genui
A2UI catalog — no hand-written `CatalogItem`s, no hand-authored JSON schemas. The emitter is the
build-time toolchain (`restage_codegen`); `restage_a2ui` (this package) is the optional production-safe
check you add at the end.

There are **two paths** — you pick at step 1:

| Path | What you add | Use it when |
| --- | --- | --- |
| **Minimal** | `restage_codegen` (build-time) + `genui` — **zero Restage runtime in your app** | you render your own surfaces and control the payloads |
| **Production-safe** | the above **plus** `restage_a2ui` — a fail-closed pre-render check + version stamp | you render payloads you did not author (model- or server-generated) |

**1. Add dependencies.** The codegen is a *build-time* tool — it does not ship in your app; `genui` is the
renderer; `rfw_catalog_schema` holds the annotations.

```yaml
dependencies:
  genui: ^0.9.2                 # the renderer the generated catalog targets
  json_schema_builder: ^0.1.3   # the generated catalog's data schemas are built with this
  rfw_catalog_schema: ^1.0.1    # the @RestageWidget / @RestageProperty / @RestageLibrary annotations
  # Production-safe path only — the app-side pre-render check + capability sidecar (step 8):
  # restage_a2ui: ^0.1.2

dev_dependencies:
  restage_codegen: ^1.0.3       # the build-time A2UI emitter (not shipped in your app)
  build_runner: ^2.4.0
```

**2. Annotate a widget.** A normal Flutter widget plus `@RestageWidget`; mark its inputs with
`@RestageProperty`. A value property paired with a matching-type `ValueChanged` callback wires the two-way
binding automatically — no pairing annotation needed.

```dart
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'RatingPicker',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.input,
  description: 'A 1–5 star rating control bound to an integer value.',
  fires: [WidgetEventName.onChanged],
)
class RatingPicker extends StatelessWidget {
  const RatingPicker({required this.rating, required this.onRatingChanged, super.key});

  @RestageProperty(description: 'The selected rating, 1 through 5.')
  final int rating;

  @RestageProperty(description: 'Reports the newly selected rating.')
  final ValueChanged<int> onRatingChanged;

  @override
  Widget build(BuildContext context) {
    /* … your widget … */
    return const SizedBox.shrink();
  }
}
```

(A property typed as your own **data class** auto-generates a rich nested schema — see
[Rich data](#rich-data--structured-restagewidget-properties).)

**3. Declare the library.** A barrel that declares your custom library — its namespace and capability
version — and re-exports the widgets that belong to it. The build phase reads `capabilityVersion` off this
declaration and stamps it into the generated catalog.

```dart
// lib/restage_imports.dart
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

export 'widgets/rating_picker.dart';
// … export your other @RestageWidget files

@RestageLibrary(
  library: WidgetLibrary.custom('acme.widgets'),
  capabilityVersion: 1, // bump when you add a widget or make a render-affecting change
)
const restageLibrary = 0;
```

**4. Enable the A2UI builder.** It is opt-in (`auto_apply: none`) because the generated catalog imports
`genui`. If you target A2UI only (not RFW delivery), also turn the two RFW builders **off** — otherwise
they emit unused `.g.dart` files and a spurious "not mechanically generatable for RFW" warning.

```yaml
# build.yaml in the package that declares your @RestageWidget libraries
targets:
  $default:
    builders:
      restage_codegen:user_a2ui_catalog:
        enabled: true
      restage_codegen:user_catalog:    # RFW builder — off for an A2UI-only target
        enabled: false
      restage_codegen:user_factories:  # RFW builder — off for an A2UI-only target
        enabled: false
```

**5. Generate:**

```bash
dart run build_runner build --delete-conflicting-outputs
```

**6. Your two outputs appear** (under `lib/`):

- `…catalog.g.dart` — `buildRestageCatalogItems()`: the genui `CatalogItem`s (each with its data schema and
  widget builder) that genui renders against.
- `…catalog.a2ui.json` — the A2UI-standard catalog document (`{ restageCapability, a2uiCatalog }`).

**7. Render with genui:**

```dart
import 'package:genui/genui.dart';

final catalog = Catalog(buildRestageCatalogItems());
// hand `catalog` to your genui surface — it renders your widgets from an A2UI payload.
```

**That's the whole loop.** On the **minimal** path you now depend on `genui` at runtime and on **no Restage
package** — `restage_codegen` is build-time only. You've replaced hand-written `CatalogItem`s with
auto-generated ones, with zero runtime lock-in.

**8. (Production-safe) Add the fail-closed pre-render check.** If you render payloads you did not author,
add `restage_a2ui` (uncomment it in step 1) and gate each payload before handing it to genui — a bad
payload then fails *closed* with a diagnostic instead of throwing mid-render, and you get the
capability-version check. That is the [Quickstart](#quickstart) below.

A worked version of steps 1–7 lives in [`example/`](example/) — the annotated widgets, the library barrel,
the `build.yaml`, the committed generated catalog, and a test that renders them against genui 0.9.2. It has
no app entrypoint: run `dart run build_runner build` to regenerate, then `flutter test` to see it render.
(`example/`'s own README shows the step-8 pre-render check.)

## Quickstart

Add the dependency:

```yaml
dependencies:
  restage_a2ui: ^0.1.2
  genui: ^0.9.2
```

Build the check once (it is immutable — reuse it for every payload), then gate each cached payload before
handing it to genui:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';
import 'package:restage_a2ui/restage_a2ui.dart';

// 1. The genui catalog your build emitted — the `CatalogItem` set genui renders
//    against. `buildRestageCatalogItems()` is generated by the toolchain (see
//    "Producing the catalog and stamp" below).
final catalog = Catalog(buildRestageCatalogItems());

// 2. What that catalog PROVIDES, parsed from the `restageCapability` block the
//    toolchain emits next to the catalog. This is the available side of the
//    version check; supply it so Restage-stamped payloads can be verified.
final installed = A2uiInstalledCapability.fromStampJson(restageCapability);

// 3. The check — one instance, reused.
final check = RestageA2uiPreRenderCheck(catalog: catalog, installed: installed);

// 4. Gate every payload before render. `check.check` accepts either a raw A2UI
//    payload or a Restage sidecar wrapping one.
Widget? renderCached(String cachedJson) {
  final cached = jsonDecode(cachedJson) as Map<String, Object?>;
  switch (check.check(cached)) {
    case A2uiRenderable():
      // Safe to render. If you cached the sidecar (recommended — it carries the
      // version stamp), unwrap it and hand the inner payload to genui:
      final payload = RestageA2uiSidecar.isRestageSidecar(cached)
          ? RestageA2uiSidecar.fromJson(cached).a2ui
          : cached;
      return renderWithGenui(payload); // your genui render call
    case A2uiRejected(:final diagnostic, :final gap):
      // Do NOT render. Fall back to a built-in surface and log why.
      debugPrint('A2UI rejected: $diagnostic${gap == null ? '' : ' ($gap)'}');
      return null;
  }
}
```

The check fails **closed** at every path: a malformed envelope, an unknown component, an unmet version, or
a stamped payload with no `installed` descriptor all yield an `A2uiRejected` — never a throw at the render
seam.

If you do not cache the sidecar and only have raw A2UI payloads, you can omit `installed`; then only the
existence walk runs and any Restage-stamped payload is rejected as unverifiable (fail-closed). Caching the
sidecar is what enables the version check.

## Producing the catalog and stamp

The two inputs above — `buildRestageCatalogItems()` and the `restageCapability` block — are emitted by
Restage's **build-time toolchain** (`restage_codegen`), which projects your widget catalog (the built-ins
plus any `@RestageWidget` libraries) into two artifacts:

| Artifact | What it is | Who consumes it |
| --- | --- | --- |
| The generated `CatalogItem` Dart (`buildRestageCatalogItems()`) | the functional contract genui renders against — one `CatalogItem` per widget, with its data schema and widget builder | genui, at render time |
| The stamped catalog document (`{ restageCapability, a2uiCatalog }`) | the A2UI catalog JSON plus the two-axis capability stamp (built-in floor + custom-library versions) | this package's check (the `restageCapability` block → `A2uiInstalledCapability.fromStampJson`) |

Both are emitted over the **same** A2UI-emittable widget set, so they agree by construction — a widget the
emitter scopes out is absent from both.

The build wiring that produces them — the opt-in `build_runner` builder, the `build.yaml` settings, and the
generate command — is the [step-by-step walkthrough](#generate-an-a2ui-catalog-from-your-widgets--step-by-step)
above. (The lower-level emit entrypoints `emitA2uiCatalogDart(catalog)` and `emitA2uiCatalog(catalog).toJson()`
are also available for custom pipelines.)

[RFW](https://pub.dev/packages/rfw) remains Restage's native delivery path; A2UI emission is additive.

## Rich data — structured `@RestageWidget` properties

A `@RestageWidget` property typed as your own **data class** generates a rich A2UI schema automatically — no
shim types, no hand-authored schema. The emitter walks the data shape and emits a `genui` schema that
reconstructs the value at render. The supported rich shapes are:

- **nested data classes** (a data class whose fields are themselves data classes),
- **lists of objects** (`List<YourType>`),
- **String-keyed maps** (`Map<String, V>`),
- **named records** (`({double width, double height})`),
- alongside scalars, enums, scalar lists, and the two-way value/event interactivity.

```dart
class Money {
  const Money({required this.amount, required this.currency});
  final double amount;
  final String currency;
}

@RestageWidget(name: 'PriceTag', library: WidgetLibrary.custom('acme.widgets'), /* … */)
class PriceTag extends StatelessWidget {
  const PriceTag({required this.price, super.key});

  // The whole nested value arrives as one property; the generated catalog
  // reconstructs it from the payload and renders it.
  @RestageProperty(description: 'The price to render.')
  final Money price;
  // …
}
```

A required value that is missing from the payload **fails the widget safe** — the surface degrades, never
renders a fabricated value. Sealed-class **unions** are not yet recognized; a union-typed property scopes
out with a clear diagnostic rather than rendering wrong (recognition is a tracked follow-up).

> Note: rich structured properties target the A2UI catalog. Native (RFW) paywall delivery of a custom data
> class is planned, not yet available.

## Why a pre-render check

genui resolves a payload's component types against the catalog you registered **at render time**. A
component the catalog lacks throws `CatalogItemNotFoundException` part-way through building the surface. And
a payload your app **cached** against an older catalog can reference a component whose shape has since
changed — a drift the app, not genui, owns (genui has no built-in payload cache; you cache the serializable
A2UI JSON yourself).

`restage_a2ui` moves that check **before** render and makes it explicit:

1. **Existence walk (any payload).** Every component type the payload references must exist in the catalog
   you registered. Works for any A2UI payload — including one generated live by a model — and catches a
   missing component before genui would throw.
2. **Version satisfaction (Restage-stamped payloads).** A payload wrapped in a Restage sidecar carries the
   catalog **version** it was generated against. The check verifies your installed catalog meets that
   version — across both the built-in widgets and any custom widget libraries — so a payload that needs more
   than your build provides is rejected up front rather than rendered wrong.

Both fail **closed**: a malformed payload, an unknown component, or an unmet version yields a `Rejected`
result with a diagnostic. The check never throws at the render seam.

## The capability sidecar

A2UI's envelope has no place for a per-payload version stamp, so Restage wraps a cached payload:

```json
{
  "restageCapability": {
    "builtInFloor": 2,
    "requiredLibraries": [{ "namespace": "acme.widgets", "minVersion": 3 }],
    "perItemSinceVersion": { "Text": 1, "AcmeBanner": 3 }
  },
  "a2ui": { "...": "the A2UI payload" }
}
```

Cache the wrapper; run the check on it before rendering `a2ui`. The version comparison rests on the
catalog's cumulative-render-support invariant: an incompatible change to a component forks a new identity, so
an existence walk plus a version compare together are sound. (Without the stamp, name-existence alone is
not — a same-name shape change would slip through.)

## App Review

A2UI emission is declarative-data-only — a catalog of widget schemas plus version metadata, no
server-shipped executable code. This package adds only a pre-render check over that data.

## Status

Pre-1.0, tracking `genui ^0.9.2` (A2UI protocol v0.9). genui is alpha and its API is expected to change;
this package isolates the integration so a churn moves one place.
