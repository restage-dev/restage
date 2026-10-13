<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/restage-dev/restage/main/brand/restage-wordmark-bold-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/restage-dev/restage/main/brand/restage-wordmark-bold-light.svg">
    <img alt="restage" src="https://raw.githubusercontent.com/restage-dev/restage/main/brand/restage-wordmark-banner-dark.png" width="300">
  </picture>
</p>

<p align="center">
  <a href="https://pub.dev/packages/restage"><img alt="pub package" src="https://img.shields.io/pub/v/restage.svg"></a>
  &nbsp;
  <a href="https://github.com/restage-dev/restage/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg"></a>
  &nbsp;
  <a href="LICENSE"><img alt="License: BSD-3-Clause" src="https://img.shields.io/badge/license-BSD--3--Clause-blue.svg"></a>
</p>

Restage is server-driven UI for Flutter. Add one annotation to a widget you
already wrote, and it becomes a surface you can update over the air:
onboarding, messages, surveys, paywalls, or any screen. It renders as real
Flutter widgets in your app, using your theme.

This package is the runtime SDK. It renders what the build produced through
[Remote Flutter Widgets](https://pub.dev/packages/rfw).

What ships is data the app renders. Your widgets carry the logic, as real Dart
compiled into your app. An update over the air composes and configures them.
New behavior still ships as an app release.

## Why Restage

- **Your widgets, your theme.** The build compiles the code you wrote, and
  `Theme.of(context)` resolves when the surface renders.
- **Whole screens or small parts.** An onboarding flow, a paywall, a whole
  screen, or one card inside your own `Scaffold`.
- **Compatible updates.** Publish layouts, content and configuration that use
  the widgets your installed app already has.
- **It fails safe.** A surface is never served to a client too old to render
  it, and a failed fetch renders your bundled copy.

## Quick start

Here's a welcome screen, written as a plain Flutter widget with one annotation:

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@Screen(id: 'welcome', surface: Surface.onboarding)
class Welcome extends StatelessWidget {
  const Welcome({super.key});

  static const getStarted = SurfaceEvent<void>('get_started');

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Welcome', style: Theme.of(context).textTheme.headlineMedium),
          FilledButton(
            onPressed: surfaceEvent(getStarted),
            child: const Text('Get started'),
          ),
        ],
      );
}
```

Compile it with [`restage_codegen`](https://pub.dev/packages/restage_codegen):

```sh
dart run build_runner build
```

The build generates a typed mount, `WelcomeSurface`. Render it anywhere in your
app, and handle its events:

```dart
WelcomeSurface(
  onEvent: (event) => Navigator.of(context).pushNamed('/home'),
)
```

Generated mounts install the widgets and icons their surface draws, including
your own `@RestageWidget` widgets, so there is no startup call to make. If the
surface can't be delivered or rendered, the mount shows the widget you wrote.

Change the widget, rebuild, and the surface updates. Push it with
`restage surface push welcome`, make that revision live with
`restage surface publish welcome`, and installed apps pick it up over the air.
The [Quickstart](https://github.com/restage-dev/restage/blob/main/QUICKSTART.md)
walks through a full example, including the `build.yaml` for bundled assets.

## Surfaces

- **Flows**: a `@FlowGraph` sequence of screens, such as onboarding, a
  multi-step message, or a survey. Mount it with
  `RestageFlowGraph(flow: firstRunFlowRef, ...)`; the build generates the
  descriptor. See [doc/flows.md](doc/flows.md) for the full example, host
  actions, and data minimization, and
  [doc/flow_navigation_and_customization.md](doc/flow_navigation_and_customization.md)
  for back navigation and the system-back policy.
- **Paywalls**: a `@Paywall` surface for upgrade or subscription content. Mount
  it with `RestagePaywall(id: 'pro_upgrade', ...)`.
- **Screens**: any single surface you write with `@Screen`, such as a welcome
  page, a notice, or a settings card. Use the generated mount, or
  `RestageScreen(screen: welcomeRef, unavailable: ...)` to choose what shows
  when the surface can't render.

A mount by id, such as `RestagePaywall(id: ...)`, has no generated mount behind
it. An app that mounts surfaces only by id calls the generated
`registerRestageWidgets()` once at startup. That installs your `@RestageWidget`
widgets and every built-in widget and icon your Dart code uses. Later updates
can use them even if no current surface does.

```dart
void main() {
  registerRestageWidgets();
  runApp(const MyApp());
}
```

## Host data

Every surface host accepts an optional `context:` map. Its values are available
to authored widgets under `data.context.*`.

Context accepts strings, integers, finite doubles, booleans, lists, and maps
with string keys through 32 collection levels below the root. A context may
contain up to 10,000 retained normalized nodes including the root and may
inspect up to 100,000 map entries or list elements per normalization. Null map
values are omitted, and null list elements are dropped and compacted.
Normalization synchronously deep-copies accepted input. Invalid values,
unreadable collections, and exceeded limits throw in debug; release reports
diagnostics and omits the offending value or collection.

For example, a screen can render state already owned by the app:

```dart
RestageScreen(
  screen: accountSummaryScreenRef,
  unavailable: const SurfaceScreenUnavailablePolicy.hide(),
  context: <String, Object?>{
    'profile': <String, Object?>{
      'displayName': profile.displayName,
      'tasksRemaining': remainingTasks.length,
    },
  },
)
```

Equal normalized snapshots cause no renderer update. Setting `context:` to
null removes the namespace.

Changing one scalar rebuilds the node whose own arguments read that path and
the node's subtree; unchanged scalar siblings stay untouched. A list change
rebuilds the list host and its rows. Reconciliation is positional: on insert
and reorder, persistent row state stays with its position while authored row
ids move.

## Delivery

Apps that bundle their surfaces use the asset resolvers, with no server. To
fetch surfaces from Restage Cloud or your own server, call
`Restage.configure(apiKey: 'rs_pk_...', baseUrl: ...)` at startup. That
installs `RestageVariantResolver`, which fetches the active published version
and falls back to the bundled copy when the fetch fails. Flows fetch through
`ServerFlowResolver` (pass it as `flowResolver:`).

A surface is never served to a client too old to render it. If a fetch fails,
the SDK renders your bundled copy. Flows require a `FlowUnavailablePolicy`, so
a flow that can't run falls back or hides instead of running partway.

See [doc/live_refresh.md](doc/live_refresh.md) to update surfaces that are
already on screen.

## App size

A delivered surface renders with widgets compiled into your app, so what the
app can render decides what it costs. By default `Restage.configure()` installs
the whole built-in catalog and both icon tables, so a surface you deliver later
can use anything the catalog can express.

There are two ways to make it smaller.

**Drop a whole catalog.** Pass constant `includeMaterial` and
`includeCupertino` values. Both default to `true`; this example drops
Cupertino:

```dart
Restage.configure(
  includeMaterial: true,
  includeCupertino: false,
  registerWidgets: kRestageWidgetRegistration,
  // Your existing delivery settings.
);
```

`kRestageWidgetRegistration` comes from the generated `user_factories.g.dart`
and adds your app's own widgets. Without code generation, omit it. Widgets and
icons your generated surfaces need are kept either way.

**Keep only what your code draws.** Set the `catalog` option in `build.yaml`:

```yaml
targets:
  $default:
    builders:
      restage_codegen:user_factories:
        options:
          catalog: derived
```

Then call the generated helper before the installed-catalog entrypoint:

```dart
registerRestageWidgets();
Restage.configureWithInstalledCatalog(/* your existing configuration */);
```

The build collects the catalog widgets your code draws and the ones your
surfaces use. To make a widget available to future updates before your app
draws it, draw it once in a `@Screen` you never mount. Release builds need no
extra flags; don't pass `--no-tree-shake-icons`. Unused Cupertino widgets alone
don't remove the bundled Cupertino font; that also needs the font's package
dependency removed.

Each build reports which catalog selection it uses. Compare matched release
builds to measure the difference. See
[App size](https://docs.page/restage-dev/restage/delivery/app-size) for the
measurement methods and the options in full.

## Measurement and data

Measurement is in beta. Restage measures how users interact with each published
version of a surface.
There are no tracking calls to add: activity is captured automatically for
each version you ship.

- **It needs a hosted configuration.** Without an `apiKey` and `baseUrl`, the
  SDK renders bundled surfaces and calls no server.
- **No endpoint is built in.** Data goes to the `baseUrl` you configure,
  authenticated with your public key (`rs_pk_...`). Point it at Restage Cloud
  or at your own server.
- **The install id is pseudonymous.** Each install gets a random UUID. It isn't
  derived from any device or advertising identifier, and it resets on
  uninstall or `Restage.reset()`. Treat it as personal data under GDPR and
  similar laws, as we do. The SDK attaches no account id of your own.
- **Records are queued on the device** and retried if an upload fails.

**What's recorded:** the interactions each published version defines, with
their timing, the surface version, and the experiment variant where one
applies. The SDK doesn't read advertising identifiers (IDFA/GAID), location,
or contacts. Like any network call, requests expose ordinary metadata such as
the IP address to the server you point them at.

**Turning it off:** pass `measurementEnabled: false` to
`Restage.configure(...)`. The value must be a constant: the build reads it, so
generated surfaces carry nothing to measure, and the SDK starts no measurement
sessions. `analyticsEnabled: false` also turns measurement off and stops the
SDK from creating the install id, while keeping hosted delivery.

**`Restage.reset()`** gives the install a new pseudonymous id and a new
session. Experiment assignment is drawn again on the next surface
presentation, and nothing links the old id to the new one. It runs only on the
device: it doesn't delete or change anything already sent, and it doesn't
clear the metering token below.

### Device facts

Hosted surface requests describe the device so the service can choose which
version of a surface to serve, such as one for a country, for tablets, or for
a language. Each request sends the platform and, when the device can supply
them, the app build number, region, device type, language and OS version. Web
builds send no build number or OS version. These facts are sent even with
analytics or measurement off. They are stored only when a measurement session
is created.

### The metering token

Restage Cloud is billed by monthly active users, so the SDK counts them with a
metering token:

- **It exists only with a `baseUrl`**, and the SDK creates it the first time it
  fetches a surface.
- **It's a random UUID**, stored in `shared_preferences` and lost on uninstall.
  It contains nothing about the user or the device, and it isn't linked to the
  install id.
- **It's sent only with surface fetches**, and only to the server you
  configured. Your own server can ignore it.
- **`analyticsEnabled: false` doesn't remove it.** It stays as long as you
  fetch surfaces from a server.

For your privacy policy: a random per-install identifier, used only to count
active users for billing, reset when the app is uninstalled. The code is in
`lib/src/metering/` and `lib/src/measurement/`.

### Linking a signed-in user

By default, measurement knows no user. If you want measurement tied to a
signed-in account, link one explicitly:

```dart
final result = await Restage.measurement.linkSubject(request);
final reset = await Restage.measurement.resetSubject(resetRequest);
final withdrawal = await Restage.measurement.withdrawConsent(withdrawalRequest);
```

A link request carries proof from your own sign-in system, the user's consent
and region, and a challenge from the service, so a link can't happen by
accident. You get back a receipt or a failure. `resetSubject` unlinks;
`withdrawConsent` blocks future linking. These calls are refused until you pass
`governedMeasurementTransportEnabled: true` to `Restage.configure(...)`.

## Coding agents

This package ships an agent skill, `restage-authoring`, that teaches coding agents
such as Claude Code, Cursor, and Codex to write, build, and mount surfaces. Install
it from your app's directory:

```sh
dart run skills@ get --package restage
```

The [skills tool](https://pub.dev/packages/skills) asks which agent to install for.
Pass `--agent claude` (or `cursor`, `codex`, `copilot`, and others) and `--all` to skip
the prompts. Run the same command after upgrading `restage` to update the skill.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
