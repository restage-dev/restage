@Timeout(Duration(minutes: 3))
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/navigation_recognition.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Navigation trigger recognition', () {
    test('recognises static Material Navigator.push expression body', () async {
      final outcome = recogniseNavigationTrigger(
        await _parseNavigationSlot('''
() => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(
    builder: (_) => const DetailsScreen(),
  ),
)
'''),
      );

      expect(outcome, isA<NavigationRecognised>());
      final navigation = (outcome as NavigationRecognised).navigation;
      expect(navigation.routeType, NavigationRouteType.materialPageRoute);
      expect(navigation.paywallSourceId, 'details');
      expect(_constructedTypeName(navigation.pushedScreen), 'DetailsScreen');
    });

    test('recognises Navigator.of(context).push block body', () async {
      final outcome = recogniseNavigationTrigger(
        await _parseNavigationSlot('''
() {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const DetailsScreen(),
    ),
  );
}
'''),
      );

      expect(outcome, isA<NavigationRecognised>());
      final navigation = (outcome as NavigationRecognised).navigation;
      expect(navigation.routeType, NavigationRouteType.materialPageRoute);
      expect(navigation.paywallSourceId, 'details');
    });

    test('recognises CupertinoPageRoute', () async {
      final outcome = recogniseNavigationTrigger(
        await _parseNavigationSlot('''
() => Navigator.push<void>(
  context,
  cupertino.CupertinoPageRoute<void>(
    builder: (_) => const DetailsScreen(),
  ),
)
'''),
      );

      expect(outcome, isA<NavigationRecognised>());
      final navigation = (outcome as NavigationRecognised).navigation;
      expect(navigation.routeType, NavigationRouteType.cupertinoPageRoute);
      expect(navigation.paywallSourceId, 'details');
    });

    test('recognises a prefixed Flutter Navigator receiver', () async {
      final outcome = recogniseNavigationTrigger(
        await _parseNavigationSlot('''
() => fw.Navigator.push<void>(
  context,
  MaterialPageRoute<void>(
    builder: (_) => const DetailsScreen(),
  ),
)
'''),
      );

      expect(outcome, isA<NavigationRecognised>());
      final navigation = (outcome as NavigationRecognised).navigation;
      expect(navigation.paywallSourceId, 'details');
    });

    test('recognises block-bodied route builder', () async {
      final outcome = recogniseNavigationTrigger(
        await _parseNavigationSlot('''
() => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(
    builder: (context) {
      return const DetailsScreen();
    },
  ),
)
'''),
      );

      expect(outcome, isA<NavigationRecognised>());
      final navigation = (outcome as NavigationRecognised).navigation;
      expect(_constructedTypeName(navigation.pushedScreen), 'DetailsScreen');
    });

    test('extracts @PaywallSource id from pushed screen construction',
        () async {
      final outcome = recogniseNavigationTrigger(
        await _parseNavigationSlot('''
() => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(
    builder: (_) => const DetailsScreen(),
  ),
)
'''),
      );

      expect(outcome, isA<NavigationRecognised>());
      final navigation = (outcome as NavigationRecognised).navigation;
      expect(pushedPaywallSourceId(navigation.pushedScreen), 'details');
    });

    test('resolves an omitted canonical @Paywall id through package authority',
        () async {
      final outcome = recogniseNavigationTrigger(
        await _parseNavigationSlot(
          '''
() => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(
    builder: (_) => const DetailsScreen(),
  ),
)
''',
          annotation: '@Paywall()',
        ),
        canonicalPaywallIdFor: (declaration) =>
            declaration.name == 'DetailsScreen' ? 'details' : null,
      );

      expect(outcome, isA<NavigationRecognised>());
      expect(
        (outcome as NavigationRecognised).navigation.paywallSourceId,
        'details',
      );
    });

    test('keeps an explicit canonical ID authoritative after a file move',
        () async {
      final outcome = recogniseNavigationTrigger(
        await _parseNavigationSlot(
          '''
() => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(
    builder: (_) => const DetailsScreen(),
  ),
)
''',
          annotation: "@Paywall(id: 'published_offer')",
        ),
        canonicalPaywallIdFor: (declaration) =>
            declaration.name == 'DetailsScreen' ? 'published_offer' : null,
      );

      expect(outcome, isA<NavigationRecognised>());
      expect(
        (outcome as NavigationRecognised).navigation.paywallSourceId,
        'published_offer',
      );
    });

    test('gives canonical and legacy pushed paywalls the same identity',
        () async {
      final legacy = recogniseNavigationTrigger(
        await _parseNavigationSlot('''
() => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(
    builder: (_) => const DetailsScreen(),
  ),
)
'''),
      );
      final canonical = recogniseNavigationTrigger(
        await _parseNavigationSlot(
          '''
() => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(
    builder: (_) => const DetailsScreen(),
  ),
)
''',
          annotation: '@Paywall()',
        ),
        canonicalPaywallIdFor: (declaration) =>
            declaration.name == 'DetailsScreen' ? 'details' : null,
      );

      expect(legacy, isA<NavigationRecognised>());
      expect(canonical, isA<NavigationRecognised>());
      expect(
        (canonical as NavigationRecognised).navigation.paywallSourceId,
        (legacy as NavigationRecognised).navigation.paywallSourceId,
      );
    });

    test('rejects a resolved local @Paywall lookalike', () async {
      final outcome = recogniseNavigationTrigger(
        await _parseNavigationSlot(
          '''
() => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(
    builder: (_) => const DetailsScreen(),
  ),
)
''',
          annotation: '@Paywall()',
          includeRestageImport: false,
          declarations: '''
class Paywall {
  const Paywall();
}
''',
        ),
        canonicalPaywallIdFor: (_) => 'poisoned',
      );

      expect(outcome, isA<NavigationFormUnsupported>());
      expect(
        (outcome as NavigationFormUnsupported).reason,
        kNavigationPushedScreenUnsupportedReason,
      );
    });
  });

  group('Navigator pop-back recognition', () {
    test('recognises sync zero-arg callback to Navigator.pop(context)',
        () async {
      final outcome = recogniseNavigatorPopBack(
        await _parseNavigationSlot('() => Navigator.pop(context)'),
      );

      expect(outcome, isA<NavigatorPopBackRecognised>());
    });

    test('does not recognise pop through a root navigator context', () async {
      final outcome = recogniseNavigatorPopBack(
        await _parseNavigationSlot(
          '() => Navigator.pop(navKey.currentContext!)',
        ),
      );

      expect(outcome, isA<NavigatorPopNotRecognised>());
    });

    test('rejects Navigator.pop(context, result) as result-bearing', () async {
      final outcome = recogniseNavigatorPopBack(
        await _parseNavigationSlot('() => Navigator.pop(context, result)'),
      );

      expect(outcome, isA<NavigatorPopResultUnsupported>());
      expect(
        (outcome as NavigatorPopResultUnsupported).reason,
        kNavigationNavigatorPopResultReason,
      );
    });

    test('does not recognise non-pop callbacks', () async {
      final outcome = recogniseNavigatorPopBack(
        await _parseNavigationSlot("() => debugPrint('tap')"),
      );

      expect(outcome, isA<NavigatorPopNotRecognised>());
    });
  });
}

Future<Expression> _parseNavigationSlot(
  String expression, {
  String annotation = "@PaywallSource(id: 'details')",
  bool includeRestageImport = true,
  String declarations = '',
}) {
  return parseExpressionFromSourceForTest(
    '''
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/widgets.dart' as fw;
${includeRestageImport ? "import 'package:restage/restage.dart';" : ''}

$declarations

$annotation
class DetailsScreen extends StatelessWidget {
  const DetailsScreen();
  Widget build(BuildContext context) => const SizedBox();
}

class PlainScreen extends StatelessWidget {
  const PlainScreen();
  Widget build(BuildContext context) => const SizedBox();
}

Widget screenFactory() => const DetailsScreen();

Route<void> restorableRouteBuilder(BuildContext context, Object? arguments) =>
    MaterialPageRoute<void>(builder: (_) => const DetailsScreen());

final navKey = GlobalKey<NavigatorState>();

Object x(
  BuildContext context, {
  bool condition = false,
  Route<void>? route,
  Object? result,
}) => $expression;
''',
    rootPackage: 'apps_examples',
  );
}

String _constructedTypeName(InstanceCreationExpression expression) =>
    expression.constructorName.type.name.lexeme;
