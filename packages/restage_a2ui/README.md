# restage_a2ui

[![pub package](https://img.shields.io/pub/v/restage_a2ui.svg)](https://pub.dev/packages/restage_a2ui) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

Turn your own Flutter widgets into an [A2UI](https://github.com/google/genui)
catalog that a generative-UI model can build screens from, and check each
payload against that catalog before Google's
[`genui`](https://pub.dev/packages/genui) SDK renders it.

Part of [Restage](https://restage.dev), server-driven UI for Flutter.

You annotate ordinary widgets. Restage's build-time toolchain
(`restage_codegen`) generates the genui catalog from them. This package is the
app-side runtime for that catalog: the generated code imports it, and it adds a
check that rejects a payload with a missing component or a too-old catalog,
with a clear message, instead of letting genui throw mid-render.

It does not fetch, host, or stream A2UI; your app or your model session does
that. Generate the catalog before connecting it to GenUI. Neither local GenUI
rendering nor Widgetbook previews need RFW bundling or `restage build push`; that
command builds dashboard previews.

## Generate an A2UI catalog from your widgets

Write a plain Flutter widget, annotate it, run `build_runner`, and get a genui
catalog. You don't write `CatalogItem`s or JSON schemas by hand.

**1. Add dependencies.** The codegen runs at build time and does not ship in
your app.

```yaml
dependencies:
  genui: ^0.10.1                # the renderer
  a2ui_core: ^0.1.0            # incoming A2UI messages
  json_schema_builder: ^0.1.3   # used by the generated data schemas
  restage_a2ui: ^0.2.0          # imported by the generated catalog; the pre-render check
  rfw_catalog_schema: ^2.0.0    # the widget and data-field annotations

dev_dependencies:
  restage_codegen: ^2.0.0       # the build-time catalog generator
  build_runner: ^2.4.0
```

**2. Declare your widget library once.** A barrel file names the library and
its capability version, and re-exports the widgets it owns. The build stamps
`capabilityVersion` into the generated catalog. Raise it when you add a widget
or change how one renders.

```dart
// lib/restage_imports.dart
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

export 'widgets/rating_picker.dart';
// export your other @RestageWidget files

@RestageLibrary(
  library: WidgetLibrary.custom('acme.widgets'),
  capabilityVersion: 1,
)
const restageLibrary = 0;
```

**3. Annotate a widget.** A plain widget plus `@RestageWidget()` is enough.
The class name becomes the component name, and the barrel that exports it
supplies its library. Its public constructor inputs become the component's
properties. Use `@RestageProperty` only to add a description or constraints. A
value property paired with a `ValueChanged` callback of the same type becomes a
two-way binding automatically.

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

A property typed as your own data class gets a nested schema automatically. See
[Rich data](#rich-data).

To set catalog grouping or library identity yourself, pass them on the annotation:
`@RestageWidget(library: WidgetLibrary.custom('acme.widgets'), category:
WidgetCategory.input)`. Use `name:` when the component name must differ from
the class name.

**4. Turn on the A2UI builder.** It is off by default because the generated
catalog imports `genui`. If you only target A2UI, also turn off the three RFW
builders; otherwise they produce files you won't use.

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

These emitter options do not require RFW bundling. Leave `bundled_runtime` at its
default, `false`; no generated surface assets need to be added to the app.

**5. Generate:**

```bash
dart run build_runner build
```

**6. Two outputs appear:**

- `lib/generated/restage_a2ui_catalog.g.dart`: `buildRestageCatalog()`, the
  genui `Catalog` to render against, plus `restageA2uiCapability`, what that
  catalog provides.
- `.restage/build/a2ui/restage_a2ui_catalog.a2ui.json`: the standard A2UI
  catalog document with each component's full data schema. Hand it to whatever
  produces payloads.

A generated component keeps `id` and `component` on the A2UI envelope and puts
every constructor input under one required `props` object:

```json
{
  "id": "rating-control",
  "component": "RatingPicker",
  "props": {
    "rating": 4
  }
}
```

A `Widget` or `List<Widget>` input takes a component ID or a list of IDs, under
whatever name the constructor gives it.

**7. Connect GenUI.** Create a controller with the generated catalog, feed it
A2UI messages, and mount the requested surface:

```dart
import 'package:a2ui_core/a2ui_core.dart' show A2uiMessage;
import 'package:flutter/widgets.dart';
import 'package:genui/genui.dart' as genui;

import 'generated/restage_a2ui_catalog.g.dart';

class A2uiSession {
  final catalog = buildRestageCatalog();
  late final controller = genui.SurfaceController(catalogs: [catalog]);

  void receiveMessage(Map<String, Object?> message) {
    controller.handleMessage(A2uiMessage.fromJson(message));
  }

  Widget buildSurface(String surfaceId) =>
      genui.Surface(surfaceContext: controller.contextFor(surfaceId));

  void dispose() => controller.dispose();
}
```

Own one session in a widget or conversation, and call `dispose()` when that
owner ends. The producer must use `restageA2uiCatalogId` in `createSurface`
messages. GenUI 0.10.1 accepts `v0.9` message envelopes; the generated catalog's
`0.9.1` schema metadata is a separate field. Your app supplies the model
connection and handles outward actions.

`genui.PromptBuilder.chat(catalog: session.catalog)` includes the generated
usage guidance. If you combine `buildRestageCatalogItems()` with other items,
assign the combined contract its own catalog ID and give it to the producer.

**8. Check external or cached payloads before rendering.** Use the same catalog
for the check and controller. The [complete A2UI guide](https://docs.restage.dev/tools/a2ui)
shows message envelopes, checking, and rendering together. The worked
[`example/`](example/) also includes rendering and interaction tests.

## Quickstart

Given an `A2uiSession session`, create one check and reuse it for incoming
messages. A cached Restage sidecar must be checked before unwrapping:

```dart
import 'package:restage_a2ui/restage_a2ui.dart';

final check = RestageA2uiPreRenderCheck(
  catalog: session.catalog,
  installed: restageA2uiCapability.installedCapability,
);

void receiveChecked(Object? incoming) {
  if (check.check(incoming) case A2uiRejected(:final diagnostic)) {
    throw FormatException(diagnostic);
  }
  final payload = RestageA2uiSidecar.isRestageSidecar(incoming)
      ? RestageA2uiSidecar.fromJson(
          Map<String, Object?>.from(incoming! as Map),
        ).a2ui
      : incoming;
  for (final raw in payload is List ? payload : [payload]) {
    session.receiveMessage(Map<String, Object?>.from(raw as Map));
  }
}
```

Feed decoded JSON to `receiveChecked`. Handle rejection and parsing errors at
the message boundary, keeping a native fallback available.

The check returns `A2uiRejected` for:

- a component type the catalog doesn't have;
- a payload that needs a newer catalog version than your build provides;
- a malformed Restage sidecar;
- a stamped payload when you passed no `installed` capability.

It checks which components exist and which versions they need. It does not
validate every field inside a component, so a malformed component can still
fail when genui parses it.

## The capability sidecar

An A2UI payload has no place for a version stamp, so Restage wraps a cached
payload:

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

Cache the wrapper and run the check before rendering `a2ui`. The check compares
the required libraries with the installed catalog's versions and declared
compatibility floors. The generated catalog JSON describes available
capabilities; it is not a payload's required-capability sidecar.

For raw A2UI payloads, the check confirms component names exist but cannot verify
library-version compatibility. A stamped payload is rejected if its requirements
cannot be verified.

## Guiding the model with `description` and `usage`

- Every `description` on a widget or property becomes that field's schema
  `description`, so the model reads the words you wrote.
- An optional `@a2ui.Config.usage('...')` becomes that widget's line in the
  catalog's system prompt: guidance on *when* to use the widget. Without it,
  the widget's `description` is used.

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

`buildRestageCatalog()` attaches these lines to the genui `Catalog`. If you
only need the raw items, use `buildRestageCatalogItems()`.

## Rich data

A property typed as your own data class generates a nested schema, with no
hand-written schema. Supported shapes:

- nested data classes;
- lists of objects (`List<YourType>`);
- `String`-keyed maps (`Map<String, V>`);
- named records (`({double width, double height})`);
- scalars, enums, and scalar lists.

Add `@RestageDataField(description: '...')` to a nested field to describe it in
the schema.

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

  @RestageProperty(description: 'The price to render.')
  final Money price;
  // ...
}
```

If a required value is missing from the payload, the widget does not render a
made-up value. Sealed-class unions are not supported yet. A required unsupported
input stops generation; an optional input can be omitted only when its
constructor default is preserved.

Values bound from data (`{path}`, `{call}`) are not checked against your
constraints, so your widget still validates them.

The same widgets can also ship as RFW surfaces. There, structured objects,
maps, records, and lists work only when Restage can rebuild them for the exact
property. Unsupported structured shapes fail generation with an error instead
of being dropped or decoded as a different shape.

## App Review

The generated catalog describes widget schemas and versions. The widgets
themselves are Dart compiled into your app; an A2UI document only composes and
configures them.

## Status

Pre-1.0, tracking `genui ^0.10.1` (A2UI protocol v0.9). genui is alpha and its
API is expected to change; this package keeps the integration in one place.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
