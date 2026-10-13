// Libraries that share a file name in different folders build independently.

import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _package = 'apps_examples';

String _screen(
  String className,
  String id, {
  String stem = 'welcome_banner',
}) =>
    '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/$stem.restage.g.dart';

@Screen(id: '$id', surface: Surface.general)
final class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) => const Text('$id');
}
''';

const _plainWidget = '''
import 'package:flutter/material.dart';

final class WelcomeBanner extends StatelessWidget {
  const WelcomeBanner({super.key});

  @override
  Widget build(BuildContext context) => const Text('before');
}
''';

String _paywall(String className, String id) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/offer.restage.g.dart';

@Paywall(id: '$id')
class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: paywallEvent('continue'),
        child: const Text('$id'),
      );
}
''';

const _flowScreen = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/hello.restage.g.dart';

@Screen()
class HelloScreen extends StatelessWidget {
  const HelloScreen({super.key});

  @override
  Widget build(BuildContext context) => const Text('hello');
}
''';

String _flow(String className, String? id, {required String screens}) => '''
import 'package:restage/restage.dart';

import '$screens/hello.dart';

part 'restage.generated/first_run.restage.g.dart';

@FlowGraph(${id == null ? '' : "id: '$id', "}surface: Surface.onboarding)
final class $className extends RestageFlow {
  const $className();

  @override
  FlowDef buildFlow() {
    return flow(
      initial: helloScreenRef,
      states: [screen(helloScreenRef)],
    );
  }
}
''';

String _catalogWidget(String className, String libraryName) => '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@RestageWidget(
  name: '$className',
  library: WidgetLibrary.custom('$libraryName'),
  category: WidgetCategory.decoration,
  description: 'A banner.',
)
class $className extends StatelessWidget {
  const $className({super.key, required this.title});

  @RestageProperty(description: 'The title.', required: true)
  final String title;

  @override
  Widget build(BuildContext context) => Text(title);
}
''';

void main() {
  test('two annotated libraries keep their own parts and surface ids',
      () async {
    final built = await _build({
      'lib/welcome_banner.dart': _screen('WelcomeBanner', 'welcome_after'),
      'lib/before/welcome_banner.dart':
          _screen('WelcomeBannerBefore', 'welcome_before'),
    });

    final after = built.read(
      'lib/restage.generated/welcome_banner.restage.g.dart',
    );
    final before = built.read(
      'lib/before/restage.generated/welcome_banner.restage.g.dart',
    );
    expect(after, contains("'welcome_after'"));
    expect(after, isNot(contains("'welcome_before'")));
    expect(before, contains("'welcome_before'"));
    expect(before, isNot(contains("'welcome_after'")));
    expect(
      built.exists('.restage/build/bundles/lib/welcome_banner.rsbundle'),
      isTrue,
    );
    expect(
      built.exists('.restage/build/bundles/lib/before/welcome_banner.rsbundle'),
      isTrue,
    );
  });

  test('an unannotated library beside an annotated namesake is skipped',
      () async {
    final built = await _build({
      'lib/welcome_banner.dart': _screen('WelcomeBanner', 'welcome_banner'),
      'lib/before/welcome_banner.dart': _plainWidget,
    });

    expect(
      built.read('lib/restage.generated/welcome_banner.restage.g.dart'),
      contains("'welcome_banner'"),
    );
    expect(
      built
          .exists('lib/before/restage.generated/welcome_banner.restage.g.dart'),
      isFalse,
    );
    expect(
      built.exists('.restage/build/bundles/lib/before/welcome_banner.rsbundle'),
      isFalse,
    );
  });

  test('two catalog widget libraries with one file name both register',
      () async {
    final built = await _build(
      {
        'lib/widgets/banner.dart':
            _catalogWidget('WelcomeBanner', 'example.widgets'),
        'lib/legacy/banner.dart':
            _catalogWidget('LegacyBanner', 'example.legacy'),
      },
      catalog: true,
    );

    final factories = built.read('lib/user_factories.g.dart');
    expect(factories, contains('WelcomeBanner'));
    expect(factories, contains('LegacyBanner'));
  });

  test('per-folder builders place nested namesakes at their own paths',
      () async {
    final built = await _build(
      {
        'lib/paywalls/offer.dart': _paywall('Offer', 'offer'),
        'lib/paywalls/legacy/offer.dart': _paywall('LegacyOffer', 'old_offer'),
        'lib/onboarding/screens/welcome.dart':
            _screen('Welcome', 'welcome', stem: 'welcome'),
        'lib/onboarding/screens/old/welcome.dart':
            _screen('OldWelcome', 'old_welcome', stem: 'welcome'),
      },
      conventional: true,
    );

    for (final path in [
      'assets/paywalls/offer.rfw',
      'assets/paywalls/legacy/offer.rfw',
      'assets/paywalls/screens/paywall_legacy/offer.rfw',
      'assets/onboarding/screens/welcome.rfw',
      'assets/onboarding/screens/old/welcome.rfw',
    ]) {
      expect(built.exists(path), isTrue, reason: path);
    }
    expect(
      built.read('assets/paywalls/legacy/offer.rfwtxt'),
      contains('old_offer'),
    );
    expect(
      built.read('assets/onboarding/screens/old/welcome.rfwtxt'),
      contains('old_welcome'),
    );
  });

  test('nested flow namesakes keep their own documents, parts and bundles',
      () async {
    final built = await _build(
      {
        'lib/onboarding/screens/hello.dart': _flowScreen,
        'lib/onboarding/flows/first_run.dart':
            _flow('FirstRunFlow', 'first_run', screens: '../screens'),
        'lib/onboarding/flows/old/first_run.dart':
            _flow('OldFirstRunFlow', 'old_first_run', screens: '../../screens'),
      },
      conventional: true,
    );

    for (final path in [
      'lib/onboarding/flows/restage.generated/first_run.restage.g.dart',
      'lib/onboarding/flows/old/restage.generated/first_run.restage.g.dart',
      '.restage/build/bundles/lib/onboarding/flows/first_run.rsbundle',
      '.restage/build/bundles/lib/onboarding/flows/old/first_run.rsbundle',
    ]) {
      expect(built.exists(path), isTrue, reason: path);
    }
    expect(
      built.read('assets/onboarding/flows/first_run.flow.json'),
      allOf(contains('"first_run"'), isNot(contains('old_first_run'))),
    );
    expect(
      built.read('assets/onboarding/flows/old/first_run.flow.json'),
      contains('"old_first_run"'),
    );
  });

  test('namesakes without ids report one duplicate id naming both', () async {
    final built = await _build(
      {
        'lib/onboarding/screens/hello.dart': _flowScreen,
        'lib/onboarding/flows/first_run.dart':
            _flow('FirstRunFlow', null, screens: '../screens'),
        'lib/onboarding/flows/old/first_run.dart':
            _flow('OldFirstRunFlow', null, screens: '../../screens'),
      },
      expectSuccess: false,
    );

    expect(built.succeeded, isFalse);
    expect(
      built.log,
      allOf(
        contains('[duplicateId]'),
        contains('lib/onboarding/flows/first_run.dart'),
        contains('lib/onboarding/flows/old/first_run.dart'),
      ),
    );
  });
}

final class _Built {
  const _Built(this.readerWriter, {required this.succeeded, this.log = ''});

  final TestReaderWriter readerWriter;
  final bool succeeded;
  final String log;

  String read(String path) =>
      readerWriter.testing.readString(AssetId(_package, path));

  bool exists(String path) =>
      readerWriter.testing.exists(AssetId(_package, path));
}

Future<_Built> _build(
  Map<String, String> sources, {
  bool catalog = false,
  bool conventional = false,
  bool expectSuccess = true,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
  );
  final logs = <String>[];
  const options = BuilderOptions.forRoot;
  final result = await testBuilders(
    [
      restageSourceRosterBuilder(options),
      userCatalogJsonBuilder(BuilderOptions.empty),
      restagePackageSurfaceCompilerBuilder(options),
      restageGeneratedDartBuilder(options),
      restageOutputsBuilder(options),
      if (conventional) ...[
        restageCodegenBuilder(BuilderOptions.empty),
        paywallFlowBuilder(BuilderOptions.empty),
        onboardingScreenBuilder(BuilderOptions.empty),
        onboardingFlowBuilder(BuilderOptions.empty),
      ],
      if (catalog) ...[
        userCatalogBuilder(options),
        userFactoryBuilder(options),
      ],
    ],
    {
      for (final entry in sources.entries)
        '$_package|${entry.key}': entry.value,
    },
    rootPackage: _package,
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) => logs.add(record.message),
  );
  if (expectSuccess) {
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
  }
  return _Built(
    readerWriter,
    succeeded: result.succeeded,
    log: logs.join('\n'),
  );
}
