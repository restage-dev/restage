import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/user_catalog_json_builder.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:test/test.dart';

import 'helpers.dart';

const String _package = 'apps_examples';

const String _imports = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
''';

String _stateless(String name, String body, {String extraImports = ''}) => '''
$_imports$extraImports
@Paywall()
class $name extends StatelessWidget {
  const $name({super.key});

  @override
  Widget build(BuildContext context) {
$body
  }
}
''';

String _stateful(String name, {required String members, required String body}) {
  return '''
$_imports
@Paywall()
class $name extends StatefulWidget {
  const $name({super.key});

  @override
  State<$name> createState() => _${name}State();
}

class _${name}State extends State<$name> {
$members

  @override
  Widget build(BuildContext context) {
$body
  }
}
''';
}

final String _themePrelude = _stateless('PreludeTheme', '''
    final empty = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Column(
      children: [
        Container(color: empty, height: 8),
        Container(color: empty, height: 12),
        Container(color: empty, height: 16),
      ],
    );''');

final String _themeInlined = _stateless('InlinedTheme', '''
    return Column(
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          height: 8,
        ),
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          height: 12,
        ),
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          height: 16,
        ),
      ],
    );''');

final String _chainPrelude = _stateless('PreludeChain', '''
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    return Container(color: accent, height: 24);''');

final String _chainInlined = _stateless('InlinedChain', '''
    return Container(
      color: Theme.of(context).colorScheme.primary,
      height: 24,
    );''');

final String _shadowPrelude = _stateful(
  'PreludeShadow',
  members: '  bool annual = false;',
  body: '''
    final annual = 'Annual plan';
    return Text(annual);''',
);

final String _shadowInlined = _stateful(
  'InlinedShadow',
  members: '  bool annual = false;',
  body: "    return const Text('Annual plan');",
);

final String _eventPrelude = _stateless('PreludeEvent', '''
    final term = 'annual';
    return GestureDetector(
      onTap: paywallEvent('continue', args: {'term': term}),
      child: const Text('Go'),
    );''');

final String _eventInlined = _stateless('InlinedEvent', '''
    return GestureDetector(
      onTap: paywallEvent('continue', args: {'term': 'annual'}),
      child: const Text('Go'),
    );''');

const String _toggleMembers = '''
  bool annual = false;

  void toggle() => setState(() => annual = !annual);''';

final String _statefulPrelude = _stateful(
  'PreludeStateful',
  members: _toggleMembers,
  body: '''
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: toggle,
      child: Container(
        color: annual ? scheme.primary : scheme.surface,
        height: 20,
      ),
    );''',
);

final String _statefulInlined = _stateful(
  'InlinedStateful',
  members: _toggleMembers,
  body: '''
    return GestureDetector(
      onTap: toggle,
      child: Container(
        color: annual
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surface,
        height: 20,
      ),
    );''',
);

final Map<String, String> _fixtures = {
  'prelude_theme': _themePrelude,
  'inlined_theme': _themeInlined,
  'prelude_chain': _chainPrelude,
  'inlined_chain': _chainInlined,
  'prelude_shadow': _shadowPrelude,
  'inlined_shadow': _shadowInlined,
  'prelude_event': _eventPrelude,
  'inlined_event': _eventInlined,
  'prelude_stateful': _statefulPrelude,
  'inlined_stateful': _statefulInlined,
};

const String _promoCard = '''
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.ds'),
  capabilityVersion: 1,
)
const acmeLibrary = 0;

@RestageWidget(
  name: 'PromoCard',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'promo',
)
class PromoCard extends StatelessWidget {
  const PromoCard({required this.title, super.key});

  @RestageProperty(description: 't', required: true)
  final String title;

  @override
  Widget build(BuildContext context) => Text(title);
}
''';

const String _promoImport = "import 'promo_card.dart';\n";

// Intentionally shares a name with `PromoCard.title` but has a distinct
// element.
final String _promoPrelude = _stateless(
  'PromoPrelude',
  '''
    final title = 'Pro';
    return Column(children: [PromoCard(title: title)]);''',
  extraImports: _promoImport,
);

final String _promoInlined = _stateless(
  'PromoInlined',
  "    return Column(children: [PromoCard(title: 'Pro')]);",
  extraImports: _promoImport,
);

final String _promoCollectorPrelude = _stateless(
  'PromoCollectorPrelude',
  '''
    final card = PromoCard(title: 'Collector');
    return Column(children: [card]);''',
  extraImports: _promoImport,
);

final String _promoCollectorInlined = _stateless(
  'PromoCollectorInlined',
  "    return Column(children: [PromoCard(title: 'Collector')]);",
  extraImports: _promoImport,
);

final String _promoKeyed = _stateless(
  'PromoKeyed',
  '''
    return PromoCard(
      title: 'Keyed',
      key: const ValueKey<String>('promo'),
    );''',
  extraImports: _promoImport,
);

final String _navPrelude = _stateless('PreludeNav', r'''
    final route = Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const SizedBox()),
    );
    return Text('$route');''');

final String _literalWidgetKey = _stateless(
  'LiteralWidgetKey',
  "    return const Text('Ready', key: ValueKey<String>('literal'));",
);

final String _sourceInnocuousWidgetKey = _stateless(
  'SourceInnocuousWidgetKey',
  '''
    final key = const ValueKey<String>('hidden');
    return Text('Ready', key: key);''',
);

final String _sourceNestedInnocuousWidgetKey = _stateless(
  'SourceNestedInnocuousWidgetKey',
  '''
    final key = const ValueKey<String>('hidden');
    final child = Text('Ready', key: key);
    return child;''',
);

const String _sourceEffectfulWidgetKey = '''
$_imports
Key auditedKey(BuildContext context) {
  Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => const SizedBox()),
  );
  return const ValueKey<String>('effect');
}

@Paywall()
class SourceEffectfulWidgetKey extends StatelessWidget {
  const SourceEffectfulWidgetKey({super.key});

  @override
  Widget build(BuildContext context) {
    final key = auditedKey(context);
    return Text('Ready', key: key);
  }
}
''';

const String _sourceNestedEffectfulWidgetKey = '''
$_imports
Key auditedKey(BuildContext context) {
  Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => const SizedBox()),
  );
  return const ValueKey<String>('effect');
}

@Paywall()
class SourceNestedEffectfulWidgetKey extends StatelessWidget {
  const SourceNestedEffectfulWidgetKey({super.key});

  @override
  Widget build(BuildContext context) {
    final key = auditedKey(context);
    final child = Text('Ready', key: key);
    return child;
  }
}
''';

const String _valueKeyTypedWidgetKey = '''
$_imports
class ValueKeyHost extends StatelessWidget {
  const ValueKeyHost({ValueKey<String>? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => const Text('Ready');
}

@Paywall()
class ValueKeyTypedWidgetKey extends StatelessWidget {
  const ValueKeyTypedWidgetKey({super.key});

  @override
  Widget build(BuildContext context) {
    final key = const ValueKey<String>('hidden');
    return ValueKeyHost(key: key);
  }
}
''';

const String _boundedGenericWidgetKey = '''
$_imports
class GenericKeyHost<T extends Key> extends StatelessWidget {
  const GenericKeyHost({T? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => const Text('Ready');
}

@Paywall()
class BoundedGenericWidgetKey extends StatelessWidget {
  const BoundedGenericWidgetKey({super.key});

  @override
  Widget build(BuildContext context) {
    final key = const ValueKey<String>('hidden');
    return GenericKeyHost<ValueKey<String>>(key: key);
  }
}
''';

typedef _CustomWidgetFixture = ({String widget, String root});

_CustomWidgetFixture _customWidgetFixture(
  String slug,
  String name,
  String body, {
  String helper = '',
}) =>
    (
      widget: '''
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

$helper
@RestageLibrary(
  library: WidgetLibrary.custom('acme.widgets'),
  capabilityVersion: 1,
)
const acmeWidgets = 0;

@RestageWidget(
  name: '$name',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.layout,
  description: 'custom widget',
)
class $name extends StatelessWidget {
  const $name({super.key});

  @override
  Widget build(BuildContext context) {
$body
  }
}
''',
      root: '''
$_imports
import '../widgets/$slug.dart';

@Paywall()
class ${name}Surface extends StatelessWidget {
  const ${name}Surface({super.key});

  @override
  Widget build(BuildContext context) => const $name();
}
''',
    );

final _CustomWidgetFixture _customUnreadInnocuous = _customWidgetFixture(
  'custom_unread_innocuous',
  'CustomUnreadInnocuous',
  '''
    final label = 'hidden';
    return const Text('Ready');''',
);

final _CustomWidgetFixture _customUnreadEffectful = _customWidgetFixture(
  'custom_unread_effectful',
  'CustomUnreadEffectful',
  '''
    final pushed = Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const SizedBox()),
    );
    return const Text('Ready');''',
);

final _CustomWidgetFixture _customKeyInnocuous = _customWidgetFixture(
  'custom_key_innocuous',
  'CustomKeyInnocuous',
  '''
    final key = const ValueKey<String>('hidden');
    return Text('Ready', key: key);''',
);

final _CustomWidgetFixture _customNestedKeyInnocuous = _customWidgetFixture(
  'custom_nested_key_innocuous',
  'CustomNestedKeyInnocuous',
  '''
    final key = const ValueKey<String>('hidden');
    final child = Text('Ready', key: key);
    return child;''',
);

final _CustomWidgetFixture _customKeyEffectful = _customWidgetFixture(
  'custom_key_effectful',
  'CustomKeyEffectful',
  '''
    final key = auditedKey(context);
    return Text('Ready', key: key);''',
  helper: '''
Key auditedKey(BuildContext context) {
  Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => const SizedBox()),
  );
  return const ValueKey<String>('effect');
}
''',
);

final _CustomWidgetFixture _customNestedKeyEffectful = _customWidgetFixture(
  'custom_nested_key_effectful',
  'CustomNestedKeyEffectful',
  '''
    final key = auditedKey(context);
    final child = Text('Ready', key: key);
    return child;''',
  helper: '''
Key auditedKey(BuildContext context) {
  Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => const SizedBox()),
  );
  return const ValueKey<String>('effect');
}
''',
);

final _CustomWidgetFixture _customDirectCycle = _customWidgetFixture(
  'custom_direct_cycle',
  'CustomDirectCycle',
  '''
    final Widget child = child;
    return child;''',
);

final _CustomWidgetFixture _customTransitiveCycle = _customWidgetFixture(
  'custom_transitive_cycle',
  'CustomTransitiveCycle',
  '''
    final Widget first = second;
    final Widget second = first;
    return first;''',
);

final _CustomWidgetFixture _customKeyDirectCycle = _customWidgetFixture(
  'custom_key_direct_cycle',
  'CustomKeyDirectCycle',
  '''
    final dynamic child = Text('Ready', key: child);
    return child;''',
);

final _CustomWidgetFixture _customKeyTransitiveCycle = _customWidgetFixture(
  'custom_key_transitive_cycle',
  'CustomKeyTransitiveCycle',
  '''
    final dynamic first = second;
    final dynamic second = Text('Ready', key: first);
    return second;''',
);

final _CustomWidgetFixture _customGroupedFinal = _customWidgetFixture(
  'custom_grouped_final',
  'CustomGroupedFinal',
  '''
    final first = 'A', second = 'B';
    return Text(first + second);''',
);

final _CustomWidgetFixture _customGroupedConst = _customWidgetFixture(
  'custom_grouped_const',
  'CustomGroupedConst',
  '''
    const first = 'A', second = 'B';
    return Text(first + second);''',
);

final _CustomWidgetFixture _customMissingInitializer = _customWidgetFixture(
  'custom_missing_initializer',
  'CustomMissingInitializer',
  '''
    final String label;
    return const Text('Ready');''',
);

final _CustomWidgetFixture _customLateFinal = _customWidgetFixture(
  'custom_late_final',
  'CustomLateFinal',
  '''
    late final label = 'Ready';
    return Text(label);''',
);

final _CustomWidgetFixture _customLiteralWidgetKey = _customWidgetFixture(
  'custom_literal_widget_key',
  'CustomLiteralWidgetKey',
  "    return const Text('Ready', key: ValueKey<String>('literal'));",
);

Future<TestReaderWriter> _seeded(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
    includeFlutter: true,
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  return readerWriter;
}

String _text(TestBuilderResult result, String id) => result.readerWriter.testing
    .readString(AssetId(_package, 'assets/paywalls/$id.rfwtxt'));

List<int> _bytes(TestBuilderResult result, String id) =>
    result.readerWriter.testing
        .readBytes(AssetId(_package, 'assets/paywalls/$id.rfw'));

void _expectTwins(TestBuilderResult result, String prelude, String inlined) {
  expect(_text(result, prelude), _text(result, inlined));
  expect(
    _withoutMeasurementIdentity(
      fmt
          .decodeLibraryBlob(Uint8List.fromList(_bytes(result, prelude)))
          .toString(),
    ),
    _withoutMeasurementIdentity(
      fmt
          .decodeLibraryBlob(Uint8List.fromList(_bytes(result, inlined)))
          .toString(),
    ),
  );
}

String _withoutMeasurementIdentity(String source) => source
    .replaceAll(RegExp(r'carriers: \[[^\]]*\]'), 'carriers: [...]')
    .replaceAll(RegExp(r'pointTokens: \[[^\]]*\]'), 'pointTokens: [...]')
    .replaceAll(
      RegExp('__restage_measurement_route_v1: [^,}]+'),
      '__restage_measurement_route_v1: ...',
    );

Future<String> _refusalLog(
  String slug,
  String source, {
  String? customWidgetSource,
}) async {
  final asset = '$_package|lib/paywalls/$slug.dart';
  final sources = {
    asset: source,
    if (customWidgetSource != null)
      '$_package|lib/widgets/$slug.dart': customWidgetSource,
  };
  final logs = <String>[];
  await testBuilder(
    restageCodegenBuilder(BuilderOptions.empty),
    sources,
    rootPackage: _package,
    readerWriter: await _seeded(sources),
    outputs: const {},
    onLog: (record) => logs.add(record.message),
  );
  return logs.join('\n');
}

void main() {
  late TestBuilderResult result;

  setUpAll(() async {
    final sources = <String, String>{
      for (final entry in _fixtures.entries)
        '$_package|lib/paywalls/${entry.key}.dart': entry.value,
      '$_package|lib/paywalls/literal_widget_key.dart': _literalWidgetKey,
    };
    result = await testBuilders(
      [restageCodegenBuilder(BuilderOptions.empty)],
      sources,
      rootPackage: _package,
      readerWriter: await _seeded(sources),
      flattenOutput: true,
    );
  });

  test('every prelude fixture compiles', () {
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    expect(result.errors, isEmpty);
  });

  test('a theme read through one local lowers at every use site', () {
    expect(
      _text(result, 'prelude_theme'),
      contains('data.theme.colorScheme.surfaceContainerHighest'),
    );
    _expectTwins(result, 'prelude_theme', 'inlined_theme');
  });

  test('a local initialized from another local resolves through the chain', () {
    expect(
      _text(result, 'prelude_chain'),
      contains('data.theme.colorScheme.primary'),
    );
    _expectTwins(result, 'prelude_chain', 'inlined_chain');
  });

  test('a local shadowing a State field resolves to the local', () {
    expect(_text(result, 'prelude_shadow'), contains('"Annual plan"'));
    expect(_text(result, 'prelude_shadow'), isNot(contains('state.annual')));
    _expectTwins(result, 'prelude_shadow', 'inlined_shadow');
  });

  test('a local referenced inside an event payload lowers', () {
    expect(_text(result, 'prelude_event'), contains('event "continue"'));
    expect(_text(result, 'prelude_event'), contains('"annual"'));
    _expectTwins(result, 'prelude_event', 'inlined_event');
  });

  test('a stateful root admits a prelude', () {
    expect(_text(result, 'prelude_stateful'), contains('state.annual'));
    expect(
      _text(result, 'prelude_stateful'),
      contains('data.theme.colorScheme.primary'),
    );
    _expectTwins(result, 'prelude_stateful', 'inlined_stateful');
  });

  test('a literal widget key remains compile-time inert', () {
    expect(
      _text(result, 'literal_widget_key'),
      contains('Text(text: "Ready")'),
    );
    expect(_text(result, 'literal_widget_key'), isNot(contains('key:')));
  });

  test('a read local holding an imperative call emits nothing', () async {
    final log = await _refusalLog('prelude_nav', _navPrelude);
    expect(log, contains('route'));
  });

  test('an innocuous source local used only as widget key emits nothing',
      () async {
    final log = await _refusalLog(
      'source_innocuous_widget_key',
      _sourceInnocuousWidgetKey,
    );
    expect(log, contains("local 'key'"));
    expect(log, contains('read only as a widget key'));
    expect(log, contains('discards key operands'));
  });

  test('an effectful source local used only as widget key emits nothing',
      () async {
    final log = await _refusalLog(
      'source_effectful_widget_key',
      _sourceEffectfulWidgetKey,
    );
    expect(log, contains("local 'key'"));
    expect(log, contains('read only as a widget key'));
    expect(log, contains('discards key operands'));
  });

  test('a nested source widget-key local remains unread', () async {
    final log = await _refusalLog(
      'source_nested_innocuous_widget_key',
      _sourceNestedInnocuousWidgetKey,
    );
    expect(log, contains("local 'key'"));
    expect(log, contains('read only as a widget key'));
    expect(log, contains('discards key operands'));
  });

  test('an effectful nested source widget-key local remains unread', () async {
    final log = await _refusalLog(
      'source_nested_effectful_widget_key',
      _sourceNestedEffectfulWidgetKey,
    );
    expect(log, contains("local 'key'"));
    expect(log, contains('read only as a widget key'));
    expect(log, contains('discards key operands'));
  });

  test('a ValueKey-typed widget formal discards its key operand', () async {
    final log = await _refusalLog(
      'value_key_typed_widget_key',
      _valueKeyTypedWidgetKey,
    );
    expect(log, contains("local 'key'"));
    expect(log, contains('read only as a widget key'));
    expect(log, contains('discards key operands'));
  });

  test('a Key-bounded widget formal discards its key operand', () async {
    final log = await _refusalLog(
      'bounded_generic_widget_key',
      _boundedGenericWidgetKey,
    );
    expect(log, contains("local 'key'"));
    expect(log, contains('read only as a widget key'));
    expect(log, contains('discards key operands'));
  });

  test('a custom widget with an innocuous unread local emits nothing',
      () async {
    final log = await _refusalLog(
      'custom_unread_innocuous',
      _customUnreadInnocuous.root,
      customWidgetSource: _customUnreadInnocuous.widget,
    );
    expect(log, contains("local 'label'"));
    expect(log, contains('never read'));
  });

  test('a custom widget with an effectful unread local emits nothing',
      () async {
    final log = await _refusalLog(
      'custom_unread_effectful',
      _customUnreadEffectful.root,
      customWidgetSource: _customUnreadEffectful.widget,
    );
    expect(log, contains("local 'pushed'"));
    expect(log, contains('never read'));
  });

  test('an innocuous custom local used only as widget key emits nothing',
      () async {
    final log = await _refusalLog(
      'custom_key_innocuous',
      _customKeyInnocuous.root,
      customWidgetSource: _customKeyInnocuous.widget,
    );
    expect(log, contains("local 'key'"));
    expect(log, contains('read only as a widget key'));
    expect(log, contains('discards key operands'));
  });

  test('an effectful custom local used only as widget key emits nothing',
      () async {
    final log = await _refusalLog(
      'custom_key_effectful',
      _customKeyEffectful.root,
      customWidgetSource: _customKeyEffectful.widget,
    );
    expect(log, contains("local 'key'"));
    expect(log, contains('read only as a widget key'));
    expect(log, contains('discards key operands'));
  });

  test('a nested custom widget-key local remains unread', () async {
    final log = await _refusalLog(
      'custom_nested_key_innocuous',
      _customNestedKeyInnocuous.root,
      customWidgetSource: _customNestedKeyInnocuous.widget,
    );
    expect(log, contains("local 'key'"));
    expect(log, contains('read only as a widget key'));
    expect(log, contains('discards key operands'));
  });

  test('an effectful nested custom widget-key local remains unread', () async {
    final log = await _refusalLog(
      'custom_nested_key_effectful',
      _customNestedKeyEffectful.root,
      customWidgetSource: _customNestedKeyEffectful.widget,
    );
    expect(log, contains("local 'key'"));
    expect(log, contains('read only as a widget key'));
    expect(log, contains('discards key operands'));
  });

  test('a custom widget direct binding cycle emits nothing', () async {
    final log = await _refusalLog(
      'custom_direct_cycle',
      _customDirectCycle.root,
      customWidgetSource: _customDirectCycle.widget,
    );
    expect(log, contains("local 'child'"));
    expect(log, contains('cyclic build() binding'));
  });

  test('a custom widget transitive binding cycle emits nothing', () async {
    final log = await _refusalLog(
      'custom_transitive_cycle',
      _customTransitiveCycle.root,
      customWidgetSource: _customTransitiveCycle.widget,
    );
    expect(log, contains('cyclic build() binding'));
  });

  test('a custom widget rejects a direct cycle through a widget key', () async {
    final log = await _refusalLog(
      'custom_key_direct_cycle',
      _customKeyDirectCycle.root,
      customWidgetSource: _customKeyDirectCycle.widget,
    );
    expect(log, contains('cyclic build() binding'));
  });

  test('a custom widget rejects a transitive cycle through a widget key',
      () async {
    final log = await _refusalLog(
      'custom_key_transitive_cycle',
      _customKeyTransitiveCycle.root,
      customWidgetSource: _customKeyTransitiveCycle.widget,
    );
    expect(log, contains('cyclic build() binding'));
  });

  test('a custom widget rejects grouped final declarations', () async {
    final log = await _refusalLog(
      'custom_grouped_final',
      _customGroupedFinal.root,
      customWidgetSource: _customGroupedFinal.widget,
    );
    expect(log, contains("grouped declaration 'first, second'"));
    expect(log, contains('split it'));
  });

  test('a custom widget rejects grouped const declarations', () async {
    final log = await _refusalLog(
      'custom_grouped_const',
      _customGroupedConst.root,
      customWidgetSource: _customGroupedConst.widget,
    );
    expect(log, contains("grouped declaration 'first, second'"));
    expect(log, contains('split it'));
  });

  test('a custom widget rejects a final without an initializer', () async {
    final log = await _refusalLog(
      'custom_missing_initializer',
      _customMissingInitializer.root,
      customWidgetSource: _customMissingInitializer.widget,
    );
    expect(log, contains('no resolved declaration or initializer'));
  });

  test('a custom widget late final prelude emits nothing', () async {
    final log = await _refusalLog(
      'custom_late_final',
      _customLateFinal.root,
      customWidgetSource: _customLateFinal.widget,
    );
    expect(log, contains('body is not a single returned expression'));
  });

  test('a custom widget literal key remains compile-time inert', () async {
    const slug = 'custom_literal_widget_key';
    const asset = '$_package|lib/paywalls/$slug.dart';
    final sources = {
      asset: _customLiteralWidgetKey.root,
      '$_package|lib/widgets/$slug.dart': _customLiteralWidgetKey.widget,
    };
    final literal = await testBuilders(
      [
        const UserCatalogJsonBuilder(BuilderOptions.empty),
        restageCodegenBuilder(BuilderOptions.empty),
      ],
      sources,
      rootPackage: _package,
      readerWriter: await _seeded(sources),
      flattenOutput: true,
    );
    expect(literal.succeeded, isTrue, reason: literal.errors.join('\n'));
    expect(_text(literal, slug), contains('Text(text: "Ready")'));
    expect(_text(literal, slug), isNot(contains('key:')));
  });

  group('custom widget constructed in a prelude local', () {
    late TestBuilderResult twins;

    setUpAll(() async {
      final sources = {
        '$_package|lib/paywalls/promo_card.dart': _promoCard,
        '$_package|lib/paywalls/promo_prelude.dart': _promoPrelude,
        '$_package|lib/paywalls/promo_inlined.dart': _promoInlined,
        '$_package|lib/paywalls/promo_collector_prelude.dart':
            _promoCollectorPrelude,
        '$_package|lib/paywalls/promo_collector_inlined.dart':
            _promoCollectorInlined,
        '$_package|lib/paywalls/promo_keyed.dart': _promoKeyed,
      };
      // Emit the custom widget catalog used by the surface builder.
      twins = await testBuilders(
        [
          const UserCatalogJsonBuilder(BuilderOptions.empty),
          restageCodegenBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: _package,
        readerWriter: await _seeded(sources),
        flattenOutput: true,
      );
    });

    test('inlines it identically to the hand-inlined twin', () {
      expect(twins.succeeded, isTrue, reason: twins.errors.join('\n'));
      expect(_text(twins, 'promo_prelude'), contains('widget PromoCard'));
      expect(
        _text(twins, 'promo_prelude'),
        contains('PromoCard(title: "Pro")'),
      );
      expect(
        _text(twins, 'promo_prelude'),
        isNot(contains('PromoCard(title: args.title)')),
      );
      expect(
        _text(twins, 'promo_prelude'),
        contains('widget PromoCard = Text(text: args.title)'),
      );
      _expectTwins(twins, 'promo_prelude', 'promo_inlined');
    });

    test('finds a widget held in a local through collector roots', () {
      expect(twins.succeeded, isTrue, reason: twins.errors.join('\n'));
      final dsl = _text(twins, 'promo_collector_prelude');
      expect(dsl, contains('PromoCard(title: "Collector")'));
      expect(dsl, contains('widget PromoCard = Text(text: args.title)'));
      _expectTwins(
        twins,
        'promo_collector_prelude',
        'promo_collector_inlined',
      );
    });

    test('drops the custom widget call-site key', () {
      expect(twins.succeeded, isTrue, reason: twins.errors.join('\n'));
      final dsl = _text(twins, 'promo_keyed');
      expect(dsl, contains('PromoCard(title: "Keyed")'));
      expect(dsl, isNot(contains('key:')));
    });
  });
}
