import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('customer.measurement'),
  capabilityVersion: 1,
)
const customerMeasurementLibrary = 0;

@RestageWidget(
  name: 'InlineAction',
  library: WidgetLibrary.custom('customer.measurement'),
  category: WidgetCategory.input,
  description: 'An inlinable customer action.',
)
final class InlineAction extends StatelessWidget {
  const InlineAction({required this.onPressed, super.key});

  @RestageProperty(description: 'Activation callback.', required: true)
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onPressed,
        child: const Text('Inline'),
      );
}

@RestageWidget(
  name: 'OpaqueAction',
  library: WidgetLibrary.custom('customer.measurement'),
  category: WidgetCategory.input,
  description: 'An app-backed customer action.',
)
final class OpaqueAction extends StatelessWidget {
  const OpaqueAction({required this.onPressed, super.key});

  @RestageProperty(description: 'Activation callback.', required: true)
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _OpaqueActionPainter());
}

final class _OpaqueActionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
