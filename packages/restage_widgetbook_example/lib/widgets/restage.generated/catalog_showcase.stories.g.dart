// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering, unused_element, strict_raw_type

part of 'catalog_showcase.stories.dart';

// **************************************************************************
// StoryGenerator
// **************************************************************************

typedef _Component = Component<CatalogShowcase, StoryArgs<CatalogShowcase>>;
typedef _Scenario = CatalogShowcaseScenario;
typedef _Defaults = CatalogShowcaseDefaults;
typedef _Story = CatalogShowcaseStory;
typedef _Args = CatalogShowcaseStoryInputArgs;
final CatalogShowcaseComponent =
    Component<CatalogShowcase, StoryArgs<CatalogShowcase>>(
      name: component.name ?? 'CatalogShowcase',
      path: component.path ?? 'widgets/restage.generated',
      docsBuilder: component.docsBuilder,
      docComment:
          r'''A customer catalog widget proving one source can feed every enabled target.
It combines ordinary scalar state, an enum, callback write-back, native
child-bearing inputs, and customer-owned structured data. The independently
named `hero`, `details`, and `footer` inputs require no slot annotation.

The second paragraph is retained in generated property metadata so
multi-paragraph Dart documentation is never reduced to its first line.''',
      stories: [
        $RestageCatalog..$generatedName = 'RestageCatalog',
        $EnabledFalse..$generatedName = 'EnabledFalse',
        $StatusProcessing..$generatedName = 'StatusProcessing',
      ],
    );
typedef CatalogShowcaseScenario =
    Scenario<CatalogShowcase, CatalogShowcaseStoryInputArgs>;
typedef CatalogShowcaseDefaults =
    Defaults<CatalogShowcase, CatalogShowcaseStoryInputArgs>;

class CatalogShowcaseStory
    extends Story<CatalogShowcase, CatalogShowcaseStoryInputArgs> {
  CatalogShowcaseStory({
    super.name,
    super.designLink,
    super.setup,
    super.modes,
    CatalogShowcaseStoryInputArgs? args,
    StoryWidgetBuilder<CatalogShowcase, CatalogShowcaseStoryInputArgs>? builder,
    super.scenarios,
    super.excludeFromTests,
  }) : super(
         args: args ?? CatalogShowcaseStoryInputArgs(),
         builder: builder ?? defaults.builder!,
       );
}

class CatalogShowcaseStoryInputArgs extends StoryArgs<CatalogShowcase> {
  CatalogShowcaseStoryInputArgs({
    Arg<String>? restageMetadataDescription,
    Arg<String>? restageMetadataUsage,
    Arg<String>? title,
    Arg<bool>? enabled,
    Arg<_RestageChoice2>? status,
    Arg<bool>? onChanged,
    Arg<_RestageValue4>? hero,
    Arg<_RestageValue5>? details,
    Arg<_RestageValue6>? footer,
    Arg<_RestageValue7>? data,
  }) : this.restageMetadataDescriptionArg = $initArg(
         'restageMetadataDescription',
         restageMetadataDescription,
         StringArg(
           "A customer catalog widget proving one source can feed every enabled target. It combines ordinary scalar state, an enum, callback write-back, native child-bearing inputs, and customer-owned structured data. The independently named `hero`, `details`, and `footer` inputs require no slot annotation.\n\nThe second paragraph is retained in generated property metadata so multi-paragraph Dart documentation is never reduced to its first line.",
         ),
       )!,
       this.restageMetadataUsageArg = $initArg(
         'restageMetadataUsage',
         restageMetadataUsage,
         StringArg(
           "Use to verify a customer catalog across RFW, A2UI, and Widgetbook.",
         ),
       )!,
       this.titleArg = $initArg('title', title, StringArg(""))!,
       this.enabledArg = $initArg('enabled', enabled, BoolArg(true))!,
       this.statusArg = $initArg(
         'status',
         status,
         EnumArg<_RestageChoice2>(
           _RestageChoice2.value0,
           values: _RestageChoice2.values,
         ),
       )!,
       this.onChangedArg = $initArg('onChanged', onChanged, BoolArg(true))!,
       this.heroArg = $initArg(
         'hero',
         hero,
         ConstArg(const _RestageValue4.absent()),
       )!,
       this.detailsArg = $initArg(
         'details',
         details,
         ConstArg(const _RestageValue5.absent()),
       )!,
       this.footerArg = $initArg(
         'footer',
         footer,
         ConstArg(const _RestageValue6.absent()),
       )!,
       this.dataArg = $initArg(
         'data',
         data,
         ConstArg(const _RestageValue7.absent()),
       )!;

  CatalogShowcaseStoryInputArgs.fixed({
    String restageMetadataDescription =
        "A customer catalog widget proving one source can feed every enabled target. It combines ordinary scalar state, an enum, callback write-back, native child-bearing inputs, and customer-owned structured data. The independently named `hero`, `details`, and `footer` inputs require no slot annotation.\n\nThe second paragraph is retained in generated property metadata so multi-paragraph Dart documentation is never reduced to its first line.",
    String restageMetadataUsage =
        "Use to verify a customer catalog across RFW, A2UI, and Widgetbook.",
    String title = "",
    bool enabled = true,
    _RestageChoice2 status = _RestageChoice2.value0,
    bool onChanged = true,
    _RestageValue4 hero = const _RestageValue4.absent(),
    _RestageValue5 details = const _RestageValue5.absent(),
    _RestageValue6 footer = const _RestageValue6.absent(),
    _RestageValue7 data = const _RestageValue7.absent(),
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
       this.statusArg = $initArg('status', Arg.fixed(status), null)!,
       this.onChangedArg = $initArg('onChanged', Arg.fixed(onChanged), null)!,
       this.heroArg = $initArg('hero', Arg.fixed(hero), null)!,
       this.detailsArg = $initArg('details', Arg.fixed(details), null)!,
       this.footerArg = $initArg('footer', Arg.fixed(footer), null)!,
       this.dataArg = $initArg('data', Arg.fixed(data), null)!;

  final Arg<String> restageMetadataDescriptionArg;

  final Arg<String> restageMetadataUsageArg;

  final Arg<String> titleArg;

  final Arg<bool> enabledArg;

  final Arg<_RestageChoice2> statusArg;

  final Arg<bool> onChangedArg;

  final Arg<_RestageValue4> heroArg;

  final Arg<_RestageValue5> detailsArg;

  final Arg<_RestageValue6> footerArg;

  final Arg<_RestageValue7> dataArg;

  String get restageMetadataDescription => restageMetadataDescriptionArg.value;

  String get restageMetadataUsage => restageMetadataUsageArg.value;

  String get title => titleArg.value;

  bool get enabled => enabledArg.value;

  _RestageChoice2 get status => statusArg.value;

  bool get onChanged => onChangedArg.value;

  _RestageValue4 get hero => heroArg.value;

  _RestageValue5 get details => detailsArg.value;

  _RestageValue6 get footer => footerArg.value;

  _RestageValue7 get data => dataArg.value;

  @override
  List<Arg?> get list => [
    restageMetadataDescriptionArg,
    restageMetadataUsageArg,
    titleArg,
    enabledArg,
    statusArg,
    onChangedArg,
    heroArg,
    detailsArg,
    footerArg,
    dataArg,
  ];
}
