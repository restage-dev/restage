import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_catalog_source_index.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_plan.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_source_renderer.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('runtime-resolved defaults', () {
    for (final variant in <({String name, String annotation})>[
      (
        name: 'token',
        annotation: '''
          TokenRefDefault(
            WireIdRef(
              library: 'fixture.tokens',
              wireId: WireId.unallocatedDesignToken,
            ),
          )
        ''',
      ),
      (
        name: 'theme',
        annotation: '''
          ThemeBindingDefault(ThemeBindingPath.path('colorScheme.primary'))
        ''',
      ),
    ]) {
      test('${variant.name} default receives an automatic native preview',
          () async {
        final source = _runtimeDefaultWidget(variant.annotation);
        await _runProbe(
          {'apps_examples|lib/customer_card.dart': source},
          outputMatcher: allOf(
            contains('.Color(0xFF000000)'),
            contains("import 'dart:ui' show Color;"),
            variant.name == 'token'
                ? contains('resolved from a design token at runtime')
                : contains('resolved from the Flutter theme at runtime'),
          ),
        );
      });
    }
  });

  test(
      'lookalike framework types are rejected by resolved identity during '
      'classification', () async {
    await _runProbe(
      const {'apps_examples|lib/lookalike.dart': _lookalikeColorWidget},
      captureErrors: true,
      logMatcher: allOf(
        contains("not Flutter's `Color`"),
        contains('matched by defining library'),
        contains('package:apps_examples/lookalike.dart'),
        isNot(contains('Supported types:')),
      ),
    );
  });

  test('a customer type named Widget is not accepted as Flutter Widget',
      () async {
    await _runProbe(
      const {'apps_examples|lib/lookalike_widget.dart': _lookalikeWidgetWidget},
      captureErrors: true,
      logMatcher: allOf(
        contains("not Flutter's `Widget`"),
        contains('matched by defining library'),
        contains('package:apps_examples/lookalike_widget.dart'),
        isNot(contains('Supported types:')),
      ),
    );
  });

  test('records Widgetbook auto-exclusions in the generated story artifact',
      () async {
    await _runProbe(
      const {
        'apps_examples|lib/host_state_card.dart': _hostStateWidget,
      },
      outputMatcher: allOf(
        contains(
          'const List<Map<String, String>> restageExclusions = [',
        ),
        contains('"widget": "HostStateCard"'),
        contains('"property": "hostState"'),
        contains('"target": "widgetbook"'),
        contains('Object?'),
      ),
    );
  });

  test('routes Widgetbook exclusions by source identity', () async {
    await _runProbe(
      const {
        'apps_examples|lib/first_card.dart': _firstSameNamedCard,
        'apps_examples|lib/second_card.dart': _secondSameNamedCard,
      },
      widgetName: 'SecondCard',
      outputMatcher: allOf(
        contains('class Card'),
        isNot(contains(r'$RestageExclusions')),
        isNot(contains('hostState')),
      ),
    );
  });

  test('malformed framework literal defaults fail with a default path',
      () async {
    await _runProbe(
      const {'apps_examples|lib/bad_default.dart': _badColorDefaultWidget},
      captureErrors: true,
      outputMatcher: allOf(
        contains('/defaults/color'),
        contains('valid color value'),
      ),
    );
  });

  test('constructor enum defaults are checked against allowed values',
      () async {
    await _runProbe(
      const {'apps_examples|lib/enum_default.dart': _enumDefaultWidget},
      captureErrors: true,
      outputMatcher: contains('/constructorDefaults/tone'),
    );
  });

  test('explicit null defaults are checked against allowed values', () async {
    await _runProbe(
      const {
        'apps_examples|lib/null_default.dart': _nullDefaultAllowedValueWidget,
      },
      captureErrors: true,
      outputMatcher: allOf(
        contains('/constructorDefaults/value'),
        contains('violates its constraints'),
      ),
    );
  });

  test('structural constructor defaults preserve the ordinary Dart story value',
      () async {
    await _runProbe(
      const {
        'apps_examples|lib/nonportable_default.dart':
            _nonportableConstructorDefaultWidget,
      },
      outputMatcher: allOf(
        contains(
          'this.color = const restage_native_0.Color.new(4281558681)',
        ),
        contains('restage_source.ColorDefaultCard(color: args.color)'),
      ),
    );
  });

  test('constraints without a deterministic valid seed fail loudly', () async {
    await _runProbe(
      const {'apps_examples|lib/patterned.dart': _patternedStringWidget},
      captureErrors: true,
      outputMatcher: allOf(
        contains('/generated/code'),
        contains('cannot deterministically satisfy its constraints'),
      ),
    );
  });

  test('nullable inputs may use null beside non-null constraints', () async {
    await _runProbe(
      const {'apps_examples|lib/nullable_pattern.dart': _nullablePatternWidget},
      outputMatcher: matches(
        RegExp(r'_RestageNullableStringArg\(\s+null,'),
      ),
    );
  });

  test('collection synthesis satisfies the minimum item count', () async {
    await _runProbe(
      const {'apps_examples|lib/constrained_list.dart': _constrainedListWidget},
      outputMatcher: allOf(
        matches(
          RegExp(
            r'<restage_native_\d+\.Widget>\[\s*'
            r'const restage_native_\d+\.SizedBox\.shrink\(\),\s*'
            r'const restage_native_\d+\.SizedBox\.shrink\(\),?\s*\]',
          ),
        ),
        isNot(matches(RegExp(r'<restage_native_\d+\.Widget>\[\]'))),
      ),
    );
  });

  test('enum controls retain the customer enum member labels', () async {
    await _runProbe(
      const {'apps_examples|lib/status.dart': _enumLabelWidget},
      outputMatcher: allOf(
        contains('_RestageChoice0.value0 => "ready"'),
        contains('_RestageChoice0.value1 => "processing"'),
        contains('required super.labelBuilder'),
      ),
    );
  });

  test('legacy validation rules reject invalid catalog defaults', () async {
    await _runProbe(
      const {'apps_examples|lib/legacy_invalid.dart': _legacyInvalidWidget},
      captureErrors: true,
      outputMatcher: allOf(
        contains('/constructorDefaults/score'),
        contains('violates its constraints'),
      ),
    );
  });

  test('legacy validation rules drive controls and sidebar descriptions',
      () async {
    await _runProbe(
      const {'apps_examples|lib/legacy_valid.dart': _legacyValidWidget},
      outputMatcher: allOf(
        contains('Inclusive range: 1–5.'),
        contains('SliderIntArgStyle(min: 1, max: 5, divisions: 4)'),
      ),
    );
  });

  test('portable constructor defaults retain sidebar provenance', () async {
    await _runProbe(
      const {
        'apps_examples|lib/constructor_default.dart': _constructorDefaultWidget,
      },
      outputMatcher: allOf(
        contains("Default: the widget constructor's Dart default."),
        contains('opacity: _RestageDoubleArg('),
        contains('      0.5,'),
      ),
    );
  });

  test('constructor default provenance wins over catalog default metadata',
      () async {
    await _runProbe(
      const {
        'apps_examples|lib/constructor_default_precedence.dart':
            _constructorDefaultPrecedenceWidget,
      },
      outputMatcher: allOf(
        contains(
          'Literal conflict. '
          "Default: the widget constructor's Dart default.",
        ),
        contains(
          'Token conflict. '
          "Default: the widget constructor's Dart default.",
        ),
        contains('opacity: _RestageDoubleArg('),
        contains('      0.5,'),
        matches(RegExp(r'label: _RestageStringArg\(\s*"constructor",')),
        isNot(contains('Default: 0.8.')),
        isNot(contains('Default: resolved from a design token at runtime.')),
      ),
    );
  });

  test('one-sided bounds remain descriptive without inventing a slider',
      () async {
    await _runProbe(
      const {'apps_examples|lib/bounded.dart': _boundedWidget},
      outputMatcher: allOf(<Matcher>[
        contains('Inclusive range: 0.1–unbounded.'),
        contains('_RestageDoubleArg('),
        isNot(contains('Slider')),
      ]),
    );
  });

  test('substituted super-formal inputs render as native story arguments',
      () async {
    await _runProbe(
      const {'apps_examples|lib/super_card.dart': _superFormalWidget},
      outputMatcher: allOf(
        contains('SuperCard('),
        contains('label:'),
        contains('_RestageStringArg'),
        isNot(contains('key:')),
      ),
    );
  });

  test('rejects a Widgetbook Meta collision at the widget property path',
      () async {
    await _runProbe(
      const {
        'restage_widgetbook_example|lib/models.dart': _metaModel,
        'restage_widgetbook_example|lib/customer_card.dart': _metaCard,
      },
      rootPackage: 'restage_widgetbook_example',
      includeWidgetbookNamespace: true,
      captureErrors: true,
      outputMatcher: allOf(
        contains('lib/customer_card.dart#CustomerCard.data'),
        contains('package:restage_widgetbook_example/models.dart#Meta'),
        contains('package:widgetbook/widgetbook.dart export'),
      ),
    );
  });

  test('rejects a model that collides with the source widget class', () async {
    await _runProbe(
      const {
        'apps_examples|lib/models.dart': _sameNamedWidgetModel,
        'apps_examples|lib/customer_card.dart': _sameNamedModelCard,
      },
      captureErrors: true,
      outputMatcher: allOf(
        contains('lib/customer_card.dart#CustomerCard.data'),
        contains('package:apps_examples/models.dart#CustomerCard'),
        contains('source widget import at lib/customer_card.dart#CustomerCard'),
      ),
    );
  });

  test('rejects a customer model that collides with implicit dart:core',
      () async {
    await _runProbe(
      const {
        'apps_examples|lib/models.dart': _stringModel,
        'apps_examples|lib/customer_card.dart': _stringModelCard,
      },
      captureErrors: true,
      outputMatcher: allOf(
        contains('lib/customer_card.dart#CustomerCard.data'),
        contains('package:apps_examples/models.dart#String'),
        contains('implicit dart:core namespace'),
      ),
    );
  });

  test('checks recursively required additional types for bare collisions',
      () async {
    await _runProbe(
      const {
        'restage_widgetbook_example|lib/models.dart': _metaModel,
        'restage_widgetbook_example|lib/customer_card.dart': _metaListCard,
      },
      rootPackage: 'restage_widgetbook_example',
      includeWidgetbookNamespace: true,
      captureErrors: true,
      outputMatcher: allOf(
        contains('lib/customer_card.dart#CustomerCard.items'),
        contains('package:restage_widgetbook_example/models.dart#Meta'),
        contains('package:widgetbook/widgetbook.dart export'),
      ),
    );
  });

  test('keeps a non-colliding source widget and customer model valid',
      () async {
    const sourceImport =
        "import 'package:apps_examples/customer_card.dart' show CustomerCard;";
    await _runProbe(
      const {
        'apps_examples|lib/models.dart': _cardDataModel,
        'apps_examples|lib/customer_card.dart': _cardDataCard,
      },
      outputMatcher: allOf(
        contains(
          "import 'package:apps_examples/models.dart' as restage_native_0;",
        ),
        contains(
          "import 'package:apps_examples/models.dart' show CardData;",
        ),
        contains('restage_native_0.CardData'),
        contains(sourceImport),
        predicate<String>(
          (source) => source.split(sourceImport).length == 2,
          'contains the source show import exactly once',
        ),
      ),
    );
  });

  test('rejects a source widget named for an actual Widgetbook export',
      () async {
    await _runProbe(
      const {
        'restage_widgetbook_example|lib/config.dart': _configWidget,
      },
      rootPackage: 'restage_widgetbook_example',
      includeWidgetbookNamespace: true,
      captureErrors: true,
      outputMatcher: allOf(
        contains('lib/config.dart#Config'),
        contains('package:widgetbook/widgetbook.dart export'),
        contains('conflicting bare namespace bindings'),
      ),
    );
  });

  test('rejects a source widget named for an implicit dart:core type',
      () async {
    await _runProbe(
      const {'apps_examples|lib/date_time.dart': _dateTimeWidget},
      captureErrors: true,
      outputMatcher: allOf(
        contains('lib/date_time.dart#DateTime'),
        contains('implicit dart:core namespace'),
        contains('conflicting bare namespace bindings'),
      ),
    );
  });
}

Future<void> _runProbe(
  Map<String, String> sources, {
  Matcher outputMatcher = anything,
  Matcher? logMatcher,
  bool captureErrors = false,
  String? widgetName,
  String rootPackage = 'apps_examples',
  bool includeWidgetbookNamespace = false,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: rootPackage,
  );
  final logs = <String>[];
  for (final entry in sources.entries) {
    final separator = entry.key.indexOf('|');
    readerWriter.testing.writeString(
      AssetId(
        entry.key.substring(0, separator),
        entry.key.substring(separator + 1),
      ),
      entry.value,
    );
  }
  if (includeWidgetbookNamespace) {
    readerWriter.testing
      ..writeString(
        AssetId('widgetbook', 'lib/widgetbook.dart'),
        "export 'src/meta.dart';",
      )
      ..writeString(
        AssetId('widgetbook', 'lib/src/meta.dart'),
        '''
class Config { const Config(); }
class Meta { const Meta(); }
''',
      );
  }
  await testBuilder(
    _StoryPlanProbeBuilder(
      captureErrors: captureErrors,
      widgetName: widgetName,
    ),
    sources,
    rootPackage: rootPackage,
    readerWriter: readerWriter,
    outputs: {
      '$rootPackage|lib/customer.stories.dart': decodedMatches(outputMatcher),
    },
    onLog: logMatcher == null
        ? null
        : (record) {
            logs.add('${record.level.name}: ${record.message}');
          },
  );
  if (logMatcher != null) {
    expect(logs.join('\n'), logMatcher);
  }
}

const _superFormalWidget = r'''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class BaseCard<T> extends StatelessWidget {
  const BaseCard({super.key, required this.label});

  /// Visible label.
  final T label;

  @override
  Widget build(BuildContext context) => Text('$label');
}

/// A concrete customer card.
@RestageWidget(
  name: 'SuperCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
)
class SuperCard extends BaseCard<String> {
  const SuperCard({super.key, required super.label});
}
''';

const _metaModel = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Meta {
  const Meta({required this.label});

  @RestageProperty(description: 'Metadata label.')
  final String label;
}
''';

const _metaCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'models.dart';

@RestageWidget(
  name: 'CustomerCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Customer card.',
)
class CustomerCard extends StatelessWidget {
  const CustomerCard({required this.data});

  @RestageProperty(description: 'Customer metadata.')
  final Meta data;

  @override
  Widget build(BuildContext context) => Text(data.label);
}
''';

const _sameNamedWidgetModel = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class CustomerCard {
  const CustomerCard({required this.label});

  @RestageProperty(description: 'Model label.')
  final String label;
}
''';

const _sameNamedModelCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'models.dart' as models;

@RestageWidget(
  name: 'CustomerCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Customer card.',
)
class CustomerCard extends StatelessWidget {
  const CustomerCard({required this.data});

  @RestageProperty(description: 'Customer data.')
  final models.CustomerCard data;

  @override
  Widget build(BuildContext context) => Text(data.label);
}
''';

const _stringModel = '''
import 'dart:core' as core;

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class String {
  const String({required this.value});

  @RestageProperty(description: 'Model value.')
  final core.String value;
}
''';

const _stringModelCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'models.dart' as models;

@RestageWidget(
  name: 'CustomerCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Customer card.',
)
class CustomerCard extends StatelessWidget {
  const CustomerCard({required this.data});

  @RestageProperty(description: 'Customer data.')
  final models.String data;

  @override
  Widget build(BuildContext context) => Text(data.value);
}
''';

const _metaListCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'models.dart';

@RestageWidget(
  name: 'CustomerCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Customer card.',
)
class CustomerCard extends StatelessWidget {
  const CustomerCard({required this.items});

  @RestageProperty(description: 'Customer metadata items.')
  final List<Meta> items;

  @override
  Widget build(BuildContext context) => Text(items.length.toString());
}
''';

const _cardDataModel = '''
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class CardData {
  const CardData({required this.label});

  @RestageProperty(description: 'Card label.')
  final String label;
}
''';

const _cardDataCard = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'models.dart';

@RestageWidget(
  name: 'CustomerCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Customer card.',
)
class CustomerCard extends StatelessWidget {
  const CustomerCard({required this.data});

  @RestageProperty(description: 'Customer data.')
  final CardData data;

  @override
  Widget build(BuildContext context) => Text(data.label);
}
''';

const _configWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'Config',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A customer widget named like a Widgetbook export.',
)
class Config extends StatelessWidget {
  const Config({required this.label});

  @RestageProperty(description: 'Visible label.')
  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}
''';

const _dateTimeWidget = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'DateTime',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'A customer widget named like a dart:core type.',
)
class DateTime extends StatelessWidget {
  const DateTime({required this.label});

  @RestageProperty(description: 'Visible label.')
  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}
''';

final class _StoryPlanProbeBuilder implements Builder {
  const _StoryPlanProbeBuilder({
    this.captureErrors = false,
    this.widgetName,
  });

  final bool captureErrors;
  final String? widgetName;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['customer.stories.dart'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    try {
      final index = await loadWidgetbookCatalogSourceIndex(buildStep);
      final widget = widgetName == null
          ? index.widgets.single
          : index.widgets.singleWhere(
              (candidate) => candidate.entry.name == widgetName,
            );
      final plan = planWidgetbookStory(
        index: index,
        widget: widget,
      );
      await buildStep.writeAsString(
        AssetId(buildStep.inputId.package, 'lib/customer.stories.dart'),
        renderWidgetbookStorySource(
          plan: plan,
          packageName: buildStep.inputId.package,
          sourcePath: widget.sourceAsset.path,
        ),
      );
    } catch (error) {
      if (!captureErrors) rethrow;
      await buildStep.writeAsString(
        AssetId(buildStep.inputId.package, 'lib/customer.stories.dart'),
        error.toString(),
      );
    }
  }
}

String _runtimeDefaultWidget(String defaultSource) => '''
  import 'package:flutter/material.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'CustomerCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Customer card.',
  )
  class CustomerCard extends StatelessWidget {
    const CustomerCard({this.color});
    @RestageProperty(
      description: 'Customer color.',
      defaultSource: $defaultSource,
    )
    final Color? color;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _lookalikeColorWidget = '''
  import 'package:flutter/widgets.dart' hide Color;
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  class Color {
    const Color();
  }

  @RestageWidget(
    name: 'LookalikeCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Lookalike card.',
  )
  class LookalikeCard extends StatelessWidget {
    const LookalikeCard({required this.color});
    @RestageProperty(
      description: 'Lookalike color.',
      defaultSource: LiteralDefault('#336699'),
    )
    final Color color;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _lookalikeWidgetWidget = '''
  import 'package:flutter/widgets.dart' as flutter;
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  class Widget {
    const Widget();
  }

  @RestageWidget(
    name: 'LookalikeWidgetCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Lookalike widget card.',
  )
  class LookalikeWidgetCard extends flutter.StatelessWidget {
    const LookalikeWidgetCard({this.child});
    @RestageProperty(description: 'Lookalike child.')
    final Widget? child;
    @override
    flutter.Widget build(flutter.BuildContext context) =>
        const flutter.SizedBox();
  }
''';

const _hostStateWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'HostStateCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Host state card.',
  )
  class HostStateCard extends StatelessWidget {
    const HostStateCard({required this.label, this.hostState});
    @RestageProperty(description: 'Visible label.')
    final String label;
    /// State supplied only by the host application.
    final Object? hostState;
    @override
    Widget build(BuildContext context) => Text(label);
  }
''';

const _firstSameNamedCard = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'FirstCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'First same-named card.',
  )
  class Card extends StatelessWidget {
    const Card({required this.label, this.hostState});
    @RestageProperty(description: 'Visible label.')
    final String label;
    /// State supplied only by the host application.
    final Object? hostState;
    @override
    Widget build(BuildContext context) => Text(label);
  }
''';

const _secondSameNamedCard = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'SecondCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Second same-named card.',
  )
  class Card extends StatelessWidget {
    const Card({required this.label});
    @RestageProperty(description: 'Visible label.')
    final String label;
    @override
    Widget build(BuildContext context) => Text(label);
  }
''';

const _badColorDefaultWidget = '''
  import 'package:flutter/material.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'BadDefaultCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Bad default card.',
  )
  class BadDefaultCard extends StatelessWidget {
    const BadDefaultCard({required this.color});
    @RestageProperty(
      description: 'Card color.',
      defaultSource: LiteralDefault('not-a-color'),
    )
    final Color color;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _enumDefaultWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  enum Tone { calm, urgent }

  @RestageWidget(
    name: 'EnumCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Enum card.',
  )
  class EnumCard extends StatelessWidget {
    const EnumCard({this.tone = Tone.urgent});
    @RestageProperty(
      description: 'Card tone.',
      constraints: RestageConstraints(allowedValues: ['calm']),
    )
    final Tone tone;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _nonportableConstructorDefaultWidget = '''
  import 'package:flutter/material.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'ColorDefaultCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Color default card.',
  )
  class ColorDefaultCard extends StatelessWidget {
    const ColorDefaultCard({this.color = const Color(0xFF336699)});
    @RestageProperty(description: 'Card color.')
    final Color color;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _nullDefaultAllowedValueWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'NullDefaultCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Null-default card.',
  )
  class NullDefaultCard extends StatelessWidget {
    const NullDefaultCard({this.value = null});
    @RestageProperty(
      description: 'Finite customer value.',
      constraints: RestageConstraints(allowedValues: ['ready']),
    )
    final String? value;
    @override
    Widget build(BuildContext context) => Text(value ?? 'none');
  }
''';

const _patternedStringWidget = r'''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'PatternedCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Patterned card.',
  )
  class PatternedCard extends StatelessWidget {
    const PatternedCard({required this.code});
    @RestageProperty(
      description: 'Uppercase code.',
      constraints: RestageConstraints(pattern: r'^[A-Z]+$'),
    )
    final String code;
    @override
    Widget build(BuildContext context) => Text(code);
  }
''';

const _nullablePatternWidget = r'''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'NullablePatternCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Nullable patterned card.',
  )
  class NullablePatternCard extends StatelessWidget {
    const NullablePatternCard({this.code});
    @RestageProperty(
      description: 'Optional uppercase code.',
      constraints: RestageConstraints(pattern: r'^[A-Z]+$'),
    )
    final String? code;
    @override
    Widget build(BuildContext context) => Text(code ?? 'none');
  }
''';

const _constrainedListWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'ConstrainedListCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.layout,
    description: 'Constrained list card.',
    childrenSlot: ChildrenSlot.list,
  )
  class ConstrainedListCard extends StatelessWidget {
    const ConstrainedListCard({required this.children});
    @RestageProperty(
      description: 'Customer children.',
      constraints: RestageConstraints(minItems: 2, maxItems: 3),
    )
    final List<Widget> children;
    @override
    Widget build(BuildContext context) => Column(children: children);
  }
''';

const _enumLabelWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  enum Status { ready, processing }

  @RestageWidget(
    name: 'StatusCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Status card.',
  )
  class StatusCard extends StatelessWidget {
    const StatusCard({required this.status});
    @RestageProperty(description: 'Current status.')
    final Status status;
    @override
    Widget build(BuildContext context) => Text(status.name);
  }
''';

const _boundedWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'BoundedCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Bounded card.',
  )
  class BoundedCard extends StatelessWidget {
    const BoundedCard({this.opacity = 0.5});
    @RestageProperty(
      description: 'Card opacity.',
      constraints: RestageConstraints(minimum: 0.1),
    )
    final double opacity;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _legacyInvalidWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'LegacyInvalidCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Legacy invalid card.',
  )
  class LegacyInvalidCard extends StatelessWidget {
    const LegacyInvalidCard({this.score = 9});
    @RestageProperty(
      description: 'Card score.',
      defaultSource: LiteralDefault(9),
      validationRule: ValidationExpr(
        expression: 'range(1, 5)',
        message: 'Score must be between one and five.',
      ),
    )
    final int score;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _legacyValidWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'LegacyValidCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Legacy valid card.',
  )
  class LegacyValidCard extends StatelessWidget {
    const LegacyValidCard({this.score = 3});
    @RestageProperty(
      description: 'Card score.',
      defaultSource: LiteralDefault(3),
      validationRule: ValidationExpr(
        expression: 'range(1, 5)',
        message: 'Score must be between one and five.',
      ),
    )
    final int score;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _constructorDefaultWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'ConstructorDefaultCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Constructor default card.',
  )
  class ConstructorDefaultCard extends StatelessWidget {
    const ConstructorDefaultCard({this.opacity = 0.5});
    @RestageProperty(description: 'Card opacity.')
    final double opacity;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';

const _constructorDefaultPrecedenceWidget = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'ConstructorDefaultPrecedenceCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'Constructor default precedence card.',
  )
  class ConstructorDefaultPrecedenceCard extends StatelessWidget {
    const ConstructorDefaultPrecedenceCard({
      this.opacity = 0.5,
      this.label = 'constructor',
    });
    @RestageProperty(
      description: 'Literal conflict.',
      defaultSource: LiteralDefault(0.8),
    )
    final double opacity;
    @RestageProperty(
      description: 'Token conflict.',
      defaultSource: TokenRefDefault(
        WireIdRef(
          library: 'fixture.tokens',
          wireId: WireId.unallocatedDesignToken,
        ),
      ),
    )
    final String label;
    @override
    Widget build(BuildContext context) => const SizedBox();
  }
''';
