@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:collection/collection.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/production_helpers.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
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

    test('event-name census includes custom static string constants', () async {
      final translation = await _translateEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

class Alignment {
  static const String nav = 'restageNav0';
}

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
      onPressed: paywallEvent(Alignment.nav),
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
      expect(translation.navigation, isNotNull);
      expect(translation.navigation!.transitions.single.event, 'restageNav1');
    });

    test('an event inside a build local reserves its authored name', () async {
      final translation = await _translateBuildEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context) {
  final terms = ElevatedButton(
    onPressed: paywallEvent('restageNav0'),
    child: const Text('Terms'),
  );
  return Column(
    children: [
      terms,
      ElevatedButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
        ),
        child: const Text('Choose'),
      ),
      ElevatedButton(
        onPressed: paywallEvent('skip'),
        child: const Text('Dismiss'),
      ),
    ],
  );
}
''');

      expect(translation.issues, isEmpty);
      expect(
        RegExp(r'event "restageNav0" \{\}').allMatches(translation.dsl),
        hasLength(1),
      );
      expect(
        RegExp(r'event "restageNav1" \{\}').allMatches(translation.dsl),
        hasLength(1),
      );
      expect(translation.dsl, contains('event "skip" {}'));
      expect(translation.dsl, contains('Text(text: "Terms")'));
      expect(translation.dsl, contains('Text(text: "Choose")'));
      expect(translation.dsl, contains('Text(text: "Dismiss")'));
      expect(translation.navigation!.transitions.single.event, 'restageNav1');
      expect(
        translation.navigation!.transitions.single.pushedId,
        'choose_plan',
      );
    });

    test('an inlined action reserves its authored navigation name', () async {
      final translation = await _translateCustomBuildEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'TermsAction',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'terms action',
)
class TermsAction extends StatelessWidget {
  const TermsAction();

  Widget build(BuildContext context) => ElevatedButton(
    onPressed: paywallEvent('restageNav0'),
    child: const Text('Terms'),
  );
}

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context) => Column(
  children: [
    const TermsAction(),
    ElevatedButton(
      onPressed: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
      ),
      child: const Text('Choose'),
    ),
    ElevatedButton(
      onPressed: paywallEvent('skip'),
      child: const Text('Dismiss'),
    ),
  ],
);
''');

      expect(translation.issues, isEmpty);
      final emitted = [
        ...translation.widgetDefinitions.values,
        translation.dsl,
      ].join('\n');
      expect(
        (
          event: translation.navigation!.transitions.single.event,
          authoredHandlers:
              RegExp(r'event "restageNav0" \{\}').allMatches(emitted).length,
          generatedHandlers:
              RegExp(r'event "restageNav1" \{\}').allMatches(emitted).length,
        ),
        (event: 'restageNav1', authoredHandlers: 1, generatedHandlers: 1),
      );
    });

    test('a false collection branch leaves the first navigation name free',
        () async {
      final translation = await _translateCustomBuildEntry(
        _navigationActionSource('''
Column(
  children: [
    if (false)
      ElevatedButton(
        onPressed: paywallEvent('restageNav0'),
        child: const Text('Hidden'),
      ),
    const Text('Terms'),
  ],
)
'''),
      );

      expect(translation.issues, isEmpty);
      final definition = translation.widgetDefinitions['TermsAction']!;
      expect(
        (
          definition: definition,
          authoredHandlers:
              RegExp(r'event "restageNav0" \{\}').allMatches(definition).length,
          generatedHandlers: RegExp(r'event "restageNav0" \{\}')
              .allMatches(translation.dsl)
              .length,
          nextHandlers: RegExp(r'event "restageNav1" \{\}')
              .allMatches(translation.dsl)
              .length,
          event: translation.navigation!.transitions.single.event,
        ),
        (
          definition: 'Column(children: [Text(text: "Terms")])',
          authoredHandlers: 0,
          generatedHandlers: 1,
          nextHandlers: 0,
          event: 'restageNav0',
        ),
      );
    });

    test('a true collection branch reserves its authored navigation name',
        () async {
      final translation = await _translateCustomBuildEntry(
        _navigationActionSource('''
Column(
  children: [
    if (true)
      ElevatedButton(
        onPressed: paywallEvent('restageNav0'),
        child: const Text('Terms'),
      ),
  ],
)
'''),
      );

      expect(translation.issues, isEmpty);
      final definition = translation.widgetDefinitions['TermsAction']!;
      expect(
        (
          definition: definition,
          authoredHandlers:
              RegExp(r'event "restageNav0" \{\}').allMatches(definition).length,
          generatedHandlers: RegExp(r'event "restageNav1" \{\}')
              .allMatches(translation.dsl)
              .length,
          event: translation.navigation!.transitions.single.event,
        ),
        (
          definition: 'Column(children: [ElevatedButton(onPressed: event '
              '"restageNav0" {}, child: Text(text: "Terms"))])',
          authoredHandlers: 1,
          generatedHandlers: 1,
          event: 'restageNav1',
        ),
      );
    });

    test('a collection branch reserves only its selected event name', () async {
      final translation = await _translateCustomBuildEntry(
        _navigationActionSource('''
Column(
  children: [
    if (false)
      ElevatedButton(
        onPressed: paywallEvent('restageNav0'),
        child: const Text('First'),
      )
    else
      ElevatedButton(
        onPressed: paywallEvent('restageNav2'),
        child: const Text('Second'),
      ),
  ],
)
'''),
      );

      expect(translation.issues, isEmpty);
      final definition = translation.widgetDefinitions['TermsAction']!;
      expect(
        (
          definition: definition,
          firstHandlers:
              RegExp(r'event "restageNav0" \{\}').allMatches(definition).length,
          selectedHandlers:
              RegExp(r'event "restageNav2" \{\}').allMatches(definition).length,
          generatedHandlers: RegExp(r'event "restageNav0" \{\}')
              .allMatches(translation.dsl)
              .length,
          event: translation.navigation!.transitions.single.event,
        ),
        (
          definition: 'Column(children: [ElevatedButton(onPressed: event '
              '"restageNav2" {}, child: Text(text: "Second"))])',
          firstHandlers: 0,
          selectedHandlers: 1,
          generatedHandlers: 1,
          event: 'restageNav0',
        ),
      );
    });

    test('static spread and for leaves reserve their authored names', () async {
      final translation = await _translateCustomBuildEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'TermsAction',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'terms action',
)
class TermsAction extends StatelessWidget {
  const TermsAction();

  Widget build(BuildContext context) => ElevatedButton(
    onPressed: paywallEvent('restageNav1'),
    child: const Text('Terms'),
  );
}

@RestageWidget(
  name: 'TermsGroup',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'terms group',
)
class TermsGroup extends StatelessWidget {
  const TermsGroup();

  Widget build(BuildContext context) => Column(
    children: [
      ...<Widget>[
        ElevatedButton(
          onPressed: paywallEvent('restageNav0'),
          child: const Text('Spread'),
        ),
      ],
      for (final action in const <Widget>[TermsAction()]) action,
    ],
  );
}

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context) => Column(
  children: [
    const TermsGroup(),
    ElevatedButton(
      onPressed: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
      ),
      child: const Text('Choose'),
    ),
    ElevatedButton(
      onPressed: paywallEvent('skip'),
      child: const Text('Dismiss'),
    ),
  ],
);
''');

      expect(translation.issues, isEmpty);
      expect(
        (
          spreadHandlers: RegExp(r'event "restageNav0" \{\}')
              .allMatches(translation.widgetDefinitions['TermsGroup']!)
              .length,
          loopHandlers: RegExp(r'event "restageNav1" \{\}')
              .allMatches(translation.widgetDefinitions['TermsAction']!)
              .length,
          generatedHandlers: RegExp(r'event "restageNav2" \{\}')
              .allMatches(translation.dsl)
              .length,
          event: translation.navigation!.transitions.single.event,
        ),
        (
          spreadHandlers: 1,
          loopHandlers: 1,
          generatedHandlers: 1,
          event: 'restageNav2',
        ),
      );
    });

    test('a nested action reached through a helper list reserves its name',
        () async {
      final translation = await _translateCustomBuildEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'TermsAction',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'terms action',
)
class TermsAction extends StatelessWidget {
  const TermsAction();

  Widget build(BuildContext context) => ElevatedButton(
    onPressed: paywallEvent('restageNav0'),
    child: const Text('Terms'),
  );
}

@RestageWidget(
  name: 'TermsGroup',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.layout,
  description: 'terms group',
)
class TermsGroup extends StatelessWidget {
  const TermsGroup();

  Widget action() => const TermsAction();

  Widget build(BuildContext context) {
    final actions = <Widget>[action()];
    return Column(children: actions);
  }
}

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context) => Column(
  children: [
    const TermsGroup(),
    ElevatedButton(
      onPressed: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
      ),
      child: const Text('Choose'),
    ),
    ElevatedButton(
      onPressed: paywallEvent('skip'),
      child: const Text('Dismiss'),
    ),
  ],
);
''');

      expect(translation.issues, isEmpty);
      expect(
        translation.widgetDefinitions['TermsAction'],
        contains('event "restageNav0" {}'),
      );
      expect(translation.widgetDefinitions, contains('TermsGroup'));
      expect(translation.navigation!.transitions.single.event, 'restageNav1');
    });

    test('an unused inlined action does not reserve a navigation name',
        () async {
      final translation = await _translateCustomBuildEntry(
        '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'UnusedAction',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'unused action',
)
class UnusedAction extends StatelessWidget {
  const UnusedAction();

  Widget build(BuildContext context) => ElevatedButton(
    onPressed: paywallEvent('restageNav0'),
    child: const Text('Unused'),
  );
}

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
      onPressed: paywallEvent('skip'),
      child: const Text('Dismiss'),
    ),
  ],
);

Object unused() => const UnusedAction();
''',
        additionalFunctions: const ['unused'],
      );

      expect(translation.issues, isEmpty);
      expect(translation.widgetDefinitions, isEmpty);
      expect(translation.navigation!.transitions.single.event, 'restageNav0');
    });

    test('a parenthesized final chain reserves the exact shadowed name',
        () async {
      final translation = await _translateBuildEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

const eventName = 'restageNav9';

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context) {
  const seed = 'restageNav0';
  final eventName = (seed);
  final chainedName = ((eventName));
  return Column(
    children: [
      ElevatedButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
        ),
        child: const Text('Choose'),
      ),
      ElevatedButton(
        onPressed: paywallEvent(chainedName),
        child: const Text('Terms'),
      ),
      ElevatedButton(
        onPressed: paywallEvent('skip'),
        child: const Text('Dismiss'),
      ),
    ],
  );
}
''');

      expect(translation.issues, isEmpty);
      expect(
        RegExp(r'event "restageNav0" \{\}').allMatches(translation.dsl),
        hasLength(1),
      );
      expect(
        RegExp(r'event "restageNav1" \{\}').allMatches(translation.dsl),
        hasLength(1),
      );
      expect(translation.dsl, isNot(contains('restageNav9')));
      expect(translation.navigation!.transitions.single.event, 'restageNav1');
    });

    test('bound event names match inline navigation bytes', () async {
      const skin = '''
class Skin {
  const Skin({required this.prefix});
  final String prefix;
}
const skin = Skin(prefix: 'restage');
''';
      for (final (declarations, prelude, inlineName)
          in <(String, String, String)>[
        (
          '',
          "final prefix = 'restage';\n"
              "final eventName = prefix + 'Nav0';",
          "'restage' + 'Nav0'",
        ),
        (
          skin,
          'final selected = skin;\n'
              "final eventName = selected.prefix + 'Nav0';",
          "skin.prefix + 'Nav0'",
        ),
      ]) {
        final bound = await _translateBuildEntry(
          _paywallSourceWithRoot(
            _eventNavigationRoot('eventName'),
            declarations: declarations,
            prelude: prelude,
          ),
        );
        final inline = await _translateBuildEntry(
          _paywallSourceWithRoot(
            _eventNavigationRoot(inlineName),
            declarations: declarations,
          ),
        );

        expect(bound.issues, isEmpty);
        expect(inline.issues, isEmpty);
        expect(utf8.encode(bound.dsl), utf8.encode(inline.dsl));
        expect(
          RegExp(r'event "restageNav0" \{\}').allMatches(bound.dsl),
          hasLength(1),
        );
        expect(
          RegExp(r'event "restageNav1" \{\}').allMatches(bound.dsl),
          hasLength(1),
        );
        expect(bound.navigation!.transitions.single.event, 'restageNav1');
        expect(
          inline.navigation!.transitions.single.event,
          bound.navigation!.transitions.single.event,
        );
      }
    });

    test('reserved event names keep their diagnostic through bindings',
        () async {
      final inline = await _translateBuildEntry(
        _paywallSourceWithRoot(
          _eventButton("false ? 'continue' : 'restore'"),
        ),
      );
      final local = await _translateBuildEntry(
        _paywallSourceWithRoot(
          _eventButton('eventName'),
          prelude: "final eventName = false ? 'continue' : 'restore';",
        ),
      );
      final formal = await _translateCustomBuildEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'RestoreHelperAction',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'Restore helper action',
)
class RestoreHelperAction extends StatelessWidget {
  const RestoreHelperAction();

  Widget action(String eventName) => ElevatedButton(
    onPressed: paywallEvent(eventName),
    child: const Text('Restore'),
  );

  Widget build(BuildContext context) =>
      action(false ? 'continue' : 'restore');
}

Object x(BuildContext context) => const RestoreHelperAction();
''');
      final inlined = await _translateCustomBuildEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'RestoreAction',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'Restore action',
)
class RestoreAction extends StatelessWidget {
  const RestoreAction();

  Widget build(BuildContext context) {
    final eventName = false ? 'continue' : 'restore';
    return ElevatedButton(
      onPressed: paywallEvent(eventName),
      child: const Text('Restore'),
    );
  }
}

Object x(BuildContext context) => const RestoreAction();
''');

      const expectedMessage =
          "The authored commerce event 'restore' is unsupported. Authored "
          'surfaces cannot initiate purchases or restores. Applications '
          'invoke the typed commerce boundary from explicit host-controlled '
          'code. The current facade is unavailable until activated.';
      expect(
        [
          for (final (name, result) in <(String, TranslationResult)>[
            ('inline', inline),
            ('local', local),
            ('formal', formal),
            ('inlined', inlined),
          ])
            (
              name,
              result.dsl,
              result.issues.single.code,
              result.issues.single.message,
            ),
        ],
        [
          for (final name in <String>['inline', 'local', 'formal', 'inlined'])
            (
              name,
              '',
              IssueCode.unsupportedCommerceAuthoring,
              expectedMessage,
            ),
        ],
      );
    });

    test('runtime and conditional event-name values refuse identically',
        () async {
      for (final initializer in <String>[
        'runtimeName()',
        "true ? 'first' : 'second'",
        r"'${'custom'}Event'",
      ]) {
        final translation = await _translateBuildEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

String runtimeName() => 'runtime';

Object x(BuildContext context) {
  final name = $initializer;
  return ElevatedButton(
    onPressed: paywallEvent(name),
    child: const Text('Go'),
  );
}
''');

        expect(translation.dsl, isEmpty, reason: initializer);
        expect(translation.issues, hasLength(1), reason: initializer);
        expect(
          (translation.issues.single.code, translation.issues.single.message),
          (
            IssueCode.unrecognizedMethodCall,
            'paywallEvent requires a statically resolved String name.',
          ),
          reason: initializer,
        );
      }
    });

    test('a dismiss event inside a build local terminates navigation',
        () async {
      final translation = await _translateBuildEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context) {
  final dismiss = ElevatedButton(
    onPressed: paywallEvent('skip'),
    child: const Text('Dismiss'),
  );
  return Column(
    children: [
      ElevatedButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
        ),
        child: const Text('Choose'),
      ),
      dismiss,
    ],
  );
}
''');

      expect(translation.issues, isEmpty);
      expect(translation.dsl, contains('event "restageNav0" {}'));
      expect(translation.dsl, contains('event "skip" {}'));
      expect(translation.dsl, contains('Text(text: "Choose")'));
      expect(translation.dsl, contains('Text(text: "Dismiss")'));
      expect(translation.navigation!.transitions.single.event, 'restageNav0');
      expect(translation.navigation!.terminatingEvent, 'skip');
    });

    test('a navigation trigger held in a build local refuses', () async {
      final translation = await _translateBuildEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context) {
  final next = ElevatedButton(
    onPressed: () => Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
    ),
    child: const Text('Choose'),
  );
  return Column(
    children: [
      next,
      ElevatedButton(
        onPressed: paywallEvent('skip'),
        child: const Text('Dismiss'),
      ),
    ],
  );
}
''');

      expect(translation.dsl, isEmpty);
      expect(
        translation.issues.map((issue) => issue.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      expect(translation.navigation, isNull);
    });

    test('a modal trigger held in a build local refuses', () async {
      final translation = await _translateBuildEntry('''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

Object x(BuildContext context) {
  final open = ElevatedButton(
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(),
    ),
    child: const Text('Open'),
  );
  return Column(children: [open]);
}
''');

      expect(translation.dsl, isEmpty);
      expect(
        translation.issues.map((issue) => issue.code),
        contains(IssueCode.unrecognizedMethodCall),
      );
      expect(translation.navigation, isNull);
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

    test('canonical pushed paywalls lower identically to legacy sources',
        () async {
      const root = '''
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
''';
      final legacy = await _translateEntry(_paywallSourceWithRoot(root));
      final canonical = await _translateEntry(
        _paywallSourceWithRoot(root, annotation: '@Paywall()'),
        canonicalPaywallIdFor: (declaration) =>
            declaration.name == 'ChoosePlan' ? 'choose_plan' : null,
      );

      expect(canonical.issues, legacy.issues);
      expect(canonical.suppressed, legacy.suppressed);
      expect(canonical.dsl, legacy.dsl);
      expect(canonical.navigation?.entryId, legacy.navigation?.entryId);
      expect(
        [
          for (final transition in canonical.navigation!.transitions)
            (transition.event, transition.pushedId),
        ],
        [
          for (final transition in legacy.navigation!.transitions)
            (transition.event, transition.pushedId),
        ],
      );
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
    test('emits the navplan JSON for a lowered root push', () async {
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
          'apps_examples|assets/paywalls/screens/paywall_entry.capability.json':
              anything,
          'apps_examples|assets/paywalls/screens/paywall_entry.rfw': isNotEmpty,
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
          'apps_examples|assets/paywalls/screens/paywall_entry.capability.json':
              anything,
          'apps_examples|assets/paywalls/screens/paywall_entry.rfw':
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
  String? Function(ClassElement declaration)? canonicalPaywallIdFor,
}) async {
  final parsed = await _parseEntryRoot(source);
  return ExpressionTranslator(
    catalog: _navigationCatalog,
    helpers: productionPaywallHelperRegistry(),
    canonicalPaywallIdFor: canonicalPaywallIdFor,
  ).translate(
    parsed.rootExpression,
    entryId: 'entry',
    buildContextParameter: parsed.buildContextParameter,
    flowScreenContext: flowScreenContext,
  );
}

Future<TranslationResult> _translateBuildEntry(String source) async {
  final parsed = await _parseEntryBuildRoot(source);
  return ExpressionTranslator(
    catalog: _navigationCatalog,
    helpers: productionPaywallHelperRegistry(),
  ).translate(
    parsed.rootExpression,
    entryId: 'entry',
    buildContextParameter: parsed.buildContextParameter,
    rootLocalBindings: parsed.localBindings,
  );
}

Future<TranslationResult> _translateCustomBuildEntry(
  String source, {
  List<String> additionalFunctions = const [],
}) async {
  final assetId = AssetId('apps_examples', 'lib/navigation_widget_probe.dart');
  late final LibraryElement library;
  late final ResolvedLibraryResult resolved;
  await resolveSources(
    {assetId.toString(): source},
    (resolver) async {
      library = await resolver.libraryFor(assetId);
      final result = await library.session.getResolvedLibraryByElement(library);
      if (result is! ResolvedLibraryResult) {
        throw StateError('Navigation widget fixture did not resolve.');
      }
      resolved = result;
    },
    resolverFor: assetId.toString(),
    rootPackage: assetId.package,
    readAllSourcesFromFilesystem: true,
  );

  ({
    Expression rootExpression,
    Element? buildContextParameter,
    Map<Element, Expression> localBindings,
  }) functionBuild(String name) {
    final function = library.topLevelFunctions.singleWhere(
      (element) => element.name == name,
    );
    final node = resolved.getFragmentDeclaration(function.firstFragment)?.node;
    if (node is! FunctionDeclaration) {
      throw StateError('Navigation widget fixture has no $name() declaration.');
    }
    final extracted = extractInlinableBuildBody(node.functionExpression.body);
    if (extracted == null) {
      throw StateError('Navigation widget fixture has no $name() value.');
    }
    final parameters = node.functionExpression.parameters?.parameters ??
        const <FormalParameter>[];
    final contextParameter = parameters
        .where((parameter) => parameter.name?.lexeme == 'context')
        .firstOrNull;
    return (
      rootExpression: extracted.expression,
      buildContextParameter: contextParameter?.declaredFragment?.element,
      localBindings: extracted.localBindings,
    );
  }

  final entry = functionBuild('x');
  final otherEntries = additionalFunctions.map(functionBuild).toList();
  final helpers = productionPaywallHelperRegistry();
  final classification = await classifyReferencedCustomWidgets(
    rootExpressions: [
      entry.rootExpression,
      ...entry.localBindings.values,
      for (final other in otherEntries) ...[
        other.rootExpression,
        ...other.localBindings.values,
      ],
    ],
    catalog: _navigationCatalog,
    helpers: helpers,
    astNodeFor: (fragment) async =>
        resolved.getFragmentDeclaration(fragment)?.node,
  );
  return ExpressionTranslator(
    catalog: _navigationCatalog,
    helpers: helpers,
    customWidgetClassifications: classification.classifications,
    customWidgetBlueprints: classification.blueprints,
  ).translate(
    entry.rootExpression,
    entryId: 'entry',
    buildContextParameter: entry.buildContextParameter,
    rootLocalBindings: entry.localBindings,
  );
}

String _navigationActionSource(String body) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'TermsAction',
  library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.input,
  description: 'terms action',
)
class TermsAction extends StatelessWidget {
  const TermsAction();

  Widget build(BuildContext context) => $body;
}

@PaywallSource(id: 'choose_plan')
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context) => Column(
  children: [
    const TermsAction(),
    ElevatedButton(
      onPressed: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (_) => const ChoosePlan()),
      ),
      child: const Text('Choose'),
    ),
    ElevatedButton(
      onPressed: paywallEvent('skip'),
      child: const Text('Dismiss'),
    ),
  ],
);
''';

Future<
    ({
      Expression rootExpression,
      Element? buildContextParameter,
      Map<Element, Expression> localBindings,
    })> _parseEntryBuildRoot(String source) async {
  final assetId = AssetId('apps_examples', 'lib/navigation_build_probe.dart');
  late final LibraryElement library;
  late final ResolvedLibraryResult resolved;
  await resolveSources(
    {assetId.toString(): source},
    (resolver) async {
      library = await resolver.libraryFor(assetId);
      final result = await library.session.getResolvedLibraryByElement(library);
      if (result is! ResolvedLibraryResult) {
        throw StateError('Navigation fixture did not resolve.');
      }
      resolved = result;
    },
    resolverFor: assetId.toString(),
    rootPackage: assetId.package,
    readAllSourcesFromFilesystem: true,
  );
  final function = library.topLevelFunctions.singleWhere(
    (element) => element.name == 'x',
  );
  final node = resolved.getFragmentDeclaration(function.firstFragment)?.node;
  if (node is! FunctionDeclaration) {
    throw StateError('Navigation fixture has no resolved x() declaration.');
  }
  final extracted = extractInlinableBuildBody(node.functionExpression.body);
  if (extracted == null) {
    throw StateError('Navigation fixture has no supported build body.');
  }
  final parameters = node.functionExpression.parameters?.parameters ??
      const <FormalParameter>[];
  final contextParameter = parameters
      .where((parameter) => parameter.name?.lexeme == 'context')
      .firstOrNull;
  return (
    rootExpression: extracted.expression,
    buildContextParameter: contextParameter?.declaredFragment?.element,
    localBindings: extracted.localBindings,
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

String _paywallSourceWithRoot(
  String rootExpression, {
  String annotation = "@PaywallSource(id: 'choose_plan')",
  String declarations = '',
  String prelude = '',
}) {
  final function = prelude.isEmpty
      ? 'Object x(BuildContext context) => $rootExpression;'
      : '''
Object x(BuildContext context) {
$prelude
  return $rootExpression;
}
''';
  return '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

$declarations
$annotation
class ChoosePlan extends StatelessWidget {
  const ChoosePlan();
  Widget build(BuildContext context) => const SizedBox();
}

$function
''';
}

String _eventNavigationRoot(String eventName) => '''
Column(children: [
  ElevatedButton(
    onPressed: () => Navigator.push<void>(context,
      MaterialPageRoute<void>(builder: (_) => const ChoosePlan())),
    child: const Text('Choose')),
  ElevatedButton(onPressed: paywallEvent($eventName),
    child: const Text('Terms')),
  ElevatedButton(onPressed: paywallEvent('skip'),
    child: const Text('Dismiss')),
])
''';

String _eventButton(String eventName) => '''
ElevatedButton(
  onPressed: paywallEvent($eventName),
  child: const Text('Restore'),
)
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
      flutterType:
          'package:flutter/src/material/elevated_button.dart#ElevatedButton',
    ),
    entry(
      name: 'GestureDetector',
      properties: [
        prop('onTap', PropertyType.event),
        prop('child', PropertyType.widget),
      ],
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
