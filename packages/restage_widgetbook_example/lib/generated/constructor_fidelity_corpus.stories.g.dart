// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering, unused_element, strict_raw_type

part of 'constructor_fidelity_corpus.stories.dart';

// **************************************************************************
// StoryGenerator
// **************************************************************************

typedef _Component =
    Component<ConstructorFidelityCorpus, StoryArgs<ConstructorFidelityCorpus>>;
typedef _Scenario = ConstructorFidelityCorpusScenario;
typedef _Defaults = ConstructorFidelityCorpusDefaults;
typedef _Story = ConstructorFidelityCorpusStory;
typedef _Args = ConstructorFidelityCorpusStoryInputArgs;
final ConstructorFidelityCorpusComponent =
    Component<ConstructorFidelityCorpus, StoryArgs<ConstructorFidelityCorpus>>(
      name: component.name ?? 'ConstructorFidelityCorpus',
      path: component.path ?? 'generated',
      docsBuilder: component.docsBuilder,
      docComment:
          r'''Broad reusable fixture for accepted named constructor shapes.''',
      stories: [$RestageCatalog..$generatedName = 'RestageCatalog'],
    );
typedef ConstructorFidelityCorpusScenario =
    Scenario<
      ConstructorFidelityCorpus,
      ConstructorFidelityCorpusStoryInputArgs
    >;
typedef ConstructorFidelityCorpusDefaults =
    Defaults<
      ConstructorFidelityCorpus,
      ConstructorFidelityCorpusStoryInputArgs
    >;

class ConstructorFidelityCorpusStory
    extends
        Story<
          ConstructorFidelityCorpus,
          ConstructorFidelityCorpusStoryInputArgs
        > {
  ConstructorFidelityCorpusStory({
    super.name,
    super.designLink,
    super.setup,
    super.modes,
    ConstructorFidelityCorpusStoryInputArgs? args,
    StoryWidgetBuilder<
      ConstructorFidelityCorpus,
      ConstructorFidelityCorpusStoryInputArgs
    >?
    builder,
    super.scenarios,
    super.excludeFromTests,
  }) : super(
         args: args ?? ConstructorFidelityCorpusStoryInputArgs(),
         builder: builder ?? defaults.builder!,
       );
}

class ConstructorFidelityCorpusStoryInputArgs
    extends StoryArgs<ConstructorFidelityCorpus> {
  ConstructorFidelityCorpusStoryInputArgs({
    Arg<String>? description,
    Arg<String>? usage,
    Arg<String>? value,
    Arg<String>? ordinaryLabel,
    Arg<String>? requiredNamed,
    Arg<String?>? nullableText,
    Arg<String?>? nullableSeed,
    Arg<bool>? enabled,
    Arg<int>? count,
    Arg<_RestageChoice7>? mode,
    Arg<Color>? directColor,
    Arg<Color>? publicColor,
    Arg<_RestageValue10>? data,
    Arg<bool>? resetProof,
    Arg<bool>? whenEnabledChanges,
    Arg<bool>? reportCount,
  }) : this.descriptionArg = $initArg(
         'description',
         description,
         StringArg(
           "Broad reusable fixture for accepted named constructor shapes.",
         ),
       )!,
       this.usageArg = $initArg(
         'usage',
         usage,
         StringArg(
           "Use to verify accepted constructor, default, and callback families.",
         ),
       )!,
       this.valueArg = $initArg('value', value, StringArg(""))!,
       this.ordinaryLabelArg = $initArg(
         'ordinaryLabel',
         ordinaryLabel,
         StringArg(""),
       )!,
       this.requiredNamedArg = $initArg(
         'requiredNamed',
         requiredNamed,
         StringArg(""),
       )!,
       this.nullableTextArg = $initArg(
         'nullableText',
         nullableText,
         NullableStringArg(null),
       )!,
       this.nullableSeedArg = $initArg(
         'nullableSeed',
         nullableSeed,
         NullableStringArg("nullable-default"),
       )!,
       this.enabledArg = $initArg('enabled', enabled, BoolArg(true))!,
       this.countArg = $initArg('count', count, IntArg(7))!,
       this.modeArg = $initArg(
         'mode',
         mode,
         EnumArg<_RestageChoice7>(
           _RestageChoice7.value0,
           values: _RestageChoice7.values,
         ),
       )!,
       this.directColorArg = $initArg(
         'directColor',
         directColor,
         ColorArg(const restage_native_0.Color.new(4279312947)),
       )!,
       this.publicColorArg = $initArg(
         'publicColor',
         publicColor,
         ColorArg(restage_source.ConstructorCorpusDefaults.publicColor),
       )!,
       this.dataArg = $initArg(
         'data',
         data,
         ConstArg(const _RestageValue10.absent()),
       )!,
       this.resetProofArg = $initArg('resetProof', resetProof, BoolArg(false))!,
       this.whenEnabledChangesArg = $initArg(
         'whenEnabledChanges',
         whenEnabledChanges,
         BoolArg(false),
       )!,
       this.reportCountArg = $initArg(
         'reportCount',
         reportCount,
         BoolArg(false),
       )!;

  ConstructorFidelityCorpusStoryInputArgs.fixed({
    String description =
        "Broad reusable fixture for accepted named constructor shapes.",
    String usage =
        "Use to verify accepted constructor, default, and callback families.",
    String value = "",
    String ordinaryLabel = "",
    String requiredNamed = "",
    String? nullableText = null,
    String? nullableSeed = "nullable-default",
    bool enabled = true,
    int count = 7,
    _RestageChoice7 mode = _RestageChoice7.value0,
    Color directColor = const restage_native_0.Color.new(4279312947),
    Color publicColor = restage_source.ConstructorCorpusDefaults.publicColor,
    _RestageValue10 data = const _RestageValue10.absent(),
    bool resetProof = false,
    bool whenEnabledChanges = false,
    bool reportCount = false,
  }) : this.descriptionArg = $initArg(
         'description',
         Arg.fixed(description),
         null,
       )!,
       this.usageArg = $initArg('usage', Arg.fixed(usage), null)!,
       this.valueArg = $initArg('value', Arg.fixed(value), null)!,
       this.ordinaryLabelArg = $initArg(
         'ordinaryLabel',
         Arg.fixed(ordinaryLabel),
         null,
       )!,
       this.requiredNamedArg = $initArg(
         'requiredNamed',
         Arg.fixed(requiredNamed),
         null,
       )!,
       this.nullableTextArg = $initArg(
         'nullableText',
         nullableText == null ? null : Arg.fixed(nullableText),
         null,
       ),
       this.nullableSeedArg = $initArg(
         'nullableSeed',
         nullableSeed == null ? null : Arg.fixed(nullableSeed),
         null,
       ),
       this.enabledArg = $initArg('enabled', Arg.fixed(enabled), null)!,
       this.countArg = $initArg('count', Arg.fixed(count), null)!,
       this.modeArg = $initArg('mode', Arg.fixed(mode), null)!,
       this.directColorArg = $initArg(
         'directColor',
         Arg.fixed(directColor),
         null,
       )!,
       this.publicColorArg = $initArg(
         'publicColor',
         Arg.fixed(publicColor),
         null,
       )!,
       this.dataArg = $initArg('data', Arg.fixed(data), null)!,
       this.resetProofArg = $initArg(
         'resetProof',
         Arg.fixed(resetProof),
         null,
       )!,
       this.whenEnabledChangesArg = $initArg(
         'whenEnabledChanges',
         Arg.fixed(whenEnabledChanges),
         null,
       )!,
       this.reportCountArg = $initArg(
         'reportCount',
         Arg.fixed(reportCount),
         null,
       )!;

  final Arg<String> descriptionArg;

  final Arg<String> usageArg;

  final Arg<String> valueArg;

  final Arg<String> ordinaryLabelArg;

  final Arg<String> requiredNamedArg;

  final Arg<String?>? nullableTextArg;

  final Arg<String?>? nullableSeedArg;

  final Arg<bool> enabledArg;

  final Arg<int> countArg;

  final Arg<_RestageChoice7> modeArg;

  final Arg<Color> directColorArg;

  final Arg<Color> publicColorArg;

  final Arg<_RestageValue10> dataArg;

  final Arg<bool> resetProofArg;

  final Arg<bool> whenEnabledChangesArg;

  final Arg<bool> reportCountArg;

  String get description => descriptionArg.value;

  String get usage => usageArg.value;

  String get value => valueArg.value;

  String get ordinaryLabel => ordinaryLabelArg.value;

  String get requiredNamed => requiredNamedArg.value;

  String? get nullableText => nullableTextArg?.value;

  String? get nullableSeed => nullableSeedArg?.value;

  bool get enabled => enabledArg.value;

  int get count => countArg.value;

  _RestageChoice7 get mode => modeArg.value;

  Color get directColor => directColorArg.value;

  Color get publicColor => publicColorArg.value;

  _RestageValue10 get data => dataArg.value;

  bool get resetProof => resetProofArg.value;

  bool get whenEnabledChanges => whenEnabledChangesArg.value;

  bool get reportCount => reportCountArg.value;

  @override
  List<Arg?> get list => [
    descriptionArg,
    usageArg,
    valueArg,
    ordinaryLabelArg,
    requiredNamedArg,
    nullableTextArg,
    nullableSeedArg,
    enabledArg,
    countArg,
    modeArg,
    directColorArg,
    publicColorArg,
    dataArg,
    resetProofArg,
    whenEnabledChangesArg,
    reportCountArg,
  ];
}
