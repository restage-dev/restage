import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/native_screen_source_index.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  for (final consumer in NativeScreenSourceConsumer.values) {
    group('${consumer.name} shared ScreenSource admission', () {
      test('rejects a source outside the exact RFW screen topology', () async {
        final probe = await _runIndexProbe(
          {'lib/wrong_path.dart': _screenSource('wrong_path')},
          consumer: consumer,
          addGeneratedPartDirective: false,
        );

        expect(probe.result.succeeded, isFalse);
        expect(probe.output, isEmpty);
        expect(probe.logs.join('\n'), contains('invalidScreenSourceLocation'));
      });

      test('rejects an id that differs from the input file stem', () async {
        final probe = await _runIndexProbe(
          {
            'lib/onboarding/screens/expected_id.dart':
                _screenSource('actual_id', generatedPartStem: 'expected_id'),
          },
          consumer: consumer,
          addGeneratedPartDirective: false,
        );

        expect(probe.result.succeeded, isFalse);
        expect(probe.output, isEmpty);
        expect(probe.logs.join('\n'), contains('filenameMismatch'));
      });

      test('rejects a missing generated RFW part directive', () async {
        final probe = await _runIndexProbe(
          {
            'lib/onboarding/screens/missing_part.dart':
                _screenSource('missing_part', includeGeneratedPart: false),
          },
          consumer: consumer,
          addGeneratedPartDirective: false,
        );

        expect(probe.result.succeeded, isFalse);
        expect(probe.output, isEmpty);
        expect(probe.logs.join('\n'), contains('missingPartDirective'));
      });

      for (final decoy in _partDirectiveDecoys.entries) {
        test(
          'rejects a ${decoy.key} part-directive decoy with no native output',
          () async {
            final probe = await _runIndexProbe(
              {
                'lib/onboarding/screens/part_decoy.dart': _screenSource(
                  'part_decoy',
                  includeGeneratedPart: false,
                  partDirectiveDecoy: decoy.value,
                ),
              },
              consumer: consumer,
              addGeneratedPartDirective: false,
            );

            expect(probe.result.succeeded, isFalse);
            expect(probe.output, isEmpty);
            expect(
              probe.logs.join('\n'),
              contains('missingPartDirective'),
            );
          },
        );
      }

      test('rejects more than one source in an input library', () async {
        final probe = await _runIndexProbe(
          {
            'lib/onboarding/screens/duplicate_class.dart': _screenSource(
              'duplicate_class',
              additionalClass: true,
            ),
          },
          consumer: consumer,
          addGeneratedPartDirective: false,
        );

        expect(probe.result.succeeded, isFalse);
        expect(probe.output, isEmpty);
        expect(probe.logs.join('\n'), contains('invalidScreenSourceCount'));
      });
    });

    test(
      'indexes package-wide canonical screens with implicit and colocated '
      'explicit IDs alongside legacy compatibility sources',
      () async {
        final probe = await _runIndexProbe(
          const {
            'lib/features/implicit_notice.dart': _canonicalImplicitNotice,
            'lib/features/message_bundle.dart': _canonicalMessageBundle,
            'lib/onboarding/screens/legacy_notice.dart': _legacyNotice,
          },
          consumer: consumer,
          addGeneratedPartDirective: false,
        );

        expect(probe.result.succeeded, isTrue, reason: probe.logs.join('\n'));
        const implicitIdentity =
            'identity=package:apps_examples/features/implicit_notice.dart#'
            'ImplicitNotice';
        for (final expected in const <String>[
          'id=implicit_notice',
          'version=2',
          'minClient=3',
          'events=continued:continue:String',
          'id=stable-first',
          'id=stable-second',
          'id=legacy_notice',
        ]) {
          expect(probe.output, contains(expected));
        }
        expect(probe.output, contains(implicitIdentity));
      },
    );
  }

  for (final config in const {
    'rfw': "import 'package:rfw_catalog_schema/rfw.dart' as target;",
    'a2ui': "import 'package:rfw_catalog_schema/a2ui.dart' as target;",
    'widgetbook':
        "import 'package:rfw_catalog_schema/widgetbook.dart' as target;",
  }.entries) {
    test('rejects ${config.key}.Config.enabled on ScreenSource', () async {
      final source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
${config.value}

part 'restage.generated/enabled_${config.key}.restage.g.dart';

@ScreenSource(id: 'enabled_${config.key}')
@target.Config.enabled(false)
class EnabledScreen extends StatelessWidget {
  const EnabledScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

      final probe = await _runIndexProbe({
        'lib/onboarding/screens/enabled_${config.key}.dart': source,
      });

      expect(probe.result.succeeded, isFalse);
      expect(probe.output, isEmpty);
      expect(
        probe.logs.join('\n'),
        allOf(
          contains('invalidTargetConfigPlacement'),
          contains('@RestageWidget'),
          contains('ScreenSource'),
        ),
      );
    });
  }

  test('rejects an explicit null Config.enabled key on ScreenSource', () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw.dart' as rfw;

part 'restage.generated/enabled_null.restage.g.dart';

@ScreenSource(id: 'enabled_null')
@rfw.Config(enabled: null)
class EnabledNullScreen extends StatelessWidget {
  const EnabledNullScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe({
      'lib/onboarding/screens/enabled_null.dart': source,
    });

    expect(probe.result.succeeded, isFalse);
    expect(probe.output, isEmpty);
    expect(probe.logs.join('\n'), contains('invalidTargetConfigPlacement'));
  });

  test(
      'rejects inherited property placement of class-only enabled on '
      'ScreenSource', () async {
    const base = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;

abstract class BaseScreen extends StatelessWidget {
  const BaseScreen({super.key, this.label = ''});

  @a2ui.Config.enabled(false)
  final String label;
}
''';
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

import '../../base_screen.dart';

@ScreenSource(id: 'inherited_enabled')
class InheritedEnabledScreen extends BaseScreen {
  const InheritedEnabledScreen({super.key, super.label});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe({
      'lib/base_screen.dart': base,
      'lib/onboarding/screens/inherited_enabled.dart': screen,
    });

    expect(probe.result.succeeded, isFalse);
    expect(probe.output, isEmpty);
    expect(
      probe.logs.join('\n'),
      allOf(
        contains('invalidTargetConfigPlacement'),
        contains('lib/base_screen.dart#InheritedEnabledScreen.label'),
      ),
    );
  });

  test('retains exact native screen identity and shared source facts',
      () async {
    const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart' as restage;
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

enum ProofTone { calm, urgent }

/// A native proof screen.
///
/// Keeps its full multi-line description.
@restage.ScreenSource(id: 'proof', version: 2, minClient: 4)
@a2ui.Config.usage('Use for a native flow proof.')
@wb.Config(maxStories: 7)
class ProofScreen extends StatelessWidget {
  const ProofScreen({
    super.key,
    required this.title,
    this.enabled = true,
    this.tone = ProofTone.calm,
  });

  static const continued = restage.SurfaceEvent<String>('continue');

  /// Visible title.
  final String title;

  /// Whether continuing is enabled.
  @wb.Config.allValues()
  final bool enabled;

  /// Current visual tone.
  final ProofTone tone;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: enabled
            ? restage.surfaceEvent(continued, 'preview')
            : null,
        child: Text(title),
      );
}
''';

    final probe = await _runIndexProbe(
      {'lib/onboarding/screens/proof.dart': source},
    );

    expect(probe.result.succeeded, isTrue, reason: probe.logs.join('\n'));
    expect(
      probe.output,
      allOf(<Matcher>[
        contains('id=proof'),
        contains('version=2'),
        contains('minClient=4'),
        contains(
          'identity=package:apps_examples/onboarding/screens/proof.dart#'
          'ProofScreen',
        ),
        contains('source=lib/onboarding/screens/proof.dart'),
        contains('declaration=lib/onboarding/screens/proof.dart'),
        contains(
          'import=package:apps_examples/onboarding/screens/proof.dart',
        ),
        contains(
          r'description=A native proof screen.\n\nKeeps its full multi-line description.',
        ),
        contains('inputs=title:required,enabled:optional,tone:optional'),
        contains('defaults=enabled:true,tone:ProofTone.calm'),
        contains('a2uiUsage=Use for a native flow proof.'),
        contains('widgetbookMaxStories=7'),
        contains('widgetbookAllValues=enabled'),
        contains('events=continued:continue:String'),
      ]),
    );
  });

  test('indexes a prefixed canonical SurfaceEvent through its concrete type',
      () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' as restage;

@restage.ScreenSource(id: 'prefixed_surface_event')
class PrefixedSurfaceEventScreen extends StatelessWidget {
  const PrefixedSurfaceEventScreen({super.key});

  static const continueEvent = restage.SurfaceEvent<String>('continue');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe({
      'lib/onboarding/screens/prefixed_surface_event.dart': source,
    });

    expect(probe.result.succeeded, isTrue, reason: probe.logs.join('\n'));
    expect(probe.output, contains('events=continueEvent:continue:String'));
  });

  test('indexes a prefixed deprecated OnboardingEvent alias through type.alias',
      () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' as restage;

@restage.ScreenSource(id: 'prefixed_onboarding_event')
class PrefixedOnboardingEventScreen extends StatelessWidget {
  const PrefixedOnboardingEventScreen({super.key});

  static const continueEvent = restage.OnboardingEvent<String>('continue');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe({
      'lib/onboarding/screens/prefixed_onboarding_event.dart': source,
    });

    expect(probe.result.succeeded, isTrue, reason: probe.logs.join('\n'));
    expect(probe.output, contains('events=continueEvent:continue:String'));
  });

  test('A2UI consumption is not gated by Widgetbook-only config', () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

@ScreenSource(id: 'a2ui_independent')
@wb.Config.values([true])
class A2uiIndependentScreen extends StatelessWidget {
  const A2uiIndependentScreen({super.key, required this.enabled});

  /// Whether the screen is enabled.
  final bool enabled;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe(
      {'lib/onboarding/screens/a2ui_independent.dart': source},
      consumer: NativeScreenSourceConsumer.a2ui,
    );

    expect(probe.result.succeeded, isTrue, reason: probe.logs.join('\n'));
    expect(probe.output, contains('id=a2ui_independent'));
  });

  test('Widgetbook screen indexing ignores unevaluable A2UI-only config',
      () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;

final runtimePairings = <String, String>{'onChanged': 'value'};

@ScreenSource(id: 'widgetbook_independent')
@a2ui.Config.writeBackValues(runtimePairings)
class WidgetbookIndependentScreen extends StatelessWidget {
  const WidgetbookIndependentScreen({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe({
      'lib/onboarding/screens/widgetbook_independent.dart': source,
    });

    expect(probe.result.succeeded, isTrue, reason: probe.logs.join('\n'));
    expect(probe.output, contains('id=widgetbook_independent'));
  });

  test('uses the owning library identity for aliased annotations and parts',
      () async {
    const library = '''
library shared_screens;

import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' as rs;

part '../../src/part_screen.dart';
''';
    const part = '''
part of '../onboarding/screens/part_screen.dart';

/// A screen declared in a part.
@rs.ScreenSource(id: 'part_screen')
class PartScreen extends StatelessWidget {
  const PartScreen({super.key, required this.label});

  /// Visible label.
  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}
''';

    final probe = await _runIndexProbe({
      'lib/onboarding/screens/part_screen.dart': library,
      'lib/src/part_screen.dart': part,
    });

    expect(probe.result.succeeded, isTrue, reason: probe.logs.join('\n'));
    expect(
      probe.output,
      allOf(
        contains(
          'identity=package:apps_examples/onboarding/screens/part_screen.dart#'
          'PartScreen',
        ),
        contains('source=lib/onboarding/screens/part_screen.dart'),
        contains('declaration=lib/src/part_screen.dart'),
        contains(
          'import=package:apps_examples/onboarding/screens/part_screen.dart',
        ),
        isNot(contains('package:apps_examples/src/part_screen.dart')),
      ),
    );
  });

  test('rejects dual ScreenSource and RestageWidget annotation by identity',
      () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@ScreenSource(id: 'screen-contract')
@RestageWidget(
  name: 'different-widget-contract',
  library: WidgetLibrary.custom('acme.widgets'),
  description: 'A conflicting widget contract.',
)
class DualSource extends StatelessWidget {
  const DualSource({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe({
      'lib/onboarding/screens/screen-contract.dart': source,
    });

    expect(probe.result.succeeded, isFalse);
    expect(
      probe.logs.join('\n'),
      allOf(
        contains('@ScreenSource'),
        contains('@RestageWidget'),
        contains(
          'package:apps_examples/onboarding/screens/screen-contract.dart#'
          'DualSource',
        ),
        contains('lib/onboarding/screens/screen-contract.dart'),
      ),
    );
  });

  test('rejects duplicate exact screen IDs across libraries and parts',
      () async {
    const firstLibrary = '''
library shared_screens;

import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part '../../src/first_screen.dart';
''';
    const firstPart = '''
part of '../onboarding/screens/duplicate.dart';

@ScreenSource(id: 'duplicate')
class FirstScreen extends StatelessWidget {
  const FirstScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
    const second = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'duplicate')
class SecondScreen extends StatelessWidget {
  const SecondScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe({
      'lib/onboarding/screens/duplicate.dart': firstLibrary,
      'lib/src/first_screen.dart': firstPart,
      'lib/message/screens/duplicate.dart': second,
    });

    expect(probe.result.succeeded, isFalse);
    final logs = probe.logs.join('\n');
    expect(logs, contains('@ScreenSource id "duplicate"'));
    expect(
      logs,
      contains(
        'package:apps_examples/onboarding/screens/duplicate.dart#FirstScreen',
      ),
    );
    expect(logs, contains('lib/src/first_screen.dart'));
    expect(
      logs,
      contains(
        'package:apps_examples/message/screens/duplicate.dart#SecondScreen',
      ),
    );
    expect(logs, contains('lib/message/screens/duplicate.dart'));
    expect(
      logs.indexOf(
        'package:apps_examples/message/screens/duplicate.dart#SecondScreen',
      ),
      lessThan(
        logs.indexOf(
          'package:apps_examples/onboarding/screens/duplicate.dart#FirstScreen',
        ),
      ),
    );
  });

  test('rejects an exact screen and customer A2UI component name collision',
      () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'shared_component')
class NativeScreen extends StatelessWidget {
  const NativeScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
    const widget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'shared_component',
  library: WidgetLibrary.custom('acme.widgets'),
  description: 'A colliding customer component.',
)
class CustomerComponent extends StatelessWidget {
  const CustomerComponent({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe(
      {
        'lib/onboarding/screens/shared_component.dart': screen,
        'lib/customer_component.dart': widget,
      },
      validateA2uiNamespace: true,
    );

    expect(probe.result.succeeded, isFalse);
    expect(
      probe.logs.join('\n'),
      allOf(
        contains('A2UI component name "shared_component"'),
        contains('@ScreenSource'),
        contains(
          'package:apps_examples/onboarding/screens/shared_component.dart#'
          'NativeScreen',
        ),
        contains('lib/onboarding/screens/shared_component.dart'),
        contains('@RestageWidget'),
        contains(
          'package:apps_examples/customer_component.dart#CustomerComponent',
        ),
        contains('lib/customer_component.dart'),
      ),
    );
  });

  test('canonicalizes same-package relative imports without traversal',
      () async {
    const model = '''
enum ScreenTone { calm, urgent }
''';
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import '../../model.dart';

@ScreenSource(id: 'relative_import')
class RelativeImportScreen extends StatelessWidget {
  const RelativeImportScreen({super.key, required this.tone});

  final ScreenTone tone;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe({
      'lib/model.dart': model,
      'lib/onboarding/screens/relative_import.dart': screen,
    });

    expect(probe.result.succeeded, isTrue, reason: probe.logs.join('\n'));
    expect(
      probe.output,
      contains('imports=package:apps_examples/model.dart,'
          'package:apps_examples/onboarding/screens/relative_import.dart'),
    );
    expect(probe.output, isNot(contains('../')));
  });

  test('retains a non-core dart import required by a constructor default',
      () async {
    const screen = '''
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'dart_import')
class DartImportScreen extends StatelessWidget {
  const DartImportScreen({super.key, this.radius = math.pi});

  final double radius;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe({
      'lib/onboarding/screens/dart_import.dart': screen,
    });

    expect(probe.result.succeeded, isTrue, reason: probe.logs.join('\n'));
    expect(
      probe.output,
      contains('imports=dart:math,'
          'package:apps_examples/onboarding/screens/dart_import.dart'),
    );
  });

  test('rejects a dependency-private constructor import', () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/src/authoring/flow_source.dart';
import 'package:restage/src/flow/flow_descriptors.dart';

@ScreenSource(id: 'private_dependency')
class PrivateDependencyScreen extends StatelessWidget {
  const PrivateDependencyScreen({super.key, required this.event});

  final OnboardingEvent<String> event;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe(
      {'lib/onboarding/screens/private_dependency.dart': screen},
    );

    expect(probe.result.succeeded, isFalse);
    expect(
      probe.logs.join('\n'),
      allOf(
        contains('dependency-private'),
        contains('package:restage/src/flow/flow_descriptors.dart'),
        contains('PrivateDependencyScreen.event'),
      ),
    );
  });

  test('rejects a constructor import from an undeclared direct dependency',
      () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@ScreenSource(id: 'transitive_dependency')
class TransitiveDependencyScreen extends StatelessWidget {
  const TransitiveDependencyScreen({super.key, required this.category});

  final WidgetCategory category;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe(
      {'lib/onboarding/screens/transitive_dependency.dart': screen},
      dependencies: const {'flutter', 'restage'},
    );

    expect(probe.result.succeeded, isFalse);
    expect(
      probe.logs.join('\n'),
      allOf(
        contains('declared direct dependency'),
        contains('rfw_catalog_schema'),
        contains('TransitiveDependencyScreen.category'),
      ),
    );
  });

  test('rejects a private annotated screen class for native siblings',
      () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'private_screen')
class _PrivateScreen extends StatelessWidget {
  const _PrivateScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe({
      'lib/onboarding/screens/private_screen.dart': screen,
    });

    expect(probe.result.succeeded, isFalse);
    expect(
      probe.logs.join('\n'),
      allOf(
        contains('private annotated screen class'),
        contains(
          'package:apps_examples/onboarding/screens/private_screen.dart#'
          '_PrivateScreen',
        ),
        contains(
          'lib/onboarding/screens/private_screen.dart#_PrivateScreen',
        ),
      ),
    );
  });

  test('rejects an abstract Flutter ScreenSource for native siblings',
      () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' as restage;

@restage.ScreenSource(id: 'abstract_screen')
abstract class AbstractScreen extends StatelessWidget {
  const AbstractScreen({super.key});
}
''';

    final probe = await _runIndexProbe({
      'lib/onboarding/screens/abstract_screen.dart': screen,
    });

    expect(probe.result.succeeded, isFalse);
    expect(
      probe.logs.join('\n'),
      allOf(
        contains('has no build() method'),
        contains('lib/onboarding/screens/abstract_screen.dart#AbstractScreen'),
      ),
    );
  });

  test('rejects a non-Widget ScreenSource by exact analyzer identity',
      () async {
    const screen = '''
import 'package:restage/restage.dart' as restage;

class StatelessWidget {}

@restage.ScreenSource(id: 'not_a_widget')
class NotAWidgetScreen extends StatelessWidget {
  const NotAWidgetScreen();
}
''';

    final probe = await _runIndexProbe({
      'lib/onboarding/screens/not_a_widget.dart': screen,
    });

    expect(probe.result.succeeded, isFalse);
    expect(
      probe.logs.join('\n'),
      allOf(
        contains('has no build() method'),
        contains(
          'lib/onboarding/screens/not_a_widget.dart#NotAWidgetScreen',
        ),
      ),
    );
  });

  test('accepts a concrete ScreenSource through a Flutter Widget subclass',
      () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' as restage;

abstract class ScreenBase extends StatelessWidget {
  const ScreenBase({super.key});
}

@restage.ScreenSource(id: 'concrete_screen')
final class ConcreteScreen extends ScreenBase {
  const ConcreteScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe({
      'lib/onboarding/screens/concrete_screen.dart': screen,
    });

    expect(probe.result.succeeded, isTrue, reason: probe.logs.join('\n'));
    expect(probe.output, contains('id=concrete_screen'));
  });

  test('rejects a private same-library constructor type', () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

final class _PrivateModel {
  const _PrivateModel();
}

@ScreenSource(id: 'private_input')
class PrivateInputScreen extends StatelessWidget {
  const PrivateInputScreen({super.key, required this.model});

  final _PrivateModel model;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe({
      'lib/onboarding/screens/private_input.dart': screen,
    });

    expect(probe.result.succeeded, isFalse);
    expect(
      probe.logs.join('\n'),
      allOf(
        contains('private Dart identity'),
        contains('_PrivateModel'),
        contains(
          'lib/onboarding/screens/private_input.dart#PrivateInputScreen.model',
        ),
      ),
    );
  });

  test('rejects a private same-library constructor default symbol', () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

const _privateTitle = 'private';

@ScreenSource(id: 'private_default')
class PrivateDefaultScreen extends StatelessWidget {
  const PrivateDefaultScreen({super.key, this.title = _privateTitle});

  final String title;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe({
      'lib/onboarding/screens/private_default.dart': screen,
    });

    expect(probe.result.succeeded, isFalse);
    expect(
      probe.logs.join('\n'),
      allOf(
        contains('private Dart identity'),
        contains('_privateTitle'),
        contains(
          'lib/onboarding/screens/private_default.dart#PrivateDefaultScreen.'
          'title default',
        ),
      ),
    );
  });

  test('rejects a private named constructor used by a default', () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

final class PublicModel {
  const PublicModel._();
}

@ScreenSource(id: 'private_default_constructor')
class PrivateDefaultConstructorScreen extends StatelessWidget {
  const PrivateDefaultConstructorScreen({
    super.key,
    this.model = const PublicModel._(),
  });

  final PublicModel model;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe(
      {'lib/onboarding/screens/private_default_constructor.dart': screen},
    );

    expect(probe.result.succeeded, isFalse);
    expect(
      probe.logs.join('\n'),
      allOf(
        contains('private Dart identity'),
        contains('PublicModel._'),
        contains(
          'lib/onboarding/screens/private_default_constructor.dart#'
          'PrivateDefaultConstructorScreen.model default',
        ),
      ),
    );
  });

  test('accepts Pub graph dependencies from legal flow-style YAML', () async {
    const screen = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@ScreenSource(id: 'flow_yaml')
class FlowYamlScreen extends StatelessWidget {
  const FlowYamlScreen({super.key, required this.category});

  final WidgetCategory category;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final probe = await _runIndexProbe(
      {'lib/onboarding/screens/flow_yaml.dart': screen},
      pubspec: '''
name: apps_examples
dependencies: {flutter: any, restage: any, rfw_catalog_schema: any}
''',
    );

    expect(probe.result.succeeded, isTrue, reason: probe.logs.join('\n'));
    expect(probe.output, contains('id=flow_yaml'));
  });

  test('normalizes an ordinary dual Flutter barrel to the defining area',
      () async {
    const screen = '''
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart' as widgets;
import 'package:restage/restage.dart';

@ScreenSource(id: 'ambiguous_import')
class AmbiguousImportScreen extends widgets.StatelessWidget {
  const AmbiguousImportScreen({super.key, required this.child});

  final widgets.Widget child;

  @override
  widgets.Widget build(widgets.BuildContext context) => child;
}
''';

    final probe = await _runIndexProbe(
      {'lib/onboarding/screens/ambiguous_import.dart': screen},
    );

    expect(probe.result.succeeded, isTrue, reason: probe.logs.join('\n'));
    expect(
      probe.output,
      contains(
        'imports=package:apps_examples/onboarding/screens/ambiguous_import.dart,'
        'package:flutter/widgets.dart',
      ),
    );
    expect(probe.output, isNot(contains('package:flutter/material.dart')));
  });
}

Future<({TestBuilderResult result, List<String> logs, String output})>
    _runIndexProbe(
  Map<String, String> dartSources, {
  NativeScreenSourceConsumer consumer = NativeScreenSourceConsumer.widgetbook,
  bool validateA2uiNamespace = false,
  String? pubspec,
  Set<String> dependencies = const {
    'flutter',
    'restage',
    'rfw_catalog_schema',
  },
  bool addGeneratedPartDirective = true,
}) async {
  final pubspecBuffer = StringBuffer()
    ..writeln('name: apps_examples')
    ..writeln('dependencies:');
  for (final dependency in dependencies.toList()..sort()) {
    pubspecBuffer.writeln('  $dependency: any');
  }
  final admittedDartSources = <String, String>{
    for (final entry in dartSources.entries)
      entry.key: addGeneratedPartDirective
          ? _withGeneratedPartDirective(entry.key, entry.value)
          : entry.value,
  };
  final sources = <String, String>{
    'apps_examples|pubspec.yaml': pubspec ?? pubspecBuffer.toString(),
    'apps_examples|.dart_tool/package_graph.json': _packageGraph(
      dependencies,
    ),
    for (final entry in admittedDartSources.entries)
      'apps_examples|${entry.key}': entry.value,
  };
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  final logs = <String>[];
  final result = await runWithNativeScreenPackageGraphForTesting(
    packageGraphSource: _packageGraph(dependencies),
    body: () => testBuilder(
      _NativeScreenIndexProbeBuilder(
        consumer: consumer,
        validateA2uiNamespace: validateA2uiNamespace,
      ),
      sources,
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
      onLog: (record) => logs.add(record.message),
    ),
  );
  final outputId = AssetId(
    'apps_examples',
    'lib/native_screen_source_index.txt',
  );
  final output = result.readerWriter.testing.exists(outputId)
      ? utf8.decode(result.readerWriter.testing.readBytes(outputId))
      : '';
  return (result: result, logs: logs, output: output);
}

String _screenSource(
  String id, {
  String? generatedPartStem,
  bool includeGeneratedPart = true,
  bool additionalClass = false,
  String partDirectiveDecoy = '',
}) =>
    '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

${includeGeneratedPart ? "part 'restage.generated/${generatedPartStem ?? id}.restage.g.dart';" : ''}
$partDirectiveDecoy

@ScreenSource(id: '$id')
class AdmissionScreen extends StatelessWidget {
  const AdmissionScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

${additionalClass ? '''
@ScreenSource(id: '$id')
class AdditionalAdmissionScreen extends StatelessWidget {
  const AdditionalAdmissionScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''' : ''}
''';

const _partDirectiveDecoys = <String, String>{
  'comment': "// part 'restage.generated/part_decoy.restage.g.dart';",
  'string':
      "const partDirectiveText = \"part 'restage.generated/part_decoy.restage.g.dart';\";",
};

const _canonicalImplicitNotice = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/implicit_notice.restage.g.dart';

@Screen(surface: Surface.general, version: 2, minClient: 3)
final class ImplicitNotice extends StatelessWidget {
  const ImplicitNotice({super.key, required this.title});

  static const continued = SurfaceEvent<String>('continue');

  final String title;

  @override
  Widget build(BuildContext context) => Text(title);
}
''';

const _canonicalMessageBundle = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/message_bundle.restage.g.dart';

@Screen(id: 'stable-first', surface: Surface.message)
final class StableFirst extends StatelessWidget {
  const StableFirst({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'stable-second', surface: Surface.message)
final class StableSecond extends StatelessWidget {
  const StableSecond({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _legacyNotice = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/legacy_notice.restage.g.dart';

@ScreenSource(id: 'legacy_notice')
final class LegacyNotice extends StatelessWidget {
  const LegacyNotice({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

String _withGeneratedPartDirective(String path, String source) {
  final match = RegExp(
    r'^lib/(?:onboarding|message|survey)/screens/([^/]+)\.dart$',
  ).firstMatch(path);
  if (match == null) return source;
  final stem = match.group(1)!;
  if (source.contains('$stem.rsscreen.g.dart')) return source;
  final imports = RegExp(
    r'''^import\s+['"][^'"]+['"][^;]*;''',
    multiLine: true,
  ).allMatches(source).toList(growable: false);
  if (imports.isEmpty) return source;
  final offset = imports.last.end;
  return source.replaceRange(
    offset,
    offset,
    "\n\npart 'restage.generated/$stem.restage.g.dart';",
  );
}

String _packageGraph(Set<String> dependencies) => jsonEncode({
      'roots': ['apps_examples'],
      'packages': [
        {
          'name': 'apps_examples',
          'version': '0.0.0',
          'dependencies': dependencies.toList()..sort(),
          'devDependencies': <String>[],
        },
      ],
    });

final class _NativeScreenIndexProbeBuilder implements Builder {
  const _NativeScreenIndexProbeBuilder({
    required this.consumer,
    required this.validateA2uiNamespace,
  });

  final NativeScreenSourceConsumer consumer;
  final bool validateA2uiNamespace;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['native_screen_source_index.txt'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final index = await loadNativeScreenSourceIndex(
      buildStep,
      consumer: consumer,
      validateA2uiNamespace: validateA2uiNamespace,
    );
    final output = StringBuffer();
    for (final screen in index.screens) {
      final widgetbookAllValues = screen
          .widgetbookTargetConfig.properties.entries
          .where((entry) => entry.value.allValues)
          .map((entry) => entry.key)
          .join(',');
      final events = screen.events
          .map(
            (event) => '${event.fieldName}:${event.id}:'
                '${event.payloadType.getDisplayString()}',
          )
          .join(',');
      output
        ..writeln('id=${screen.id}')
        ..writeln('version=${screen.version}')
        ..writeln('minClient=${screen.minClient}')
        ..writeln('identity=${screen.classIdentity}')
        ..writeln('source=${screen.sourceAsset.path}')
        ..writeln('declaration=${screen.declarationSourcePath}')
        ..writeln('import=${screen.importUri}')
        ..writeln('imports=${screen.importUris.join(',')}')
        ..writeln(
          'description=${screen.description?.replaceAll('\n', r'\n')}',
        )
        ..writeln(
          'inputs=${screen.constructorFacts.inputs.map((input) {
            return '${input.name}:${input.required ? 'required' : 'optional'}';
          }).join(',')}',
        )
        ..writeln(
          'defaults=${screen.constructorFacts.inputs.map((input) {
                final value = input.constructorDefault.reconstructedValue;
                return value == null
                    ? null
                    : '${input.name}:${_displayDefault(value)}';
              }).whereType<String>().join(',')}',
        )
        ..writeln('a2uiUsage=${screen.a2uiTargetConfig.usage}')
        ..writeln(
          'widgetbookMaxStories=${screen.widgetbookTargetConfig.maxStories}',
        )
        ..writeln(
          'widgetbookAllValues=$widgetbookAllValues',
        )
        ..writeln('events=$events');
    }
    await buildStep.writeAsString(
      AssetId(
        buildStep.inputId.package,
        'lib/native_screen_source_index.txt',
      ),
      output.toString(),
    );
  }
}

String _displayDefault(DartConstValue value) => switch (value) {
      DartConstNull() => 'null',
      DartConstScalar(:final value) => '$value',
      DartConstReference(:final owner, :final member) =>
        owner == null ? member : '$owner.$member',
      _ => value.runtimeType.toString(),
    };
