# Restage SDK examples

A small, curated library of paywall and engagement surfaces built with the
Restage Flutter SDK. BSD-3-Clause — it ships with the public SDK. The fastest way from
zero to a shipped surface is to copy one of these, preview it live, publish it,
and iterate.

Every surface here is authored in standard Flutter and renders as **real
Flutter widgets** — no webview, no DSL to learn. The build-time codegen lowers
each surface to a small render blob the SDK decodes at runtime; that same blob
is what ships over the air.

Run it:

```sh
flutter run
```

Pick a surface from the gallery. The app-bar brightness toggle flips the whole
app between light and dark — the example surfaces here are fixed-brand, so they
hold their palette; a theme-adaptive surface would repaint.

## What's in here

### Paywalls — `lib/paywalls/`

Each paywall is a `@PaywallSource`-annotated `StatefulWidget` written in
ordinary Flutter. All six are fixed-brand surfaces (deliberate literal-colour
palettes) and present a real plan *choice*: tap a plan and its selection
indicator updates (in that surface's own visual language) while the purchase
CTA re-targets to the selected plan. The selection lives in widget `State`
(`setState`); the codegen lowers those state reads to render-blob state
switches, so the interaction also travels inside the delivered blob with no
host code.

| Source (`id`) | Archetype | Plan selection |
|---|---|---|
| `pulse_premium` (Pulse) | Dark, segmented tiers | Tri-state tier strip (`int` state) + tap-to-select plan cards |
| `ascend_premium` (Ascend) | Free-trial timeline | Tap "Start free trial" → a modal sheet rises; "See All Plans" swaps the content |
| `fluent_pro` (Fluent Pro) | Gradient-hero free trial | Two plan cards (Personal / Family); "View all plans" pushes a second screen (see below) |
| `sentinel_protection` (Sentinel) | Light savings-badge | Tap-to-select rows with a moving radio |
| `narrate_membership` (Narrate) | Expandable plan cards | Tap a plan — it expands with its benefits + CTA while the other collapses |
| `lumen_premium` (Lumen) | Calm meditation selector | Tap-to-select rows with a moving radio; also the subscription climax of the meditation onboarding flow |

`fluent_pro` additionally demonstrates **screen navigation**: its "VIEW ALL
PLANS" control is a real `Navigator.push` to a second `@PaywallSource`
(`fluent_pro_choose_plan`), which the build-time codegen lowers to a 2-screen
flow (entry → choose-a-plan), hosted transparently by `RestagePaywall`.

Each paywall appears in the gallery twice: a local widget mount (the authoring
preview, with placeholder prices) and the delivered render blob
(`RestagePaywall(id:)` decoding the bundled `.rfw`, with live prices from the
example product config in `lib/stub_products.dart`). On the delivered tiles the
demo host wires `onEvent` to a small SnackBar so every tap has a visible result
— purchases, and the Restore / Terms / Privacy actions that fire host events; a
real app performs the actual action there instead.

The gallery also includes a minimal `hello` blob (rendered straight through
`RestagePaywall(id: "hello")`) to show the bare runtime decode + render path.

### Engagement surfaces — `lib/onboarding/`

The same pipeline drives multi-screen engagement surfaces, not just paywalls.
The gallery presents four:

- **Meditation onboarding → paywall** (`flows/lumen_onboarding.dart`) — a calm
  multi-screen flow: welcome → two personalization questions → an enable-
  reminders host-action gate → recap → the embedded Lumen paywall. Purchasing
  ends the flow.
- **Location permission primer** (`flows/crave_permission.dart`) — a delivery-
  app location soft-ask: "Use current location" runs a host-action gate; "Not
  now" is a host-handled custom event that carries on without the grant.
- **In-app message** (`flows/apex_drop.dart`) — the smallest flow the runtime
  supports: a single-screen retail "drop" announcement whose CTA acts and whose
  × dismisses.
- **Cancellation survey** (`flows/reel_cancel.dart`) — a streaming retention
  flow: two questions → a save-offer host-action gate ("Keep my discount"
  advances on a redemption; "No thanks" fires a host-handled cancel).

### Capabilities & reference — `lib/`

Standalone SDK-mechanic demos, curated into the gallery's "Capabilities" and
"Reference" sections (and also runnable directly with `flutter run -t`):

- **Modal sheet** (`lib/main_modal_sheet_demo.dart`) — the declarative drag-to-
  dismiss bottom sheet.
- **Draggable sheet** (`lib/main_draggable_sheet_demo.dart`) — the persistent,
  non-closeable detent sheet (peek ↔ mid ↔ full with snap physics).
- **Hosted delivery** (`lib/main_hosted_paywall_demo.dart`) — a paywall fetched
  through the hosted-delivery resolver (served here by an in-app fake server),
  with the fail-closed fallback — the over-the-air path, end to end.
- **Chrome customization ladder** (`lib/onboarding/chrome_ladder_demo.dart`) —
  a dev how-to: one flow shown at the five chrome-customization levels (Default
  / Theme / Slots / Layout / DIY).

A handful of additional `lib/main_*.dart` entrypoints are dev-only smokes for
specific capabilities (the sheet-lowering paths, the selection controls, the
server-driven onboarding path) and are runnable with `flutter run -t` but not
listed in the gallery.

### Custom widgets — `lib/widgets/`

Three `@RestageWidget`-annotated custom widgets — `AcmeBorder`, `AcmeStack`,
`PromoBadge` — show the custom-widget registration path. They are registered
with the SDK via `registerRestageCustomerWidgets()` (generated into
`lib/user_factories.g.dart`) and demonstrate how a developer's own widget joins
the catalog; they are standalone capability demos, not used by the paywalls
above.

## The author → build → preview loop

A paywall is a `StatefulWidget` annotated `@PaywallSource`, written in ordinary
Flutter. The build-time codegen lowers it:

```
lib/paywalls/<name>.dart  ──(dart run build_runner build)──▶  assets/paywalls/<name>.rfwtxt
                                                              assets/paywalls/<name>.rfw
```

The committed `.rfwtxt` is the human-readable codegen output; the `.rfw` is the
binary blob the runtime decodes. Both are committed. For a fast loop on an
already-authored paywall, recompile just `.rfwtxt → .rfw`:

```sh
dart run tool/build_paywall.dart            # one-shot compile of every .rfwtxt
dart run tool/build_paywall.dart --watch    # rebuild on save
```

Preview a compiled paywall live in the desktop host:

```sh
restage preview assets/paywalls/fluent_pro.rfw
```

And when it looks right, publish it and iterate over the air:

```sh
restage paywall publish fluent_pro
```

Flutter does not hot-reload bundled assets — after a `.rfw` rebuild, hot-restart
the running app (press `R` in `flutter run`).

### Onboarding & messages

Flows are authored the same way, under `lib/onboarding/`:

```
lib/onboarding/screens/<screen>.dart  ──▶  <screen>.rsscreen.g.dart + assets/onboarding/screens/<screen>.rfw
lib/onboarding/flows/<flow>.dart      ──▶  <flow>.rsflow.g.dart    + assets/onboarding/flows/<flow>.flow.json
```

A message is just the smallest flow — one screen, one terminal state — so it
lives here too (see `flows/apex_drop.dart`).

> **Build note:** the generated flow descriptor (`<flow>.rsflow.g.dart`) is not
> yet auto-formatted by the codegen, so after a `build_runner` regen, run
> `dart format` over it before committing. (The generated screen descriptors are
> already format-clean; this is a known gap on the flow descriptor only.)

## Authoring an interactive paywall

A `@PaywallSource` is a `StatefulWidget`, so selection state lives directly in
the widget's `State` as a plain field — a `bool` for a two-plan choice, an `int`
for a tier strip. Tapping a plan calls `setState` to update that field; the
selection indicator and which plan the purchase CTA buys are both driven by
reading the field in `build`. See `lib/paywalls/fluent_pro.dart` for the
two-plan (`bool personalSelected`) shape, or `lib/paywalls/pulse_premium.dart`
for the tri-state tier strip (`int selectedTier`).

The CTA targets the selected plan's product **slot**:

```dart
GestureDetector(
  onTap: paywallPurchase(
    slot: personalSelected ? 'monthly' : 'family',
  ),
  child: /* the styled button face */,
)
```

`paywallPurchase(slot:)` references a slot configured via
`Restage.configure(products:)` (see `lib/stub_products.dart`), so the same
source drives the local authoring preview (real `setState`) and the delivered
blob (the conditional lowers to a render-blob state switch). The displayed price
and the charged slot must match — that mapping is the one thing a copy-paste
must get right (the Family card shows the family product, so its CTA charges the
`family` slot).

For prices, read the slot's price with `paywallPriceFor(slot:)`; the runtime
fills it from the host app's resolved store prices.

## Authoring constraints

These keep a surface transpilable. They apply to paywalls and onboarding screens
alike:

- **Strings are single literals.** Adjacent-string concatenation (`'a' 'b'`) is
  not supported — write one literal.
- **Full-width without `double.infinity`.** `SizedBox(width: double.infinity)`
  does not survive lowering (a non-finite double has no render-blob literal), so
  the element ends up hugging its content once delivered. For a full-width child
  in a centered column, wrap it as `Row(children: [Expanded(child: ...)])`; for a
  column that is full-width throughout, set `crossAxisAlignment:
  CrossAxisAlignment.stretch`.
- **Keep the build tree flat.** Don't extract helper widgets or methods — author
  the surface inline so the transpiler can follow it.
- **Write theme reads inline.** If a surface reads the ambient theme, use the
  full `Theme.of(context).colorScheme.<role>` chain at the point of use;
  hoisting it into a local (`final scheme = Theme.of(context).colorScheme;`) is a
  form the transpiler can't follow.
