# Runtime configuration

Start with the hosted or offline setup in
[setup-and-delivery.md](setup-and-delivery.md). Configure once at app startup;
add the settings below when the app needs their behavior. Generated mounts still
provide registration, implicit placements and compiled-widget fallback.

## Delivery settings

| Setting | Default | When to change it |
| --- | --- | --- |
| `apiKey`, `baseUrl` | Unset; no hosted delivery | Supply the public SDK key and HTTPS service URL for hosted delivery. A blank key clears hosted configuration. |
| `surfaces` | Empty list | Pass generated `restageSurfaces` to prefetch known surfaces after the first frame. Prefetch does not enroll experiment participants. |
| `renderDeadline` | `Duration(milliseconds: 300)` | Adjust how long a mount waits for fresh content. Eligible local content must be ready by the deadline; the fetch can continue for later mounts. |
| `channel` | Unset | Label the app build for delivery rules, such as `beta` or `stable`. Empty values and values over 128 UTF-8 bytes are omitted. |
| `environment` | `RestageEnvironment.production` | Set a matching local hint for sandbox integrations. Hosted authorization uses the environment bound to the API key; this setting does not select a server environment. |

Leave `resolver`, `flowResolver` and `surfaceScreenResolver` unset for normal
hosted delivery. These are extension points for custom resolution; an explicit
override bypasses the corresponding default placement path. The SDK installs
the hosted flow resolver automatically.

Generated mounts supply a fallback for the deadline. A direct mount with no
usable fallback can keep waiting for the response.

## Catalog selection

| Choice | Use |
| --- | --- |
| `Restage.configure(...)` | Default setup. Installs the full built-in catalog when no catalog selection exists. |
| `includeMaterial`, `includeCupertino` | Both default to `true`. Set a family to `false` to omit its full catalog. Core widgets and explicitly installed or generated-required entries remain available. |
| `registerWidgets: kRestageWidgetRegistration` | Pass the generated registration object from `user_factories.g.dart` when startup registration must respect the family flags. Generated mounts already register their required widgets. |
| `Restage.configureWithInstalledCatalog(...)` | Use after generated `registerRestageWidgets()` with `catalog: derived`, or with a catalog the app installs itself. It skips built-in catalog bootstrap and has no family-selection or registration-callback arguments. |

The registration callback runs after shared configuration and before catalog
bootstrap. Calling `registerRestageWidgets()` with no arguments uses its normal
family defaults; it does not inherit flags from a later `configure` call.
Existing widget and icon selections are preserved independently when no callback
is supplied. See [App size](setup-and-delivery.md#app-size) for the derived setup
and its limit on which widgets later updates can use.

## Reserve widgets for later updates

With `catalog: derived`, you can include building blocks before any visible
surface uses them. The build scans authored libraries under the app's `lib/`,
including screens that nothing mounts. For example, put this in
`lib/ota_reserve.dart` and leave it off the app's navigation:

<!-- skill-check: file lib/ota_reserve.dart -->
```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/ota_reserve.restage.g.dart';

@Screen(id: 'ota_reserve')
class OtaReserve extends StatelessWidget {
  const OtaReserve({super.key});

  @override
  Widget build(BuildContext context) =>
      const ExpansionTile(title: Text('More options'));
}
```

Regenerate, then install the app-wide catalog at startup. For example, this can
replace the app's existing configuration call; preserve any other settings it
needs:

<!-- skill-check: file lib/reserved_catalog.dart -->
```dart
import 'package:restage/restage.dart';

import 'restage_surfaces.g.dart';
import 'user_factories.g.dart';

void configureReservedCatalog({String? apiKey, String? baseUrl}) {
  registerRestageWidgets();
  Restage.configureWithInstalledCatalog(
    apiKey: apiKey,
    baseUrl: baseUrl,
    surfaces: restageSurfaces,
  );
}
```

The generated registration references the reserved factories, keeping them
available to runtime delivery even though `OtaReserve` is never shown. A
generated mount installs its own built-in vocabulary and the complete custom
libraries it uses; it does not install the app-wide reserve set. The source scan
does not inspect Flutter composition inside dependency packages.

Custom widgets have a separate route: annotate them with `@RestageWidget`,
export them from their declared library, and regenerate as described in
[custom-widgets.md](custom-widgets.md). The startup helper registers every
admitted custom factory, including widgets no current surface uses. Those
factories do not need a reserve screen. The annotation alone does not register
them at runtime.

Ship the app with this registration before publishing content that needs the
reserved widgets. Later OTA updates can then use those installed capabilities
without another app release. `restage build push` updates dashboard previews;
it does not install native code on users' devices.

## Live refresh

Ambient refresh is off by default. Choose `SurfaceRefreshTrigger.appResume` to
recheck when the app returns to the foreground, or
`SurfaceRefreshTrigger.updateChannel` for change notifications.

| Setting | Default | Effect |
| --- | --- | --- |
| `liveRefresh` | Empty set | App-wide ambient triggers. |
| `liveRefreshOverrides` | Empty map | Per-surface trigger sets, keyed by surface slug. An empty set disables ambient refresh for that surface. |
| `liveRefreshEdgeUrl` | Unset | Creates the hosted update channel when hosted delivery is configured. Use the refresh endpoint supplied for the deployment. |
| `updateChannel` | Unset | Supplies an app-owned `SurfaceUpdateChannel`, for example from an existing push service. Takes precedence over `liveRefreshEdgeUrl`. |

A widget-level override wins over the per-surface override, which wins over the
global set. The selected set replaces the others; sets are never merged. The
`updateChannel` trigger needs a configured channel. Supplying a channel alone
does not turn on the trigger.

This startup helper enables resume checks, keeps one surface's ambient refresh
off, and logs resolution sources:

<!-- skill-check: file lib/configure_restage.dart -->
```dart
import 'package:flutter/foundation.dart';
import 'package:restage/restage.dart';

void configureRestage({
  required String apiKey,
  required String baseUrl,
  required List<RestageSurfaceRef> surfaces,
}) {
  Restage.configure(
    apiKey: apiKey,
    baseUrl: baseUrl,
    surfaces: surfaces,
    channel: 'stable',
    liveRefresh: {SurfaceRefreshTrigger.appResume},
    liveRefreshOverrides: {'checkout': <SurfaceRefreshTrigger>{}},
    onSurfaceResolution: (report) =>
        debugPrint('${report.surface}: ${report.source.name}'),
  );
}
```

Pass generated `restageSurfaces` as `surfaces` and replace `checkout` with the
surface slug to override. Fresh mounts and `Restage.reloadSurfaces()` do not
require ambient triggers. Reload optionally accepts `surfaceId:`. Compatibility
and swap-safety checks still apply: interaction, contributed state, a busy flow
or a locked assignment can prevent replacement. A standalone screen showing
its compiled fallback needs a remount to use a later accepted response.

## Measurement and delivery reporting

| Setting | Default | Effect when `false` |
| --- | --- | --- |
| `measurementEnabled` | `true` | Stops new Measurement sessions and assignment credentials. Use a compile-time boolean literal or constant in `Restage.configure`; all such calls in the package must agree. |
| `analyticsEnabled` | `true` | Disables anonymous analytics identity, assignment credentials and Measurement collection. Hosted delivery and metering remain available. |
| `deliveryReceiptsEnabled` | `true` | Stops delivery receipt uploads and placement reporting. Local capture remains available. |

Hosted collection needs a key and base URL. Views, steps, events and completions
are recorded automatically; do not add duplicate tracking calls. Delivery
receipts describe content source, routing and rendering without a device,
install or user identifier. Device facts used for delivery selection are still
sent when analytics or Measurement is disabled. None of these flags is a switch
for all SDK networking.

`onSurfaceResolution` is unset by default. Use it to inspect `fresh`,
`holdLastGood` or `bundled` resolution and available routing details. Callback
errors do not stop delivery. A resolution report alone does not prove that
content painted or that an experiment presentation was recorded.

## Authenticated identity and privacy operations

Ordinary anonymous Measurement does not need a governed transport.
Authenticated subject linking, consent withdrawal and privacy requests use
`Restage.measurement` and `Restage.privacy` with explicit authority evidence.
For those integrations, set `governedMeasurementTransportEnabled: true` to use
the hosted transport after configuring the host's identity-provider proof
source, or supply a `RestageGovernedMeasurementTransport`. The flag defaults to
`false`; the two transport options are mutually exclusive. With neither option,
these governed operations return unavailable results.

The compatibility parameters `identity` and `locale` currently have no useful
runtime effect in `configure`: the identity callback is not invoked, and the
locale is not applied to delivery or Flutter localization. Pass app-owned data
through generated mount inputs, as described in
[surfaces-and-events.md](surfaces-and-events.md), and configure localization in
the Flutter app.
