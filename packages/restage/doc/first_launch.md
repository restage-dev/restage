# First launch

On a fresh install, nothing is saved on the device yet. A mount waits up to
`firstLaunchWait` for delivered content, then paints its compiled original.
This page shows how long delivered content usually takes to arrive, and how to
choose the wait.

## How fast delivered content arrives

These times run from app start to when the delivered content reaches the device.
They come from one Android phone on Wi-Fi, and an Android emulator with its network
throttled to stand in for slower mobile networks.

| Network | Fresh install | Returning launch |
|---|---|---|
| Wi-Fi (phone) | About 0.6 s typical; 0.4–1.1 s across runs, and 1.2 s once | About 0.25 s typical; 0.2–0.5 s across runs, and 1.1 s once |
| Fast 3G (emulator; 1.6 Mbps, 150 ms round trip) | 1.1–1.4 s | Not measured |
| Slow 3G (emulator; 384 kbps, 300 ms) | 2.0–2.2 s | Not measured |
| EDGE / 2G (emulator; 240 kbps, 500 ms) | 3.1–3.7 s | Not measured |

The first launch after you publish a change takes a little longer: 0.7–0.9 s on
Wi-Fi. For about 10 s after a publish returns, a device can still receive the
previous version.

These come from one phone and one emulator, all Android, so treat them as a
rough guide rather than a promise. Your users' times depend on their network,
their distance from the service and the size of your surfaces.

## Choosing `firstLaunchWait`

The default is 3 s. The wait ends as soon as the request for delivered content
answers or fails and the device has read what it saved, so on a fast network it
costs nothing: the mount paints as soon as the content is there. A request that
stalls, as on a network with no internet access, keeps a fresh install waiting the
whole time before it paints the compiled original. Show a `loadingBuilder`
meanwhile.

The wait counts from when the surface mounts, which is a little after app start
(0.2 s on Wi-Fi, and 0.4 s or more on slower networks in these measurements). So a 3 s
wait covers content that arrives up to about 3.2–3.4 s after app start.

| Wait | Effect, from the measurements above |
|---|---|
| 1 s | Wi-Fi and fast 3G showed delivered content. Slow 3G and EDGE showed the compiled original on every first launch. |
| 3 s (default) | Slow 3G also showed delivered content, with about 1 s to spare. EDGE made it in 3 of 3 runs, with almost no margin. |
| 5 s | Covers EDGE with margin. A user on a poor network waits longer before anything appears. |

Recommendations:

- Keep 3 s for surfaces where showing your current content matters on the very
  first screen, such as onboarding.
- Lower the wait for a surface whose compiled original is a fine first
  impression. Use `firstLaunchWaits` to set it for one placement.
- Show a `loadingBuilder` for any wait longer than a moment, so users see
  progress rather than a blank space.
- Watch `SurfaceLoadCompleted` on `Restage.events`. If `source` is `original`
  and `firstLaunchWaitPassed` is `true`, delivery missed the wait. The share of
  launches where that happens tells you whether to adjust it.

```dart
Restage.configure(
  apiKey: 'rs_pk_...',
  baseUrl: 'https://api.example.com',
  // From `restage keys delivery`.
  deliveryKeys: const ['42:Hx3...'],
  // The default; shown here for clarity.
  firstLaunchWait: const Duration(seconds: 3),
  // A surface whose compiled original is a fine first impression.
  firstLaunchWaits: {'home_banner': const Duration(milliseconds: 800)},
);
```

A mount with saved content doesn't use this wait. It waits `freshWindow`
(150 ms by default) for a newer version, then shows the saved one.
