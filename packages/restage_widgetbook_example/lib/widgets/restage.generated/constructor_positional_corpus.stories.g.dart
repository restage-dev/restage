// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering, unused_element, strict_raw_type

part of 'constructor_positional_corpus.stories.dart';

// **************************************************************************
// StoryGenerator
// **************************************************************************

typedef _Component =
    Component<
      ConstructorPositionalCorpus,
      StoryArgs<ConstructorPositionalCorpus>
    >;
typedef _Scenario = ConstructorPositionalCorpusScenario;
typedef _Defaults = ConstructorPositionalCorpusDefaults;
typedef _Story = ConstructorPositionalCorpusStory;
typedef _Args = ConstructorPositionalCorpusStoryInputArgs;
final ConstructorPositionalCorpusComponent =
    Component<
      ConstructorPositionalCorpus,
      StoryArgs<ConstructorPositionalCorpus>
    >(
      name: component.name ?? 'ConstructorPositionalCorpus',
      path: component.path ?? 'widgets/restage.generated',
      docsBuilder: component.docsBuilder,
      docComment: r'''Reusable positional-hole fixture.''',
      stories: [$RestageCatalog..$generatedName = 'RestageCatalog'],
    );
typedef ConstructorPositionalCorpusScenario =
    Scenario<
      ConstructorPositionalCorpus,
      ConstructorPositionalCorpusStoryInputArgs
    >;
typedef ConstructorPositionalCorpusDefaults =
    Defaults<
      ConstructorPositionalCorpus,
      ConstructorPositionalCorpusStoryInputArgs
    >;

class ConstructorPositionalCorpusStory
    extends
        Story<
          ConstructorPositionalCorpus,
          ConstructorPositionalCorpusStoryInputArgs
        > {
  ConstructorPositionalCorpusStory({
    super.name,
    super.designLink,
    super.setup,
    super.modes,
    ConstructorPositionalCorpusStoryInputArgs? args,
    StoryWidgetBuilder<
      ConstructorPositionalCorpus,
      ConstructorPositionalCorpusStoryInputArgs
    >?
    builder,
    super.scenarios,
    super.excludeFromTests,
  }) : super(
         args: args ?? ConstructorPositionalCorpusStoryInputArgs(),
         builder: builder ?? defaults.builder!,
       );
}

class ConstructorPositionalCorpusStoryInputArgs
    extends StoryArgs<ConstructorPositionalCorpus> {
  ConstructorPositionalCorpusStoryInputArgs({
    Arg<String>? restageMetadataDescription,
    Arg<String>? restageMetadataUsage,
    Arg<String>? requiredLabel,
    Arg<String>? leading,
    Arg<String>? trailing,
  }) : this.restageMetadataDescriptionArg = $initArg(
         'restageMetadataDescription',
         restageMetadataDescription,
         StringArg("Reusable positional-hole fixture."),
       )!,
       this.restageMetadataUsageArg = $initArg(
         'restageMetadataUsage',
         restageMetadataUsage,
         StringArg("Reusable positional-hole fixture."),
       )!,
       this.requiredLabelArg = $initArg(
         'requiredLabel',
         requiredLabel,
         StringArg(""),
       )!,
       this.leadingArg = $initArg(
         'leading',
         leading,
         StringArg("leading-default"),
       )!,
       this.trailingArg = $initArg(
         'trailing',
         trailing,
         StringArg("trailing-default"),
       )!;

  ConstructorPositionalCorpusStoryInputArgs.fixed({
    String restageMetadataDescription = "Reusable positional-hole fixture.",
    String restageMetadataUsage = "Reusable positional-hole fixture.",
    String requiredLabel = "",
    String leading = "leading-default",
    String trailing = "trailing-default",
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
       this.requiredLabelArg = $initArg(
         'requiredLabel',
         Arg.fixed(requiredLabel),
         null,
       )!,
       this.leadingArg = $initArg('leading', Arg.fixed(leading), null)!,
       this.trailingArg = $initArg('trailing', Arg.fixed(trailing), null)!;

  final Arg<String> restageMetadataDescriptionArg;

  final Arg<String> restageMetadataUsageArg;

  final Arg<String> requiredLabelArg;

  final Arg<String> leadingArg;

  final Arg<String> trailingArg;

  String get restageMetadataDescription => restageMetadataDescriptionArg.value;

  String get restageMetadataUsage => restageMetadataUsageArg.value;

  String get requiredLabel => requiredLabelArg.value;

  String get leading => leadingArg.value;

  String get trailing => trailingArg.value;

  @override
  List<Arg?> get list => [
    restageMetadataDescriptionArg,
    restageMetadataUsageArg,
    requiredLabelArg,
    leadingArg,
    trailingArg,
  ];
}
