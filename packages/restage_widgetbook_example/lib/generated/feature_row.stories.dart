// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: library_private_types_in_public_api, unused_import

import 'package:widgetbook/widgetbook.dart' as widgetbook;
import 'package:widgetbook/widgetbook.dart';
import 'package:restage_widgetbook_example/widgets/feature_row.dart'
    as restage_source;
import 'package:restage_widgetbook_example/widgets/feature_row.dart'
    show FeatureRow;

part 'feature_row.stories.g.dart';

class FeatureRowStoryInput {
  const FeatureRowStoryInput({
    this.description = "A feature-list row: check icon, title, and subtitle.",
    this.usage = "A feature-list row: check icon, title, and subtitle.",
    this.title = "Unlimited projects",
    this.subtitle = "No caps on what you ship.",
  });

  final String description;
  final String usage;
  final String title;
  final String subtitle;
}

const meta = widgetbook.Meta(
  restage_source.FeatureRow.new,
  argsType: FeatureRowStoryInput.new,
);

const component = widgetbook.ComponentMeta(path: 'layout');

final defaults = _Defaults(
  builder: (context, args) =>
      restage_source.FeatureRow(title: args.title, subtitle: args.subtitle),
);

final $RestageCatalog = _Story(
  args: _Args(
    description: _RestageMetadataArg(
      "A feature-list row: check icon, title, and subtitle.",
      name: 'description',
    ),
    usage: _RestageMetadataArg(
      "A feature-list row: check icon, title, and subtitle.",
      name: 'usage',
    ),
    title: _RestageStringArg(
      "Unlimited projects",
      description: "Feature title. Default: Unlimited projects.",
    ),
    subtitle: _RestageStringArg(
      "No caps on what you ship.",
      description:
          "Supporting line under the title. Default: No caps on what you ship.",
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
