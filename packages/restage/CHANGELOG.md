# Changelog

## Unreleased

Apple receipt-only access refreshes through its signed history anchor when proof
metadata is omitted; existing exact receipt proofs remain usable.

Commerce keeps confirmed access while provider reports are pending, retains
receipt-only access during catalog refresh, and exports typed promotional
signatures for store adapters. Ambiguous offering
purchases return `packageSelectionRequired`; select an exact package to retry.

**Unreleased store-adapter SPI:** the opaque
`CommerceStorePurchasable.offerSignature` argument is removed. Pass typed
`promotionalOffer` instead.

The first-launch request the Android and iOS plugins send before Dart starts
follows what the app last configured. After a `Restage.configure` with no
publishable key, such as `apiKey: ''`, the next launch sends none. After
`analyticsEnabled: false`, it carries no install id, registration or experiment
assignment; the metering token and delivery stay, so the user still counts as
active. With `measurementEnabled: false`, from the first launch, it registers
nothing and carries no assignment; the install id stays while analytics is on.
A choice takes effect from the next launch; a launch where the app passes no
`analyticsEnabled` follows the build's default. The registration is made only
for a request that carries it.

The SDK uses the platform's answer when the platform's request asks for what
its own startup request asks for: the same endpoint, build, placements and
identity, and no widget, icon or library the app doesn't install. Which
artifacts ride inline and the device facts don't have to match. Otherwise Dart
sends its own request and, in debug builds, says why.

`analyticsEnabled` on `Restage.configure` and
`Restage.configureWithInstalledCatalog` defaults to the generated setup's
`analytics` option, then true, so an app can ship with analytics off from its
first launch and turn it on after consent. The option reaches `configure`
through `registerWidgets: kRestageWidgetRegistration`, or through
`registerRestageWidgets()` called before it, with or without a key in
`build.yaml`; in debug builds, a `registerRestageWidgets()` call after
`configure` is reported. **Breaking:** `RestageBuildDelivery` implements the
new `RestageBuildAnalytics`, which carries `analyticsEnabled`, and generated
code calls the new `Restage.declareBuildAnalytics`; regenerate with
`dart run build_runner build`.

**Breaking:** an app built with `restage_codegen` sends its first placement
request from the Android and iOS plugins, before Dart starts, from a template
the build writes to `android/app/src/main/assets/restage_early.json` and
`ios/Runner/restage_early.json`. The template uses the `api_key` and
`base_url` you set under the `restage_codegen:user_factories` options in
`build.yaml`. Without them the app builds and runs offline, the build says so
in one line, and the first request is sent from Dart. The
`early_request: false` option and `RESTAGE_EARLY_REQUEST` are removed. iOS
reads the template from the app's Flutter assets when `pubspec.yaml` lists
`ios/Runner/restage_early.json` under `flutter: assets:`, so nothing has to be
added to the Xcode project; `restage init` adds the entry.

`Restage.configure` and `Restage.configureWithInstalledCatalog` take the same
key, service URL and channel from the app's generated setup,
`kRestageWidgetRegistration`, when you pass it as `registerWidgets:`, so your
Dart code doesn't repeat them. A value you pass wins. `apiKey: ''` turns hosted
delivery off, and from the next launch the built-in first-launch request is not
sent.
`configureWithInstalledCatalog` now takes `registerWidgets:` too.

The service URL is used without trailing slashes, so `https://api.restage.dev/`
and `https://api.restage.dev` configure the same service. A blank `baseUrl` is
no URL.

In debug builds, the app reports through `FlutterError.onError`, with the fix,
when it configures hosted delivery with no first-launch request in the app
bundle or with one built for another key or URL, and when it has a first-launch
request built in but its `Restage.configure` or
`Restage.configureWithInstalledCatalog` call got no key.

Add `Restage.privacy.request()` for current-install erasure, with durable retries
and local identity reset after confirmed completion. It uses the existing
governed transport opt-in. Debug builds warn when an identity, consent or privacy
call is blocked because its transport is not configured.

- Upgrading can change a published screen's compiled contract even when its
  Dart source is unchanged. Colors now pass as native `Color` values where
  earlier generated code passed numbers. Affected published screens need a
  higher `@Screen(version:)`: regenerate the app, release it with the new
  screen version, and push that version. Older installed apps keep using
  their existing screen version. Push refusals describe the changed inputs
  and identify compiler or SDK changes when both builds recorded provenance.

A generated surface can render parts of its widget tree from the app's own code. `RestageIslandScope` supplies those widgets to published content. Each keeps its element and state when a newer version replaces the shown one. `RestageIslandScope.keyed` gives a widget the same identity in the compiled fallback. `RestageIslandPlaceholder` stands in for a widget whose app code isn't available. A version that draws these widgets is laid out before it is shown. It counts as shown from its first paint. `RestageWidgetLibraryRegistration.islands` marks the libraries that hold them.

`SurfaceVocabulary.stepMounts` maps a flow step to a `RestageStepMount`. A `RestageStepMount` renders the step's published content with the values the app computes for it. It reads the step's inputs from the step widget the app builds. `RestageStepValues` carries those values to the content. A flow becomes unavailable when a step has a `RestageStepMount` and no bound screen builder.

- **Breaking:** Remove `paywallEvent`. A paywall makes things happen with plain callbacks, such as `onPressed: onClose`, which its generated mount takes and hands to the delivered design. For an event a Restage host acts on, declare `static const startTrial = SurfaceEvent<void>('start_trial');` and fire it with `context.surfaceEvent(startTrial)`; an `args:` map becomes the event's `SurfaceEvent<Map<String, Object?>>` value. The host still receives a `PaywallCustomEvent` named by the event's id. `dart run restage_codegen:migrate_events` rewrites each call and declares its event; it leaves deciding which events should be plain callbacks to you. `activeDispatcher`, `RestagePaywallEventDispatcher.scoped`, `RestagePaywallEventDispatcher.island`, `RestageRecording.event`, `RestageRecording.withEvents` and the `events:` parameter of `RestageRecording.island` are removed, and the paywall dispatcher no longer adds a render object.
- **Breaking:** Authored events fire from a widget's own context: `context.surfaceEvent(event, [value])` replaces the top-level `surfaceEvent`, `surfaceEventWithContext` and the deprecated `onboardingEvent`. The callback finds its surface when it runs, without depending on it, so copies of a surface each receive their own events. `activeSurfaceEventDispatcher` and `activeOnboardingEventDispatcher` are removed. `RestageOnboardingEventDispatcher` and `RestageSurfaceEventDispatcher` are removed too, and `dart fix --apply` renames them to `RestageEventDispatcher`. `dart fix` can't add the context; `dart run restage_codegen:migrate_events` does: `surfaceEvent(event)` becomes `context.surfaceEvent(event)` with the context of the widget that builds the button, and `surfaceEventWithContext(context, event)` becomes `context.surfaceEvent(event)`. It prints each call it can't rewrite with the fix. A callback whose widget is no longer mounted, or that isn't built inside a surface, refuses and names the fix.
- Add `PlacementMountBinding.eventOwner`, the generated mount whose recorded events a surface receives, and `RestageRecording(mount:)`, the context a flow step's generated mount fires its events from. Generated code sets both.
- Add `SurfaceFlowRef.surfaceWidget`, the name of the widget generated for a flow. Error messages use it to name the widget to switch to.
- Add `PaywallRef.surfaceWidget`, the name of the widget generated for a paywall. Error messages use it to name the widget to switch to.
- Add `SurfaceScreenRef.surfaceWidget`, the name of the widget generated for a screen. Messages use it to name that widget.
- Add `RestageIslandScope.hostOf`. Generated step code uses it to keep a separate copy of a step's widgets for each place the step is shown.
- **Breaking:** Rename the flow function `state` to `flowState`, so it no longer hides the `state` a `Cubit` or `Notifier` inherits in files that import Restage. `dart fix --apply` renames existing calls.
- Add `@RenderInApp`, which leaves a widget to the app's code instead of putting it in the design. Put it on a widget class, a `library` directive or a local variable in `build`.
- **Breaking:** `RestageFlowGraph`, `RestageOnboarding`, `RestageScreen` and generated screen and flow mounts take optional `fallbackBuilder` and `errorBuilder` in place of `unavailable:`, as `RestagePaywall` does. `FlowUnavailablePolicy`, `SurfaceScreenUnavailablePolicy`, `FlowUnavailableBuilder` and `SurfaceScreenUnavailableBuilder` are removed. `dart fix` can't rewrite these, so change them by hand: `unavailable: FlowUnavailablePolicy.fallback(builder: (context, error) => w)` becomes `fallbackBuilder: (context) => w`. To show the error itself on a host with no compiled original, pass an `errorBuilder` and no `fallbackBuilder`; it then receives every failure. A rebuilt flow host reads a new `actions` registry with the same contracts in place and compares `installedSignalNames` by value, so neither reloads the flow; a registry with changed contracts reloads it, and so does a new `resolver` object, so hold the resolver rather than creating it in `build`. Drop `unavailable: ...hide()` on a host without a compiled original; on a generated mount or a flow with a compiled original, pass `fallbackBuilder: (_) => const SizedBox.shrink()` to show nothing instead of the original.
- **Breaking:** `RestagePlacement` and its factories take an optional `fallbackBuilder` in place of the required `fallback`, and an `errorBuilder` that receives a `PlacementUnavailableError`, whose `cause` is the mounted host's error. `dart fix --apply` renames `fallback:`.
- **Breaking:** `RestagePaywall.errorBuilder`, and the `errorBuilder` of every other host, shows for a failure after the user made progress, and for any failure when the host has neither a `fallbackBuilder` nor a compiled original. Otherwise a failure before progress shows the `fallbackBuilder` or the compiled original, so a paywall given both builders now shows its fallback for a failure before progress. A paywall given only an `errorBuilder` behaves as before. Showing nothing on a host with a compiled original takes `fallbackBuilder: (_) => const SizedBox.shrink()`, which counts as a shown fallback: the load completes, its bounds are reported, and a late answer is kept for the next mount.
- `RuntimeErrorBoundary` takes `guardsRendering`. With `false` it guards only building, so a parent-data child stays the direct child of its parent.

A navigation paywall that fails after the user left its first screen, or after
the user tapped its content, shows `errorBuilder` when one is set, and its
fallback otherwise (nothing if it has none, as before). Going back to the first
screen does not change this. A failure on the first screen before that shows the
original, even after the screen painted: the paywall fires
`PaywallDismissed` for the delivered view, then `PaywallLoadFailed`, then
`PaywallViewed` for the original.

Every surface host takes the same optional `fallbackBuilder` and `errorBuilder`
and walks the same fallbacks: fresh published content, then the last good copy
on the device, then the bundled copy, then `fallbackBuilder`. Without one, a
host shows its compiled original, or nothing on a host without one. The
`errorBuilder` shows instead of restarting the user when a load fails after they
made progress: entered a second screen, dragged, scrolled or typed in the
surface, or an event or host action reached the app. It also shows for any
failure on a host with no fallback and no original, rather than nothing. A
rebind starts a new load with no progress. A flow whose delivered content fails
restarts in its compiled original. Delivered content that fails to render
reports `SurfaceLoadFailed` with `render_error` before the original shows, on
every host; a paywall then fires `PaywallViewed` for the original. A paywall
that fails after the user interacted with its loading state shows its error
builder. A screen whose fetched version fails its checks now falls back to the
last good copy and then the bundled copy, as other hosts do. A hosted flow tries
its bundled copy before its compiled original. A live refresh never replaces a
surface the user made progress in during this load, on every host. A live
refresh of a screen that returns the content already shown keeps that screen,
with its state and events, and a screen keeps what it shows when the content
meant to replace it fails to show, unless what it shows is no longer valid. A
flow given a `fallbackBuilder` shows it once the first-launch wait passes with
nothing ready, as screens and paywalls do, instead of waiting for fresh content;
this is not reported as a failure. A `fallbackBuilder` or `errorBuilder` that
throws, or whose widget throws while building, shows nothing, fails the load
with `render_error`, and reports to `FlutterError.onError`, on every host. It
reports once per load unless a staged refresh moves it and builds it again. A
flow that restarted in its compiled original and then shows a newer version
restarts in the original again if that version fails too.

A paywall now handles a new placement the way a first mount does. It drops the
earlier placement's content at once, waits for the new placement's content or
original under the same rules, and reports that load's own outcome. Rebinding a
viewed paywall fires `PaywallDismissed` for the earlier view, to the earlier
widget's `onEvent`, before the new load starts.

`firstLaunchWait` now defaults to 3 s instead of 300 ms. On a fresh install, a
mount waits up to 3 s for delivered content before it shows its compiled
widget, so users on slower mobile networks see your current content on the
first launch. Content still paints as soon as it arrives. Set
`Restage.configure(firstLaunchWait: ...)` to keep a shorter wait.
`doc/first_launch.md` gives typical delivery times and how to choose the wait.

Every mount now reports its load, for placements, paywalls, generated
surfaces, screens and flows, on `Restage.events`, and to the `onEvent` of
paywalls and placements. A `RestageFlowController` you create reports only to
its own `onEvent`. `SurfaceLoadStarted` fires when a load starts. A paywall or
placement starts a new load when its placement changes; a screen or flow starts
one for a different surface or a new resolver object, and a flow also for a
different placement or a new `actions` or installed-signals object. Then at
most one terminal event fires, after the frame in which the mount first paints,
and none if the mount is disposed first. `SurfaceLoadCompleted.source` is `delivered`, `saved`
or `original`: a mount that paints its compiled widget or fallback completes
with `original`, including when nothing is published. `SurfaceLoadFailed` fires
when the mount paints its error state or nothing: it had no content to show, or
its content failed to render. It comes with a `reason` of `unavailable`,
`invalid`, `renderError` or `unknown`. The paywall load events are unchanged. These are new
`RestageEvent` subtypes, so an exhaustive `switch` over `RestageEvent` with no
`case _:` no longer compiles.

The SDK keeps the surfaces an install has shown since the service last
answered, with the UTC month of each, and sends them in the next placement
request. A surface counts when content the service delivered paints, under the
surface that content belongs to; the compiled-in widget reports nothing. The
list belongs to the API key that delivered the surfaces, so an install that
switches keys never reports one key's mounts under another. It survives the
app being killed, holds at most 64 surfaces and is cleared
only once the service answers the request that carried it. The startup request
an app built with `restage_codegen` ships carries it too. Until such an app is
rebuilt, its shipped request lacks the report and a launch with one pending
sends one extra request. A placement the startup request did not answer, one that
mounts later and is served by its own request, counts when it is served.

**Breaking:** delivered content renders only when it is signed by a key passed
to `Restage.configure(deliveryKeys: ...)`. `restage keys delivery` prints the
keys. Content that is unsigned, signed by another key, or altered after signing
falls back to the saved copy, then to the compiled widget. Content the server
authorized before the newest version this device has shown falls back the same
way. A rollback, a rule change or a new experiment authorizes its versions
again, and they render.

**Breaking:** `renderDeadline` on `Restage.configure` and
`Restage.configureWithInstalledCatalog` is now `firstLaunchWait` (its new
default is described above). A surface with a saved
version waits `freshWindow` (150 ms by default) for a newer one, then shows the
saved version. `dart fix --apply` renames the parameter.

Generated code passes the app's surfaces to the SDK at startup through
`Restage.declareSurfaces`. Apps don't call it directly.

Delivery receipts are saved on the device until the service accepts them. A view counts once, even when the app is killed while sending and resends after relaunch.

An SDK key that no environment recognizes is reported once per run, in release builds too, after it has been refused for about a minute. Receipts wait and retry meanwhile, so a key that was only just created is never reported.

Placement requests send the build contract once, then name the build by its
hash. A service that does not hold the contract answers 409 and gets it in full
on one resend; a service that refuses the hash form with 400 gets the full
contract from then on.

A placement keeps the decision it saved and shows it again on later launches,
within the render deadline, while the device facts that decision depended on
still hold. The service names those facts, such as install age or country, in
each decision. A decision that did not depend on install age survives the day
changing, and a decision the startup prefetch saved serves the first mount.
This needs a service that names the facts; a response without them is refused.

`surfaceEvent` fires a standalone paywall's custom event, with a value under
`args['value']`. Flows evaluate `always` and `matches` host-action result
predicates.

`FlowOutboundPolicy.customEvents` hands named screen events to the app with the
event arguments each carries. A custom event neither moves nor completes the
flow.

Placement mounts find a surface's root widget by one rule: `main`, as the editor
writes it, then `Paywall`, then `OnboardingScreen`, each declared once, else the
library's only declaration. A placement mount used to miss an editor-authored
`main`.

A surface that fails to render still falls back as before, and the error now also
reaches your app's `FlutterError.onError` handler, once, as it would without
Restage. In widget tests, call `tester.takeException()` for an expected failure. A
failing widget test with a surface mounted now fails at once; it used to wait for
the test timeout. In debug builds the fallback prints one `[restage]` line naming
the surface.

Generated mounts install the app's own `@RestageWidget` widgets from the library a
surface draws on, so apps with generated mounts need no startup registration call.
`registerRestageWidgets()` is still needed when an app mounts surfaces only by id.

When a mount shows the widget you wrote, because nothing is published or delivery
failed, its events reach `onEvent` as the same typed classes as on the hosted path.
`context.surfaceEvent` returns a callback that works as both a tap and a value
callback: pass it directly, as in `onChanged: context.surfaceEvent(pick)`, and the
widget's value becomes the event's value. An event that already carries a map
gets the widget's value added under `value`, on the delivered design and in your
own widget alike. A closure around it never fires in your own widget.

Hosted requests no longer wait without limit. Optional inputs such as the metering
key share a short deadline, measurement setup has its own, and every request stops
after a period with no response or no data. A surface then falls back as before.

New libraries: `package:restage/catalog.dart` for generated catalog code, and
`package:restage/render_support.dart` for the frame geometry and icon table that
preview hosts share with the SDK. Apps don't import either directly. The render
host that `restage build push` bundles is a separate package,
`restage_render_host`.

The package ships an agent skill, `restage-authoring`, for coding agents such as
Claude Code, Cursor, and Codex. It covers annotations, events, host data,
generated mounts, flows, custom widgets, what an update can change without an app
release, and fixes for build errors, with examples that compile against this
version. Install or update it with `dart run skills@ get --package restage`.

**Breaking:** `Restage.configure` no longer installs every built-in icon; it
still includes the complete built-in widget catalog. Generated registration
installs the icons the app and its compiled surfaces use, and a surface served
by Restage carries a font for any other literal icon it draws. An icon whose code
point comes from data, an icon with a key, a raw `.rfw` blob and a surface from a
custom resolver need installed entries. Call
`InstalledIconTable.add(builtInIconTable())` at startup to keep every built-in
icon.
`resolveInstalledIcon` is no longer exported; use
`InstalledIconTable.current.lookUp(fontFamily, codePoint)`, which returns null
for a missing icon instead of throwing.

The independent `includeMaterial` and `includeCupertino` options can
omit a complete family while preserving app-required entries. Both default to
true. Regenerate with `dart run build_runner build` after upgrading, then pass
`kRestageWidgetRegistration` to `registerWidgets` to apply the same choices to
generated registration. The standalone `registerRestageWidgets()` function
retains its inclusive widget defaults and the derived icon set.

To derive a smaller selection from the app's Dart and authored surfaces, set
`catalog: derived` on the `restage_codegen:user_factories` builder in `build.yaml`.
Call the generated registration before `Restage.configureWithInstalledCatalog`
when handling registration separately. Measure matched release builds of the app
to determine the saving; APK growth and estimated download growth are different
quantities.

Release builds no longer need `--no-tree-shake-icons`. Don't pass it: it puts the
whole icon font back into an app that would otherwise have derived its icons.
Generated builds use icon tables of compile-time constants, so Flutter's
icon tree-shaking works as usual.

A generated paywall mount installs the widgets and icons its surface draws, as
generated screen and flow mounts already did, so it renders in an app that never
calls `registerRestageWidgets()`.

`RestageWidgetLibraries.builtIn()` and `builtInIconTable()` return the complete
built-in catalogs by default. Both accept `includeMaterial` and
`includeCupertino` for an explicit family selection.

`RestageIconTable.fromFamilies` takes named `families:` and `mirrored:`
parameters. The two maps have the same type and were adjacent, so a positional
call could swap them silently.

Icons carry their font family and text-direction mirroring end to end, so a
Cupertino icon renders as itself and a mirrored icon flips in a right-to-left
layout.

Generated flow mounts retain the original graph and Flutter screen constructors.
Active delivery gates against that compiled contract without requiring runtime
bundles; unavailable initial delivery runs the complete original closure through
the existing controller. Running flows fail closed without restarting or replaying
actions.

Generated paywall mounts can retain the authored Flutter widget as an initial
delivery fallback. Authored paywall events keep the existing dispatcher and
stale-callback guards.

`Restage.configure` accepts an omitted, empty, or whitespace-only API key.
Without a credential, default delivery uses bundled assets and hosted clients,
analytics, metering, and governed Measurement remain inactive. Reconfiguration
also clears a previous hosted setup; explicit resolvers and local settings
still apply.

`Restage.configure` reports the configured delivery mode in debug builds, once
per mode or origin change. Hosted diagnostics print only the origin and never
the API key, URL credentials, path, or query.

The SDK no longer sends events to the Restage service. `Restage.events` is
unchanged and remains the way an app feeds its own analytics, and the events it
carries are unchanged. `analyticsEnabled` on `configure` still applies: it gates
the anonymous identifier used for surface assignment and for Measurement. The
debug-only `debugAnalyticsHttpClient` and `debugFlushAnalytics` statics are
removed with the egress they served.

Hosted surface requests now describe the device more fully so the service can
choose a published version of a surface for it. The request API level moves to
3, adding device region (for example, `se`), device class (`phone`), device
language (`sv`) and operating-system version (`17` on iOS and macOS, the API
level `34` on Android) alongside platform (`ios`) and app build ordinal (`412`).
Every request carries the platform; it carries each of the other five whenever
the device can supply it and omits any it cannot, so an app whose build number
is not a plain number still describes its platform, region, class, language and
operating-system version. A device whose language is not a two-letter code, and
a browser or desktop build with no operating-system ordinal to report, omit
those keys and send the rest. A web build now also omits the app build ordinal,
which it previously sent, and sends its platform, region, device class and
language; native platforms are unchanged. These facts are sent regardless of the analytics
and measurement flags. With analytics off, a hosted request carries no
analytics identifier and no assignment credential; the metering token is
separate and unaffected.

Reading the operating-system version uses `device_info_plus`. A project that
resolves its 12.x or 13.x line needs Kotlin 2.2; a project on 11.x needs
nothing new. It requests no runtime permission on any platform. Both it and the
existing `package_info_plus` are now reached only from platform-selected files
a web build does not compile, which is why a web build reports neither fact.

`Restage.configure` takes an `onSurfaceResolution` callback, and every mounted
surface now reports through it: paywalls, hosted flows and typed screens, on
each tier of delivery. The report is a `SurfaceResolutionReport` naming the
surface and a `SurfaceResolutionSource` of `fresh`, `holdLastGood` or
`bundled`, and both types are exported. A callback that throws can never fail a
resolution.

The published `data.device.countryCode` is now the device region as a
two-letter code. A locale whose region is not a two-letter code, such as `419`,
omits the key rather than publishing the raw subtag.

Measurement reports a shown surface's view 3 seconds after its first paint,
unless the surface has already closed or the app has gone to the background.
The rest of the measurement for that surface is sent when it closes, when the
app goes to the background, or when a purchase is reported from it. If the
server refuses a report, or the SDK holds one back after an error, that
surface's later reports are still sent, and a newer report for a surface
replaces an older one still waiting to be sent.

With the hosted update channel, a surface on screen fetches the content a
publish announces, and the new content comes with that answer. The update
signals one publish sends on a surface's several channels cause one fetch.
When the service can't confirm the answer includes that content, the surface
keeps what it shows until the next update.
On Android, iOS and desktop, the channel pings its connection every 30
seconds and replaces a connection that stops answering.

## 2.0.0

The published device data carries the ambient view padding alongside the safe
areas, so a surface can read the inset the operating system applies whether or
not something is covering it.

The published theme data carries `brightness`, the ambient theme's `light` /
`dark` token, so a delivered surface can pick its own palette per mode.

The published theme data carries the ambient `TextTheme` as
`textTheme.<style>.<field>`, so a delivered surface can follow the app's own
type scale, whether a screen reads one field or hands a whole style to a
`style:` slot. Each style carries every `TextStyle` field a slot holds as a
scalar or a list of scalars — the two colours, the font family and its
fallbacks, size, weight, posture, letter and word spacing, height, baseline,
leading distribution, overflow, and the decoration group — so a branded app's
display face, its italics and its underlines reach the surface;
`defaultTextStyle` carries the same set. A `decoration` combining more than one
line has no published token, so its key is omitted and the slot keeps its own
default. `populateThemeData` takes the text theme as a required argument.
The device data published on every mount gains `languageCode` and
`countryCode`, so a surface can match a locale subtag without parsing the full
locale tag. `countryCode` is omitted when the ambient locale carries no
country. It also gains `shortestSide`, `longestSide`, and `orientation`.

A mounted paywall re-publishes its device data when the screen it renders on
changes. It previously published once per load, so a rotation or a window
resize left `data.device.*` stale.

A breaking release. The breaking changes are called out below; everything
else is additive.

**Breaking. Hosted delivery no longer exposes experiment assignment metadata.**
`FlowAssignment`, `ResolvedFlow.assignment`, `ResolvedSurfaceScreen.assignment`,
and `RestageFlowController.renderedAssignment` are removed. The `experimentId`,
`variantId`, and `experimentEpoch` fields on `ResolvedVariant` and
`PaywallViewed` are also removed. There is no alias or replacement.
Responses carrying the retired decision or assignment tuple are refused and use
the normal bundled/default fallback ladder.

**Breaking. The app-global recording controls are removed from `Restage`:**

- `Restage.identify(String, {Map?})`
- `Restage.track(String, {Map?})`
- `Restage.beginSurfaceSession()`
- `Restage.endSurfaceSession()`
- `Restage.sdkVersion`

There is no replacement call and no compatibility alias. Explicit, opt-in
measurement operations live on `Restage.measurement`, and privacy requests on
`Restage.privacy`. Both are separate surfaces with their own contracts rather
than renamed versions of these. `Restage.sdkVersion` was only ever read to
stamp the recorded app context, which is unchanged; if you displayed it, hold
your own version constant. `beginSurfaceSession` and `endSurfaceSession`
managed an app-global session slot that surface attribution does not use.

**Not removed.** `Restage.reset()` and `Restage.configure(analyticsEnabled:)`
stay, because they are the only remaining controls over the legacy recording
runtime, which still ships until its replacement is served. `analyticsEnabled`
turns that recording off. Both retire together with the recording layer itself,
not before it.

`Restage.reset()`'s documentation was wrong and is corrected. It described
itself as a privacy "forget me" primitive, which it is not. It is a local call
that rotates the on-device pseudonymous actor and re-draws experiment assignment
going forward. It sends nothing, erases nothing already uploaded, does not clear
the metering token, and is not a server-side erasure request. Nothing about its
behavior changed, only the description, which could have led you to answer a
deletion request with it.

`Restage.events` and `Restage.fireEvent` retain their existing behavior. The
sealed `RestageEvent` family adds `PagerPageChanged` and
`SurveyQuestionResponded`, and `ResolvedVariant.surfaceVersion` is now required
and non-empty so every rendered paywall has a stable content version. Custom
variant resolvers must provide a new value when their resolved bytes change.
Event firing routes through the recording listener rather than calling the
bridge directly, preserving the existing public behavior.

**Breaking. Commerce is reset to a provider-neutral contract.** Legacy billing
gateways, products, native purchase helpers, and commerce events are removed.
`Restage.configure` no longer accepts `products` or `billingGateway`, and there
are no compatibility aliases.

Import `package:restage/commerce.dart` for the inert, provider-neutral typed
request and response surface. `Restage.commerce` is the only commerce addition
to the root `Restage` API. Using the facade with typed request and result types
requires both `package:restage/restage.dart` and
`package:restage/commerce.dart`. Commerce is inert in 2.0 and has no
configuration hook. Any implementation requires explicit host opt-in; a
package update alone never activates purchasing.

Offering, quote, localization, refund, consumable handling and fulfillment,
value, and purchaser-management capabilities are not included in 2.0. Unknown
availability capabilities report `CommerceFailureCode.unsupportedCapability`.
An offer on a known non-purchase capability reports
`CommerceFailureCode.invalidRequest`. Other known valid availability requests
report `CommerceFailureCode.notActivated`.

**New. `Restage.measurement` and `Restage.privacy`.** `Restage.measurement`
carries the explicit subject operations: issue a link challenge, link a subject,
reset a subject, withdraw consent. `Restage.privacy` carries privacy requests.
Both fail closed. Every operation returns a `temporarilyUnavailable` result
until the service serves measurement for your app, so calling them today is safe
and does nothing. They are not drop-in replacements for the removed controls.

**New. Measurement contracts.** `package:restage` now depends on
`restage_measurement_schema` and re-exports the inert contract types its own API
names (measurement targets and identifiers, canonical digests and documents,
publication bindings and their references, published identity and manifest
records, ingest envelopes, and the governed-subject request and result types),
so they are available from `package:restage/restage.dart` as well as directly
from `package:restage_measurement_schema/restage_measurement_schema.dart`. The
re-export is an explicit list, not the whole package: a contract type this
package's API never hands you does not become part of this package's surface.
Purpose and subject policies appear only as revision references. The policy
bodies, the audience and eligibility vocabulary, the metric and metric-binding
definitions, the layer and activation vocabulary, and the statistical inference
and result-reporting types are not part of that package: the service evaluates them, so they are not usable from
your app and are not published. `Restage.configure` gains
`governedMeasurementTransportEnabled` and `governedMeasurementTransport`;
`RestageGovernedMeasurementTransport` is exported as the transport seam. The
package also gains a `path_provider` dependency for the measurement journal's
application-support path.

**Breaking — renamed host widgets and one generated handle.** The three source
annotations and the widgets that mount them now line up, and every annotated
class generates exactly one handle.

| Before | Now |
|---|---|
| `RestageSurfaceScreen<E>` | `RestageScreen<E>` |
| `RestageSurfaceFlow<R>` | `RestageFlowGraph<R>` |
| `RestageSurfaceScreenResolver` | `RestageScreenResolver` |
| `RestageSurfaceEventDispatcher` | `RestageEventDispatcher` |
| `WelcomeScreenDescriptor.ref` | `welcomeScreenRef` |
| `FirstRunFlowDescriptor.ref` | `firstRunFlowRef` |

The old spellings remain as `@Deprecated` aliases and keep working through
2.x. They are removed at 3.0. The rule is one sentence: the build generates
`<className>Ref`, plus `<ClassName><Event>Event` for each event the class
declares.

The authored flow base class `RestageFlow` is **unchanged**. The host widget
for `@FlowGraph` is `RestageFlowGraph`, so the base keeps its name and
`extends RestageFlow` continues to compile untouched.

If you do mix them up, the analyzer rejects it — the host widget is a `final
class` — and the flow compiler adds a message naming the class you wanted.

A categorized `@Screen(surface:)` no longer generates an in-flow neutral
reference. Categorized screens are standalone and neutral `@Screen()` screens
are flow steps; the two were always exclusive, and the extra handle went
unused.

No wire-format change. The `.rfw`, the event-contract hash, and the published
identity are keyed on the annotation `id` and the event schema, never on Dart
symbol names — the delivery-artifact digests are identical across this
release.

**Breaking. The flow surfaces no longer draw back or skip controls.** The
chrome customization ladder is removed with them. `RestageFlowGraph`,
`RestageFlowView` and `RestageOnboarding` lose `enableSkip`, `chromeTheme`,
`persistentChrome`, `backBuilder`, `skipBuilder`, `chromeBuilder` and
`persistentChromeBuilder`, and `FlowChromeTheme`, `FlowChromeState`,
`FlowChromeAffordanceBuilder`, `FlowChromeBuilder` and
`FlowPersistentChromeBuilder` are gone from the public API. There are no
aliases.

A screen that wants a back control carries an `AppBar` or a
`CupertinoNavigationBar`. The surface hosts each screen as a route on a
`Navigator` of its own, so a screen with another behind it reports `canPop` and
both bars show their platform back control with `automaticallyImplyLeading` at
its default. The bar's back control, `Navigator.maybePop` and Android system
back each pop one flow screen. A screen with no app bar shows no control. A host
close control that should leave the flow from any screen calls
`Navigator.of(context).pop()` from outside the surface; `onComplete` runs with
the flow already finished.

Because the screens are routes, they move with the app's `pageTransitionsTheme`,
a `Hero` flies between them, and the iOS leading-edge swipe and Android
predictive back work as they do anywhere else. Exactly one level owns the
gesture at a time: the flow screen while in-flow back is available, the
enclosing route once it is exhausted. `RestageFlowView.transition`,
`RestageFlowGraph.transition` and `RestageOnboarding.transition` replace that
motion for one flow, receiving the entering screen's animation and the secondary
animation that displaces the screen beneath; `defaultFlowTransitionBuilder` is
removed, since the platform transition needs no builder. The surface needs bounded
constraints, like any `Navigator`, and says so if it is given none.

For a control you draw yourself, read `controller.canBack` and
`controller.canSkip` and call `controller.back()` and `controller.skip()` inside
a `ListenableBuilder`; that path is unchanged and needs a controller you own
under `RestageFlowView`. A control that must persist across screens belongs
outside the surface, since a control inside a screen travels with that screen's
route. `SystemBackPolicy` keeps its four variants and their meanings,
re-expressed over the route's `canPop`. Built-in skip is dropped with no
replacement affordance.

### Also in 2.0.0

**Breaking.** The closed event-name export is removed. Custom callback
constructor properties now use their exact Dart names as event identities.

**Breaking.** The commerce types that describe entitlement state are renamed
to say whose state it is:

| Old | New |
|---|---|
| `CommerceCustomerState` | `CommercePurchaserState` |
| `CommerceCustomerStateStatusCode` | `CommercePurchaserStateStatusCode` |
| `CommerceCapabilityCode.customerStateRead` | `CommerceCapabilityCode.purchaserStateRead` |

The capability's wire code changes from `customer_state.read` to
`purchaser_state.read`. There is no alias.

Other changes:

- Reading a generated artifact no longer asks the platform for a logical path
  the asset manifest proves is not packaged. Resolving a paywall is flow-first,
  so a paywall with a single screen used to request a flow document that was
  never generated — free where assets are read from disk, a failed request and
  a logged 404 on every load where they are read over the network. As a result
  the asset manifest is now read before the first artifact, where it used to be
  read only after one failed to load; if you pass your own `bundle:` to a
  resolver, that bundle's manifest must describe it, and a bundle with no
  manifest keeps its previous behavior exactly.
- Add `package:restage/a2ui.dart` and `package:restage/rfw.dart` convenience
  entrypoints for target-specific custom catalog configuration.
- Add the Widgetbook configuration entrypoint and typed per-widget/per-input
  emit-target routing annotations.
- Experiment attribution applies to every surface: onboarding, message and
  survey surfaces attribute an experiment the same way a paywall does. Experiment
  dimensions come only from an authoritative root binding; payload-claimed
  assignments are scrubbed and never trusted.
- Added optional host render context to screen, paywall, flow, and onboarding
  mounts through `context:`.
- Added `populateContextData` for publishing inert host values under
  `data.context.*`.
- Host context: maps and lists can nest 32 levels deep below the root. A context
  holds up to 10,000 values, counting the root, and each update reads at most
  100,000 map entries or list elements. Null map values are left out, and null
  list elements are removed so the list closes up. In debug builds, an invalid
  value, an unreadable collection, or a value over a limit throws; in release
  builds the SDK reports it and leaves that value or collection out.
- A scalar context change rebuilds only the nodes that read its path; list
  reconciliation is positional.
- A generated `<Screen>Surface` displays the compiled-in authored widget when
  delivery or rendering is unavailable, and delivery refuses with a
  contract-mismatch reason when the served contract does not match the
  installed build.

## 1.3.0

- Add opt-in live refresh for mounted surfaces: pass a `liveRefresh` trigger
  set (`SurfaceRefreshTrigger.appResume` / `.updateChannel`) to
  `Restage.configure`, with per-surface `liveRefreshOverrides`. A mounted
  surface re-resolves and swaps in place when newer published content is
  available; a surface with in-progress user state is never swapped
  mid-interaction.
- Add the `SurfaceUpdateChannel` SPI (`SurfaceRef` / `SurfaceUpdate`) for
  custom change-signal sources, and `liveRefreshEdgeUrl` for Restage-hosted
  realtime update signals.
- Add `Restage.reloadSurfaces()` for an explicit host-initiated refresh pass.
- Add general-delivery flow authoring:
  `@FlowSource(delivery: FlowDeliveryMode.general)` produces flows with
  untyped `Map` results validated at build time.
- Analytics impressions now report the resolved surface version.

## 1.2.0

- Add a neutral default surface floor.
- Additive runtime support for upcoming surface work; no breaking changes.

## 1.1.1

- Republish without stray build artifacts that were accidentally included in
  the 1.1.0 archive. No code change from 1.1.0.

## 1.1.0

- Add flow branching: decision states and predicate evaluation
  (`flow_predicates`) plus host-supplied initial flow state (`flow_seed`),
  enabling answer-driven onboarding and survey flows.

## 1.0.1

- Declare supported platforms (Android, iOS) explicitly.
- Update the `in_app_purchase` dependencies to their latest stable versions.

## 1.0.0

- Initial scaffold.
