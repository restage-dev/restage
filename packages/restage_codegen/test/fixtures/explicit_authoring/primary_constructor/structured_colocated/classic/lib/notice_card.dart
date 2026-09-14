// @dart=3.13
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class Badge {
  const Badge({required this.label, required this.count});
  final String label;
  final int count;
}

@RestageWidget(
  name: 'NoticeCard',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.decoration,
  description: 'A notice card.',
)
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    @RestageProperty(description: 'The badge.') required this.badge,
    super.key,
  });
  final Badge badge;
  @override
  Widget build(BuildContext context) => Text(badge.label);
}

@RestageLibrary(
  library: WidgetLibrary.custom('acme.widgets'),
  capabilityVersion: 1,
)
const restageLibrary = 0;
