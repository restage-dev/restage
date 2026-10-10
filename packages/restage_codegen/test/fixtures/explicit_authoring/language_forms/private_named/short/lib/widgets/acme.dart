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
    @RestageProperty(description: 'The label.') required this._label,
    @RestageProperty(description: 'The opacity.') this._tone = 1.0,
  });

  final String _label;
  final double _tone;

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: _tone, child: Text(_label));
}

@RestageWidget(
  name: 'AcmeChip',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.decoration,
  description: 'A chip.',
)
final class const AcmeChip({
  super.key,
  @RestageProperty(description: 'The text.') required final String _text,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Chip(label: Text(_text));
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
    @RestageProperty(description: 'The title.') required this._title,
    @RestageProperty(description: 'The fill.') this._fill,
  });

  final String _title;
  final Color? _fill;

  @override
  State<AcmeBanner> createState() => _AcmeBannerState();
}

final class _AcmeBannerState extends State<AcmeBanner> {
  bool open = false;

  @override
  Widget build(BuildContext context) => Container(
    color: widget._fill ?? Colors.blue,
    child: Text(open ? widget._title : 'Closed'),
  );
}
