// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: library_private_types_in_public_api, unused_import

import 'package:widgetbook/widgetbook.dart' as widgetbook;
import 'package:widgetbook/widgetbook.dart';
import 'package:restage_widgetbook_example/widgets/stat_tile.dart'
    as restage_source;
import 'package:restage_widgetbook_example/widgets/stat_tile.dart'
    show StatTile;

part 'stat_tile.stories.g.dart';

class StatTileStoryInput {
  const StatTileStoryInput({
    this.description =
        "A labelled value tile, e.g. \"Active users\" over \"1,204\".",
    this.usage = "A labelled value tile, e.g. \"Active users\" over \"1,204\".",
    this.label = "Active users",
    this.value = "1,204",
  });

  final String description;
  final String usage;
  final String label;
  final String value;
}

const meta = widgetbook.Meta(
  restage_source.StatTile.new,
  argsType: StatTileStoryInput.new,
);

const component = widgetbook.ComponentMeta(path: 'decoration');

final defaults = _Defaults(
  builder: (context, args) =>
      restage_source.StatTile(label: args.label, value: args.value),
);

final $RestageCatalog = _Story(
  args: _Args(
    description: _RestageMetadataArg(
      "A labelled value tile, e.g. \"Active users\" over \"1,204\".",
      name: 'description',
    ),
    usage: _RestageMetadataArg(
      "A labelled value tile, e.g. \"Active users\" over \"1,204\".",
      name: 'usage',
    ),
    label: _RestageStringArg(
      "Active users",
      description: "Caption text. Default: Active users.",
    ),
    value: _RestageStringArg(
      "1,204",
      description: "Value text. Default: 1,204.",
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
