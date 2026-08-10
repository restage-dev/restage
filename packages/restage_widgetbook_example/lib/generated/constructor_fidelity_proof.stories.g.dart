// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering, unused_element, strict_raw_type

part of 'constructor_fidelity_proof.stories.dart';

// **************************************************************************
// StoryGenerator
// **************************************************************************

typedef _Component =
    Component<ConstructorFidelityProof, StoryArgs<ConstructorFidelityProof>>;
typedef _Scenario = ConstructorFidelityProofScenario;
typedef _Defaults = ConstructorFidelityProofDefaults;
typedef _Story = ConstructorFidelityProofStory;
typedef _Args = ConstructorFidelityProofStoryInputArgs;
final ConstructorFidelityProofComponent =
    Component<ConstructorFidelityProof, StoryArgs<ConstructorFidelityProof>>(
      name: component.name ?? 'ConstructorFidelityProof',
      path: component.path ?? 'generated',
      docsBuilder: component.docsBuilder,
      docComment:
          r'''A compact executable proof that all generated targets invoke Dart's
constructor contract rather than merely emitting source bytes.''',
      stories: [$RestageCatalog..$generatedName = 'RestageCatalog'],
    );
typedef ConstructorFidelityProofScenario =
    Scenario<ConstructorFidelityProof, ConstructorFidelityProofStoryInputArgs>;
typedef ConstructorFidelityProofDefaults =
    Defaults<ConstructorFidelityProof, ConstructorFidelityProofStoryInputArgs>;

class ConstructorFidelityProofStory
    extends
        Story<
          ConstructorFidelityProof,
          ConstructorFidelityProofStoryInputArgs
        > {
  ConstructorFidelityProofStory({
    super.name,
    super.designLink,
    super.setup,
    super.modes,
    ConstructorFidelityProofStoryInputArgs? args,
    StoryWidgetBuilder<
      ConstructorFidelityProof,
      ConstructorFidelityProofStoryInputArgs
    >?
    builder,
    super.scenarios,
    super.excludeFromTests,
  }) : super(
         args: args ?? ConstructorFidelityProofStoryInputArgs(),
         builder: builder ?? defaults.builder!,
       );
}

class ConstructorFidelityProofStoryInputArgs
    extends StoryArgs<ConstructorFidelityProof> {
  ConstructorFidelityProofStoryInputArgs({
    Arg<String>? restageMetadataDescription,
    Arg<String>? restageMetadataUsage,
    Arg<String>? label,
    Arg<bool>? enabled,
    Arg<String>? optionalText,
    Arg<bool>? onChanged,
  }) : this.restageMetadataDescriptionArg = $initArg(
         'restageMetadataDescription',
         restageMetadataDescription,
         StringArg(
           "A compact executable proof that all generated targets invoke Dart's constructor contract rather than merely emitting source bytes.",
         ),
       )!,
       this.restageMetadataUsageArg = $initArg(
         'restageMetadataUsage',
         restageMetadataUsage,
         StringArg(
           "Use to verify generated constructor binding and callback write-back.",
         ),
       )!,
       this.labelArg = $initArg('label', label, StringArg(""))!,
       this.enabledArg = $initArg('enabled', enabled, BoolArg(true))!,
       this.optionalTextArg = $initArg(
         'optionalText',
         optionalText,
         StringArg("constructor-default"),
       )!,
       this.onChangedArg = $initArg('onChanged', onChanged, BoolArg(true))!;

  ConstructorFidelityProofStoryInputArgs.fixed({
    String restageMetadataDescription =
        "A compact executable proof that all generated targets invoke Dart's constructor contract rather than merely emitting source bytes.",
    String restageMetadataUsage =
        "Use to verify generated constructor binding and callback write-back.",
    String label = "",
    bool enabled = true,
    String optionalText = "constructor-default",
    bool onChanged = true,
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
       this.enabledArg = $initArg('enabled', Arg.fixed(enabled), null)!,
       this.optionalTextArg = $initArg(
         'optionalText',
         Arg.fixed(optionalText),
         null,
       )!,
       this.onChangedArg = $initArg('onChanged', Arg.fixed(onChanged), null)!;

  final Arg<String> restageMetadataDescriptionArg;

  final Arg<String> restageMetadataUsageArg;

  final Arg<String> labelArg;

  final Arg<bool> enabledArg;

  final Arg<String> optionalTextArg;

  final Arg<bool> onChangedArg;

  String get restageMetadataDescription => restageMetadataDescriptionArg.value;

  String get restageMetadataUsage => restageMetadataUsageArg.value;

  String get label => labelArg.value;

  bool get enabled => enabledArg.value;

  String get optionalText => optionalTextArg.value;

  bool get onChanged => onChangedArg.value;

  @override
  List<Arg?> get list => [
    restageMetadataDescriptionArg,
    restageMetadataUsageArg,
    labelArg,
    enabledArg,
    optionalTextArg,
    onChangedArg,
  ];
}
