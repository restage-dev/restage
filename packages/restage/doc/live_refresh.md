# Live refresh

Every surface picks up new content the next time it is shown. That is the default, and it covers most changes: publish a new version, and the next onboarding run, paywall view, or survey render uses it.

Live refresh is the opt-in accelerator on top of that. When you turn it on, a surface that is already on screen updates itself in place, with no navigation and no app restart. It works the same for every surface. An onboarding screen re-themes while the user is looking at it, a paywall swaps its offer, an in-app message updates its copy. Same lane, same rules.

Two things are worth stating plainly:

- Content updates on the next view by default. Live refresh live-updates on-screen surfaces when you opt in. It does not claim instant delivery everywhere.
- It never weakens delivery. A live refresh re-resolves through the same fail-safe path your first render uses, skips unchanged content, and applies a change only when the surface is safe to swap: not mid-interaction, not mid-purchase, not enrolled in an experiment. If the realtime lane is unavailable, the surface keeps rendering what it already has. Live refresh accelerates delivery. It is never a bypass.

There are no timers. The realtime lane runs only while a surface is mounted and foregrounded. A resume check covers anything published while the app was backgrounded.

## Turning it on

Opt surfaces in with a set of triggers, resolved most-specific-wins (widget override, then per-surface override, then the app-global set):

```dart
Restage.configure(
  apiKey: 'rs_pk_...',
  baseUrl: 'https://your-backend.example',
  // Wire the Restage-hosted realtime lane.
  liveRefreshEdgeUrl: Uri.parse('https://your-edge.example'),
  // App-global default: every surface takes live edge pushes + the resume check.
  liveRefresh: const {
    SurfaceRefreshTrigger.updateChannel,
    SurfaceRefreshTrigger.appResume,
  },
  // Per-surface override by id (wins over the global set).
  liveRefreshOverrides: const {
    'welcome_flow': {SurfaceRefreshTrigger.appResume},
  },
);

// Per-widget override (wins over everything). An empty set opts this one out.
RestageSurfaceFlow<FirstRunResult>(
  flow: welcomeFlow,
  liveRefresh: const {SurfaceRefreshTrigger.updateChannel},
  unavailable: const FlowUnavailablePolicy.hide(),
);
```

`liveRefreshEdgeUrl` (with `baseUrl` and no custom channel) installs the Restage-hosted realtime lane, so mounted surfaces that opt into `updateChannel` refresh in place as you publish.

When you branch on a trigger, prefer an `if` or a membership test over an exhaustive `switch`. The `SurfaceRefreshTrigger` set is additive, so code that switches over every case would break when a new trigger is added.

## Bring your own channel

To drive live refresh from your own infrastructure (your push provider, your own socket), implement `SurfaceUpdateChannel` and pass it as `updateChannel`. A signal means "this surface may have changed." The SDK re-resolves through its normal delivery path, skips unchanged content, and applies a change through the same swap-safety gate. A channel signals opportunity. It can never force a swap.

```dart
class MyPushChannel implements SurfaceUpdateChannel {
  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) {
    // Emit a SurfaceUpdate(surface) whenever your backend says this surface's
    // content changed. The SDK subscribes while the surface is mounted and
    // foregrounded, and cancels on dispose or background.
    return myPushStream
        .where((message) => message.matches(surface))
        .map((_) => SurfaceUpdate(surface));
  }
}

Restage.configure(
  apiKey: 'rs_pk_...',
  baseUrl: 'https://your-backend.example',
  updateChannel: MyPushChannel(),
  liveRefresh: const {SurfaceRefreshTrigger.updateChannel},
);
```
