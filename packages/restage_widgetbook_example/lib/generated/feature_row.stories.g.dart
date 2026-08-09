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
  path: component.path ?? 'generated',
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
    Arg<String>? description,
    Arg<String>? usage,
    Arg<String>? title,
    Arg<String>? subtitle,
  }) : this.descriptionArg = $initArg(
         'description',
         description,
         StringArg("A feature-list row: check icon, title, and subtitle."),
       )!,
       this.usageArg = $initArg(
         'usage',
         usage,
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
    String description = "A feature-list row: check icon, title, and subtitle.",
    String usage = "A feature-list row: check icon, title, and subtitle.",
    String title = "Unlimited projects",
    String subtitle = "No caps on what you ship.",
  }) : this.descriptionArg = $initArg(
         'description',
         Arg.fixed(description),
         null,
       )!,
       this.usageArg = $initArg('usage', Arg.fixed(usage), null)!,
       this.titleArg = $initArg('title', Arg.fixed(title), null)!,
       this.subtitleArg = $initArg('subtitle', Arg.fixed(subtitle), null)!;

  final Arg<String> descriptionArg;

  final Arg<String> usageArg;

  final Arg<String> titleArg;

  final Arg<String> subtitleArg;

  String get description => descriptionArg.value;

  String get usage => usageArg.value;

  String get title => titleArg.value;

  String get subtitle => subtitleArg.value;

  @override
  List<Arg?> get list => [descriptionArg, usageArg, titleArg, subtitleArg];
}
