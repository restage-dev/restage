// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: library_private_types_in_public_api, unused_import

import 'package:widgetbook/widgetbook.dart' as widgetbook;
import 'package:widgetbook/widgetbook.dart';
import 'package:flutter/widgets.dart' as restage_native_0;
import 'package:flutter/widgets.dart' show Widget;
import 'package:restage_widgetbook_example/widgets/catalog_showcase.dart'
    as restage_source;
import 'package:restage_widgetbook_example/widgets/catalog_showcase.dart'
    show CatalogShowcase;
import 'package:restage_widgetbook_example/widgets/catalog_showcase.dart'
    show CatalogShowcaseData, CatalogShowcaseStatus;

part 'catalog_showcase.stories.g.dart';

enum _RestageChoice2 { value0, value1 }

final class _RestageValue4 {
  const _RestageValue4.absent() : hasValue = false, value = null;

  const _RestageValue4(this.value) : hasValue = true;

  final bool hasValue;
  final restage_native_0.Widget? value;
}

final class _RestageValue5 {
  const _RestageValue5.absent() : hasValue = false, value = null;

  const _RestageValue5(this.value) : hasValue = true;

  final bool hasValue;
  final List<restage_native_0.Widget>? value;
}

final class _RestageValue6 {
  const _RestageValue6.absent() : hasValue = false, value = null;

  const _RestageValue6(this.value) : hasValue = true;

  final bool hasValue;
  final restage_source.CatalogShowcaseData? value;
}

class CatalogShowcaseStoryInput {
  const CatalogShowcaseStoryInput({
    this.description =
        "A customer catalog widget proving one source can feed every enabled target. It combines ordinary scalar state, an enum, callback write-back, native child slots, and customer-owned structured data.\n\nThe second paragraph is retained in generated property metadata so multi-paragraph Dart documentation is never reduced to its first line.",
    this.usage =
        "Use to verify a customer catalog across RFW, A2UI, and Widgetbook.",
    this.title = "",
    this.enabled = true,
    this.status = _RestageChoice2.value0,
    this.onChanged = false,
    this.header = const _RestageValue4.absent(),
    this.children = const _RestageValue5.absent(),
    this.data = const _RestageValue6.absent(),
  });

  final String description;
  final String usage;
  final String title;
  final bool enabled;
  final _RestageChoice2 status;
  final bool onChanged;
  final _RestageValue4 header;
  final _RestageValue5 children;
  final _RestageValue6 data;
}

const meta = widgetbook.Meta(
  restage_source.CatalogShowcase.new,
  argsType: CatalogShowcaseStoryInput.new,
);

const component = widgetbook.ComponentMeta(path: 'input');

final defaults = _Defaults(
  builder: (context, args) => restage_source.CatalogShowcase(
    title: args.title,
    enabled: args.enabled,
    status: switch (args.status) {
      _RestageChoice2.value0 => restage_source.CatalogShowcaseStatus.ready,
      _RestageChoice2.value1 => restage_source.CatalogShowcaseStatus.processing,
    },
    onChanged: (_) {},
    header: args.header.hasValue
        ? args.header.value!
        : const restage_native_0.SizedBox.shrink(),
    children: args.children.hasValue
        ? args.children.value!
        : <restage_native_0.Widget>[],
    data: args.data.hasValue
        ? args.data.value!
        : restage_source.CatalogShowcaseData(note: "", count: 0),
  ),
);

final $RestageCatalog = _Story(
  args: _Args(
    description: _RestageMetadataArg(
      "A customer catalog widget proving one source can feed every enabled target. It combines ordinary scalar state, an enum, callback write-back, native child slots, and customer-owned structured data.\n\nThe second paragraph is retained in generated property metadata so multi-paragraph Dart documentation is never reduced to its first line.",
      name: 'description',
    ),
    usage: _RestageMetadataArg(
      "Use to verify a customer catalog across RFW, A2UI, and Widgetbook.",
      name: 'usage',
    ),
    title: _RestageStringArg("", description: "Visible customer title."),
    enabled: _RestageBoolArg(
      true,
      description:
          "Whether the customer control is enabled. Default: the widget constructor's Dart default.",
    ),
    status: _RestageEnumArg<_RestageChoice2>(
      _RestageChoice2.value0,
      values: _RestageChoice2.values,
      labelBuilder: (value) => switch (value) {
        _RestageChoice2.value0 => "ready",
        _RestageChoice2.value1 => "processing",
      },
      description: "Current customer state.",
    ),
    onChanged: _RestageBoolArg(
      false,
      description: "Reports changes to [enabled].",
    ),
    header: _RestageConstArg<_RestageValue4>(
      _RestageValue4(const restage_native_0.SizedBox.shrink()),
      description: "Customer widget shown before the content list.",
    ),
    children: _RestageConstArg<_RestageValue5>(
      _RestageValue5(<restage_native_0.Widget>[]),
      description: "Customer widgets shown in source order.",
    ),
    data: _RestageConstArg<_RestageValue6>(
      _RestageValue6(restage_source.CatalogShowcaseData(note: "", count: 0)),
      description: "Customer-owned structured information.",
    ),
  ),
);

mixin _RestageArgDescription<T> on widgetbook.Arg<T> {
  String get restageDescription;

  @override
  String? get description => restageDescription;
}

final class _RestageMetadataArg extends widgetbook.Arg<String>
    with widgetbook.NoFields<String> {
  _RestageMetadataArg(super.value, {required super.name});

  @override
  String get description => value;
}

final class _RestageStringArg extends widgetbook.StringArg
    with _RestageArgDescription<String> {
  _RestageStringArg(super.value, {required String description})
    : restageDescription = description;

  @override
  final String restageDescription;
}

final class _RestageBoolArg extends widgetbook.BoolArg
    with _RestageArgDescription<bool> {
  _RestageBoolArg(super.value, {required String description})
    : restageDescription = description;

  @override
  final String restageDescription;
}

final class _RestageEnumArg<T extends Enum> extends widgetbook.EnumArg<T>
    with _RestageArgDescription<T> {
  _RestageEnumArg(
    super.value, {
    required super.values,
    required super.labelBuilder,
    required String description,
  }) : restageDescription = description;

  @override
  final String restageDescription;
}

final class _RestageConstArg<T> extends widgetbook.ConstArg<T>
    with _RestageArgDescription<T> {
  _RestageConstArg(super.value, {required String description})
    : restageDescription = description;

  @override
  final String restageDescription;
}
