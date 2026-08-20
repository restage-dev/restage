# restage_a2ui

[![pub package](https://img.shields.io/pub/v/restage_a2ui.svg)](https://pub.dev/packages/restage_a2ui) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

The app-side half of Restage's [A2UI](https://github.com/google/genui) target:
a fail-closed pre-render check, plus a capability sidecar for cached A2UI
payloads.

Restage's build-time toolchain can emit your widget catalog as an A2UI
component catalog, which a generative-UI model renders against through
Google's [`genui`](https://pub.dev/packages/genui) SDK. `restage_a2ui` runs in
the app on the other end. Before a payload reaches genui, it checks the payload
against the catalog the app registered, so a missing component or a capability
gap fails with a clear diagnostic instead of throwing mid-render.

What this package does:

- checks a payload before render, and wraps cached payloads in a capability
  sidecar;
- depends on `genui`, which your app already depends on to render A2UI, so it
  adds no second render stack.

What it does not do:

- fetch, host, or stream A2UI. Your app or your model session owns delivery;
- generate the catalog. The build-time toolchain does that;
- validate every malformed inner A2UI component shape. It is a capability
  check.

## Generate an A2UI catalog from your widgets, step by step

The whole loop: write a plain Flutter widget, annotate it, run `build_runner`,
and get a genui A2UI catalog. No hand-written `CatalogItem`s and no hand-written
JSON schemas. `restage_codegen` is the emitter; `restage_a2ui` is the optional
check you add at the end.

Pick a path at step 1:

| Path | What you add | Use it when |
| --- | --- | --- |
| **Minimal** | `restage_codegen` (build time) + `genui`. No Restage runtime in your app. | You render your own surfaces and control the payloads. |
| **Production-safe** | The above plus `restage_a2ui`: a fail-closed pre-render check and a version stamp. | You render payloads you did not write (model- or server-generated). |

**1. Add dependencies.** The codegen runs at build time and does not ship in
your app. `genui` is the renderer. `rfw_catalog_schema` holds the annotations.

```yaml
dependencies:
  genui: ^0.10.1                # the renderer the generated catalog targets
  json_schema_builder: ^0.1.3   # the generated catalog's data schemas use this
  rfw_catalog_schema: ^1.2.0    # the widget and data-field annotations
  # Production-safe path only (step 8):
  # restage_a2ui: ^0.1.6

dev_dependencies:
  restage_codegen: ^1.3.0       # the build-time A2UI emitter
  build_runner: ^2.4.0
```

**2. Declare the library once.** Add a typed barrel that declares the custom
library's namespace and capability version, and re-exports the widgets it owns.
The build reads `capabilityVersion` from this declaration and stamps it into the
generated catalog.

```dart
// lib/restage_imports.dart
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

export 'widgets/rating_picker.dart';
// export your other @RestageWidget files

final class AcmeWidgets extends WidgetLibrary {
  const AcmeWidgets();

  @override
  final String namespace = 'acme.widgets';
}

const WidgetLibrary acmeWidgets = AcmeWidgets();

@RestageLibrary(library: acmeWidgets, capabilityVersion: 1)
const restageCatalog = 0;
```

**3. Annotate a widget.** A plain Flutter widget plus bare `@RestageWidget()`
is enough to include its supported public constructor inputs. The class name
becomes the component name, the exporting barrel supplies its library, and an
omitted category means root placement. Use `@RestageProperty` only for shared
metadata such as constraints or an explicit description. A value property
paired with a `ValueChanged` callback of the same type wires the two-way
binding automatically.

```dart
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A 1-5 star rating control bound to an integer value.
@RestageWidget()
class RatingPicker extends StatelessWidget {
  const RatingPicker({required this.rating, required this.onRatingChanged, super.key});

  @RestageProperty(description: 'The selected rating, 1 through 5.')
  final int rating;

  @RestageProperty(description: 'Reports the newly selected rating.')
  final ValueChanged<int> onRatingChanged;

  @override
  Widget build(BuildContext context) {
    /* your widget */
    return const SizedBox.shrink();
  }
}
```

A property typed as your own data class generates a nested schema
automatically. See [Rich data](#rich-data-structured-restagewidget-properties).

For placement or identity control, keep typed overrides on the widget:
`@RestageWidget(library: WidgetLibrary.custom('acme.widgets'), category:
WidgetCategory.input)`. The explicit library disambiguates multiple owners.
`name:` sets a stable component key when it must differ from the Dart class
name.

**4. Enable the A2UI builder.** It is opt-in (`auto_apply: none`) because the
generated catalog imports `genui`. If you target A2UI only, also turn the three
RFW customer builders off. Otherwise they emit unused RFW catalog and factory
artifacts, and they may reject fields that only the A2UI target supports.

```yaml
# build.yaml in the package that declares your @RestageWidget libraries
targets:
  $default:
    builders:
      restage_codegen:user_a2ui_catalog:
        enabled: true
      restage_codegen:user_catalog:       # RFW builders, off for an A2UI-only target
        enabled: false
      restage_codegen:user_catalog_json:
        enabled: false
      restage_codegen:user_factories:
        enabled: false
```

**5. Generate:**

```bash
dart run build_runner build
```

**6. Two outputs appear** under `lib/generated/`:

- `restage_a2ui_catalog.g.dart`: `buildRestageCatalogItems()`, the genui
  `CatalogItem`s (each with its data schema and widget builder) that genui
  renders against, plus the content-derived `restageA2uiCatalogId`.
- `restage_a2ui_catalog.a2ui.json`: the A2UI-standard catalog document
  (`{ restageCapability, a2uiCatalog }`). Each
  `a2uiCatalog.components.<Name>` carries that component's full data schema,
  the same schema genui's own `Catalog.toCapabilitiesJson()` would emit, so a
  producer can generate payloads from this document alone.

Every generated component has one required object-valued `props` property.
The A2UI envelope owns `id` and `component`; every Dart constructor input lives
under `props`. So a source input can be named `id`, `component`, `catalogId`,
or even `props` with no escaping or aliasing. Recursive component schemas are
standalone schema resources: resolve component-root-relative `#/$defs/...`
pointers within the component schema, not against the whole catalog file.

The payload shape is:

```json
{
  "id": "rating-control",
  "component": "RatingPicker",
  "props": {
    "rating": 4
  }
}
```

`Widget` and `List<Widget>` inputs follow the same rule: their property names
under `props` carry a component ID or a list of component IDs. No input has to
be named `child` or `children`.

Typed `RestageConstraints` are projected onto the literal arm of a generated
field schema. They describe the accepted literal catalog shape. Values resolved
from `{path}` or `{call}` remain application data, so the widget or app still
enforces its runtime domain rules.

**7. Render with genui:**

```dart
import 'package:genui/genui.dart';

final catalog = buildRestageCatalog();
// hand `catalog` to your genui surface; it renders your widgets from an A2UI payload.
```

`buildRestageCatalog()` wraps `buildRestageCatalogItems()` with the composed
`systemPromptFragments` described in
[Guiding the model](#guiding-the-model-with-description-and-usage) below. If
you only need the raw `CatalogItem`s, `buildRestageCatalogItems()` alone works.

That is the whole loop. On the minimal path you now depend on `genui` at
runtime and on no Restage package; `restage_codegen` runs at build time only.

**8. (Production-safe) Add the pre-render check.** If you render payloads you
did not write, add `restage_a2ui` (uncomment it in step 1) and gate each
payload before handing it to genui. Unknown component types in well-formed
entries and capability-version gaps then fail closed with a diagnostic. That is
the [Quickstart](#quickstart) below.

A worked version of steps 1 to 7 lives in [`example/`](example/): the annotated
widgets, the library barrel, the `build.yaml`, the committed generated catalog,
and a test that renders them against genui 0.10.1. It has no app entrypoint.
Run `dart run build_runner build` to regenerate, then `flutter test` to see it
render. The `example/` README shows the step-8 check.

## Quickstart

Add the dependency:

```yaml
dependencies:
  restage_a2ui: ^0.1.6
  genui: ^0.10.1
```

Build the check once (it is immutable, so reuse it for every payload), then
gate each cached payload before handing it to genui:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';
import 'package:restage_a2ui/restage_a2ui.dart';

// 1. The genui catalog your build emitted: the `CatalogItem` set genui renders
//    against, with its system-prompt fragments attached. The toolchain
//    generates `buildRestageCatalog()` (see "Producing the catalog and stamp"
//    below). Use `Catalog(buildRestageCatalogItems())` instead if you only
//    need the raw `CatalogItem`s.
final catalog = buildRestageCatalog();

// 2. What that catalog PROVIDES, parsed from the `restageCapability` block the
//    toolchain emits next to the catalog. This is the available side of the
//    version check. Supply it so Restage-stamped payloads can be verified.
final installed = A2uiInstalledCapability.fromStampJson(restageCapability);

// 3. The check. One instance, reused.
final check = RestageA2uiPreRenderCheck(catalog: catalog, installed: installed);

// 4. Gate every payload before render. `check.check` accepts either a raw A2UI
//    payload or a Restage sidecar wrapping one.
Widget? renderCached(String cachedJson) {
  final cached = jsonDecode(cachedJson) as Map<String, Object?>;
  switch (check.check(cached)) {
    case A2uiRenderable():
      // Safe to render. If you cached the sidecar (recommended, it carries the
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

The check fails closed, with an `A2uiRejected`, for a malformed Restage sidecar
envelope, an unknown component type in a well-formed `{id, component}` entry,
an unmet version, or a stamped payload with no `installed` descriptor. It does
not validate the inner A2UI payload shape; a malformed component entry can
still fail when genui parses it at render.

If you do not cache the sidecar and only have raw A2UI payloads, you can omit
`installed`. Then only the existence walk runs, and the check rejects any
Restage-stamped payload as unverifiable. Caching the sidecar is what enables
the version check.

## Producing the catalog and stamp

Restage's build-time toolchain (`restage_codegen`) emits the two inputs above,
`buildRestageCatalogItems()` and the `restageCapability` block, from your
`@RestageWidget` libraries:

| Artifact | What it is | Who consumes it |
| --- | --- | --- |
| The generated `CatalogItem` Dart (`buildRestageCatalogItems()`) | The contract genui renders against: one `CatalogItem` per widget, with its data schema and widget builder | genui, at render time |
| The stamped catalog document (`{ restageCapability, a2uiCatalog }`) | The A2UI catalog JSON plus the two-axis capability stamp (built-in floor + custom-library versions) | This package's check (`restageCapability` → `A2uiInstalledCapability.fromStampJson`) |

Both come from the same set of `@RestageWidget` libraries, so they agree by
construction: a widget the emitter scopes out is absent from both. The
generated catalog contains only your own widgets. Projecting Flutter's built-in
widgets into an A2UI catalog is separate work and not part of this path.

The build wiring (the opt-in builder, the `build.yaml` settings, and the
generate command) is the
[step-by-step walkthrough](#generate-an-a2ui-catalog-from-your-widgets-step-by-step)
above. The lower-level emit entrypoints `emitA2uiCatalogDart(catalog)` and
`emitA2uiCatalog(catalog).toJson()` are available for custom pipelines.

[RFW](https://pub.dev/packages/rfw) remains Restage's native delivery path.
A2UI emission is additive.

## Guiding the model with `description` and `usage`

Restage descriptions and A2UI target configuration feed the generative-UI model
directly. Both are guidance you wrote, never inferred:

- Every `description` you write on a widget or property is emitted as that
  field's schema `description` in the generated A2UI catalog. A model reading
  the catalog's JSON schema sees the words you wrote.
- An optional `@a2ui.Config.usage('...')` becomes that widget's line in genui's
  `Catalog.systemPromptFragments`: guidance the model reads when it decides
  *when* to reach for the widget, separate from the schema it fills in. A
  widget with no `usage` falls back to its `description`. A widget with neither
  contributes no line.

```dart
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@a2ui.Config.usage(
  'Use for a short highlighted aside around optional content.',
)
/// A message callout that wraps an optional child.
@RestageWidget()
class Callout extends StatelessWidget { /* ... */ }
```

`buildRestageCatalog()` returns the genui `Catalog` with these fragments
attached. Use it in place of `Catalog(buildRestageCatalogItems())` when you
want your `description` and `usage` notes to reach the model's system prompt.

## Rich data: structured `@RestageWidget` properties

A `@RestageWidget` property typed as your own data class generates a rich A2UI
schema automatically, with no shim types and no hand-written schema. The
emitter walks the data shape and emits a `genui` schema that reconstructs the
value at render. The supported rich shapes are:

- nested data classes (a data class whose fields are themselves data classes),
- lists of objects (`List<YourType>`),
- String-keyed maps (`Map<String, V>`),
- named records (`({double width, double height})`),
- alongside scalars, enums, scalar lists, and the two-way value/event
  interactivity.

Annotate a nested field with `@RestageDataField(description: '...')` when its
schema should carry an explicit description. The description attaches to the
nested occurrence or shared definition without changing the reconstructed Dart
value.

```dart
class Money {
  const Money({required this.amount, required this.currency});
  final double amount;
  final String currency;
}

/// Displays a structured price value.
@RestageWidget()
class PriceTag extends StatelessWidget {
  const PriceTag({required this.price, super.key});

  // The whole nested value arrives as one property. The generated catalog
  // reconstructs it from the payload and renders it.
  @RestageProperty(description: 'The price to render.')
  final Money price;
  // ...
}
```

A required value that is missing from the payload fails the widget safe: the
surface degrades and never renders a fabricated value. Sealed-class unions are
not recognized yet. A union-typed property scopes out with a clear diagnostic
instead of rendering wrong.

> RFW delivery admits supported structured objects, maps, records, and lists
> only when Restage can form a reconstruction plan for the exact property.
> Unsupported structured shapes fail generation with an error instead of being
> dropped or decoded as a different shape.

## Why a pre-render check

genui resolves a payload's component types against the catalog you registered
at render time. A component the catalog lacks throws
`CatalogItemNotFoundException` part-way through building the surface. And a
payload your app cached against an older catalog can reference a component
whose shape has since changed. That drift is the app's to own, since genui has
no built-in payload cache; you cache the serializable A2UI JSON yourself.

`restage_a2ui` moves that check before render and makes it explicit:

1. **Existence walk (any payload).** Every component type the payload
   references must exist in the catalog you registered. This works for any
   A2UI payload, including one a model generated live, and catches a missing
   component before genui would throw.
2. **Version satisfaction (Restage-stamped payloads).** A payload wrapped in a
   Restage sidecar carries the catalog version it was generated against. The
   check verifies that your installed catalog meets that version, across both
   the built-in content floor and any custom widget libraries, so a payload
   that needs more than your build provides is rejected up front.

Both return a `Rejected` result with a diagnostic for malformed Restage sidecar
envelopes, unknown component types in well-formed `{id, component}` entries,
and unmet versions. They do not validate every inner A2UI component shape;
malformed component entries can still fail when genui parses them at render.

## The capability sidecar

A2UI's envelope has no place for a per-payload version stamp, so Restage wraps
a cached payload:

```json
{
  "restageCapability": {
    "builtInFloor": 1,
    "requiredLibraries": [{ "namespace": "acme.widgets", "minVersion": 3 }],
    "perItemSinceVersion": { "RatingPicker": 1, "AcmeBanner": 3 }
  },
  "a2ui": { "...": "the A2UI payload" }
}
```

`builtInFloor` is the built-in content floor the payload needs. For a catalog
built only from your own widgets it stays at the baseline, and
`requiredLibraries` carries your custom-library versions. Cache the wrapper and
run the check on it before rendering `a2ui`. The version comparison rests on
the catalog's cumulative-render-support invariant: an incompatible change to a
component forks a new identity, so an existence walk plus a version compare
together are sound. Without the stamp, name existence alone is not: a
same-name shape change would slip through.

## App Review

A2UI emission is declarative data only: a catalog of widget schemas plus
version metadata, with no server-shipped executable code. This package adds
only a pre-render check over that data.

## Status

Pre-1.0, tracking `genui ^0.10.1` (A2UI protocol v0.9). genui is alpha and its
API is expected to change. This package isolates the integration so a change
moves one place.
