// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering, unused_element, strict_raw_type

part of 'get_started_screen.stories.dart';

// **************************************************************************
// StoryGenerator
// **************************************************************************

typedef _Component = Component<GetStartedScreen, StoryArgs<GetStartedScreen>>;
typedef _Scenario = GetStartedScreenScenario;
typedef _Defaults = GetStartedScreenDefaults;
typedef _Story = GetStartedScreenStory;
typedef _Args = GetStartedScreenStoryInputArgs;
final GetStartedScreenComponent =
    Component<GetStartedScreen, StoryArgs<GetStartedScreen>>(
      name: component.name ?? 'GetStartedScreen',
      path: component.path ?? 'onboarding/screens/restage.generated',
      docsBuilder: component.docsBuilder,
      docComment: r'''An onboarding screen with a Get started action.

One authored class feeds RFW, A2UI, and Widgetbook in the normal build.''',
      stories: [
        $RestageCatalog..$generatedName = 'RestageCatalog',
        $EnabledFalse..$generatedName = 'EnabledFalse',
        $ToneUrgent..$generatedName = 'ToneUrgent',
      ],
    );
typedef GetStartedScreenScenario =
    Scenario<GetStartedScreen, GetStartedScreenStoryInputArgs>;
typedef GetStartedScreenDefaults =
    Defaults<GetStartedScreen, GetStartedScreenStoryInputArgs>;

class GetStartedScreenStory
    extends Story<GetStartedScreen, GetStartedScreenStoryInputArgs> {
  GetStartedScreenStory({
    super.name,
    super.designLink,
    SetupBuilder<GetStartedScreen, GetStartedScreenStoryInputArgs>? setup,
    super.modes,
    GetStartedScreenStoryInputArgs? args,
    StoryWidgetBuilder<GetStartedScreen, GetStartedScreenStoryInputArgs>?
    builder,
    super.scenarios,
    super.excludeFromTests,
  }) : super(
         args: args ?? GetStartedScreenStoryInputArgs(),
         builder: builder ?? defaults.builder!,
         setup: setup ?? defaults.setup!,
       );
}

class GetStartedScreenStoryInputArgs extends StoryArgs<GetStartedScreen> {
  GetStartedScreenStoryInputArgs({
    Arg<String>? restageMetadataDescription,
    Arg<String>? restageMetadataUsage,
    Arg<String>? title,
    Arg<bool>? enabled,
    Arg<_RestageChoice2>? tone,
    Arg<String>? data,
    Arg<String>? context,
    Arg<String>? itemContext,
    Arg<_RestageChoice6>? restageA2uiStatus,
    Arg<String>? description,
    Arg<String>? usage,
  }) : this.restageMetadataDescriptionArg = $initArg(
         'restageMetadataDescription',
         restageMetadataDescription,
         StringArg(
           "An onboarding screen with a Get started action.\n\nOne authored class feeds RFW, A2UI, and Widgetbook in the normal build.",
         ),
       )!,
       this.restageMetadataUsageArg = $initArg(
         'restageMetadataUsage',
         restageMetadataUsage,
         StringArg("Use for the final action in a native onboarding flow."),
       )!,
       this.titleArg = $initArg('title', title, StringArg(""))!,
       this.enabledArg = $initArg('enabled', enabled, BoolArg(true))!,
       this.toneArg = $initArg(
         'tone',
         tone,
         EnumArg<_RestageChoice2>(
           _RestageChoice2.value0,
           values: _RestageChoice2.values,
         ),
       )!,
       this.dataArg = $initArg('data', data, StringArg("Example data"))!,
       this.contextArg = $initArg(
         'context',
         context,
         StringArg("Example context"),
       )!,
       this.itemContextArg = $initArg(
         'itemContext',
         itemContext,
         StringArg("Example item context"),
       )!,
       this.restageA2uiStatusArg = $initArg(
         'restageA2uiStatus',
         restageA2uiStatus,
         EnumArg<_RestageChoice6>(
           _RestageChoice6.value0,
           values: _RestageChoice6.values,
         ),
       )!,
       this.descriptionArg = $initArg(
         'description',
         description,
         StringArg("Example description"),
       )!,
       this.usageArg = $initArg('usage', usage, StringArg("Example usage"))!;

  GetStartedScreenStoryInputArgs.fixed({
    String restageMetadataDescription =
        "An onboarding screen with a Get started action.\n\nOne authored class feeds RFW, A2UI, and Widgetbook in the normal build.",
    String restageMetadataUsage =
        "Use for the final action in a native onboarding flow.",
    String title = "",
    bool enabled = true,
    _RestageChoice2 tone = _RestageChoice2.value0,
    String data = "Example data",
    String context = "Example context",
    String itemContext = "Example item context",
    _RestageChoice6 restageA2uiStatus = _RestageChoice6.value0,
    String description = "Example description",
    String usage = "Example usage",
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
       this.enabledArg = $initArg('enabled', Arg.fixed(enabled), null)!,
       this.toneArg = $initArg('tone', Arg.fixed(tone), null)!,
       this.dataArg = $initArg('data', Arg.fixed(data), null)!,
       this.contextArg = $initArg('context', Arg.fixed(context), null)!,
       this.itemContextArg = $initArg(
         'itemContext',
         Arg.fixed(itemContext),
         null,
       )!,
       this.restageA2uiStatusArg = $initArg(
         'restageA2uiStatus',
         Arg.fixed(restageA2uiStatus),
         null,
       )!,
       this.descriptionArg = $initArg(
         'description',
         Arg.fixed(description),
         null,
       )!,
       this.usageArg = $initArg('usage', Arg.fixed(usage), null)!;

  final Arg<String> restageMetadataDescriptionArg;

  final Arg<String> restageMetadataUsageArg;

  final Arg<String> titleArg;

  final Arg<bool> enabledArg;

  final Arg<_RestageChoice2> toneArg;

  final Arg<String> dataArg;

  final Arg<String> contextArg;

  final Arg<String> itemContextArg;

  final Arg<_RestageChoice6> restageA2uiStatusArg;

  final Arg<String> descriptionArg;

  final Arg<String> usageArg;

  String get restageMetadataDescription => restageMetadataDescriptionArg.value;

  String get restageMetadataUsage => restageMetadataUsageArg.value;

  String get title => titleArg.value;

  bool get enabled => enabledArg.value;

  _RestageChoice2 get tone => toneArg.value;

  String get data => dataArg.value;

  String get context => contextArg.value;

  String get itemContext => itemContextArg.value;

  _RestageChoice6 get restageA2uiStatus => restageA2uiStatusArg.value;

  String get description => descriptionArg.value;

  String get usage => usageArg.value;

  @override
  List<Arg?> get list => [
    restageMetadataDescriptionArg,
    restageMetadataUsageArg,
    titleArg,
    enabledArg,
    toneArg,
    dataArg,
    contextArg,
    itemContextArg,
    restageA2uiStatusArg,
    descriptionArg,
    usageArg,
  ];
}
