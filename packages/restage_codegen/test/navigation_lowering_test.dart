@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:collection/collection.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/production_helpers.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Navigation lowering translation', () {
    test(
        'a const-object-field event name is collected so the synthetic nav '
        'minter does not reuse it', () async {
      // The authored `paywallEvent(_skin.nav)` folds to 'restageNav0'. The
      // scanner must see that folded name (via the unified scalar boundary) so
      // the synthetic nav-event minter avoids it and picks the next free slot —
      // otherwise an authored button and the navigation trigger collide on the
      // same event.
      final translation = await _translateEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

class Skin {
  const Skin({required this.nav});
  final String nav;
}

const _skin = Skin(nav: 'restageNav0');

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context) => Column(
  children: [
    ElevatedButton(
      onPressed: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
      ),
      child: const Text('Choose'),
    ),
    ElevatedButton(
      onPressed: paywallEvent(_skin.nav),
      child: const Text('Terms'),
    ),
    ElevatedButton(
      onPressed: paywallEvent('skip'),
      child: const Text('Skip'),
    ),
  ],
);
''');
      expect(translation.issues, isEmpty);
      // Authored event name (folded from the const-object field) is present…
      expect(translation.dsl, contains('event "restageNav0" {}'));
      // …and the navigation transition fires on a DIFFERENT, minted event —
      // the minter avoided the authored name rather than colliding on it.
      expect(translation.navigation, isNotNull);
      expect(translation.navigation!.transitions, hasLength(1));
      expect(translation.navigation!.transitions.single.event, 'restageNav1');
    });

    test('root push rewrites both artifacts and exposes a navigation plan',
        () async {
      final standalone = await _translateEntry(
        _paywallSourceWithRoot('''
Column(
  children: [
    ElevatedButton(
      onPressed: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
      ),
      child: const Text('Choose'),
    ),
    ElevatedButton(
      onPressed: paywallEvent('skip'),
      child: const Text('Skip'),
    ),
  ],
)
'''),
      );
      final adapter = await _translateEntry(
        _paywallSourceWithRoot('''
Column(
  children: [
    ElevatedButton(
      onPressed: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
      ),
      child: const Text('Choose'),
    ),
    ElevatedButton(
      onPressed: paywallEvent('skip'),
      child: const Text('Skip'),
    ),
  ],
)
'''),
        flowScreenContext: true,
      );

      for (final translation in [standalone, adapter]) {
        expect(translation.issues, isEmpty);
        expect(translation.dsl, contains('event "restageNav0" {}'));
        expect(translation.navigation, isNotNull);
        expect(translation.navigation!.entryId, 'entry');
        expect(translation.navigation!.terminatingEvent, 'skip');
        expect(translation.navigation!.transitions, hasLength(1));
        expect(
          translation.navigation!.transitions.single.event,
          'restageNav0',
        );
        expect(
          translation.navigation!.transitions.single.pushedId,
          'choose_plan',
        );
      }
    });

    test('Navigator.pop is back in the adapter and suppresses standalone',
        () async {
      final source = _paywallSourceWithRoot('''
GestureDetector(
  onTap: () => Navigator.pop(context),
  child: const Text('Back'),
)
''');

      final adapter = await _translateEntry(source, flowScreenContext: true);
      expect(adapter.issues, isEmpty);
      expect(adapter.dsl, contains('event "back" {}'));
      expect(adapter.navigation, isNull);
      expect(adapter.suppressed, isFalse);

      final standalone = await _translateEntry(source);
      expect(standalone.dsl, isEmpty);
      expect(standalone.suppressed, isTrue);
      expect(
        standalone.issues.map((issue) => issue.code),
        contains(IssueCode.navigationStandaloneArtifactSkipped),
      );
      expect(standalone.issues.single.code.isBuildNotice, isTrue);
      expect(
        standalone.issues.single.message,
        'this paywall uses an in-flow Navigator.pop (back); its standalone '
        'blob is not emitted — it renders as a flow screen. Use '
        "paywallEvent('close') for a standalone dismiss, or present it via "
        'a flow.',
      );
      expect(standalone.navigation, isNull);
    });

    test('const-authored events are skipped when minting navigation events',
        () async {
      final translation = await _translateEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

const authoredNav = 'restageNav0';

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context) => Column(
  children: [
    ElevatedButton(
      onPressed: paywallEvent(authoredNav),
      child: const Text('Author'),
    ),
    ElevatedButton(
      onPressed: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
      ),
      child: const Text('Choose'),
    ),
    ElevatedButton(
      onPressed: paywallEvent('skip'),
      child: const Text('Skip'),
    ),
  ],
);
''');

      expect(translation.issues, isEmpty);
      expect(translation.dsl, contains('event "restageNav0" {}'));
      expect(translation.dsl, contains('event "restageNav1" {}'));
      expect(translation.navigation, isNotNull);
      expect(translation.navigation!.transitions.single.event, 'restageNav1');
      expect(
        translation.navigation!.transitions.single.pushedId,
        'choose_plan',
      );
    });

    test('adapter pop through a root navigator context is not lowered',
        () async {
      final translation = await _translateEntry(
        '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

final navKey = GlobalKey<NavigatorState>();

Object x(BuildContext context) => GestureDetector(
  onTap: () => Navigator.pop(navKey.currentContext!),
  child: const Text('Back'),
);
''',
        flowScreenContext: true,
      );

      expect(translation.dsl, isEmpty);
      expect(translation.dsl, isNot(contains('event "back" {}')));
      expect(translation.issues, isNotEmpty);
      expect(translation.navigation, isNull);
    });

    test('adapter pop through a captured context fatal-defers', () async {
      final translation = await _translateEntry(
        '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

Object x(BuildContext context, BuildContext rootContext) => GestureDetector(
  onTap: () => Navigator.pop(rootContext),
  child: const Text('Back'),
);
''',
        flowScreenContext: true,
      );

      expect(translation.dsl, isEmpty);
      expect(
        translation.issues.map((issue) => issue.code),
        contains(IssueCode.navigationFormUnsupported),
      );
      expect(
        translation.issues.single.message,
        contains('non-build-context targets a different navigator'),
      );
      expect(translation.navigation, isNull);
    });

    test('a navigation paywall without skip fatal-defers', () async {
      final translation = await _translateEntry(
        _paywallSourceWithRoot('''
ElevatedButton(
  onPressed: () => Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
  ),
  child: const Text('Choose'),
)
'''),
      );

      expect(translation.dsl, isEmpty);
      expect(
        translation.issues.map((issue) => issue.code),
        contains(IssueCode.navigationFormUnsupported),
      );
      expect(translation.issues.single.message, contains('paywallEvent'));
      expect(translation.issues.single.message, contains('skip'));
      expect(translation.navigation, isNull);
    });

    test('an entry paywall Navigator.pop fatal-defers (not a flow back)',
        () async {
      final source = _paywallSourceWithRoot('''
Column(
  children: [
    ElevatedButton(
      onPressed: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
      ),
      child: const Text('Choose'),
    ),
    ElevatedButton(
      onPressed: paywallEvent('skip'),
      child: const Text('Skip'),
    ),
    ElevatedButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Close'),
    ),
  ],
)
''');

      // The paywall has a recognised push, so it is a flow ENTRY. Its
      // Navigator.pop is a host dismiss, not a flow back, and must fatal-defer
      // in BOTH artifacts rather than silently lower to a no-op `back`.
      for (final flowScreenContext in [true, false]) {
        final translation = await _translateEntry(
          source,
          flowScreenContext: flowScreenContext,
        );
        expect(
          translation.issues.map((issue) => issue.code),
          contains(IssueCode.navigationFormUnsupported),
          reason: 'entry pop must fatal-defer (flowScreenContext='
              '$flowScreenContext)',
        );
        expect(
          translation.issues.map((issue) => issue.message).join('\n'),
          contains("paywallEvent('skip')"),
        );
        expect(translation.dsl, isNot(contains('event "back"')));
      }
    });

    test('captured context identifiers do not satisfy the build context',
        () async {
      final translation = await _translateEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context, BuildContext rootContext) => Column(
  children: [
    ElevatedButton(
      onPressed: () => Navigator.push<void>(
        rootContext,
        MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
      ),
      child: const Text('Choose'),
    ),
    ElevatedButton(
      onPressed: paywallEvent('skip'),
      child: const Text('Skip'),
    ),
  ],
);
''');

      expect(translation.dsl, isEmpty);
      expect(
        translation.issues.map((issue) => issue.code),
        contains(IssueCode.navigationFormUnsupported),
      );
      expect(
        translation.issues.single.message,
        contains('build method BuildContext'),
      );
      expect(translation.navigation, isNull);
    });

    test('multiple pushes mint distinct events and transitions', () async {
      final translation = await _translateEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

@PaywallSource(id: 'confirm_plan')
class ConfirmPlan extends StatelessWidget {
  const ConfirmPlan();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context) => Column(
  children: [
    ElevatedButton(
      onPressed: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
      ),
      child: const Text('Choose'),
    ),
    ElevatedButton(
      onPressed: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const ConfirmPlan()),
      ),
      child: const Text('Confirm'),
    ),
    ElevatedButton(
      onPressed: paywallEvent('skip'),
      child: const Text('Skip'),
    ),
  ],
);
''');

      expect(translation.issues, isEmpty);
      expect(translation.dsl, contains('event "restageNav0" {}'));
      expect(translation.dsl, contains('event "restageNav1" {}'));
      expect(translation.navigation, isNotNull);
      expect(
        [
          for (final transition in translation.navigation!.transitions)
            (transition.event, transition.pushedId),
        ],
        [
          ('restageNav0', 'choose_plan'),
          ('restageNav1', 'confirm_plan'),
        ],
      );
    });

    test('non-navigation paywalls are identical across artifacts', () async {
      final source = _paywallSourceWithRoot('''
ElevatedButton(
  onPressed: paywallEvent('skip'),
  child: const Text('Skip'),
)
''');
      final standalone = await _translateEntry(source);
      final adapter = await _translateEntry(source, flowScreenContext: true);

      expect(standalone.issues, isEmpty);
      expect(adapter.issues, isEmpty);
      expect(adapter.dsl, standalone.dsl);
      expect(standalone.navigation, isNull);
      expect(adapter.navigation, isNull);
    });
  });

  group('Navigation lowering builder emission', () {
    test('emits the internal navplan JSON for a lowered root push', () async {
      const entrySource = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../screens/choose_plan.dart';

@PaywallSource(id: 'entry')
class EntryPaywall extends StatelessWidget {
  const EntryPaywall();

  Widget build(BuildContext context) => Column(
    children: [
      ElevatedButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
        ),
        child: const Text('Choose'),
      ),
      ElevatedButton(
        onPressed: paywallEvent('skip'),
        child: const Text('Skip'),
      ),
    ],
  );
}
''';
      const choosePlanSource = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}
''';
      final sources = {
        'apps_examples|lib/paywalls/entry.dart': entrySource,
        'apps_examples|lib/screens/choose_plan.dart': choosePlanSource,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      for (final entry in sources.entries) {
        readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
      }

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/entry.capability.json': anything,
          'apps_examples|assets/paywalls/entry.rfwtxt': decodedMatches(
            contains('event "restageNav0" {}'),
          ),
          'apps_examples|assets/paywalls/entry.rfw': isNotEmpty,
          'apps_examples|assets/onboarding/screens/paywall_entry.rfw':
              isNotEmpty,
          'apps_examples|assets/paywalls/entry.navplan.json':
              decodedMatches(const _NavPlanMatcher()),
        },
      );
    });

    test('captured context through the builder fatal-defers with no outputs',
        () async {
      const entrySource = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../screens/choose_plan.dart';

@PaywallSource(id: 'entry')
class EntryPaywall extends StatelessWidget {
  const EntryPaywall({required this.rootContext});
  final BuildContext rootContext;

  Widget build(BuildContext context) => Column(
    children: [
      ElevatedButton(
        onPressed: () => Navigator.push<void>(
          rootContext,
          MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
        ),
        child: const Text('Choose'),
      ),
      ElevatedButton(
        onPressed: paywallEvent('skip'),
        child: const Text('Skip'),
      ),
    ],
  );
}
''';
      const choosePlanSource = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}
''';
      final sources = {
        'apps_examples|lib/paywalls/entry.dart': entrySource,
        'apps_examples|lib/screens/choose_plan.dart': choosePlanSource,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      for (final entry in sources.entries) {
        readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
      }

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: const {},
      );
    });

    test('pop-only paywall emits adapter but suppresses standalone', () async {
      const entrySource = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'entry')
class EntryPaywall extends StatelessWidget {
  const EntryPaywall();

  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.pop(context),
    child: const Text('Back'),
  );
}
''';
      final sources = {'apps_examples|lib/paywalls/entry.dart': entrySource};
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      for (final entry in sources.entries) {
        readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
      }

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/onboarding/screens/paywall_entry.rfw':
              const _RfwBlobContainsMatcher('event back {}'),
        },
      );
    });
  });

  group('Navigation lowering classifier admission', () {
    test('navigation inside a custom widget fatal-defers loudly', () async {
      final result = await classifyFixtureResult(
        {
          'lib/navigation_custom_widget.dart': '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

@RestageWidget(
  name: 'NavButton',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'navigation button',
)
class NavButton extends StatelessWidget {
  const NavButton();

  Widget build(BuildContext context) => ElevatedButton(
    onPressed: () => Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
    ),
    child: const SizedBox(),
  );
}
''',
        },
        inputPath: 'lib/navigation_custom_widget.dart',
        widgetName: 'NavButton',
        catalog: _navigationCatalog,
      );
      const key =
          'package:apps_examples/navigation_custom_widget.dart#NavButton';
      final classification = result.classifications[key];

      expect(classification, isA<UnclassifiableWidget>());
      final unclassifiable = classification! as UnclassifiableWidget;
      expect(
        unclassifiable.diagnosticCode,
        IssueCode.navigationFormUnsupported,
      );
      expect(unclassifiable.reason, contains('paywall root'));
      expect(unclassifiable.reason, contains('custom widget'));
    });
  });
}

Future<TranslationResult> _translateEntry(
  String source, {
  bool flowScreenContext = false,
}) async {
  final parsed = await _parseEntryRoot(source);
  return ExpressionTranslator(
    catalog: _navigationCatalog,
    helpers: productionPaywallHelperRegistry(),
  ).translate(
    parsed.rootExpression,
    entryId: 'entry',
    buildContextParameter: parsed.buildContextParameter,
    flowScreenContext: flowScreenContext,
  );
}

Future<({Expression rootExpression, Element? buildContextParameter})>
    _parseEntryRoot(String source) async {
  final rootExpression = await parseExpressionFromSourceForTest(
    source,
    rootPackage: 'apps_examples',
  );
  AstNode? node = rootExpression;
  while (node != null && node is! FunctionDeclaration) {
    node = node.parent;
  }
  final declaration = node as FunctionDeclaration?;
  final parameters = declaration?.functionExpression.parameters?.parameters ??
      const <FormalParameter>[];
  final contextParameter = parameters
      .where((parameter) => parameter.name?.lexeme == 'context')
      .firstOrNull;
  return (
    rootExpression: rootExpression,
    buildContextParameter: contextParameter?.declaredFragment?.element,
  );
}

String _paywallSourceWithRoot(String rootExpression) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context) => $rootExpression;
''';

final Catalog _navigationCatalog = Catalog(
  schemaVersion: kSupportedSchemaVersion,
  generatedAt: '1970-01-01T00:00:00Z',
  libraries: <WidgetLibrary, LibraryInfo>{
    WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
    WidgetLibrary.material: const LibraryInfo(version: '0.1.0'),
  },
  widgets: [
    entry(
      name: 'Column',
      properties: [prop('children', PropertyType.widgetList)],
      childrenSlot: ChildrenSlot.list,
      flutterType: 'package:flutter/src/widgets/basic.dart#Column',
    ),
    entry(
      name: 'ElevatedButton',
      library: WidgetLibrary.material,
      properties: [
        prop('onPressed', PropertyType.event),
        prop('child', PropertyType.widget),
      ],
      fires: const [WidgetEventName.onPressed],
      flutterType:
          'package:flutter/src/material/elevated_button.dart#ElevatedButton',
    ),
    entry(
      name: 'GestureDetector',
      properties: [
        prop('onTap', PropertyType.event),
        prop('child', PropertyType.widget),
      ],
      fires: const [WidgetEventName.onTap],
      flutterType:
          'package:flutter/src/widgets/gesture_detector.dart#GestureDetector',
    ),
    entry(
      name: 'Text',
      properties: [prop('text', PropertyType.string, positional: true)],
      flutterType: 'package:flutter/src/widgets/text.dart#Text',
    ),
    entry(
      name: 'SizedBox',
      properties: const [],
      flutterType: 'package:flutter/src/widgets/basic.dart#SizedBox',
    ),
  ],
);

class _NavPlanMatcher extends Matcher {
  const _NavPlanMatcher();

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! String) return false;
    final Object? decoded;
    try {
      decoded = jsonDecode(item);
    } on FormatException catch (e) {
      matchState['error'] = e;
      return false;
    }
    const expected = {
      'entryId': 'entry',
      'transitions': [
        {'event': 'restageNav0', 'pushedId': 'choose_plan'},
      ],
      'terminatingEvent': 'skip',
    };
    if (decoded is! Map<String, dynamic>) return false;
    if (const DeepCollectionEquality().equals(decoded, expected)) return true;
    matchState['decoded'] = decoded;
    return false;
  }

  @override
  Description describe(Description description) {
    return description.add('a navigation plan JSON object for entry');
  }

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    if (matchState.containsKey('error')) {
      return mismatchDescription
          .add('failed to decode JSON: ')
          .addDescriptionOf(matchState['error']);
    }
    if (matchState.containsKey('decoded')) {
      return mismatchDescription
          .add('decoded to ')
          .addDescriptionOf(matchState['decoded']);
    }
    return mismatchDescription.add('was not a JSON string');
  }
}

class _RfwBlobContainsMatcher extends Matcher {
  const _RfwBlobContainsMatcher(this.expected);

  final String expected;

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! List<int>) return false;
    final library = fmt.decodeLibraryBlob(Uint8List.fromList(item));
    final source = library.toString();
    if (source.contains(expected)) return true;
    matchState['source'] = source;
    return false;
  }

  @override
  Description describe(Description description) {
    return description.add('an RFW blob containing ').addDescriptionOf(
          expected,
        );
  }

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    if (matchState.containsKey('source')) {
      return mismatchDescription
          .add('decoded to ')
          .addDescriptionOf(matchState['source']);
    }
    return mismatchDescription.add('was not RFW blob bytes');
  }
}
