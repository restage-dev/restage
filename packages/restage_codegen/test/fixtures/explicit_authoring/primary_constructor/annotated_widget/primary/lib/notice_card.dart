// @dart=3.13
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class P extends StatelessWidget {
  const P(this.a, {super.key});
  final String a;
  @override
  Widget build(BuildContext context) => Text(a);
}

@RestageWidget(
  name: 'NoticeCard',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.decoration,
  description: 'A notice card.',
)
class const NoticeCard(
  @RestageProperty(description: 'The label.') super.a, {
  @RestageProperty(description: 'The action.')
  required final VoidCallback onTap,
  @RestageProperty(description: 'The style.') required final EdgeInsets style,
}) extends P;
