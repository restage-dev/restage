// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering, unused_element, strict_raw_type

part of 'price_badge.stories.dart';

// **************************************************************************
// StoryGenerator
// **************************************************************************

typedef _Component = Component<PriceBadge, StoryArgs<PriceBadge>>;
typedef _Scenario = PriceBadgeScenario;
typedef _Defaults = PriceBadgeDefaults;
typedef _Story = PriceBadgeStory;
typedef _Args = PriceBadgeStoryInputArgs;
final PriceBadgeComponent = Component<PriceBadge, StoryArgs<PriceBadge>>(
  name: component.name ?? 'PriceBadge',
  path: component.path ?? 'generated',
  docsBuilder: component.docsBuilder,
  docComment:
      r'''A compact price pill — a formatted price followed by a billing period,
e.g. "\$9.99 / mo".''',
  stories: [$RestageCatalog..$generatedName = 'RestageCatalog'],
);
typedef PriceBadgeScenario = Scenario<PriceBadge, PriceBadgeStoryInputArgs>;
typedef PriceBadgeDefaults = Defaults<PriceBadge, PriceBadgeStoryInputArgs>;

class PriceBadgeStory extends Story<PriceBadge, PriceBadgeStoryInputArgs> {
  PriceBadgeStory({
    super.name,
    super.designLink,
    super.setup,
    super.modes,
    PriceBadgeStoryInputArgs? args,
    StoryWidgetBuilder<PriceBadge, PriceBadgeStoryInputArgs>? builder,
    super.scenarios,
    super.excludeFromTests,
  }) : super(
         args: args ?? PriceBadgeStoryInputArgs(),
         builder: builder ?? defaults.builder!,
       );
}

class PriceBadgeStoryInputArgs extends StoryArgs<PriceBadge> {
  PriceBadgeStoryInputArgs({
    Arg<String>? description,
    Arg<String>? usage,
    Arg<String>? price,
    Arg<String>? period,
  }) : this.descriptionArg = $initArg(
         'description',
         description,
         StringArg("A compact price pill, e.g. \"\$9.99 / mo\"."),
       )!,
       this.usageArg = $initArg(
         'usage',
         usage,
         StringArg("A compact price pill, e.g. \"\$9.99 / mo\"."),
       )!,
       this.priceArg = $initArg('price', price, StringArg("\$9.99"))!,
       this.periodArg = $initArg('period', period, StringArg("mo"))!;

  PriceBadgeStoryInputArgs.fixed({
    String description = "A compact price pill, e.g. \"\$9.99 / mo\".",
    String usage = "A compact price pill, e.g. \"\$9.99 / mo\".",
    String price = "\$9.99",
    String period = "mo",
  }) : this.descriptionArg = $initArg(
         'description',
         Arg.fixed(description),
         null,
       )!,
       this.usageArg = $initArg('usage', Arg.fixed(usage), null)!,
       this.priceArg = $initArg('price', Arg.fixed(price), null)!,
       this.periodArg = $initArg('period', Arg.fixed(period), null)!;

  final Arg<String> descriptionArg;

  final Arg<String> usageArg;

  final Arg<String> priceArg;

  final Arg<String> periodArg;

  String get description => descriptionArg.value;

  String get usage => usageArg.value;

  String get price => priceArg.value;

  String get period => periodArg.value;

  @override
  List<Arg?> get list => [descriptionArg, usageArg, priceArg, periodArg];
}
