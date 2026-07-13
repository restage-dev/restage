# Changelog

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
