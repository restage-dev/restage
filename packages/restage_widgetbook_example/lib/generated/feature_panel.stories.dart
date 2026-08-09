// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: library_private_types_in_public_api, unused_import

import 'package:widgetbook/widgetbook.dart' as widgetbook;
import 'package:widgetbook/widgetbook.dart';
import 'package:flutter/widgets.dart' as restage_native_0;
import 'package:flutter/widgets.dart' show Widget;
import 'package:restage_widgetbook_example/widgets/feature_panel.dart'
    as restage_source;
import 'package:restage_widgetbook_example/widgets/feature_panel.dart'
    show FeaturePanel;

part 'feature_panel.stories.g.dart';

final class _RestageValue0 {
  const _RestageValue0.absent() : hasValue = false, value = null;

  const _RestageValue0(this.value) : hasValue = true;

  final bool hasValue;
  final restage_native_0.Widget? value;
}

final class _RestageValue1 {
  const _RestageValue1.absent() : hasValue = false, value = null;

  const _RestageValue1(this.value) : hasValue = true;

  final bool hasValue;
  final List<restage_native_0.Widget>? value;
}

class FeaturePanelStoryInput {
  const FeaturePanelStoryInput({
    this.description =
        "A panel with a customer header and customer content widgets.",
    this.usage = "Use to group a compact catalog summary.",
    this.header = const _RestageValue0.absent(),
    this.children = const _RestageValue1.absent(),
  });

  final String description;
  final String usage;
  final _RestageValue0 header;
  final _RestageValue1 children;
}

const meta = widgetbook.Meta(
  restage_source.FeaturePanel.new,
  argsType: FeaturePanelStoryInput.new,
);

const component = widgetbook.ComponentMeta(path: 'layout');

final defaults = _Defaults(
  builder: (context, args) => restage_source.FeaturePanel(
    header: args.header.hasValue ? args.header.value : null,
    children: args.children.hasValue
        ? args.children.value!
        : <restage_native_0.Widget>[],
  ),
);

final $RestageCatalog = _Story(
  args: _Args(
    description: _RestageMetadataArg(
      "A panel with a customer header and customer content widgets.",
      name: 'description',
    ),
    usage: _RestageMetadataArg(
      "Use to group a compact catalog summary.",
      name: 'usage',
    ),
    header: _RestageConstArg<_RestageValue0>(
      _RestageValue0(null),
      description: "Customer widget shown as the panel header.",
    ),
    children: _RestageConstArg<_RestageValue1>(
      _RestageValue1(<restage_native_0.Widget>[]),
      description: "Customer widgets shown in the panel body.",
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

final class _RestageConstArg<T> extends widgetbook.ConstArg<T>
    with _RestageArgDescription<T> {
  _RestageConstArg(super.value, {required String description})
    : restageDescription = description;

  @override
  final String restageDescription;
}
