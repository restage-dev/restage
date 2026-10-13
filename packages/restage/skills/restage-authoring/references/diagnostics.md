# Build errors and fixes

`dart run build_runner build` stops with an error, a code in brackets, and the
source line. Nothing is published from a failed build. Fix the Dart source and rebuild.
Never edit generated files to make an error go away.

The messages below are real compiler output.

## missingPartDirective

```text
[missingPartDirective] lib/messages/recap.dart: Missing `part 'restage.generated/recap.restage.g.dart';` directive.
```

Add exactly that line below the imports. Every file with `@Screen`, `@Paywall` or
`@FlowGraph` needs it. This error stops the build before other checks run.

## invalidScreenSourceCount / duplicateId

```text
[invalidScreenSourceCount] lib/onboarding/screens.dart@24:13: Library package:app/onboarding/screens.dart declares more than one implicit Restage source ID. ... Add an explicit unique id to every declaration after the first.
[duplicateId] lib/onboarding/first_run.dart: Screen identity "screens" resolves to both ...#WelcomeStep and ...#GoalStep.
```

Several surfaces in one file all took the file name as their id. Move each into its own
file (preferred), or give each an explicit `id:`. `duplicateId` also fires when two
files use the same explicit id.

## unknownWidget

```text
[unknownWidget] lib/messages/promo.dart:16:41: Widget 'Plain' is not a known catalog widget. If it is a custom widget, annotate its class with @RestageWidget so Restage can recognise it.
```

Your own widget class is used in a surface. Add `@RestageWidget()` to it and export
it from the widget library file. See [custom-widgets.md](custom-widgets.md). The same
error names a helper declared in another library; move it into the surface's file.

## unknownProperty

```text
[unknownProperty] lib/surveys/mood_check.dart:31:11: Property 'selected' is not declared on 'ListTile'. Catalog properties: leading, title, subtitle, trailing, shape, onTap, analyticsId.
```

The catalog version of that widget doesn't have the argument. Use one of the listed
properties, express the same thing another way (an icon or a color that switches on
state), or put the widget in a `@RestageWidget` of your own.

## unrecognizedMethodCall

```text
[unrecognizedMethodCall] lib/messages/promo.dart:10:63: Unsupported expression: FunctionExpressionImpl `() => Navigator.of(context).pop()`. See the supported expression subset.
```

An inline callback that runs code. Surfaces can't run code. Fire a `SurfaceEvent`
instead and do the work in the mount's `onEvent`:

```dart
static const back = SurfaceEvent<void>('back');
// build():
TextButton(onPressed: surfaceEvent(back), child: const Text('Back'))
// app:
MySurface(onEvent: (event) => Navigator.of(context).pop())
```

The same code appears for `() => setState(() => count++)`. For selection state, use a
named method with one assignment and pass it by reference:

```dart
void pickGood() => setState(() => good = true);
// build():
ListTile(title: const Text('Good'), onTap: pickGood)
```

It also appears for expressions outside the supported set, such as record fields:

```text
[unrecognizedMethodCall] lib/paywalls/pro_upgrade.dart:27:36: Unsupported expression: PropertyAccessImpl `plan.$1`. See the supported expression subset.
```

Use a list of plain values, or host data with a plain data class.

## unsupportedInterpolation

```text
[unsupportedInterpolation] lib/messages/weekly_recap.dart:23:16: Only recognized String helpers or String State fields may appear inside string interpolation. Found: SimpleIdentifierImpl streakDays.
```

Only `String` values can be interpolated. Pass the number to a property that takes it
(for example a `@RestageWidget` with an `int` field), or declare the parameter as a
`String` and format it in the app.

## unrecognizedMethodCall on a host-data parameter

```text
[unrecognizedMethodCall] lib/messages/reminder.dart:11:48: Cannot read the parameter 'when': it is declared 'DateTime', and Restage does not support that type as host data. Host data parameters must be a scalar (bool, int, double, num, String), Object?, a List of non-nullable host-data values, or a Map<String, …> whose values are host data, optionally nullable, or a plain const data class. At 'when': framework value types are not supported.
```

Convert in the app and pass a supported type: a formatted `String`, or an `int` of
milliseconds.

## invalidEventConfiguration

```text
[invalidEventConfiguration] lib/surveys/opt_in.dart:11:72: The callback value reaches the event automatically. Pass `surfaceEvent(...)` directly to the callback, without a closure.
```

Write `onChanged: surfaceEvent(pick)`. The widget's value becomes the event's value.
A closure around `surfaceEvent(...)` builds with a warning, but the event never fires
when your own widget shows, so remove it.

## buildMethodTooComplex

```text
[buildMethodTooComplex] lib/messages/promo.dart#Promo.build: the local 'label' is declared in build() but never read; remove it or use it
```

```text
[buildMethodTooComplex] ... build() makes a recursive helper call ('_nest'); a helper cannot call itself.
```

A helper that the build can't inline is refused by name: its body must be one returned
expression, optionally after `final` or `const` locals it uses.

Every local in `build()` must reach the returned widget. Remove it, or use it. `late`,
several variables in one statement, and any statement other than a local or the
`return` also stop the build.

## nonFiniteNumericValue

```text
[nonFiniteNumericValue] lib/messages/promo.dart:10:63: A non-finite double (`double.infinity`) has no representable value in the RFW format and is silently dropped by the runtime decode. Use a finite number. ...
```

For full width, use `Column(crossAxisAlignment: CrossAxisAlignment.stretch, ...)` or
`Row(children: [Expanded(child: ...)])`.

## Warnings you can leave

- `customWidgetAppFactoryUsed`: a `@RestageWidget` renders from its compiled Dart in
  the app, because its `build()` uses something the build doesn't compile. Its
  properties still come from the surface. Changing its code needs an app release, as
  for any custom widget.
- "generated registration includes the whole built-in catalog by default": see *App
  size* in [setup-and-delivery.md](setup-and-delivery.md).

## When a fix isn't obvious

The error also prints a link to request support for a missing capability. Before that,
check whether the same design can use a catalog widget, host data, or a `@RestageWidget`.
