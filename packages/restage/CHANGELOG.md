# Changelog

## 2.0.0

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
- Host context supports 32 collection levels below the root, 10,000 retained
  normalized nodes including the root, and 100,000 inspected map entries or
  list elements per normalization. Null map values are omitted; null list
  elements are dropped and lists compact. Invalid input throws in debug or
  reports and omits the offending value or collection in release.
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
