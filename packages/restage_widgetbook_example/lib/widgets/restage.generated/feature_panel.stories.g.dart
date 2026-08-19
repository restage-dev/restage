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
  path: component.path ?? 'widgets/restage.generated',
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
    Arg<String>? restageMetadataDescription,
    Arg<String>? restageMetadataUsage,
    Arg<_RestageValue0>? header,
    Arg<_RestageValue1>? children,
  }) : this.restageMetadataDescriptionArg = $initArg(
         'restageMetadataDescription',
         restageMetadataDescription,
         StringArg(
           "A panel with a customer header and customer content widgets.",
         ),
       )!,
       this.restageMetadataUsageArg = $initArg(
         'restageMetadataUsage',
         restageMetadataUsage,
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
    String restageMetadataDescription =
        "A panel with a customer header and customer content widgets.",
    String restageMetadataUsage = "Use to group a compact catalog summary.",
    _RestageValue0 header = const _RestageValue0.absent(),
    _RestageValue1 children = const _RestageValue1.absent(),
  }) : this.restageMetadataDescriptionArg = $initArg(
         'restageMetadataDescription',
         Arg.fixed(restageMetadataDescription),
         null,
       )!,
       this.restageMetadataUsageArg = $initArg(
         'restageMetadataUsage',
         Arg.fixed(restageMetadataUsage),
         null,
       )!,
       this.headerArg = $initArg('header', Arg.fixed(header), null)!,
       this.childrenArg = $initArg('children', Arg.fixed(children), null)!;

  final Arg<String> restageMetadataDescriptionArg;

  final Arg<String> restageMetadataUsageArg;

  final Arg<_RestageValue0> headerArg;

  final Arg<_RestageValue1> childrenArg;

  String get restageMetadataDescription => restageMetadataDescriptionArg.value;

  String get restageMetadataUsage => restageMetadataUsageArg.value;

  _RestageValue0 get header => headerArg.value;

  _RestageValue1 get children => childrenArg.value;

  @override
  List<Arg?> get list => [
    restageMetadataDescriptionArg,
    restageMetadataUsageArg,
    headerArg,
    childrenArg,
  ];
}
