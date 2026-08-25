// #docregion configured-catalog-widget
import 'package:flutter/material.dart';
import 'package:restage/a2ui.dart' as a2ui;
import 'package:restage/restage.dart';
import 'package:restage/widgetbook.dart' as wb;

/// The current state of a [CatalogShowcase].
enum CatalogShowcaseStatus {
  /// The catalog item is ready for interaction.
  ready,

  /// The catalog item is processing a change.
  processing,
}

/// Structured information displayed by a [CatalogShowcase].
class CatalogShowcaseData {
  /// Creates showcase information.
  const CatalogShowcaseData({required this.note, required this.count});

  /// Supporting text.
  final String note;

  /// The displayed count.
  final int count;
}

/// A catalog widget proving one source can feed every enabled target.
/// It combines ordinary scalar state, an enum, callback write-back, native
/// child-bearing inputs, and your own structured data. The independently
/// named `hero`, `details`, and `footer` inputs require no slot annotation.
///
/// The second paragraph is retained in generated property metadata so
/// multi-paragraph Dart documentation is never reduced to its first line.
@a2ui.Config(
  usage:
      'Use to verify a custom-widget catalog across RFW, A2UI, and Widgetbook.',
)
@RestageWidget(category: WidgetCategory.input)
class CatalogShowcase extends StatelessWidget {
  /// Creates a catalog showcase.
  const CatalogShowcase({
    super.key,
    required this.title,
    this.enabled = true,
    required this.status,
    required this.onChanged,
    required this.hero,
    required this.details,
    this.footer,
    required this.data,
  });

  /// Visible title.
  final String title;

  /// Whether the control is enabled.
  @wb.Config.allValues()
  final bool enabled;

  /// Current state.
  @wb.Config.allValues()
  final CatalogShowcaseStatus status;

  /// Reports changes to [enabled].
  @a2ui.Config.writeBackValue('enabled')
  final ValueChanged<bool> onChanged;

  /// Custom widget shown before the detail list.
  final Widget hero;

  /// Detail widgets shown in source order.
  final List<Widget> details;

  /// Optional custom widget shown after the detail list.
  final Widget? footer;

  /// Structured information.
  final CatalogShowcaseData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        hero,
        Text(title),
        Text('${status.name}: ${data.note} (${data.count})'),
        Switch(value: enabled, onChanged: onChanged),
        ...details,
        ?footer,
      ],
    );
  }
}

// #enddocregion configured-catalog-widget
