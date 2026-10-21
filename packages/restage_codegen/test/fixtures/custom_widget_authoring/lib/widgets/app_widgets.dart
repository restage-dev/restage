import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('custom.authoring'),
  capabilityVersion: 1,
)
const customAuthoringLibrary = 0;

@RestageWidget(
  name: 'AppGround',
  library: WidgetLibrary.custom('custom.authoring'),
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
  name: 'AppButton',
  library: WidgetLibrary.custom('custom.authoring'),
  category: WidgetCategory.input,
  description: 'The app pill button.',
)
final class AppButton extends StatelessWidget {
  const AppButton({required this.label, this.onPressed, super.key});

  @RestageProperty(description: 'The label.', required: true)
  final String label;

  @RestageProperty(description: 'Activation callback.')
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GroundPainter());
}

@RestageWidget(
  name: 'AppText',
  library: WidgetLibrary.custom('custom.authoring'),
  category: WidgetCategory.decoration,
  description: 'Text in the app type scale.',
)
final class AppText extends StatelessWidget {
  const AppText(this.text, {this.large = false, super.key});

  @RestageProperty(description: 'The words.', required: true)
  final String text;

  @RestageProperty(description: 'Whether it is a title.')
  final bool large;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GroundPainter());
}

@RestageWidget(
  name: 'AppLegal',
  library: WidgetLibrary.custom('custom.authoring'),
  category: WidgetCategory.decoration,
  description: 'Subscription terms, one paragraph each.',
)
final class AppLegal extends StatelessWidget {
  const AppLegal({required this.paragraphs, required this.widths, super.key});

  @RestageProperty(description: 'The paragraphs.', required: true)
  final List<String> paragraphs;

  @RestageProperty(description: 'Column widths.', required: true)
  final List<double> widths;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GroundPainter());
}

final class _GroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
