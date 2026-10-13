import 'dart:convert';

import 'package:build/build.dart';
import 'package:restage_codegen/src/measurement/measurement_compiler_output.dart';
import 'package:restage_codegen/src/surface_publication/compiler_handoff.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('inlines a class helper method in a screen build', () async {
    final text = await _compileOne(
      'whats_new',
      '''
@Screen(id: 'whats_new', surface: Surface.message)
final class WhatsNew extends StatelessWidget {
  const WhatsNew({super.key});

  Widget _item(String text) =>
      ListTile(leading: const Icon(Icons.check), title: Text(text));

  @override
  Widget build(BuildContext context) =>
      Column(children: [_item('Dark mode'), _item('Faster sync')]);
}
''',
      'assets/message/screens/whats_new.rfwtxt',
    );
    expect(RegExp(r'ListTile\(').allMatches(text), hasLength(2));
    expect(text, contains('"Dark mode"'));
    expect(text, contains('"Faster sync"'));
    expect(text, isNot(contains('_item')));
  });

  test('inlines a same-library top-level helper function', () async {
    final text = await _compileOne(
      'top_level',
      '''
Widget badge(String label) => Chip(label: Text(label));

@Screen(id: 'top_level', surface: Surface.general)
final class TopLevel extends StatelessWidget {
  const TopLevel({super.key});

  @override
  Widget build(BuildContext context) =>
      Row(children: [badge('New'), badge('Beta')]);
}
''',
      'assets/general/screens/top_level.rfwtxt',
    );
    expect(RegExp(r'Chip\(').allMatches(text), hasLength(2));
    expect(text, contains('"New"'));
    expect(text, contains('"Beta"'));
  });

  test('binds a host-data field passed to a helper', () async {
    final text = await _compileOne(
      'greeting',
      '''
@Screen(id: 'greeting', surface: Surface.general)
final class Greeting extends StatelessWidget {
  const Greeting({required this.owner, super.key});

  final String owner;

  Widget _title(String name) => Text(name);

  @override
  Widget build(BuildContext context) => Center(child: _title(owner));
}
''',
      'assets/general/screens/greeting.rfwtxt',
    );
    expect(text, contains('data.context.owner'));
    expect(text, isNot(contains('_title')));
  });

  test('reads and writes state from a helper in a stateful screen', () async {
    final text = await _compileOne(
      'toggle_row',
      '''
@Screen(id: 'toggle_row', surface: Surface.general)
final class ToggleRow extends StatefulWidget {
  const ToggleRow({super.key});

  @override
  State<ToggleRow> createState() => _ToggleRowState();
}

final class _ToggleRowState extends State<ToggleRow> {
  bool on = false;

  void flip() => setState(() => on = !on);

  Widget _row(String label) => GestureDetector(
        onTap: flip,
        child: Text(on ? label : 'off'),
      );

  @override
  Widget build(BuildContext context) => Column(children: [_row('on')]);
}
''',
      'assets/general/screens/toggle_row.rfwtxt',
    );
    expect(text, contains('state.on'));
    expect(text, contains('set state.on'));
    expect(text, isNot(contains('_row')));
  });

  test('passes a surface event callback through a helper', () async {
    final text = await _compileOne(
      'event_helper',
      '''
@Screen(id: 'event_helper', surface: Surface.general)
final class EventHelper extends StatelessWidget {
  const EventHelper({super.key});

  static const done = SurfaceEvent<void>('done');

  Widget _button(String label, VoidCallback onTap) =>
      ElevatedButton(onPressed: onTap, child: Text(label));

  @override
  Widget build(BuildContext context) =>
      Center(child: _button('Continue', surfaceEvent(done)));
}
''',
      'assets/general/screens/event_helper.rfwtxt',
    );
    expect(text, contains('ElevatedButton('));
    expect(text, contains('"done"'));
    expect(text, contains('"Continue"'));
  });

  test('inlines a helper in a paywall build', () async {
    final text = await _compileOne(
      'helper_offer',
      '''
@Paywall(id: 'helper_offer')
final class HelperOffer extends StatelessWidget {
  const HelperOffer({super.key});

  Widget _feature(String text) => Text(text);

  Widget _cta(VoidCallback onTap) =>
      ElevatedButton(onPressed: onTap, child: const Text('Start'));

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _feature('Unlimited projects'),
          _cta(paywallEvent('continue')),
        ],
      );
}
''',
      'assets/paywalls/helper_offer.rfwtxt',
    );
    expect(text, contains('"Unlimited projects"'));
    expect(text, contains('"continue"'));
    expect(text, isNot(contains('_feature')));
  });

  test('inlines value-returning helpers', () async {
    final text = await _compileOne(
      'value_helpers',
      r'''
@Screen(id: 'value_helpers', surface: Surface.general)
final class ValueHelpers extends StatelessWidget {
  const ValueHelpers({required this.owner, super.key});

  final String owner;

  String _greeting(String name) => 'Hi $name';

  static Color accent() => const Color(0xFF336699);

  @override
  Widget build(BuildContext context) =>
      Text(_greeting(owner), style: TextStyle(color: accent()));
}
''',
      'assets/general/screens/value_helpers.rfwtxt',
    );
    expect(text, contains('data.context.owner'));
    expect(text, contains('0xFF336699'));
    expect(text, isNot(contains('_greeting')));
  });

  test('rejects a recursive helper with a named diagnostic', () async {
    final result = await _compile(
      'recursive',
      '''
@Screen(id: 'recursive', surface: Surface.general)
final class Recursive extends StatelessWidget {
  const Recursive({super.key});

  Widget _nest() => Column(children: [_nest()]);

  @override
  Widget build(BuildContext context) => _nest();
}
''',
    );
    expect(result.result.succeeded, isFalse);
    expect(result.result.errors.join('\n'), contains('recursive helper'));
  });
}

Future<({TestBuilderResult result, TestReaderWriter readerWriter})> _compile(
  String name,
  String body,
) async {
  final source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/$name.restage.g.dart';

$body''';
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  final result = await testBuilder(
    const PackageSurfaceCompilerBuilder(
      BuilderOptions({
        kMeasurementMinimumClientOption: 1,
        kMeasurementPrivacyPolicyRevisionOption: 'privacy.default',
        kMeasurementCollectionBudgetRevisionOption: 'budget.default',
      }),
    ),
    {'apps_examples|lib/features/$name.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  return (result: result, readerWriter: readerWriter);
}

Future<String> _compileOne(String name, String body, String output) async {
  final (:result, :readerWriter) = await _compile(name, body);
  expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  final bundle = RestageSurfacePublicationBundle.fromJson(
    jsonDecode(
      readerWriter.testing.readString(
        AssetId('apps_examples', kRestageSurfacePublicationCompilerBundlePath),
      ),
    ),
  );
  expect(bundle.valid, isTrue, reason: bundle.errors.join('\n'));
  final blob = bundle.ownedOutputs[output];
  expect(blob, isNotNull, reason: bundle.ownedOutputs.keys.join('\n'));
  return utf8.decode(blob!);
}
