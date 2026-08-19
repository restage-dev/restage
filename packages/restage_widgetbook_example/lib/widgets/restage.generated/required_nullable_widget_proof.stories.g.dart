// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering, unused_element, strict_raw_type

part of 'required_nullable_widget_proof.stories.dart';

// **************************************************************************
// StoryGenerator
// **************************************************************************

typedef _Component =
    Component<
      RequiredNullableWidgetProof,
      StoryArgs<RequiredNullableWidgetProof>
    >;
typedef _Scenario = RequiredNullableWidgetProofScenario;
typedef _Defaults = RequiredNullableWidgetProofDefaults;
typedef _Story = RequiredNullableWidgetProofStory;
typedef _Args = RequiredNullableWidgetProofStoryInputArgs;
final RequiredNullableWidgetProofComponent =
    Component<
      RequiredNullableWidgetProof,
      StoryArgs<RequiredNullableWidgetProof>
    >(
      name: component.name ?? 'RequiredNullableWidgetProof',
      path: component.path ?? 'widgets/restage.generated',
      docsBuilder: component.docsBuilder,
      docComment:
          r'''Executable RFW proof for required nullable and non-nullable widget inputs.''',
      stories: [$RestageCatalog..$generatedName = 'RestageCatalog'],
    );
typedef RequiredNullableWidgetProofScenario =
    Scenario<
      RequiredNullableWidgetProof,
      RequiredNullableWidgetProofStoryInputArgs
    >;
typedef RequiredNullableWidgetProofDefaults =
    Defaults<
      RequiredNullableWidgetProof,
      RequiredNullableWidgetProofStoryInputArgs
    >;

class RequiredNullableWidgetProofStory
    extends
        Story<
          RequiredNullableWidgetProof,
          RequiredNullableWidgetProofStoryInputArgs
        > {
  RequiredNullableWidgetProofStory({
    super.name,
    super.designLink,
    super.setup,
    super.modes,
    RequiredNullableWidgetProofStoryInputArgs? args,
    StoryWidgetBuilder<
      RequiredNullableWidgetProof,
      RequiredNullableWidgetProofStoryInputArgs
    >?
    builder,
    super.scenarios,
    super.excludeFromTests,
  }) : super(
         args: args ?? RequiredNullableWidgetProofStoryInputArgs(),
         builder: builder ?? defaults.builder!,
       );
}

class RequiredNullableWidgetProofStoryInputArgs
    extends StoryArgs<RequiredNullableWidgetProof> {
  RequiredNullableWidgetProofStoryInputArgs({
    Arg<String>? restageMetadataDescription,
    Arg<String>? restageMetadataUsage,
    Arg<_RestageValue0>? positionalNullable,
    Arg<_RestageValue1>? positionalControl,
    Arg<_RestageValue2>? namedNullable,
    Arg<_RestageValue3>? namedControl,
  }) : this.restageMetadataDescriptionArg = $initArg(
         'restageMetadataDescription',
         restageMetadataDescription,
         StringArg(
           "Executable RFW proof for required nullable and non-nullable widget inputs.",
         ),
       )!,
       this.restageMetadataUsageArg = $initArg(
         'restageMetadataUsage',
         restageMetadataUsage,
         StringArg(
           "Executable RFW proof for required nullable and non-nullable widget inputs.",
         ),
       )!,
       this.positionalNullableArg = $initArg(
         'positionalNullable',
         positionalNullable,
         ConstArg(const _RestageValue0.absent()),
       )!,
       this.positionalControlArg = $initArg(
         'positionalControl',
         positionalControl,
         ConstArg(const _RestageValue1.absent()),
       )!,
       this.namedNullableArg = $initArg(
         'namedNullable',
         namedNullable,
         ConstArg(const _RestageValue2.absent()),
       )!,
       this.namedControlArg = $initArg(
         'namedControl',
         namedControl,
         ConstArg(const _RestageValue3.absent()),
       )!;

  RequiredNullableWidgetProofStoryInputArgs.fixed({
    String restageMetadataDescription =
        "Executable RFW proof for required nullable and non-nullable widget inputs.",
    String restageMetadataUsage =
        "Executable RFW proof for required nullable and non-nullable widget inputs.",
    _RestageValue0 positionalNullable = const _RestageValue0.absent(),
    _RestageValue1 positionalControl = const _RestageValue1.absent(),
    _RestageValue2 namedNullable = const _RestageValue2.absent(),
    _RestageValue3 namedControl = const _RestageValue3.absent(),
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
       this.positionalNullableArg = $initArg(
         'positionalNullable',
         Arg.fixed(positionalNullable),
         null,
       )!,
       this.positionalControlArg = $initArg(
         'positionalControl',
         Arg.fixed(positionalControl),
         null,
       )!,
       this.namedNullableArg = $initArg(
         'namedNullable',
         Arg.fixed(namedNullable),
         null,
       )!,
       this.namedControlArg = $initArg(
         'namedControl',
         Arg.fixed(namedControl),
         null,
       )!;

  final Arg<String> restageMetadataDescriptionArg;

  final Arg<String> restageMetadataUsageArg;

  final Arg<_RestageValue0> positionalNullableArg;

  final Arg<_RestageValue1> positionalControlArg;

  final Arg<_RestageValue2> namedNullableArg;

  final Arg<_RestageValue3> namedControlArg;

  String get restageMetadataDescription => restageMetadataDescriptionArg.value;

  String get restageMetadataUsage => restageMetadataUsageArg.value;

  _RestageValue0 get positionalNullable => positionalNullableArg.value;

  _RestageValue1 get positionalControl => positionalControlArg.value;

  _RestageValue2 get namedNullable => namedNullableArg.value;

  _RestageValue3 get namedControl => namedControlArg.value;

  @override
  List<Arg?> get list => [
    restageMetadataDescriptionArg,
    restageMetadataUsageArg,
    positionalNullableArg,
    positionalControlArg,
    namedNullableArg,
    namedControlArg,
  ];
}
