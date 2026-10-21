import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('custom.failure'),
  capabilityVersion: 1,
)
const customFailureLibrary = 0;

@RestageWidget(
  name: 'AppGround',
  library: WidgetLibrary.custom('custom.failure'),
  category: WidgetCategory.layout,
  description: 'Paints the app ground behind its child.',
)
final class AppGround extends StatelessWidget {
  const AppGround({required this.child, super.key});

  @RestageProperty(description: 'The content.', required: true)
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _GroundPainter(), child: child);
}

@RestageWidget(
  name: 'AppClock',
  library: WidgetLibrary.custom('custom.failure'),
  category: WidgetCategory.decoration,
  description: 'Shows a moment.',
)
final class AppClock extends StatelessWidget {
  const AppClock({required this.moment, super.key});

  @RestageProperty(description: 'The moment.', required: true)
  final DateTime moment;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

final class _GroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
