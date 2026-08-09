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
  path: component.path ?? 'generated',
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
    Arg<String>? description,
    Arg<String>? usage,
    Arg<String>? label,
    Arg<String>? value,
  }) : this.descriptionArg = $initArg(
         'description',
         description,
         StringArg(
           "A labelled value tile, e.g. \"Active users\" over \"1,204\".",
         ),
       )!,
       this.usageArg = $initArg(
         'usage',
         usage,
         StringArg(
           "A labelled value tile, e.g. \"Active users\" over \"1,204\".",
         ),
       )!,
       this.labelArg = $initArg('label', label, StringArg("Active users"))!,
       this.valueArg = $initArg('value', value, StringArg("1,204"))!;

  StatTileStoryInputArgs.fixed({
    String description =
        "A labelled value tile, e.g. \"Active users\" over \"1,204\".",
    String usage =
        "A labelled value tile, e.g. \"Active users\" over \"1,204\".",
    String label = "Active users",
    String value = "1,204",
  }) : this.descriptionArg = $initArg(
         'description',
         Arg.fixed(description),
         null,
       )!,
       this.usageArg = $initArg('usage', Arg.fixed(usage), null)!,
       this.labelArg = $initArg('label', Arg.fixed(label), null)!,
       this.valueArg = $initArg('value', Arg.fixed(value), null)!;

  final Arg<String> descriptionArg;

  final Arg<String> usageArg;

  final Arg<String> labelArg;

  final Arg<String> valueArg;

  String get description => descriptionArg.value;

  String get usage => usageArg.value;

  String get label => labelArg.value;

  String get value => valueArg.value;

  @override
  List<Arg?> get list => [descriptionArg, usageArg, labelArg, valueArg];
}
