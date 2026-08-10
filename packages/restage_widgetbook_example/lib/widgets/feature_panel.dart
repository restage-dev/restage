import 'package:flutter/material.dart';
import 'package:restage/a2ui.dart' as a2ui;
import 'package:restage/restage.dart';

/// A panel with a customer header and customer content widgets.
@a2ui.Config.usage('Use to group a compact catalog summary.')
@RestageWidget(
  name: 'FeaturePanel',
  library: WidgetLibrary.custom('restage_widgetbook_example.widgets'),
  category: WidgetCategory.layout,
)
class FeaturePanel extends StatelessWidget {
  /// Creates a composed customer catalog panel.
  const FeaturePanel({super.key, required this.header, required this.children});

  /// Customer widget shown as the panel header.
  final Widget? header;

  /// Customer widgets shown in the panel body.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 420,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header case final header?) ...[
            header,
            const SizedBox(height: 16),
          ],
          ...children.expand(
            (child) => <Widget>[child, const SizedBox(height: 12)],
          ),
        ],
      ),
    );
  }
}
