# Design for OTA updates

Decide what the next surface update should be able to change before choosing
component boundaries. Restage can update compiled composition and data. It cannot
replace arbitrary Dart code already installed on a device.

## Composition and native behavior

Use ordinary catalog widgets for layout, text, styling and controls. Extract
repeated composition into helpers or annotated components rather than making a
whole screen one native view. The compiler follows supported helpers and attempts
to inline `@RestageWidget` composition, including referenced package sources.

The annotation does not force native rendering. A custom component has two paths:

| Generated result | What OTA can change |
| --- | --- |
| Its supported composition is inlined into RFW | The emitted layout, styling and content, within the installed contract and capabilities |
| It references the app's native widget factory | Its supported inputs and child-slot content; changing the native implementation requires an app release |

Unsupported or imperative custom-widget composition can use a registered native
factory. The `customWidgetAppFactoryUsed` diagnostic explains this path when
reported. Review it when you expected the inside of that component to change
OTA, and inspect the generated RFW even if there is no warning. A successful
build alone does not prove it is fully represented in RFW.

Do not remove `@RestageWidget` to try to force inlining. An unrecognized class can
fail as `unknownWidget`. Declare and export app components as described in
[custom-widgets.md](custom-widgets.md), then inspect what the compiler produced.

## Choose a smaller boundary

Consider a recap surface with a title, animated progress display, feature cards
and a continue button. If one native component owns the whole screen, an OTA
update can change only the inputs that component exposes. It cannot move its
private button or insert a new card into a private layout.

Keep the title, cards, spacing and button in surface composition. Give the native
progress display only the animation and painting it needs to own. Expose its
value, colors and labels as supported inputs. Expose `Widget` or `List<Widget>`
slots when content should be supplied by the surrounding surface.

The shipped [recap example](../examples/lib/messages/weekly_recap.dart) keeps its
layout and actions in the surface, an inlinable heading, and a reusable badge.
If the badge's internals also need OTA changes, use supported expressions and
confirm that they inline.

Apply this test to a component: **could the next design change be expressed by
changing the emitted composition, its inputs or its child slots?** If not, that
change needs native support in a new app build.

## Plan a stable host contract

- Pass display data through generated constructor parameters. Keep network calls,
  services, controllers and platform objects in the host app.
- Declare events for app-owned behavior and handle the generated event types at
  the mount. Put flow-owned sequencing in the flow and app work in host actions.
- Expose the values the surface actually needs. Adding a new host-data requirement,
  event shape, native property or action later may require a new app build.
- For flow topology that should change OTA, deliberately choose
  `FlowDeliveryMode.general`. Typed flows keep a fixed graph and typed result.
  General flows still run within the installed vocabulary and outbound policy;
  they cannot introduce arbitrary Dart behavior.

Do not add speculative callbacks or properties solely to avoid every possible
future release. Choose a useful contract for the intended changes and verify
compatibility before delivery.

## Preserve the available widget vocabulary

The default built-in catalog gives later updates more widgets to compose.
`catalog: derived` reduces the installed catalog to what the build uses, so it
also limits future updates. Choose that option only when the app-size tradeoff is
intentional. New native components and capability changes still need an app build.

## Verify what is actually updateable

1. Generate from the authored source and read any
   `customWidgetAppFactoryUsed` diagnostics. Identify which parts intentionally
   remain native.
2. Inspect the generated readable RFW inside the `.rsbundle` under
   `.restage/build/bundles/`. A bundle is a ZIP container: `unzip -l <bundle>`
   lists its entries; `unzip -p <bundle> '*.rfwtxt'` prints the readable output.
   Read it to understand composition; change Dart and regenerate to alter it.
3. Test the generated mount without hosted content or surface assets. Confirm the
   original widget renders, inputs reach it and events reach the host.
4. Separately test delivered RFW, using a controlled resolver or an explicit
   bundled-RFW fixture. Assert that it rendered instead of silently passing by
   falling back to the original widget. Exercise the same interactions on both.
5. Verify that an installed build admits the updated contract and capabilities
   before serving it. A new app build is required when the update needs native
   behavior or contract support the old build lacks.

Bundling is a way to test or ship RFW offline. It is not required for ordinary
mounts, for inspection of build output, or for Widgetbook/A2UI generation.
