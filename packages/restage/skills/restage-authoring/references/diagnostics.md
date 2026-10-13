# Build errors and fixes

`dart run build_runner build` stops with an error, a code in brackets, and the
source line. Nothing is published from a failed build. Fix the Dart source and rebuild.
Never edit generated files to make an error go away.

The messages below are real compiler output. Fix the first error first.

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
it from the widget library file. See [custom-widgets.md](custom-widgets.md). The
annotation lets Restage inline supported composition or register a native factory.
For an unsupported helper call, first check that it is an own method or same-library
function whose body and arguments can be inlined.

## missingCatalogDescription

Document a custom widget class and each public constructor input with Dartdoc.
The compiler uses these descriptions in the generated catalog. Explicit
`RestageWidget.description` and `RestageProperty.description` are alternatives.
Descriptions are required; a missing description stops catalog generation and can
cause later surface builds to report that the widget is unknown.

## unknownProperty

```text
[unknownProperty] lib/surveys/mood_check.dart:31:11: Property 'selected' is not declared on 'ListTile'. Catalog properties: leading, title, subtitle, trailing, shape, onTap, analyticsId.
```

The catalog version of that widget doesn't have the argument. Use one of the listed
properties or express the same design with supported composition. If the feature
requires native code, isolate it in a small `@RestageWidget` with configurable
properties and child slots; review the resulting factory notice below.

The same code names an unsupported text field setting:

```text
[unknownProperty] lib/screens/bad_decoration.dart:14:41: InputDecoration's suffixIcon is unsupported here. Supported: hintText, labelText and helperText as text, border as InputBorder.none, UnderlineInputBorder() or OutlineInputBorder(), and prefixIcon as Icon(<icon>).
[unknownProperty] lib/screens/bad_decoration.dart:17:27: keyboardType must be one of TextInputType's named keyboards: text, multiline, number, phone, emailAddress, url, name.
```

Use the listed decoration fields, and a named keyboard such as `TextInputType.number`
in place of `TextInputType.numberWithOptions(...)`.

## unrecognizedMethodCall

An expression or callback falls outside the compiler's supported subset. Keep API
calls, platform work and app navigation in the mount's event handler:

```dart
static const back = SurfaceEvent<void>('back');
// build():
TextButton(onPressed: surfaceEvent(back), child: const Text('Back'))
// app:
MySurface(onEvent: (event) => Navigator.of(context).pop())
```

Supported paywall Navigator calls can lower to flow transitions. They are constrained to
recognized routes and callbacks, without observing a pushed route's result; see
[flows.md](flows.md). Do not replace every navigation diagnostic with a custom widget.

The same code appears for an unsupported tap closure that changes state:

```text
[unrecognizedMethodCall] lib/screens/counter.dart:22:24: Unsupported expression: FunctionExpression `() => setState(() => count++)`. See the supported expression subset.
```

Use a named method with one assignment and pass it by reference:

```dart
void pickGood() => setState(() => good = true);
// build():
ListTile(title: const Text('Good'), onTap: pickGood)
```

It also appears for a value callback that does more than store the value:

```text
[unrecognizedMethodCall] lib/screens/counter.dart:25:32: Unsupported expression: FunctionExpression `(v) => setState(() => note = v.trim())`. See the supported expression subset.
```

Store the value as is, `(v) => setState(() => note = v)`, and trim it in the app when
the event arrives.

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

## stateShapeUnsupported

```text
[stateShapeUnsupported] lib/screens/flip_toggle.dart:20:41: 'on' is set by a value callback and by 'flip'. Only literal values can also be set.
[stateShapeUnsupported] lib/screens/no_initial.dart#NoInitial.note: State field 'note' must have a non-null constant scalar or enum initializer for root source state.
```

A field a value callback writes can also be set by a named method, but only to a
literal (`setState(() => on = false)`), never to a computed value such as `!on`.
State fields support `bool`, `int`, `double`, `num`, `String` and enums with non-null
constant initializers. A missing initializer, unsupported field type or lifecycle
method stops the build. Keep controllers and subscriptions in app code.

## completesOn names an event no tap fires

```text
[annotationEvaluationFailed] lib/src/measurement/restage.measurement.compiler.json: Could not construct Measurement route plan for paywall/stray_complete: Invalid argument(s): completesOn names the event 'buy', which no tap on this paywall fires. A tap names it with paywallEvent('buy') or surfaceEvent(<the declared event constant>).
```

Fire the event from the tap that completes the paywall with `paywallEvent('buy')`, or remove it from
`completesOn`.

## A widget the build can't match to an earlier one

After you remove or move widgets in a surface, the build may not know which earlier
widget a remaining one replaces. It stops and names the choices (keys shortened here):

```text
[annotationEvaluationFailed] lib/src/measurement/restage.measurement.compiler.json: This build can't tell which earlier widget the one at ...#WeeklyCheckin|...#Column.children[7]|widget:...#SizedBox replaces (candidates: ...#WeeklyCheckin|...#Column.children[10]|widget:...#SizedBox (code.auto.0000000000000006), ...#WeeklyCheckin|...#Column.children[8]|widget:...#SizedBox (code.auto.000000000000001e)). In .restage/measurement-state.json, add {"codeIdentityId": "code.auto.0000000000000006", "fromStructuralOccurrenceKey": "...#Column.children[10]|widget:...#SizedBox", "toStructuralOccurrenceKey": "...#Column.children[7]|widget:...#SizedBox"} or {"codeIdentityId": "code.auto.000000000000001e", "fromStructuralOccurrenceKey": "...#Column.children[8]|widget:...#SizedBox", "toStructuralOccurrenceKey": "...#Column.children[7]|widget:...#SizedBox"} to "acceptedRelocations" to keep that widget's history, or add {"structuralOccurrenceKey": "...#Column.children[7]|widget:...#SizedBox"} to "acceptedIntroductions" to count it as new. Then rebuild.
```

Copy one of the objects from your own build output, with the full keys, into the named
list. The state file may be edited by hand; the next build rewrites it in its canonical
form.

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
expression, optionally after `final` or `const` locals it uses. Pass every parameter
explicitly, including optional parameters, and avoid recursive helper calls.

Every local in `build()` must reach the returned widget. Remove it, or use it. `late`,
several variables in one statement, and any statement other than a local or the
`return` also stop the build.

## nonFiniteNumericValue

```text
[nonFiniteNumericValue] lib/messages/promo.dart:10:63: A non-finite double (`double.infinity`) has no representable value in the RFW format and is silently dropped by the runtime decode. Use a finite number. ...
```

For full width, use `Column(crossAxisAlignment: CrossAxisAlignment.stretch, ...)` or
`Row(children: [Expanded(child: ...)])`.

## customWidgetAppFactoryUsed

This notice identifies a component that renders from the app's compiled factory
and explains why it did not inline. Delivered surfaces can still set its arguments
and child slots. Changes to that native implementation or its defaults require an
app release.

Review this notice when maximizing OTA coverage. Move layout, copy and composition
out of a large native component, or rewrite an unsupported construct using the
supported subset. Retain a native factory for platform behavior, controllers or
custom painting that the app must own. An inlined `@RestageWidget` does not have the
same implementation boundary. See [surface-design.md](surface-design.md).

## Other build notices

- "generated registration includes the whole built-in catalog by default": see *App
  size* in [setup-and-delivery.md](setup-and-delivery.md).
- `interactionItemUnavailable` (shown with `--verbose`): taps in a loop share one
  count, or aren't measured, and the note says why:

  ```text
  [interactionItemUnavailable] lib/screens/tag_list.dart:18:35: Taps in this loop share one count: no item because its elements are not objects or maps, so they carry no position.
  ```

  To count taps per item, loop over a list of objects or maps, or over a `const` list.

## When a fix isn't obvious

Check whether the same design can use catalog composition, a supported helper or
host data. Use a small native component when the missing capability needs it. The
compiler also links to support for capability gaps.
