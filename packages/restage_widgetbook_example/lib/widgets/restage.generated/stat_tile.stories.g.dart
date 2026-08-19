// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering, unused_element, strict_raw_type

part of 'stat_tile.stories.dart';

// **************************************************************************
// StoryGenerator
// **************************************************************************

typedef _Component = Component<StatTile, StoryArgs<StatTile>>;
typedef _Scenario = StatTileScenario;
typedef _Defaults = StatTileDefaults;
typedef _Story = StatTileStory;
typedef _Args = StatTileStoryInputArgs;
final StatTileComponent = Component<StatTile, StoryArgs<StatTile>>(
  name: component.name ?? 'StatTile',
  path: component.path ?? 'widgets/restage.generated',
  docsBuilder: component.docsBuilder,
  docComment: r'''A labelled value tile, e.g. "Active users" over "1,204".''',
  stories: [$RestageCatalog..$generatedName = 'RestageCatalog'],
);
typedef StatTileScenario = Scenario<StatTile, StatTileStoryInputArgs>;
typedef StatTileDefaults = Defaults<StatTile, StatTileStoryInputArgs>;

class StatTileStory extends Story<StatTile, StatTileStoryInputArgs> {
  StatTileStory({
    super.name,
    super.designLink,
    super.setup,
    super.modes,
    StatTileStoryInputArgs? args,
    StoryWidgetBuilder<StatTile, StatTileStoryInputArgs>? builder,
    super.scenarios,
    super.excludeFromTests,
  }) : super(
         args: args ?? StatTileStoryInputArgs(),
         builder: builder ?? defaults.builder!,
       );
}

class StatTileStoryInputArgs extends StoryArgs<StatTile> {
  StatTileStoryInputArgs({
    Arg<String>? restageMetadataDescription,
    Arg<String>? restageMetadataUsage,
    Arg<String>? label,
    Arg<String>? value,
  }) : this.restageMetadataDescriptionArg = $initArg(
         'restageMetadataDescription',
         restageMetadataDescription,
         StringArg(
           "A labelled value tile, e.g. \"Active users\" over \"1,204\".",
         ),
       )!,
       this.restageMetadataUsageArg = $initArg(
         'restageMetadataUsage',
         restageMetadataUsage,
         StringArg(
           "A labelled value tile, e.g. \"Active users\" over \"1,204\".",
         ),
       )!,
       this.labelArg = $initArg('label', label, StringArg("Active users"))!,
       this.valueArg = $initArg('value', value, StringArg("1,204"))!;

  StatTileStoryInputArgs.fixed({
    String restageMetadataDescription =
        "A labelled value tile, e.g. \"Active users\" over \"1,204\".",
    String restageMetadataUsage =
        "A labelled value tile, e.g. \"Active users\" over \"1,204\".",
    String label = "Active users",
    String value = "1,204",
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
       this.labelArg = $initArg('label', Arg.fixed(label), null)!,
       this.valueArg = $initArg('value', Arg.fixed(value), null)!;

  final Arg<String> restageMetadataDescriptionArg;

  final Arg<String> restageMetadataUsageArg;

  final Arg<String> labelArg;

  final Arg<String> valueArg;

  String get restageMetadataDescription => restageMetadataDescriptionArg.value;

  String get restageMetadataUsage => restageMetadataUsageArg.value;

  String get label => labelArg.value;

  String get value => valueArg.value;

  @override
  List<Arg?> get list => [
    restageMetadataDescriptionArg,
    restageMetadataUsageArg,
    labelArg,
    valueArg,
  ];
}
