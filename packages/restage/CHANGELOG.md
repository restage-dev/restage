# Changelog

## 2.0.0

A breaking release. The breaking changes are called out below; everything
else is additive.

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

`Restage.events`, `Restage.fireEvent`, `RestageEvent` and every typed event are
unchanged. Internally, firing an event no longer calls the recording bridge
directly; the recording layer registers for events instead, so the event stream
and the recording path can be reasoned about separately. This is not a visible
change to the event API.

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
symbol names — the delivery-artifact digests are byte-identical across this
release.

### Also in 2.0.0

**Breaking.** `transactionId` is now nullable (`String?`) on `BillingGateway`'s
purchase result and on `PurchasePlatformAdapter`. Some store purchases have no
transaction identity (a Google Play promotional-code purchase has no order ID),
and the field is now absent in those cases rather than carrying an invented
value.

If you read `transactionId` off a purchase result, handle null. If you
*implement* `BillingGateway` and pass a non-null value, no change is required:
the parameter widened, so existing calls still type-check.

`RestageConversionEvent.transactionId` was already nullable and is unchanged.

**Breaking.** The closed event-name export is removed. Customer callback
constructor properties now use their exact Dart names as event identities.

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
  entrypoints for target-specific customer catalog configuration.
- Add the Widgetbook configuration entrypoint and typed per-widget/per-input
  emit-target routing annotations.
- Purchase results carry the store-issued transaction identifier where one
  exists: the StoreKit transaction ID on Apple, the Google Play order ID on
  Android. For an external-provider gateway it is the per-transaction id that
  provider surfaces.
- Native purchases carry a durable purchase intent, so a purchase keeps its
  association with the surface that initiated it even if the app dies between
  the store call and the receipt arriving.
- Experiment attribution is surface-general: onboarding, message and survey
  surfaces attribute an experiment the same way a paywall does. Experiment
  dimensions come only from an authoritative root binding; payload-claimed
  assignments are scrubbed and never trusted.
- Google Play prepaid base plans are not accepted through the bundled gateway.
  Direct gateway calls keep their existing product behavior.
- A surface with a `paywallPriceFor` price binding and no commerce context
  configured (no products, no `billingGateway`, no `priceQueries`) now
  renders the same `$X.XX` placeholder the plain-Dart authoring path already
  shows, instead of a blank surface. Whenever any commerce context exists,
  a missing price still fails closed exactly as before. **Caveat:**
  `PaywallLoadFailed` with `render_error` no longer fires for a price-bound
  surface in the no-commerce-context case, since the surface now renders
  successfully — a host that relied on that event to trigger fallback UI in
  a storeless demo will see the new placeholder behavior instead.

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
