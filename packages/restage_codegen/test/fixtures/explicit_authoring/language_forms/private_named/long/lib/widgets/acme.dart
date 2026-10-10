// @dart=3.13
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'AcmeTag',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.decoration,
  description: 'A tag.',
)
final class AcmeTag extends StatelessWidget {
  const AcmeTag({
    super.key,
    @RestageProperty(description: 'The label.') required this.label,
    @RestageProperty(description: 'The opacity.') this.tone = 1.0,
  });

  final String label;
  final double tone;

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: tone, child: Text(label));
}

@RestageWidget(
  name: 'AcmeChip',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.decoration,
  description: 'A chip.',
)
final class const AcmeChip({
  super.key,
  @RestageProperty(description: 'The text.') required final String text,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Chip(label: Text(text));
}

@RestageWidget(
  name: 'AcmeBanner',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.decoration,
  description: 'A banner.',
)
final class AcmeBanner extends StatefulWidget {
  const AcmeBanner({
    super.key,
    @RestageProperty(description: 'The title.') required this.title,
    @RestageProperty(description: 'The fill.') this.fill,
  });

  final String title;
  final Color? fill;

  @override
  State<AcmeBanner> createState() => _AcmeBannerState();
}

final class _AcmeBannerState extends State<AcmeBanner> {
  bool open = false;

  @override
  Widget build(BuildContext context) => Container(
    color: widget.fill ?? Colors.blue,
    child: Text(open ? widget.title : 'Closed'),
  );
}
