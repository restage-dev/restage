import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/card.dart' as app;
import '../widgets/factory_tally_chip.dart';
import '../widgets/own_key_chip.dart';
import '../widgets/scaled_chip.dart';
import '../widgets/tally_chip.dart';

part 'restage.generated/app_widgets.restage.g.dart';

/// The app calls the surfaces below make, in order.
final List<String> appWidgetCalls = [];

/// A label in a padded pill.
class AppPill extends StatelessWidget {
  /// Creates a pill.
  const AppPill({super.key, required this.label});

  /// The label.
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label),
      );
}

/// A pill under a heading.
class AppCard extends StatelessWidget {
  /// Creates a card.
  const AppCard({super.key, required this.heading, required this.label});

  /// The heading.
  final String heading;

  /// The pill's label.
  final String label;

  @override
  Widget build(BuildContext context) =>
      Column(children: [Text(heading), AppPill(label: label)]);
}

/// A tappable child.
class AppTap extends StatelessWidget {
  /// Creates a tap target.
  const AppTap({super.key, required this.onTap, required this.child});

  /// Called on tap.
  final VoidCallback onTap;

  /// The content.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      GestureDetector(onTap: onTap, child: child);
}

/// A switch that reports its new value.
class AppToggle extends StatelessWidget {
  /// Creates a switch.
  const AppToggle({super.key, required this.onChanged});

  /// Called with the switch's new value.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) =>
      Switch(value: false, onChanged: onChanged);
}

/// A label under a key the caller gives it.
class AppKeyed extends StatelessWidget {
  /// Creates a keyed label.
  const AppKeyed({super.key, required this.tag, required this.label});

  /// The key the label carries.
  final Key tag;

  /// The label.
  final String label;

  @override
  Widget build(BuildContext context) => Text(label, key: tag);
}

class _Boxed extends StatelessWidget {
  const _Boxed({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 200, child: Center(child: child));
}

/// How many `_Counted` states the app has created.
var appWidgetStates = 0;

class _Counted extends StatefulWidget {
  const _Counted();

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  late final int id = ++appWidgetStates;

  @override
  Widget build(BuildContext context) => Text('counted $id');
}

/// Unannotated app widgets that are pure composition.
@Paywall(id: 'app_widgets_inline')
final class AppWidgetsInline extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsInline({super.key, required this.title});

  /// The title.
  final String title;

  @override
  Widget build(BuildContext context) => Column(children: [
        AppPill(label: title),
        _Boxed(child: AppCard(heading: 'Plans', label: title)),
        AppTap(
          onTap: () => appWidgetCalls.add('tap $title'),
          child: const AppPill(label: 'Go'),
        ),
      ]);
}

/// An app widget named like a framework widget, beside the framework's own.
@Paywall(id: 'app_widgets_named_card')
final class AppWidgetsNamedCard extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsNamedCard({super.key, required this.title});

  /// The title.
  final String title;

  @override
  Widget build(BuildContext context) => Column(children: [
        app.Card(
          heading: title,
          child: AppTap(
            onTap: () => appWidgetCalls.add('tap $title'),
            child: const AppPill(label: 'Go'),
          ),
        ),
        const Card(child: Text('Framework')),
      ]);
}

/// An app widget that doesn't lower beside ones that do.
@Paywall(id: 'app_widgets_island')
final class AppWidgetsIsland extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsIsland({super.key});

  @override
  Widget build(BuildContext context) => const Column(children: [
        AppPill(label: 'Pro'),
        _Boxed(child: _Counted()),
      ]);
}

/// Split widgets in a loop, each under the app's own key.
@Paywall(id: 'app_widgets_keyed_tally')
final class AppWidgetsKeyedTally extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsKeyedTally({super.key, required this.names});

  /// The names, in the order they show.
  final List<String> names;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final name in names) TallyChip(key: ValueKey(name), label: name),
      ]);
}

/// Two islands of one kind, each with its own State.
@Paywall(id: 'app_widgets_counted_pair')
final class AppWidgetsCountedPair extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsCountedPair({super.key});

  @override
  Widget build(BuildContext context) =>
      const Column(children: [_Counted(), _Counted()]);
}

/// A tap that interpolates a screen input, with no app widget.
@Paywall(id: 'app_widgets_direct_tap')
final class AppWidgetsDirectTap extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsDirectTap({super.key, required this.title});

  /// The title.
  final String title;

  @override
  Widget build(BuildContext context) => Column(children: [
        GestureDetector(
          onTap: () => appWidgetCalls.add('tap $title'),
          child: const Text('Go'),
        ),
        GestureDetector(
          onTap: () => appWidgetCalls.add('braced ${title}'),
          child: const Text('Braced'),
        ),
        GestureDetector(
          onTap: () => appWidgetCalls.add('$title!'),
          child: const Text('Bang'),
        ),
      ]);
}

/// An action and a key passed through app widgets.
@Paywall(id: 'app_widgets_forwarded')
final class AppWidgetsForwarded extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsForwarded({super.key, required this.title});

  /// The title.
  final String title;

  @override
  Widget build(BuildContext context) => Column(children: [
        AppToggle(onChanged: (on) => appWidgetCalls.add('toggle $title $on')),
        AppKeyed(tag: ValueKey('tag $title'), label: 'Keyed'),
      ]);
}

/// A switch whose change the app handles, placed directly.
@Paywall(id: 'app_widgets_direct_toggle')
final class AppWidgetsDirectToggle extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsDirectToggle({super.key, required this.title});

  /// The title.
  final String title;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(title),
        Switch(
          value: false,
          onChanged: (on) => appWidgetCalls.add('switch $title $on'),
        ),
      ]);
}

/// Two split widgets, each with its own State.
@Paywall(id: 'app_widgets_tally')
final class AppWidgetsTally extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsTally({super.key});

  @override
  Widget build(BuildContext context) => const Column(children: [
        TallyChip(label: 'A'),
        TallyChip(label: 'B'),
      ]);
}

/// A count only its own State keeps.
class AppCount extends StatefulWidget {
  /// Creates a count.
  const AppCount({super.key});

  @override
  State<AppCount> createState() => AppCountState();
}

/// The State of an [AppCount].
class AppCountState extends State<AppCount> {
  /// The count.
  var count = 0;

  /// Counts once more.
  void bump() => setState(() => count++);

  @override
  Widget build(BuildContext context) => Text('count $count');
}

/// One app widget value placed twice: each spot has its own State.
@Paywall(id: 'app_widgets_count_twice')
final class AppWidgetsCountTwice extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsCountTwice({super.key});

  @override
  Widget build(BuildContext context) {
    // ignore: prefer_const_declarations
    final count = AppCount();
    return Column(children: [count, const Text('between'), count]);
  }
}

/// A list of app widgets spread twice: each spot has its own State.
@Paywall(id: 'app_widgets_count_spread')
final class AppWidgetsCountSpread extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsCountSpread({super.key});

  @override
  Widget build(BuildContext context) {
    final counts = <Widget>[const AppCount()];
    return Column(children: [...counts, const Text('between'), ...counts]);
  }
}

Widget _framedTwice(Widget framed) => Row(children: [framed, framed]);

/// A helper places a value holding an app widget twice: each spot has its
/// own State.
@Paywall(id: 'app_widgets_count_framed_twice')
final class AppWidgetsCountFramedTwice extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsCountFramedTwice({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('framed'),
        _framedTwice(
            const Padding(padding: EdgeInsets.zero, child: AppCount())),
      ]);
}

/// A loop inside a local value, placed by a read: each item has its own
/// State.
@Paywall(id: 'app_widgets_count_rows')
final class AppWidgetsCountRows extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsCountRows({super.key, required this.names});

  /// The names, one count each.
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final row = Row(children: [
      for (final name in names)
        Padding(padding: EdgeInsets.zero, child: AppCount(key: ValueKey(name))),
    ]);
    return Column(children: [const Text('rows'), row]);
  }
}

/// The same chips on a general screen.
@Screen(id: 'app_widgets_screen_tally', surface: Surface.general)
final class AppWidgetsScreenTally extends StatelessWidget {
  /// Creates the screen.
  const AppWidgetsScreenTally({super.key});

  @override
  Widget build(BuildContext context) => const Column(children: [
        TallyChip(label: 'A'),
        TallyChip(label: 'B'),
      ]);
}

/// Chips the design places whole, each keeping its own State.
@Paywall(id: 'app_widgets_factory_tally')
final class AppWidgetsFactoryTally extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsFactoryTally({super.key});

  @override
  Widget build(BuildContext context) => const Column(children: [
        FactoryTallyChip(label: 'A'),
        FactoryTallyChip(label: 'B'),
      ]);
}

/// A split widget whose label reads the app's text scale.
@Paywall(id: 'app_widgets_scaled')
final class AppWidgetsScaled extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsScaled({super.key});

  @override
  Widget build(BuildContext context) =>
      const Column(children: [ScaledChip(label: 'Scaled')]);
}

/// The label the app computes, counted.
String appWidgetShout(String text) {
  appWidgetCalls.add('shout $text');
  return text.toUpperCase();
}

/// A build that places a function it declares.
@Paywall(id: 'app_widgets_local_fn')
final class AppWidgetsLocalFn extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsLocalFn({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row(String text) => Text(appWidgetShout(text));
    return Column(children: [row('a'), row('b')]);
  }
}

/// A build that spreads the widgets a helper returns.
@Paywall(id: 'app_widgets_spread')
final class AppWidgetsSpread extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsSpread({super.key});

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('h'),
        ..._rows(const ['a', 'b'])
      ]);

  List<Widget> _rows(List<String> names) =>
      [for (final name in names) Text(appWidgetShout(name))];
}

/// The rows a list of names renders, each label computed by the app.
List<Widget> appWidgetRows(List<String> names) =>
    [for (final name in names) Text(appWidgetShout(name))];

/// Spreads of a helper's widget list: a member and a top-level helper, over
/// the screen's input, a const list and a list the build computes.
@Paywall(id: 'app_widgets_spread_input')
final class AppWidgetsSpreadInput extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsSpreadInput({super.key, required this.names});

  /// The names.
  final List<String> names;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('h'),
        ..._rows(names),
        ...appWidgetRows(names),
        ...appWidgetRows(const ['c']),
      ]);

  List<Widget> _rows(List<String> names) =>
      [for (final name in names) Text(appWidgetShout('m$name'))];
}

/// A spread of a helper over a list the build computes, which renders whole
/// from the app.
@Paywall(id: 'app_widgets_spread_computed')
final class AppWidgetsSpreadComputed extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsSpreadComputed({super.key, required this.names});

  /// The names.
  final List<String> names;

  @override
  Widget build(BuildContext context) => Column(children: [
        const Text('h'),
        ...appWidgetRows([
          for (final n in names)
            if (n != 'a') n
        ]),
      ]);
}

/// A meter whose getter the app reads, counted.
final class AppWidgetMeter {
  /// The inset.
  int get inset {
    appWidgetCalls.add('inset');
    return 4;
  }
}

/// The meter the getter surface reads.
final AppWidgetMeter appWidgetMeter = AppWidgetMeter();

class _Inset extends StatelessWidget {
  const _Inset({required this.inset, required this.child});

  final int inset;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.all(inset.toDouble()), child: child);
}

/// An app widget whose argument is a getter.
@Paywall(id: 'app_widgets_getter_arg')
final class AppWidgetsGetterArg extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsGetterArg({super.key, required this.title});

  /// The title.
  final String title;

  @override
  Widget build(BuildContext context) => Column(children: [
        _Inset(inset: appWidgetMeter.inset, child: Text(title)),
      ]);
}

/// A field its initializer computes, and a build that reads the theme.
@Paywall(id: 'app_widgets_init_field')
final class AppWidgetsInitField extends StatelessWidget {
  /// Creates the paywall.
  AppWidgetsInitField({super.key, required int count})
      : _label = appWidgetShout('n$count');

  final String _label;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(_label),
        Text(Theme.of(context).brightness.name),
      ]);
}

/// How the app describes a slider value.
String appWidgetDescribe(double value) => '${(value * 100).round()} percent';

/// A slider whose value the app describes, a callback that returns a value.
@Paywall(id: 'app_widgets_slider')
final class AppWidgetsSlider extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsSlider({super.key});

  @override
  Widget build(BuildContext context) => Slider(
        value: 0.25,
        onChanged: (value) => appWidgetCalls.add('slide $value'),
        semanticFormatterCallback: (value) => appWidgetDescribe(value),
      );
}

/// How many states [AppOwnKey]'s keyed child has created.
var appOwnKeyStates = 0;

class _OwnKeyed extends StatefulWidget {
  const _OwnKeyed({super.key});

  @override
  State<_OwnKeyed> createState() => _OwnKeyedState();
}

class _OwnKeyedState extends State<_OwnKeyed> {
  late final int _id = ++appOwnKeyStates;

  @override
  Widget build(BuildContext context) => Text('own $_id');
}

/// An app widget whose build keys its own child.
class AppOwnKey extends StatelessWidget {
  /// Creates the widget.
  const AppOwnKey({super.key});

  @override
  Widget build(BuildContext context) =>
      const _OwnKeyed(key: ValueKey<String>('own'));
}

/// App widgets, one annotated, whose builds key their own children.
@Paywall(id: 'app_widgets_own_keys')
final class AppWidgetsOwnKeys extends StatelessWidget {
  /// Creates the paywall.
  const AppWidgetsOwnKeys({super.key});

  @override
  Widget build(BuildContext context) =>
      const Column(children: [Text('keys'), AppOwnKey(), OwnKeyChip()]);
}
