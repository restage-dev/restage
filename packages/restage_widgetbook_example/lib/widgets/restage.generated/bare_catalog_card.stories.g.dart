// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering, unused_element, strict_raw_type

part of 'bare_catalog_card.stories.dart';

// **************************************************************************
// StoryGenerator
// **************************************************************************

typedef _Component = Component<BareCatalogCard, StoryArgs<BareCatalogCard>>;
typedef _Scenario = BareCatalogCardScenario;
typedef _Defaults = BareCatalogCardDefaults;
typedef _Story = BareCatalogCardStory;
typedef _Args = BareCatalogCardStoryInputArgs;
final BareCatalogCardComponent =
    Component<BareCatalogCard, StoryArgs<BareCatalogCard>>(
      name: component.name ?? 'BareCatalogCard',
      path: component.path ?? 'widgets/restage.generated',
      docsBuilder: component.docsBuilder,
      docComment:
          r'''A root-level customer card using only the ordinary Restage marker.''',
      stories: [$RestageCatalog..$generatedName = 'RestageCatalog'],
    );
typedef BareCatalogCardScenario =
    Scenario<BareCatalogCard, BareCatalogCardStoryInputArgs>;
typedef BareCatalogCardDefaults =
    Defaults<BareCatalogCard, BareCatalogCardStoryInputArgs>;

class BareCatalogCardStory
    extends Story<BareCatalogCard, BareCatalogCardStoryInputArgs> {
  BareCatalogCardStory({
    super.name,
    super.designLink,
    super.setup,
    super.modes,
    BareCatalogCardStoryInputArgs? args,
    StoryWidgetBuilder<BareCatalogCard, BareCatalogCardStoryInputArgs>? builder,
    super.scenarios,
    super.excludeFromTests,
  }) : super(
         args: args ?? BareCatalogCardStoryInputArgs(),
         builder: builder ?? defaults.builder!,
       );
}

class BareCatalogCardStoryInputArgs extends StoryArgs<BareCatalogCard> {
  BareCatalogCardStoryInputArgs({
    Arg<String>? restageMetadataDescription,
    Arg<String>? restageMetadataUsage,
    Arg<String>? label,
  }) : this.restageMetadataDescriptionArg = $initArg(
         'restageMetadataDescription',
         restageMetadataDescription,
         StringArg(
           "A root-level customer card using only the ordinary Restage marker.",
         ),
       )!,
       this.restageMetadataUsageArg = $initArg(
         'restageMetadataUsage',
         restageMetadataUsage,
         StringArg(
           "A root-level customer card using only the ordinary Restage marker.",
         ),
       )!,
       this.labelArg = $initArg(
         'label',
         label,
         StringArg("Bare catalog card"),
       )!;

  BareCatalogCardStoryInputArgs.fixed({
    String restageMetadataDescription =
        "A root-level customer card using only the ordinary Restage marker.",
    String restageMetadataUsage =
        "A root-level customer card using only the ordinary Restage marker.",
    String label = "Bare catalog card",
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
       this.labelArg = $initArg('label', Arg.fixed(label), null)!;

  final Arg<String> restageMetadataDescriptionArg;

  final Arg<String> restageMetadataUsageArg;

  final Arg<String> labelArg;

  String get restageMetadataDescription => restageMetadataDescriptionArg.value;

  String get restageMetadataUsage => restageMetadataUsageArg.value;

  String get label => labelArg.value;

  @override
  List<Arg?> get list => [
    restageMetadataDescriptionArg,
    restageMetadataUsageArg,
    labelArg,
  ];
}
