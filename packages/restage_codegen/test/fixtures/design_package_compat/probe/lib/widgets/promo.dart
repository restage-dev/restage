import 'package:material_ui/material_ui.dart';
import 'package:restage/restage.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('probe.widgets'),
  capabilityVersion: 1,
)
const probeWidgetLibrary = 0;

/// A registered custom widget carrying a material_ui-sourced ENUM property.
@RestageWidget(
  name: 'PromoBadge',
  library: WidgetLibrary.custom('probe.widgets'),
  category: WidgetCategory.action,
  description: 'Pill-shaped promotional label.',
)
class PromoBadge extends StatelessWidget {
  /// Const constructor.
  const PromoBadge({
    required this.label,
    this.behavior = SnackBarBehavior.floating,
    super.key,
  });

  /// Visible label.
  @RestageProperty(description: 'Visible label.', required: true)
  final String label;

  /// A material_ui-sourced enum.
  @RestageProperty(description: 'Snack bar behavior.')
  final SnackBarBehavior behavior;

  @override
  Widget build(BuildContext context) => Text(label);
}
