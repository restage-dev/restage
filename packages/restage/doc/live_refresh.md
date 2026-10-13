# Live refresh

Every surface picks up new content the next time it is shown. That is the default, and it covers most changes: publish a new version, and the next onboarding run, paywall view, or survey render uses it.

Live refresh is off until you turn it on. Then a surface that is already on screen updates in place, with no navigation and no app restart. It works the same for every surface: an onboarding screen changes its colors while the user looks at it, a paywall updates its copy, an in-app message changes its button.

- By default, content updates on the next view. Live refresh updates surfaces on screen only when you turn it on, and it isn't instant everywhere.
- A refresh fetches through the same checks as a first render, skips unchanged content, and applies a change only to a surface the user isn't interacting with and that isn't in an experiment. If the connection is unavailable, the surface keeps showing what it has.

There are no timers. The connection is open only while a surface is mounted and the app is in the foreground. A check on resume covers anything published while the app was in the background.

## Turning it on

Turn surfaces on with a set of triggers. The most specific set wins: the widget's set, then the per-surface set, then the app-wide set.

```dart
Restage.configure(
  apiKey: 'rs_pk_...',
  baseUrl: 'https://your-backend.example',
  // Connect to the update channel hosted by Restage Cloud.
  liveRefreshEdgeUrl: Uri.parse('https://your-edge.example'),
  // App-wide default: every surface takes update signals and the resume check.
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
RestageFlowGraph<FirstRunResult>(
  flow: welcomeFlow,
  liveRefresh: const {SurfaceRefreshTrigger.updateChannel},
  unavailable: const FlowUnavailablePolicy.hide(),
);
```

`liveRefreshEdgeUrl`, with `baseUrl` and no custom channel, connects to the update channel hosted by Restage Cloud, so mounted surfaces that use `updateChannel` refresh in place when you publish.

When you branch on a trigger, use an `if` or `contains` instead of a `switch` that lists every value. New triggers may be added, and such a `switch` would break.

## Bring your own channel

To drive live refresh from your own push service or socket, implement `SurfaceUpdateChannel` and pass it as `updateChannel`. A signal means "this surface may have changed." The SDK fetches through its normal delivery path, skips unchanged content, and applies a change under the same rules as above. A signal can't force a change onto a surface the user is using.

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
