// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering, unused_element, strict_raw_type

part of 'opaque_screen_proof.stories.dart';

// **************************************************************************
// StoryGenerator
// **************************************************************************

typedef _Component = Component<OpaqueScreenProof, StoryArgs<OpaqueScreenProof>>;
typedef _Scenario = OpaqueScreenProofScenario;
typedef _Defaults = OpaqueScreenProofDefaults;
typedef _Story = OpaqueScreenProofStory;
typedef _Args = OpaqueScreenProofStoryInputArgs;
final OpaqueScreenProofComponent =
    Component<OpaqueScreenProof, StoryArgs<OpaqueScreenProof>>(
      name: component.name ?? 'OpaqueScreenProof',
      path: component.path ?? 'onboarding/screens/restage.generated',
      docsBuilder: component.docsBuilder,
      docComment:
          r'''Native screen used to verify opaque A2UI and Widgetbook integration.

One authored class feeds RFW, A2UI, and Widgetbook in the normal build.''',
      stories: [
        $RestageCatalog..$generatedName = 'RestageCatalog',
        $EnabledFalse..$generatedName = 'EnabledFalse',
        $ToneUrgent..$generatedName = 'ToneUrgent',
      ],
    );
typedef OpaqueScreenProofScenario =
    Scenario<OpaqueScreenProof, OpaqueScreenProofStoryInputArgs>;
typedef OpaqueScreenProofDefaults =
    Defaults<OpaqueScreenProof, OpaqueScreenProofStoryInputArgs>;

class OpaqueScreenProofStory
    extends Story<OpaqueScreenProof, OpaqueScreenProofStoryInputArgs> {
  OpaqueScreenProofStory({
    super.name,
    super.designLink,
    SetupBuilder<OpaqueScreenProof, OpaqueScreenProofStoryInputArgs>? setup,
    super.modes,
    OpaqueScreenProofStoryInputArgs? args,
    StoryWidgetBuilder<OpaqueScreenProof, OpaqueScreenProofStoryInputArgs>?
    builder,
    super.scenarios,
    super.excludeFromTests,
  }) : super(
         args: args ?? OpaqueScreenProofStoryInputArgs(),
         builder: builder ?? defaults.builder!,
         setup: setup ?? defaults.setup!,
       );
}

class OpaqueScreenProofStoryInputArgs extends StoryArgs<OpaqueScreenProof> {
  OpaqueScreenProofStoryInputArgs({
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
           "Native screen used to verify opaque A2UI and Widgetbook integration.\n\nOne authored class feeds RFW, A2UI, and Widgetbook in the normal build.",
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
       this.dataArg = $initArg('data', data, StringArg("Customer data"))!,
       this.contextArg = $initArg(
         'context',
         context,
         StringArg("Customer context"),
       )!,
       this.itemContextArg = $initArg(
         'itemContext',
         itemContext,
         StringArg("Customer item context"),
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
         StringArg("Customer description"),
       )!,
       this.usageArg = $initArg('usage', usage, StringArg("Customer usage"))!;

  OpaqueScreenProofStoryInputArgs.fixed({
    String restageMetadataDescription =
        "Native screen used to verify opaque A2UI and Widgetbook integration.\n\nOne authored class feeds RFW, A2UI, and Widgetbook in the normal build.",
    String restageMetadataUsage =
        "Use for the final action in a native onboarding flow.",
    String title = "",
    bool enabled = true,
    _RestageChoice2 tone = _RestageChoice2.value0,
    String data = "Customer data",
    String context = "Customer context",
    String itemContext = "Customer item context",
    _RestageChoice6 restageA2uiStatus = _RestageChoice6.value0,
    String description = "Customer description",
    String usage = "Customer usage",
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
