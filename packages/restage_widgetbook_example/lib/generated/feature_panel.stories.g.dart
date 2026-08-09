// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering, unused_element, strict_raw_type

part of 'feature_panel.stories.dart';

// **************************************************************************
// StoryGenerator
// **************************************************************************

typedef _Component = Component<FeaturePanel, StoryArgs<FeaturePanel>>;
typedef _Scenario = FeaturePanelScenario;
typedef _Defaults = FeaturePanelDefaults;
typedef _Story = FeaturePanelStory;
typedef _Args = FeaturePanelStoryInputArgs;
final FeaturePanelComponent = Component<FeaturePanel, StoryArgs<FeaturePanel>>(
  name: component.name ?? 'FeaturePanel',
  path: component.path ?? 'generated',
  docsBuilder: component.docsBuilder,
  docComment:
      r'''A panel with a customer header and customer content widgets.''',
  stories: [$RestageCatalog..$generatedName = 'RestageCatalog'],
);
typedef FeaturePanelScenario =
    Scenario<FeaturePanel, FeaturePanelStoryInputArgs>;
typedef FeaturePanelDefaults =
    Defaults<FeaturePanel, FeaturePanelStoryInputArgs>;

class FeaturePanelStory
    extends Story<FeaturePanel, FeaturePanelStoryInputArgs> {
  FeaturePanelStory({
    super.name,
    super.designLink,
    super.setup,
    super.modes,
    FeaturePanelStoryInputArgs? args,
    StoryWidgetBuilder<FeaturePanel, FeaturePanelStoryInputArgs>? builder,
    super.scenarios,
    super.excludeFromTests,
  }) : super(
         args: args ?? FeaturePanelStoryInputArgs(),
         builder: builder ?? defaults.builder!,
       );
}

class FeaturePanelStoryInputArgs extends StoryArgs<FeaturePanel> {
  FeaturePanelStoryInputArgs({
    Arg<String>? description,
    Arg<String>? usage,
    Arg<_RestageValue0>? header,
    Arg<_RestageValue1>? children,
  }) : this.descriptionArg = $initArg(
         'description',
         description,
         StringArg(
           "A panel with a customer header and customer content widgets.",
         ),
       )!,
       this.usageArg = $initArg(
         'usage',
         usage,
         StringArg("Use to group a compact catalog summary."),
       )!,
       this.headerArg = $initArg(
         'header',
         header,
         ConstArg(const _RestageValue0.absent()),
       )!,
       this.childrenArg = $initArg(
         'children',
         children,
         ConstArg(const _RestageValue1.absent()),
       )!;

  FeaturePanelStoryInputArgs.fixed({
    String description =
        "A panel with a customer header and customer content widgets.",
    String usage = "Use to group a compact catalog summary.",
    _RestageValue0 header = const _RestageValue0.absent(),
    _RestageValue1 children = const _RestageValue1.absent(),
  }) : this.descriptionArg = $initArg(
         'description',
         Arg.fixed(description),
         null,
       )!,
       this.usageArg = $initArg('usage', Arg.fixed(usage), null)!,
       this.headerArg = $initArg('header', Arg.fixed(header), null)!,
       this.childrenArg = $initArg('children', Arg.fixed(children), null)!;

  final Arg<String> descriptionArg;

  final Arg<String> usageArg;

  final Arg<_RestageValue0> headerArg;

  final Arg<_RestageValue1> childrenArg;

  String get description => descriptionArg.value;

  String get usage => usageArg.value;

  _RestageValue0 get header => headerArg.value;

  _RestageValue1 get children => childrenArg.value;

  @override
  List<Arg?> get list => [descriptionArg, usageArg, headerArg, childrenArg];
}
