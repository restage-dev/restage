// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering, unused_element, strict_raw_type

part of 'welcome_screen.stories.dart';

// **************************************************************************
// StoryGenerator
// **************************************************************************

typedef _Component = Component<WelcomeScreen, StoryArgs<WelcomeScreen>>;
typedef _Scenario = WelcomeScreenScenario;
typedef _Defaults = WelcomeScreenDefaults;
typedef _Story = WelcomeScreenStory;
typedef _Args = WelcomeScreenStoryInputArgs;
final WelcomeScreenComponent =
    Component<WelcomeScreen, StoryArgs<WelcomeScreen>>(
      name: component.name ?? 'WelcomeScreen',
      path: component.path ?? 'onboarding/screens/restage.generated',
      docsBuilder: component.docsBuilder,
      docComment: r'''An onboarding screen with a Continue action.''',
      stories: [
        $RestageCatalog..$generatedName = 'RestageCatalog',
        $ToneUrgent..$generatedName = 'ToneUrgent',
      ],
    );
typedef WelcomeScreenScenario =
    Scenario<WelcomeScreen, WelcomeScreenStoryInputArgs>;
typedef WelcomeScreenDefaults =
    Defaults<WelcomeScreen, WelcomeScreenStoryInputArgs>;

class WelcomeScreenStory
    extends Story<WelcomeScreen, WelcomeScreenStoryInputArgs> {
  WelcomeScreenStory({
    super.name,
    super.designLink,
    SetupBuilder<WelcomeScreen, WelcomeScreenStoryInputArgs>? setup,
    super.modes,
    WelcomeScreenStoryInputArgs? args,
    StoryWidgetBuilder<WelcomeScreen, WelcomeScreenStoryInputArgs>? builder,
    super.scenarios,
    super.excludeFromTests,
  }) : super(
         args: args ?? WelcomeScreenStoryInputArgs(),
         builder: builder ?? defaults.builder!,
         setup: setup ?? defaults.setup!,
       );
}

class WelcomeScreenStoryInputArgs extends StoryArgs<WelcomeScreen> {
  WelcomeScreenStoryInputArgs({
    Arg<String>? restageMetadataDescription,
    Arg<String>? restageMetadataUsage,
    Arg<String>? title,
    Arg<_RestageChoice1>? tone,
  }) : this.restageMetadataDescriptionArg = $initArg(
         'restageMetadataDescription',
         restageMetadataDescription,
         StringArg("An onboarding screen with a Continue action."),
       )!,
       this.restageMetadataUsageArg = $initArg(
         'restageMetadataUsage',
         restageMetadataUsage,
         StringArg("Use for the first screen of a native onboarding flow."),
       )!,
       this.titleArg = $initArg('title', title, StringArg(""))!,
       this.toneArg = $initArg(
         'tone',
         tone,
         EnumArg<_RestageChoice1>(
           _RestageChoice1.value0,
           values: _RestageChoice1.values,
         ),
       )!;

  WelcomeScreenStoryInputArgs.fixed({
    String restageMetadataDescription =
        "An onboarding screen with a Continue action.",
    String restageMetadataUsage =
        "Use for the first screen of a native onboarding flow.",
    String title = "",
    _RestageChoice1 tone = _RestageChoice1.value0,
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
       this.toneArg = $initArg('tone', Arg.fixed(tone), null)!;

  final Arg<String> restageMetadataDescriptionArg;

  final Arg<String> restageMetadataUsageArg;

  final Arg<String> titleArg;

  final Arg<_RestageChoice1> toneArg;

  String get restageMetadataDescription => restageMetadataDescriptionArg.value;

  String get restageMetadataUsage => restageMetadataUsageArg.value;

  String get title => titleArg.value;

  _RestageChoice1 get tone => toneArg.value;

  @override
  List<Arg?> get list => [
    restageMetadataDescriptionArg,
    restageMetadataUsageArg,
    titleArg,
    toneArg,
  ];
}
