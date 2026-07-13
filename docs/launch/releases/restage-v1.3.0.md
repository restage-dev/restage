---
title: Live surface refresh
headline_tag: restage-v1.3.0
packages:
  - restage
  - restage_codegen
  - rfw_catalog_schema
  - rfw_catalog_compiler
  - restage_a2ui
---
## A mounted surface can now refresh itself

Until now, a surface picked up newly published content the next time it was
resolved, which in practice meant the next app launch. You can now opt a surface
into refreshing while it is on screen:

```dart
Restage.configure(
  apiKey: '...',
  baseUrl: 'https://api.example.com',
  liveRefresh: {SurfaceRefreshTrigger.appResume},
);
```

Two triggers ship. `appResume` rechecks when the app returns to the foreground.
`updateChannel` reacts to a change signal: implement `SurfaceUpdateChannel` to
supply your own, or pass `liveRefreshEdgeUrl` to use the hosted realtime lane.
`liveRefreshOverrides` sets the trigger set for one surface, and
`Restage.reloadSurfaces()` runs a pass on demand.

Refresh is off unless you ask for it, and a surface is never swapped out from
under someone: if the person has interaction state in flight, the swap is held
until it is safe.

## Build A2UI catalogs from your own widgets

`restage_codegen` compiles your `@RestageWidget` code into a standalone A2UI
catalog, so a model can generate against the widgets your app actually has. The
catalog now carries producer-facing metadata as well: widget and property
descriptions, plus a new optional `usage` field on `@RestageWidget` for steering
when a widget should be reached for.

```dart
@RestageWidget(usage: 'Use for a single high-emphasis call to action.')
class PrimaryButton extends StatelessWidget { /* ... */ }
```

## Also in this release

- **General-delivery flows** — `@FlowSource(delivery: FlowDeliveryMode.general)`
  generates a flow whose results are untyped maps, checked by build-time
  validators.
- **Message and survey codegen** — flow and screen builders are now
  surface-parameterized, so those surfaces reuse the onboarding builders.
- **Lists of structured values** carry their item shape through the catalog
  toolchain rather than degrading to an unknown list.

Additive throughout; no breaking changes.

**Versions:** `restage` 1.3.0 · `restage_codegen` 1.2.0 ·
`rfw_catalog_schema` / `rfw_catalog_compiler` 1.1.0 · `restage_a2ui` 0.1.5
