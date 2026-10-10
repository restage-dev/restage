// @dart=3.13
import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageWidget(
  name: 'AcmeNote',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.decoration,
  description: 'A note.',
)
final class AcmeNote extends StatelessWidget {
  const AcmeNote({
    super.key,
    @RestageProperty(description: 'The text.') required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    final shown = text;
    return Text(shown);
  }
}
