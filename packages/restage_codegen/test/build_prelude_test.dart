import 'dart:typed_data';

import 'package:build/build.dart';
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

String _snake(String name) => name
    .replaceAllMapped(RegExp('(?<=.)[A-Z]'), (m) => '_${m[0]}')
    .toLowerCase();

String _part(String slug) => "part 'restage.generated/$slug.restage.g.dart';\n";

// Imports precede the part directive; other extra declarations follow it.
String _stateless(String name, String body, {String extraImports = ''}) {
  final lines = extraImports.split('\n').where((line) => line.isNotEmpty);
  final imports = lines.where((line) => line.startsWith('import '));
  final declarations = lines.where((line) => !line.startsWith('import '));
  return '''
$_imports${imports.map((line) => '$line\n').join()}${_part(_snake(name))}${declarations.join('\n')}
@Paywall()
class $name extends StatelessWidget {
  const $name({super.key});

  @override
  Widget build(BuildContext context) {
$body
  }
}
''';
}

String _stateful(String name, {required String members, required String body}) {
  return '''
$_imports${_part(_snake(name))}
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

final String _gradientPrelude = _stateless('PreludeGradient', '''
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 24,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark
              ? const [Color(0xFF000000), Color(0xFF111111)]
              : const [Color(0xFFFFFFFF), Color(0xFFEEEEEE)],
        ),
      ),
    );''');

final String _gradientInlined = _stateless('InlinedGradient', '''
    return Container(
      height: 24,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: Theme.of(context).brightness == Brightness.dark
              ? const [Color(0xFF000000), Color(0xFF111111)]
              : const [Color(0xFFFFFFFF), Color(0xFFEEEEEE)],
        ),
      ),
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

const _continueEvent = '''
abstract final class _Events {
  static const continueFlow = SurfaceEvent<Map<String, Object?>>('continue');
}''';

final String _eventPrelude = _stateless('PreludeEvent', '''
    final term = 'annual';
    return GestureDetector(
      onTap: context.surfaceEvent(_Events.continueFlow, {'term': term}),
      child: const Text('Go'),
    );''', extraImports: _continueEvent);

final String _eventInlined = _stateless('InlinedEvent', '''
    return GestureDetector(
      onTap: context.surfaceEvent(_Events.continueFlow, {'term': 'annual'}),
      child: const Text('Go'),
    );''', extraImports: _continueEvent);

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
  'prelude_gradient': _gradientPrelude,
  'inlined_gradient': _gradientInlined,
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
    return Column(children: [Text('$route'), Text('at $route')]);''');

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

const String _sourceEffectfulWidgetKey =
    '''
$_imports
part 'restage.generated/source_effectful_widget_key.restage.g.dart';

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

const String _sourceNestedEffectfulWidgetKey =
    '''
$_imports
part 'restage.generated/source_nested_effectful_widget_key.restage.g.dart';

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

const String _valueKeyTypedWidgetKey =
    '''
$_imports
part 'restage.generated/value_key_typed_widget_key.restage.g.dart';

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

const String _boundedGenericWidgetKey =
    '''
$_imports
part 'restage.generated/bounded_generic_widget_key.restage.g.dart';

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
}) => (
  widget:
      '''
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
  root:
      '''
$_imports
import '../widgets/$slug.dart';
${_part(slug)}
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

List<int> _bytes(TestBuilderResult result, String id) => result
    .readerWriter
    .testing
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

Future<String> _compiledText(
  String slug,
  String source, {
  List<String>? logs,
}) async {
  final sources = {'$_package|lib/paywalls/$slug.dart': source};
  final compiled = await testBuilders(
    [restageCodegenBuilder(BuilderOptions.empty)],
    sources,
    rootPackage: _package,
    readerWriter: await _seeded(sources),
    flattenOutput: true,
    onLog: (record) => logs?.add(record.message),
  );
  expect(compiled.succeeded, isTrue, reason: compiled.errors.join('\n'));
  return _text(compiled, slug);
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

  test('a light and dark list chosen through a local lowers flat', () {
    expect(
      _text(result, 'prelude_gradient'),
      contains('colors: switch data.theme.brightness {'),
    );
    _expectTwins(result, 'prelude_gradient', 'inlined_gradient');
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

  test('a literal widget key is carried', () {
    expect(
      _text(result, 'literal_widget_key'),
      contains('Text(text: "Ready", key: data.context._h'),
    );
  });

  test('an imperative local read by two values is read by name', () async {
    final logs = <String>[];
    await _compiledText('prelude_nav', _navPrelude, logs: logs);
    // The mount pushes once and both values read the result.
    expect(
      logs.join('\n'),
      contains("Evaluated in the app:\n  '\$route'\n  'at \$route'"),
    );
    expect(logs.join('\n'), isNot(contains('Navigator.push')));
  });

  // A key is carried when it compares by value, read through any local;
  // otherwise the widget holding it renders from the app.
  for (final (name, slug, source, holder) in [
    (
      'a constant key read through a local is carried',
      'source_innocuous_widget_key',
      _sourceInnocuousWidgetKey,
      null,
    ),
    (
      'a constant key read through a nested local is carried',
      'source_nested_innocuous_widget_key',
      _sourceNestedInnocuousWidgetKey,
      null,
    ),
    (
      'a local constant key is carried',
      'local_const_key',
      _stateless('LocalConstKey', '''
    const key = ValueKey<String>('plan');
    return Text('Ready', key: key);'''),
      null,
    ),
    (
      'a top-level constant key is carried',
      'top_const_key',
      _stateless(
        'TopConstKey',
        "    return Text('Ready', key: _plan);",
        extraImports: "const _plan = ValueKey<String>('plan');\n",
      ),
      null,
    ),
    (
      'a static constant key is carried',
      'static_const_key',
      _stateless(
        'StaticConstKey',
        "    return Text('Ready', key: Keys.plan);",
        extraImports:
            "class Keys { static const plan = ValueKey<String>('plan'); }\n",
      ),
      null,
    ),
    (
      'a top-level constant key read through a local is carried',
      'top_const_key_local',
      _stateless(
        'TopConstKeyLocal',
        '''
    final key = _plan;
    return Text('Ready', key: key);''',
        extraImports: "const _plan = ValueKey<String>('plan');\n",
      ),
      null,
    ),
    (
      'a Key factory key is carried',
      'factory_key',
      _stateless(
        'FactoryKey',
        "    return Text('Ready', key: const Key('title'));",
      ),
      null,
    ),
    (
      'a static constant Key factory key is carried',
      'static_factory_key',
      _stateless(
        'StaticFactoryKey',
        "    return Text('Ready', key: Keys.title);",
        extraImports: "class Keys { static const title = Key('title'); }\n",
      ),
      null,
    ),
    (
      'a local constant Key factory key is carried',
      'local_factory_key',
      _stateless('LocalFactoryKey', '''
    const key = Key('title');
    return Text('Ready', key: key);'''),
      null,
    ),
    (
      'a value key built in a local is carried',
      'built_value_key',
      _stateless('BuiltValueKey', '''
    final key = ValueKey<String>('built');
    return Text('Ready', key: key);'''),
      null,
    ),
    (
      'an identity value key built in a local keeps its holder in the app',
      'identity_value_key',
      _stateless('IdentityValueKey', '''
    final key = ValueKey<Object>(Object());
    return Text('Ready', key: key);'''),
      'Text',
    ),
    (
      'a computed key read through a local keeps its holder in the app',
      'source_effectful_widget_key',
      _sourceEffectfulWidgetKey,
      'Text',
    ),
    (
      'a computed key read through a nested local keeps its holder in the app',
      'source_nested_effectful_widget_key',
      _sourceNestedEffectfulWidgetKey,
      'Text',
    ),
    (
      'a ValueKey formal given a local key keeps its holder in the app',
      'value_key_typed_widget_key',
      _valueKeyTypedWidgetKey,
      'ValueKeyHost',
    ),
    (
      'a Key-bounded formal given a local key keeps its holder in the app',
      'bounded_generic_widget_key',
      _boundedGenericWidgetKey,
      'GenericKeyHost',
    ),
  ]) {
    test(name, () async {
      final island = '${slug.replaceAll('_', '__')}_${holder}_0';
      expect(
        await _compiledText(slug, source),
        contains(
          holder == null
              ? 'widget Paywall = Text(text: "Ready", key: data.context._h'
              // A `Text` island delivers its positional `data`; the key
              // stays with its holder in the app.
              : 'widget Paywall = $island('
                    '${holder == 'Text' ? 'data: "Ready"' : ''});',
        ),
      );
    });
  }

  // A custom widget whose build the payload can't inline renders through its
  // registered factory, which runs its locals exactly as written.
  for (final (slug, name, fixture) in [
    (
      'custom_unread_innocuous',
      'CustomUnreadInnocuous',
      _customUnreadInnocuous,
    ),
    (
      'custom_unread_effectful',
      'CustomUnreadEffectful',
      _customUnreadEffectful,
    ),
    ('custom_key_innocuous', 'CustomKeyInnocuous', _customKeyInnocuous),
    ('custom_key_effectful', 'CustomKeyEffectful', _customKeyEffectful),
    (
      'custom_nested_key_innocuous',
      'CustomNestedKeyInnocuous',
      _customNestedKeyInnocuous,
    ),
    (
      'custom_nested_key_effectful',
      'CustomNestedKeyEffectful',
      _customNestedKeyEffectful,
    ),
    ('custom_grouped_final', 'CustomGroupedFinal', _customGroupedFinal),
    ('custom_grouped_const', 'CustomGroupedConst', _customGroupedConst),
    (
      'custom_missing_initializer',
      'CustomMissingInitializer',
      _customMissingInitializer,
    ),
    ('custom_late_final', 'CustomLateFinal', _customLateFinal),
    (
      'custom_literal_widget_key',
      'CustomLiteralWidgetKey',
      _customLiteralWidgetKey,
    ),
  ]) {
    test('$name renders through its registered factory', () async {
      final sources = {
        '$_package|lib/paywalls/$slug.dart': fixture.root,
        '$_package|lib/widgets/$slug.dart': fixture.widget,
      };
      final built = await testBuilders(
        [
          const UserCatalogJsonBuilder(BuilderOptions.empty),
          restageCodegenBuilder(BuilderOptions.empty),
        ],
        sources,
        rootPackage: _package,
        readerWriter: await _seeded(sources),
        flattenOutput: true,
      );
      expect(built.succeeded, isTrue, reason: built.errors.join('\n'));
      // Placed by name, so its State moves between the design and the app.
      expect(
        _text(built, slug),
        matches(
          RegExp(
            'widget Paywall = $name\\(restageIsland: "[^"]+_${name}_0"\\);',
          ),
        ),
      );
    });
  }

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

    test('carries the custom widget call-site key', () {
      expect(twins.succeeded, isTrue, reason: twins.errors.join('\n'));
      final dsl = _text(twins, 'promo_keyed');
      expect(dsl, contains('PromoCard(title: "Keyed", key: data.context._h'));
    });
  });
}
