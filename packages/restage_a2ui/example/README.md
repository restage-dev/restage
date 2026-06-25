# restage_a2ui example

`restage_a2ui` is the app-side, fail-closed **pre-render capability check** for
[A2UI](https://github.com/google/genui) payloads. It verifies a payload against
the catalog your app actually registered — and, for stamped payloads, the
catalog version — *before* handing it to [`genui`](https://pub.dev/packages/genui),
so a payload your build can't render faithfully fails with a clean diagnostic
instead of throwing mid-render.

## Gate a payload before rendering

Build the check once (it is immutable — reuse it for every payload), then gate
each payload before render:

```dart
import 'package:genui/genui.dart';
import 'package:restage_a2ui/restage_a2ui.dart';

// The genui catalog your build emitted, and what it provides.
final catalog = Catalog(buildRestageCatalogItems());
final installed = A2uiInstalledCapability.fromStampJson(restageCapability);

// One instance, reused for every payload.
final check = RestageA2uiPreRenderCheck(catalog: catalog, installed: installed);

Widget? renderCached(Map<String, Object?> payload) {
  switch (check.check(payload)) {
    case A2uiRenderable():
      return renderWithGenui(payload); // your genui render call
    case A2uiRejected(:final diagnostic):
      // Do NOT render — fall back to a built-in surface and log why.
      debugPrint('A2UI rejected: $diagnostic');
      return null;
  }
}
```

The check fails **closed** at every path — a malformed envelope, an unknown
component, an unmet version, or an unverifiable stamped payload all yield an
`A2uiRejected`, never a throw at the render seam.

See the [package README](../README.md) for the capability sidecar, the version
satisfaction rules, and how the catalog and stamp are produced.
