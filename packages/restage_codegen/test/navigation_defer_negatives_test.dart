@Timeout(Duration(minutes: 3))
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/navigation_recognition.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Navigation fatal-defer negatives', () {
    for (final scenario in <({String name, String callback})>[
      (
        name: 'pushNamed',
        callback: "() => Navigator.pushNamed(context, '/details')",
      ),
      (
        name: 'pushReplacement',
        callback: '''
() => Navigator.pushReplacement<void, void>(
  context,
  MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
)
''',
      ),
      (
        name: 'pushReplacementNamed',
        callback: "() => Navigator.pushReplacementNamed(context, '/details')",
      ),
      (
        name: 'pushAndRemoveUntil',
        callback: '''
() => Navigator.pushAndRemoveUntil<void>(
  context,
  MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
  (_) => false,
)
''',
      ),
      (
        name: 'popUntil',
        callback: '() => Navigator.popUntil(context, (_) => false)',
      ),
      (
        name: 'restorablePush',
        callback: '''
() => Navigator.restorablePush<void>(
  context,
  restorableRouteBuilder,
)
''',
      ),
      (
        name: 'restorablePushNamed',
        callback: "() => Navigator.restorablePushNamed(context, '/details')",
      ),
      (
        name: 'restorablePushReplacement',
        callback: '''
() => Navigator.restorablePushReplacement<void, void>(
  context,
  restorableRouteBuilder,
)
''',
      ),
      (
        name: 'restorablePushReplacementNamed',
        callback:
            "() => Navigator.restorablePushReplacementNamed(context, '/details')",
      ),
      (
        name: 'restorablePushAndRemoveUntil',
        callback: '''
() => Navigator.restorablePushAndRemoveUntil<void>(
  context,
  restorableRouteBuilder,
  (_) => false,
)
''',
      ),
      (
        name: 'restorablePushNamedAndRemoveUntil',
        callback: '''
() => Navigator.restorablePushNamedAndRemoveUntil(
  context,
  '/details',
  (_) => false,
)
''',
      ),
    ]) {
      test('${scenario.name} fatal-defers as unsupported navigation form',
          () async {
        final outcome = recogniseNavigationTrigger(
          await _parseNavigationSlot(scenario.callback),
        );

        _expectNavigationUnsupported(outcome);
      });
    }

    for (final scenario in <({String name, String callback})>[
      (
        name: 'PageRouteBuilder',
        callback: '''
() => Navigator.push<void>(
  context,
  PageRouteBuilder<void>(
    pageBuilder: (_, __, ___) => const DetailsScreen(),
  ),
)
''',
      ),
      (
        name: 'captured route variable',
        callback: '() => Navigator.push<void>(context, route!)',
      ),
      (
        name: 'conditional route',
        callback: '''
() => Navigator.push<void>(
  context,
  condition
      ? MaterialPageRoute<void>(builder: (_) => const DetailsScreen())
      : MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
)
''',
      ),
    ]) {
      test('${scenario.name} fatal-defers as unsupported route', () async {
        final outcome = recogniseNavigationTrigger(
          await _parseNavigationSlot(scenario.callback),
        );

        _expectNavigationUnsupported(outcome);
      });
    }

    test('customized route argument fatal-defers', () async {
      final outcome = recogniseNavigationTrigger(
        await _parseNavigationSlot('''
() => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => const DetailsScreen(),
  ),
)
'''),
      );

      _expectNavigationUnsupported(
        outcome,
        messageContains: 'fullscreenDialog',
      );
    });

    for (final scenario in <({String name, String routeBuilder})>[
      (
        name: 'context-reading builder',
        routeBuilder: 'builder: (context) => Text(context.toString())',
      ),
      (
        name: 'conditional builder',
        routeBuilder: '''
builder: (_) => condition
    ? const DetailsScreen()
    : const DetailsScreen()
''',
      ),
      (
        name: 'non-construction builder',
        routeBuilder: 'builder: (_) => screenFactory()',
      ),
      (
        name: 'wrong builder arity',
        routeBuilder: 'builder: () => const DetailsScreen()',
      ),
    ]) {
      test('${scenario.name} fatal-defers as unsupported builder', () async {
        final outcome = recogniseNavigationTrigger(
          await _parseNavigationSlot('''
() => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(
    ${scenario.routeBuilder},
  ),
)
'''),
        );

        _expectNavigationUnsupported(outcome);
      });
    }

    test('Navigator.of rootNavigator true fatal-defers', () async {
      final outcome = recogniseNavigationTrigger(
        await _parseNavigationSlot('''
() => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => const DetailsScreen(),
  ),
)
'''),
      );

      _expectNavigationUnsupported(outcome, messageContains: 'rootNavigator');
    });

    // The flow transition can only carry `paywallScreen(id)`; a pushed-screen
    // construction with arguments or a named constructor has no declarative
    // channel and must fatal-defer rather than silently drop the state.
    for (final scenario in <({String name, String construction})>[
      (
        name: 'pushed screen with constructor arguments',
        construction: "const DetailsScreen(variant: 'annual')",
      ),
      (
        name: 'pushed screen via named constructor',
        construction: 'const DetailsScreen.annual()',
      ),
    ]) {
      test('${scenario.name} fatal-defers', () async {
        final outcome = recogniseNavigationTrigger(
          await _parseNavigationSlot('''
() => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(
    builder: (_) => ${scenario.construction},
  ),
)
'''),
        );

        _expectNavigationUnsupported(outcome);
      });
    }

    // The push target navigator is determined by the context argument. A
    // context that is not a bare identifier (a key's currentContext, a method
    // call, a member access) is not the build method's BuildContext and must
    // fatal-defer rather than be lowered as a depth-1 in-flow transition. (The
    // precise "identifier resolves to the build BuildContext param" binding
    // check is Batch B, where the translator has the build context.)
    for (final scenario in <({String name, String callback})>[
      (
        name: 'static push with a non-identifier context',
        callback: '''
() => Navigator.push<void>(
  navigatorKey.currentContext!,
  MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
)
''',
      ),
      (
        name: 'Navigator.of with a non-identifier context',
        callback: '''
() => Navigator.of(navigatorKey.currentContext!).push<void>(
  MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
)
''',
      ),
    ]) {
      test('${scenario.name} fatal-defers', () async {
        final outcome = recogniseNavigationTrigger(
          await _parseNavigationSlot(scenario.callback),
        );

        _expectNavigationUnsupported(outcome);
      });
    }

    // A prefixed Flutter `Navigator` receiver is a real navigation call: an
    // unsupported prefixed form must fatal-defer with the navigation-specific
    // message rather than fall through to the generic closure rejection.
    test('prefixed unsupported Navigator form fatal-defers', () async {
      final outcome = recogniseNavigationTrigger(
        await _parseNavigationSlot(
          "() => fw.Navigator.pushNamed(context, '/details')",
        ),
      );

      _expectNavigationUnsupported(outcome);
    });

    for (final scenario in <({String name, String callback})>[
      (
        name: 'async expression body',
        callback: '''
() async => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
)
''',
      ),
      (
        name: 'await in async block',
        callback: '''
() async {
  await Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
  );
}
''',
      ),
      (
        name: 'then chain',
        callback: '''
() => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
).then((_) {})
''',
      ),
      (
        name: 'unawaited wrapper',
        callback: '''
() {
  unawaited(Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
  ));
}
''',
      ),
      (
        name: 'result assignment',
        callback: '''
() {
  final pushed = Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
  );
}
''',
      ),
      (
        name: 'non-empty trigger params',
        callback: '''
(event) => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
)
''',
      ),
      (
        name: 'more than one navigation call',
        callback: '''
() {
  Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
  );
  Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
  );
}
''',
      ),
    ]) {
      test('${scenario.name} is a result-drop fatal-defer', () async {
        final outcome = recogniseNavigationTrigger(
          await _parseNavigationSlot(scenario.callback),
        );

        expect(outcome, isA<NavigationResultDropped>());
        expect(
          (outcome as NavigationResultDropped).reason,
          kNavigationResultDroppedReason,
        );
      });
    }

    test('non-@PaywallSource pushed screen fatal-defers', () async {
      final outcome = recogniseNavigationTrigger(
        await _parseNavigationSlot('''
() => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(
    builder: (_) => const PlainScreen(),
  ),
)
'''),
      );

      _expectNavigationUnsupported(
        outcome,
        messageContains: '@PaywallSource',
      );
    });

    test('Navigator.pop(context, result) is result-unsupported', () async {
      final outcome = recogniseNavigatorPopBack(
        await _parseNavigationSlot('() => Navigator.pop(context, result)'),
      );

      expect(outcome, isA<NavigatorPopResultUnsupported>());
      expect(
        (outcome as NavigatorPopResultUnsupported).reason,
        kNavigationNavigatorPopResultReason,
      );
    });

    test('resolved customer Navigator look-alike is not recognised', () async {
      final outcome = recogniseNavigationTrigger(
        await parseExpressionFromSourceForTest(
          '''
import 'package:flutter/material.dart' hide Navigator;
import 'package:restage/restage.dart';

class Navigator {
  static Future<T?> push<T extends Object?>(
    BuildContext context,
    Route<T> route,
  ) async => null;
}

@PaywallSource(id: 'details')
class DetailsScreen extends StatelessWidget {
  const DetailsScreen();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context) => () => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(builder: (_) => const DetailsScreen()),
);
''',
          rootPackage: 'apps_examples',
        ),
      );

      expect(outcome, isA<NavigationNotRecognised>());
    });

    test('customer look-alike @PaywallSource pushed screen fatal-defers',
        () async {
      final outcome = recogniseNavigationTrigger(
        await parseExpressionFromSourceForTest(
          '''
import 'package:flutter/material.dart';

class PaywallSource {
  const PaywallSource({required this.id});
  final String id;
}

@PaywallSource(id: 'fake')
class FakeScreen extends StatelessWidget {
  const FakeScreen();
  Widget build(BuildContext context) => const SizedBox();
}

Object x(BuildContext context) => () => Navigator.push<void>(
  context,
  MaterialPageRoute<void>(builder: (_) => const FakeScreen()),
);
''',
          rootPackage: 'apps_examples',
        ),
      );

      _expectNavigationUnsupported(outcome, messageContains: '@PaywallSource');
    });

    test('non-navigation call is not recognised', () async {
      final outcome = recogniseNavigationTrigger(
        await _parseNavigationSlot("() => debugPrint('tap')"),
      );

      expect(outcome, isA<NavigationNotRecognised>());
    });

    test('fatal-defer reasons are author-facing', () {
      const reasons = [
        kNavigationResultDroppedReason,
        kNavigationNavigatorFormUnsupportedReason,
        kNavigationRouteUnsupportedReason,
        kNavigationRouteArgumentUnsupportedReason,
        kNavigationBuilderUnsupportedReason,
        kNavigationPushedScreenUnsupportedReason,
        kNavigationNavigatorPopResultReason,
      ];

      for (final reason in reasons) {
        expect(reason, isNotEmpty);
      }
    });
  });
}

Future<Expression> _parseNavigationSlot(String expression) {
  return parseExpressionFromSourceForTest(
    '''
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/widgets.dart' as fw;
import 'package:restage/restage.dart';

@PaywallSource(id: 'details')
class DetailsScreen extends StatelessWidget {
  const DetailsScreen({this.variant = 'monthly'});
  const DetailsScreen.annual() : variant = 'annual';
  final String variant;
  Widget build(BuildContext context) => const SizedBox();
}

class PlainScreen extends StatelessWidget {
  const PlainScreen();
  Widget build(BuildContext context) => const SizedBox();
}

final navigatorKey = GlobalKey<NavigatorState>();

Widget screenFactory() => const DetailsScreen();

Route<void> restorableRouteBuilder(BuildContext context, Object? arguments) =>
    MaterialPageRoute<void>(builder: (_) => const DetailsScreen());

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

void _expectNavigationUnsupported(
  NavigationTriggerOutcome outcome, {
  String? messageContains,
}) {
  expect(outcome, isA<NavigationFormUnsupported>());
  if (messageContains != null) {
    expect(
      (outcome as NavigationFormUnsupported).reason,
      contains(messageContains),
    );
  }
}
