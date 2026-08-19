// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering, unused_element, strict_raw_type

part of 'feature_row.stories.dart';

// **************************************************************************
// StoryGenerator
// **************************************************************************

typedef _Component = Component<FeatureRow, StoryArgs<FeatureRow>>;
typedef _Scenario = FeatureRowScenario;
typedef _Defaults = FeatureRowDefaults;
typedef _Story = FeatureRowStory;
typedef _Args = FeatureRowStoryInputArgs;
final FeatureRowComponent = Component<FeatureRow, StoryArgs<FeatureRow>>(
  name: component.name ?? 'FeatureRow',
  path: component.path ?? 'widgets/restage.generated',
  docsBuilder: component.docsBuilder,
  docComment: r'''A feature-list row: check icon, title, and subtitle.''',
  stories: [$RestageCatalog..$generatedName = 'RestageCatalog'],
);
typedef FeatureRowScenario = Scenario<FeatureRow, FeatureRowStoryInputArgs>;
typedef FeatureRowDefaults = Defaults<FeatureRow, FeatureRowStoryInputArgs>;

class FeatureRowStory extends Story<FeatureRow, FeatureRowStoryInputArgs> {
  FeatureRowStory({
    super.name,
    super.designLink,
    super.setup,
    super.modes,
    FeatureRowStoryInputArgs? args,
    StoryWidgetBuilder<FeatureRow, FeatureRowStoryInputArgs>? builder,
    super.scenarios,
    super.excludeFromTests,
  }) : super(
         args: args ?? FeatureRowStoryInputArgs(),
         builder: builder ?? defaults.builder!,
       );
}

class FeatureRowStoryInputArgs extends StoryArgs<FeatureRow> {
  FeatureRowStoryInputArgs({
    Arg<String>? restageMetadataDescription,
    Arg<String>? restageMetadataUsage,
    Arg<String>? title,
    Arg<String>? subtitle,
  }) : this.restageMetadataDescriptionArg = $initArg(
         'restageMetadataDescription',
         restageMetadataDescription,
         StringArg("A feature-list row: check icon, title, and subtitle."),
       )!,
       this.restageMetadataUsageArg = $initArg(
         'restageMetadataUsage',
         restageMetadataUsage,
         StringArg("A feature-list row: check icon, title, and subtitle."),
       )!,
       this.titleArg = $initArg(
         'title',
         title,
         StringArg("Unlimited projects"),
       )!,
       this.subtitleArg = $initArg(
         'subtitle',
         subtitle,
         StringArg("No caps on what you ship."),
       )!;

  FeatureRowStoryInputArgs.fixed({
    String restageMetadataDescription =
        "A feature-list row: check icon, title, and subtitle.",
    String restageMetadataUsage =
        "A feature-list row: check icon, title, and subtitle.",
    String title = "Unlimited projects",
    String subtitle = "No caps on what you ship.",
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
       this.titleArg = $initArg('title', Arg.fixed(title), null)!,
       this.subtitleArg = $initArg('subtitle', Arg.fixed(subtitle), null)!;

  final Arg<String> restageMetadataDescriptionArg;

  final Arg<String> restageMetadataUsageArg;

  final Arg<String> titleArg;

  final Arg<String> subtitleArg;

  String get restageMetadataDescription => restageMetadataDescriptionArg.value;

  String get restageMetadataUsage => restageMetadataUsageArg.value;

  String get title => titleArg.value;

  String get subtitle => subtitleArg.value;

  @override
  List<Arg?> get list => [
    restageMetadataDescriptionArg,
    restageMetadataUsageArg,
    titleArg,
    subtitleArg,
  ];
}
