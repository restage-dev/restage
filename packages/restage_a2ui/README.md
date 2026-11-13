# restage_a2ui

[![pub package](https://img.shields.io/pub/v/restage_a2ui.svg)](https://pub.dev/packages/restage_a2ui) [![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

[Restage](https://restage.dev) is server-driven UI for Flutter: it lets a team
change any screen of a shipped Flutter app without a release.

Requires A2UI 1.0 through `a2ui_flutter: ^0.3.0` and `a2ui_core: ^0.7.0`,
with Dart >=3.11.0, Flutter >=3.38.0 and `json_schema_builder` >=0.1.7.

Turn your own Flutter widgets into an [A2UI](https://a2ui.org)
catalog that a generative-UI model can build screens from, and check each
payload against that catalog before Google's
[`a2ui_flutter`](https://pub.dev/packages/a2ui_flutter) SDK renders it.

You annotate ordinary widgets. Restage's build-time toolchain
(`restage_codegen`) generates the a2ui_flutter catalog from them. This package is the
app-side runtime for that catalog: the generated code imports it, and it adds a
check that rejects a payload with a missing component or a too-old catalog,
with a clear message, instead of letting a2ui_flutter throw mid-render.

It does not fetch, host, or stream A2UI; your app or your model session does
that. Generate the catalog before connecting it to A2UI. Neither local A2UI
rendering nor Widgetbook previews need RFW bundling or `restage build push`; that
command builds dashboard previews.

## Generate an A2UI catalog from your widgets

Write a plain Flutter widget, annotate it, run `build_runner`, and get an a2ui_flutter
catalog. You don't write `ComponentImplementation`s or JSON schemas by hand.

**1. Add dependencies.** The codegen runs at build time and does not ship in
your app.

```yaml
dependencies:
  a2ui_flutter: ^0.3.0          # the renderer
  a2ui_core: ^0.7.0             # incoming A2UI messages
  json_schema_builder: ^0.1.7   # used by the generated data schemas
  restage_a2ui:
    path: ../restage_a2ui       # local repository package
  rfw_catalog_schema: ^2.0.0    # the widget and data-field annotations

dev_dependencies:
  restage_codegen:
    path: ../restage_codegen    # local repository package
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
catalog imports `a2ui_flutter`. If you only target A2UI, also turn off the three RFW
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
  a2ui_flutter `CatalogImplementation` to render against, plus `restageA2uiCapability`, what that
  catalog provides.
- `.restage/build/a2ui/restage_a2ui_catalog.a2ui.json`: the standard A2UI
  catalog document with each component's full data schema. Hand it to whatever
  produces payloads.

A generated component keeps `id` and `component` on the outer A2UI object and puts
constructor inputs in top-level properties. For ordinary names:

```json
{
  "id": "rating_control",
  "component": "RatingPicker",
  "props_rating": 4
}
```

Ordinary constructor names use `props_<DartName>` when that name is a valid
upstream UAX31 identifier and the source name does not start with `encoded_`.
Other names, including `$value`, and all source names starting with `encoded_`
use `props_encoded_<hex>`. The hex concatenates the source name's UTF-16 code
units as exactly four lowercase digits each; `$value` becomes
`props_encoded_002400760061006c00750065`. Reserving `encoded_` prevents a normal
source name from colliding with an encoded name. Producers must use the property
keys in the generated catalog schema and instructions. Dart constructor arguments
and nested rich-data keys keep their original names. Nested rich-data keys that start with `@` are written as `@@` on the wire; the runtime unescapes them.

A `Widget` or `List<Widget>` input takes a component ID or a list of IDs, under
whatever name the constructor gives it.

**7. Connect A2UI.** Own a processor for the session and render its surface:

```dart
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/widgets.dart';
import 'generated/restage_a2ui_catalog.g.dart';

class A2uiSession {
  final catalog = buildRestageCatalog();
  late final processor = MessageProcessor<ComponentImplementation>(
    catalogs: [catalog],
    defaultVersion: A2uiProtocolVersion.v1_0,
    validationConfig: ValidationConfig.strict,
    onAction: (action) { /* send the action through your app's transport */ },
  );
  void receiveMessage(Map<String, Object?> message) => processor.processMessages(message);
  Widget buildSurface(String surfaceId) =>
      A2uiSurface(surface: processor.model.getSurface(surfaceId)!);
  void dispose() => processor.dispose();
}
```

Use `version: "1.0"` messages and the exact `restageA2uiCatalogId` in
`createSurface`. Create the surface before updates, or provide initial
`components` inline on creation. Dispose the processor with its owner. Give the
producer `catalog.toJson()` and its `instructions`; your app owns transport.

**8. Check external or cached payloads before rendering.** Use the same catalog
for the check and processor. The [complete A2UI guide](https://docs.restage.dev/tools/a2ui)
shows message envelopes, checking, and rendering together. The worked
[`example/`](example/) also includes rendering and interaction tests.

## Quickstart

Given an `A2uiSession session`, create one check and reuse it for complete cached
message bundles. A cached Restage sidecar must be checked before unwrapping:

```dart
import 'package:a2ui_core/a2ui_core.dart';
import 'package:restage_a2ui/restage_a2ui.dart';

final check = RestageA2uiPreRenderCheck(
  catalogs: [session.catalog],
  installed: restageA2uiCapability.installedCapability,
  validationConfig: ValidationConfig.strict, // the processor's config
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

- a message that is not a v1 envelope, or a version other than `1.0`;
- a component type, catalog or function the catalogs don't declare, or a
  component that doesn't match its schema;
- a bundle that leaves no surface, a surface with no components, a missing
  root, a dangling child reference or a cycle;
- a payload that needs a newer catalog version than your build provides;
- a malformed Restage sidecar;
- a stamped payload when you passed no `installed` capability.

It validates each component against its explicit catalog or the surface default.
Pass a complete cached bundle, including surface creation, and the same
`validationConfig` your `MessageProcessor` uses: the check applies it to each
message as the processor does, so it rejects what the processor would reject.
The finished bundle must also render. Preflight never executes functions.

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
compatibility floors. The generated catalog JSON describes what the catalog
provides. A payload's sidecar describes what that payload needs.

For raw A2UI payloads, the check validates the bundle against the catalog but
cannot verify library-version compatibility. A stamped payload is rejected if its requirements
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

`buildRestageCatalog()` attaches these lines as the catalog `instructions`.

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
input stops generation; an optional input can be left out only when leaving it
out gives the same result as its default.

Values bound from data (`{@path}`, `{@call}`) are not checked against your
constraints, so your widget still validates them.

The same widgets can also ship as RFW surfaces. There, structured objects,
maps, records, and lists work only when Restage can rebuild them for the exact
property. Unsupported structured shapes fail generation with an error instead
of being dropped or decoded as a different shape.

## App Review

The generated catalog describes widget schemas and versions. The widgets
themselves are Dart compiled into your app; an A2UI document only composes and
configures them.

## Requirements

Requires A2UI 1.0 through `a2ui_flutter: ^0.3.0` and `a2ui_core: ^0.7.0`,
with Dart >=3.11.0, Flutter >=3.38.0 and `json_schema_builder` >=0.1.7.

## Migrating an existing integration

Regenerate the catalog and migrate producer/cached documents together. Generated
inputs now use the generated top-level property names. Ordinary names retain
`props_<DartName>`: `props` becomes `props_props`, and `id` becomes `props_id`.
Names that fail upstream UAX31 validation or start with `encoded_` use the
reserved UTF-16 hex encoding described above. Read the regenerated schema when
migrating producers and cached inputs; keep nested business-data keys unchanged. Keep
protocol `id`, `component`, and `catalogId` separate. Dynamic references use
`{"@path":"/answer"}` and `{"@call":"functionName"}`. Do not rename ordinary
business-data keys, `updateDataModel.path`, or child-template `path` fields.

Run `dart fix --apply` after updating the repository packages. The shipped fix
wraps `RestageA2uiPreRenderCheck(catalog: expression)` as
`RestageA2uiPreRenderCheck(catalogs: [expression])`. It does not regenerate
catalogs or migrate a handwritten GenUI host, transport, prompt, or cached
payload. Replace those host APIs manually with `MessageProcessor` and
`A2uiSurface`; give your producer the standard catalog JSON and its `instructions`.
Restage does not start or operate an agent service.

Code reading the removed public `.catalog` field must choose explicitly from
`.catalogs` (for example, `.catalogs.single` when exactly one is registered).
The Dart fix does not choose a catalog for a multi-catalog host.

`buildRestageCatalog()` supplies component schemas, instructions, and rich
catalog-level definitions. Manual `CatalogImplementation` composition must
merge **both** `buildRestageCatalogItems()` and
`buildRestageCatalogDefinitions()`, preserve the needed instructions, and assign
a new application-owned catalog ID to a changed schema/component set.

Component type names must satisfy upstream UAX31 identifiers and cannot be
`Surface`. Use `@RestageWidget(name: ...)` to choose a valid widget identity.
Native screens retain the exact `@Screen(id: ...)` / `@ScreenSource(id: ...)`
identity as their component type name: update invalid IDs and their consumers
explicitly. The generator never silently aliases them.

Component instance `id` values must also be UAX31 identifiers. Migrate producers
and cached payloads together, updating each renamed instance ID and all child
and template references to it. For example, rename `callout-body` to
`callout_body` in both the component declaration and every reference. The
`Surface` reservation applies to component type names, not instance IDs.
Instance IDs and their references require explicit migration; they are not
automatically aliased.

Controlled values keep explicit user paths unchanged. Literal/call local
write-back storage is `/restage_<URI-encoded component ID>/<generated property name>`,
with a `context_<URI-encoded data path>` segment before the property name inside
a template, so each row keeps its own value; this is internal fallback storage, not the component's identity. Data-model
bindings, local overrides, rebinding and disposal are qualified against the
published renderer in interaction tests.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
