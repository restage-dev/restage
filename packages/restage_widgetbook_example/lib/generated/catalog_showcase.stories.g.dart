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
      path: component.path ?? 'generated',
      docsBuilder: component.docsBuilder,
      docComment:
          r'''A customer catalog widget proving one source can feed every enabled target.
It combines ordinary scalar state, an enum, callback write-back, native
child slots, and customer-owned structured data.

The second paragraph is retained in generated property metadata so
multi-paragraph Dart documentation is never reduced to its first line.''',
      stories: [$RestageCatalog..$generatedName = 'RestageCatalog'],
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
    Arg<String>? description,
    Arg<String>? usage,
    Arg<String>? title,
    Arg<bool>? enabled,
    Arg<_RestageChoice2>? status,
    Arg<bool>? onChanged,
    Arg<_RestageValue4>? header,
    Arg<_RestageValue5>? children,
    Arg<_RestageValue6>? data,
  }) : this.descriptionArg = $initArg(
         'description',
         description,
         StringArg(
           "A customer catalog widget proving one source can feed every enabled target. It combines ordinary scalar state, an enum, callback write-back, native child slots, and customer-owned structured data.\n\nThe second paragraph is retained in generated property metadata so multi-paragraph Dart documentation is never reduced to its first line.",
         ),
       )!,
       this.usageArg = $initArg(
         'usage',
         usage,
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
       this.onChangedArg = $initArg('onChanged', onChanged, BoolArg(false))!,
       this.headerArg = $initArg(
         'header',
         header,
         ConstArg(const _RestageValue4.absent()),
       )!,
       this.childrenArg = $initArg(
         'children',
         children,
         ConstArg(const _RestageValue5.absent()),
       )!,
       this.dataArg = $initArg(
         'data',
         data,
         ConstArg(const _RestageValue6.absent()),
       )!;

  CatalogShowcaseStoryInputArgs.fixed({
    String description =
        "A customer catalog widget proving one source can feed every enabled target. It combines ordinary scalar state, an enum, callback write-back, native child slots, and customer-owned structured data.\n\nThe second paragraph is retained in generated property metadata so multi-paragraph Dart documentation is never reduced to its first line.",
    String usage =
        "Use to verify a customer catalog across RFW, A2UI, and Widgetbook.",
    String title = "",
    bool enabled = true,
    _RestageChoice2 status = _RestageChoice2.value0,
    bool onChanged = false,
    _RestageValue4 header = const _RestageValue4.absent(),
    _RestageValue5 children = const _RestageValue5.absent(),
    _RestageValue6 data = const _RestageValue6.absent(),
  }) : this.descriptionArg = $initArg(
         'description',
         Arg.fixed(description),
         null,
       )!,
       this.usageArg = $initArg('usage', Arg.fixed(usage), null)!,
       this.titleArg = $initArg('title', Arg.fixed(title), null)!,
       this.enabledArg = $initArg('enabled', Arg.fixed(enabled), null)!,
       this.statusArg = $initArg('status', Arg.fixed(status), null)!,
       this.onChangedArg = $initArg('onChanged', Arg.fixed(onChanged), null)!,
       this.headerArg = $initArg('header', Arg.fixed(header), null)!,
       this.childrenArg = $initArg('children', Arg.fixed(children), null)!,
       this.dataArg = $initArg('data', Arg.fixed(data), null)!;

  final Arg<String> descriptionArg;

  final Arg<String> usageArg;

  final Arg<String> titleArg;

  final Arg<bool> enabledArg;

  final Arg<_RestageChoice2> statusArg;

  final Arg<bool> onChangedArg;

  final Arg<_RestageValue4> headerArg;

  final Arg<_RestageValue5> childrenArg;

  final Arg<_RestageValue6> dataArg;

  String get description => descriptionArg.value;

  String get usage => usageArg.value;

  String get title => titleArg.value;

  bool get enabled => enabledArg.value;

  _RestageChoice2 get status => statusArg.value;

  bool get onChanged => onChangedArg.value;

  _RestageValue4 get header => headerArg.value;

  _RestageValue5 get children => childrenArg.value;

  _RestageValue6 get data => dataArg.value;

  @override
  List<Arg?> get list => [
    descriptionArg,
    usageArg,
    titleArg,
    enabledArg,
    statusArg,
    onChangedArg,
    headerArg,
    childrenArg,
    dataArg,
  ];
}
