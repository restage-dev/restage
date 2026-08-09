import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_catalog_source_index.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_native_value_plan.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_property_capability.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_plan.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_source_renderer.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('Widgetbook planner totality has no wildcard escape hatches', () {
    final nativePlan = File(
      'lib/src/widgetbook/widgetbook_native_value_plan.dart',
    ).readAsStringSync();
    final storyPlan = File(
      'lib/src/widgetbook/widgetbook_story_plan.dart',
    ).readAsStringSync();
    final renderer = File(
      'lib/src/widgetbook/widgetbook_story_source_renderer.dart',
    ).readAsStringSync();

    expect(
      nativePlan,
      isNot(contains("_ => throw StateError(\n          'Widgetbook native")),
    );
    expect(
      nativePlan,
      isNot(
        contains("_ => throw StateError(\n          'unsupported framework"),
      ),
    );
    expect(nativePlan, isNot(contains('case _:\n      break;')));
    expect(
      storyPlan,
      isNot(contains("_ => throw StateError(\n        \"property '")),
    );
    expect(renderer, isNot(contains('property.seed!')));
    expect(renderer, isNot(contains('property.callback!')));
  });

  test('declared capability matrix is exhaustive', () {
    const rootNative = <PropertyType>{
      PropertyType.widget,
      PropertyType.widgetList,
      PropertyType.color,
      PropertyType.edgeInsets,
      PropertyType.alignment,
      PropertyType.offset,
      PropertyType.fontWeight,
      PropertyType.duration,
      PropertyType.curve,
      PropertyType.boolean,
      PropertyType.integer,
      PropertyType.real,
      PropertyType.string,
      PropertyType.event,
      PropertyType.enumValue,
      PropertyType.structured,
    };
    const structuredNative = <PropertyType>{
      PropertyType.color,
      PropertyType.edgeInsets,
      PropertyType.alignment,
      PropertyType.offset,
      PropertyType.fontWeight,
      PropertyType.duration,
      PropertyType.curve,
      PropertyType.boolean,
      PropertyType.integer,
      PropertyType.real,
      PropertyType.string,
      PropertyType.stringList,
      PropertyType.enumValue,
      PropertyType.structured,
    };

    Set<PropertyType> nativeFor(WidgetbookPropertyContext context) => {
          for (final type in PropertyType.values)
            if (widgetbookPropertyCapability(type, context: context) ==
                WidgetbookPropertyCapability.native)
              type,
        };

    expect(
      nativeFor(WidgetbookPropertyContext.widgetProperty),
      rootNative,
    );
    expect(
      nativeFor(WidgetbookPropertyContext.structuredField),
      structuredNative,
    );
  });

  test(
    'analyzer corpus lowers every admitted root and structured-leaf family',
    () async {
      final sources = <String, String>{
        'apps_examples|lib/capability_widget.dart': _capabilityWidget,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/capability_widget.dart'),
        _capabilityWidget,
      );

      await testBuilder(
        const _CapabilityCorpusBuilder(),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/widgetbook_capability.txt': decodedMatches(
            allOf(<Matcher>[
              contains(
                'roots=child:widget,children:widgetList,color:color,'
                'padding:edgeInsets,alignment:alignment,offset:offset,'
                'weight:fontWeight,duration:duration,curve:curve,'
                'enabled:boolean,count:integer,ratio:real,label:string,'
                'onTap:event,tone:enumValue,data:structured,'
                'dataItems:unknown',
              ),
              contains(
                'leaves=color:color,padding:edgeInsets,'
                'alignment:alignment,offset:offset,weight:fontWeight,'
                'duration:duration,curve:curve,enabled:boolean,'
                'count:integer,ratio:real,label:string,tags:stringList,'
                'tone:enumValue,nested:structured,nestedItems:unknown',
              ),
              contains('class CapabilityWidgetStoryInput'),
              contains('CapabilityWidget('),
              contains('.SizedBox.shrink()'),
              contains('CapabilityData('),
              contains('CapabilityNested('),
              contains('_RestageConstArg'),
              contains('_RestageColorArg'),
              contains('_RestageDurationArg'),
              contains('_RestageStringArg'),
              contains('_RestageBoolArg'),
              contains('_RestageIntArg'),
              contains('_RestageDoubleArg'),
            ]),
          ),
        },
      );
    },
  );

  test('dart:ui-only values import and qualify their exact Dart library', () {
    final values = <WidgetbookNativeValuePlan>[
      const WidgetbookFrameworkValuePlan(
        type: WidgetbookDartTypePlan(
          libraryUri: 'dart:ui',
          symbol: 'Color',
        ),
        kind: WidgetbookFrameworkLiteralKind.color,
        value: '#336699',
      ),
      const WidgetbookFrameworkValuePlan(
        type: WidgetbookDartTypePlan(
          libraryUri: 'dart:ui',
          symbol: 'Offset',
        ),
        kind: WidgetbookFrameworkLiteralKind.offset,
        value: {'x': 1, 'y': 2},
      ),
    ];
    final renderer = WidgetbookNativeDartRenderer(
      currentLibraryUri: 'package:apps_examples/widget.dart',
      values: values,
    );

    expect(
      renderer.importDirectives,
      contains("import 'dart:ui' as restage_native_0;"),
    );
    expect(
      renderer.renderValue(values[0]),
      'const restage_native_0.Color(0xFF336699)',
    );
    expect(
      renderer.renderValue(values[1]),
      'const restage_native_0.Offset(1, 2)',
    );
  });

  test('static members and generic constructors share recursive prefixes', () {
    const same = WidgetbookDartTypePlan(
      libraryUri: 'package:a/model.dart',
      symbol: 'Same',
      nullable: true,
    );
    const seed = WidgetbookStaticMemberValuePlan(
      type: WidgetbookDartTypePlan(
        libraryUri: 'package:a/model.dart',
        symbol: 'Same',
      ),
      libraryUri: 'package:a/model.dart',
      owner: 'Defaults',
      member: 'seed',
    );
    const value = WidgetbookConstructorValuePlan(
      type: WidgetbookDartTypePlan(
        libraryUri: 'package:b/box.dart',
        symbol: 'Box',
        typeArguments: [same],
      ),
      namedConstructor: 'filled',
      arguments: [WidgetbookNativeArgumentPlan(value: seed)],
    );
    final renderer = WidgetbookNativeDartRenderer(
      currentLibraryUri: 'package:z/widget.dart',
      values: const [value],
    );

    expect(
      renderer.importDirectives,
      containsAll([
        "import 'package:a/model.dart' as restage_native_0;",
        "import 'package:b/box.dart' as restage_native_1;",
      ]),
    );
    expect(
      renderer.renderValue(value),
      'restage_native_1.Box<restage_native_0.Same?>.filled('
      'restage_native_0.Defaults.seed)',
    );
  });

  test(
    'synthesizes widgets, widget lists, and nested customer data from Dart',
    () async {
      final sources = <String, String>{
        'apps_examples|lib/models.dart': _models,
        'apps_examples|lib/leaf.dart': _leaf,
        'apps_examples|lib/rich_card.dart': _richCard,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
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

      await testBuilder(
        const _NativePlanProbeBuilder(),
        sources,
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/native_plan.txt': decodedMatches(
            allOf(<Matcher>[
              contains("import 'package:flutter/painting.dart' as "),
              contains("import 'package:flutter/widgets.dart' as "),
              contains("import 'package:apps_examples/models.dart' as "),
              contains('child='),
              contains('.SizedBox.shrink()'),
              contains('children=<restage_native_'),
              contains('data='),
              contains('CardData('),
              contains('title: ""'),
              contains('Tone.neutral'),
              contains('BadgeData(label: "", score: 0)'),
              contains('BadgeData>[]'),
              contains('.EdgeInsets.fromLTRB(0, 0, 0, 0)'),
            ]),
          ),
          'apps_examples|lib/rich_card.stories.dart': decodedMatches(
            allOf(<Matcher>[
              contains(
                "import 'package:widgetbook/widgetbook.dart';",
              ),
              contains(
                "import 'package:widgetbook/widgetbook.dart' as widgetbook;",
              ),
              contains(
                "import 'package:apps_examples/rich_card.dart' show RichCard;",
              ),
              contains(
                "import 'package:apps_examples/rich_card.dart' "
                'as restage_source;',
              ),
              contains(
                "import 'package:apps_examples/models.dart' "
                'as restage_native_',
              ),
              contains(
                "import 'package:apps_examples/models.dart' show CardData;",
              ),
              contains(
                "import 'package:flutter/widgets.dart' as restage_native_",
              ),
              contains(
                "import 'package:flutter/widgets.dart' show Widget;",
              ),
              contains('class RichCardStoryInput'),
              contains('final String description;'),
              contains('final String usage;'),
              contains('const meta = widgetbook.Meta('),
              contains('restage_source.RichCard.new'),
              contains('const component = widgetbook.ComponentMeta('),
              isNot(contains('docsBuilder')),
              contains(r'final $RestageCatalog = _Story('),
              contains("name: 'description'"),
              contains("name: 'usage'"),
              contains('child: _RestageConstArg<_RestageValue0>'),
              contains('children: _RestageConstArg<_RestageValue1>'),
              contains('data: _RestageConstArg<_RestageValue2>'),
              isNot(contains('args: _Args.fixed(')),
              contains('.SizedBox.shrink()'),
              contains('CardData('),
            ]),
          ),
        },
      );
    },
  );
}

final class _NativePlanProbeBuilder implements Builder {
  const _NativePlanProbeBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['native_plan.txt', 'rich_card.stories.dart'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final index = await loadWidgetbookCatalogSourceIndex(buildStep);
    final widget = index.widgets.singleWhere(
      (candidate) => candidate.entry.name == 'RichCard',
    );
    final planner = WidgetbookNativeValuePlanner(index);
    final values = <String, WidgetbookNativeValuePlan>{
      for (final property in widget.entry.properties)
        if (property.type.name != 'event')
          property.name: planner.synthesizeProperty(
            widget: widget,
            property: property,
            minimumItems: 0,
            path: '/generated/${property.name}',
          ),
    };
    final renderer = WidgetbookNativeDartRenderer(
      currentLibraryUri: widget.entry.flutterType.split('#').first,
      values: values.values,
    );
    final output = StringBuffer();
    renderer.importDirectives.forEach(output.writeln);
    for (final entry in values.entries) {
      output.writeln('${entry.key}=${renderer.renderValue(entry.value)}');
    }
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/native_plan.txt'),
      output.toString(),
    );
    final storyPlan = planWidgetbookStory(
      index: index,
      widget: widget,
    );
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/rich_card.stories.dart'),
      renderWidgetbookStorySource(
        plan: storyPlan,
        packageName: buildStep.inputId.package,
        sourcePath: widget.sourceAsset.path,
      ),
    );
  }
}

final class _CapabilityCorpusBuilder implements Builder {
  const _CapabilityCorpusBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['widgetbook_capability.txt'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final index = await loadWidgetbookCatalogSourceIndex(buildStep);
    final widget = index.widgets.singleWhere(
      (candidate) => candidate.entry.name == 'CapabilityWidget',
    );
    final structured = index.structuredTypes.singleWhere(
      (candidate) => candidate.name == 'CapabilityData',
    );
    final plan = planWidgetbookStory(index: index, widget: widget);
    final rendered = renderWidgetbookStorySource(
      plan: plan,
      packageName: buildStep.inputId.package,
      sourcePath: widget.sourceAsset.path,
    );
    final output = StringBuffer()
      ..writeln(
        'roots=${widget.entry.properties.map(
              (property) => '${property.name}:${property.type.name}',
            ).join(',')}',
      )
      ..writeln(
        'leaves=${structured.fields.map(
              (field) => '${field.name}:${field.type.name}',
            ).join(',')}',
      )
      ..write(rendered);
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/widgetbook_capability.txt'),
      output.toString(),
    );
  }
}

const _models = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  enum Tone { neutral, warning }

  class BadgeData {
    const BadgeData({required this.label, required this.score});
    @RestageProperty(description: 'Badge label.')
    final String label;
    @RestageProperty(description: 'Badge score.')
    final int score;
  }

  class CardData {
    const CardData({
      required this.title,
      required this.tone,
      required this.badge,
      required this.badges,
      required this.padding,
    });
    @RestageProperty(description: 'Card title.')
    final String title;
    @RestageProperty(description: 'Card tone.')
    final Tone tone;
    @RestageProperty(description: 'Primary badge.')
    final BadgeData badge;
    @RestageProperty(description: 'Related badges.')
    final List<BadgeData> badges;
    @RestageProperty(description: 'Card padding.')
    final EdgeInsets padding;
  }
''';

const _leaf = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  @RestageWidget(
    name: 'Leaf',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'A customer leaf.',
  )
  class Leaf extends StatelessWidget {
    const Leaf({required this.label, required this.onTap});
    @RestageProperty(description: 'Visible label.')
    final String label;
    @RestageProperty(description: 'Handles a tap.', required: true)
    final VoidCallback onTap;
    @override
    Widget build(BuildContext context) => Text(label);
  }
''';

const _richCard = '''
  import 'package:flutter/widgets.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
  import 'models.dart';

  @RestageWidget(
    name: 'RichCard',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
    description: 'A customer rich card.',
    usage: 'Use for customer-owned rich content.',
  )
  class RichCard extends StatelessWidget {
    const RichCard({
      required this.child,
      required this.children,
      required this.data,
    });
    @RestageProperty(description: 'Primary child.')
    final Widget child;
    @RestageProperty(description: 'Additional children.')
    final List<Widget> children;
    @RestageProperty(description: 'Customer data.')
    final CardData data;
    @override
    Widget build(BuildContext context) => child;
  }
''';

const _capabilityWidget = '''
  import 'package:flutter/material.dart';
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

  enum CapabilityTone { neutral, emphasized }

  /// The nested customer-owned value in the capability corpus.
  class CapabilityNested {
    const CapabilityNested({required this.label});

    /// Nested text.
    final String label;
  }

  /// Customer-owned structured data spanning every admitted leaf family.
  class CapabilityData {
    const CapabilityData({
      required this.color,
      required this.padding,
      required this.alignment,
      required this.offset,
      required this.weight,
      required this.duration,
      required this.curve,
      required this.enabled,
      required this.count,
      required this.ratio,
      required this.label,
      required this.tags,
      required this.tone,
      required this.nested,
      required this.nestedItems,
    });

    /// Customer color.
    final Color color;

    /// Customer padding.
    final EdgeInsets padding;

    /// Customer alignment.
    final Alignment alignment;

    /// Customer offset.
    final Offset offset;

    /// Customer font weight.
    final FontWeight weight;

    /// Customer duration.
    final Duration duration;

    /// Customer curve.
    final Curve curve;

    /// Customer boolean.
    final bool enabled;

    /// Customer integer.
    final int count;

    /// Customer real number.
    final double ratio;

    /// Customer text.
    final String label;

    /// Customer text list.
    final List<String> tags;

    /// Customer enum.
    final CapabilityTone tone;

    /// Nested customer data.
    final CapabilityNested nested;

    /// A list of nested customer data.
    final List<CapabilityNested> nestedItems;
  }

  /// Customer widget spanning every admitted root family.
  @RestageWidget(
    name: 'CapabilityWidget',
    library: WidgetLibrary.custom('fixture.widgets'),
    category: WidgetCategory.decoration,
  )
  class CapabilityWidget extends StatelessWidget {
    const CapabilityWidget({
      super.key,
      required this.child,
      required this.children,
      required this.color,
      required this.padding,
      required this.alignment,
      required this.offset,
      required this.weight,
      required this.duration,
      required this.curve,
      required this.enabled,
      required this.count,
      required this.ratio,
      required this.label,
      required this.onTap,
      required this.tone,
      required this.data,
      required this.dataItems,
    });

    /// Primary child.
    final Widget child;

    /// Additional children.
    final List<Widget> children;

    /// Root color.
    final Color color;

    /// Root padding.
    final EdgeInsets padding;

    /// Root alignment.
    final Alignment alignment;

    /// Root offset.
    final Offset offset;

    /// Root font weight.
    final FontWeight weight;

    /// Root duration.
    final Duration duration;

    /// Root curve.
    final Curve curve;

    /// Root boolean.
    final bool enabled;

    /// Root integer.
    final int count;

    /// Root real number.
    final double ratio;

    /// Root text.
    final String label;

    /// Root callback.
    final VoidCallback onTap;

    /// Root enum.
    final CapabilityTone tone;

    /// Root customer data.
    final CapabilityData data;

    /// Root customer data list.
    final List<CapabilityData> dataItems;

    @override
    Widget build(BuildContext context) => child;
  }
''';
