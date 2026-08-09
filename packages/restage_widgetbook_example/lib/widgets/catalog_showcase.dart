import 'package:flutter/material.dart';
import 'package:restage/a2ui.dart' as a2ui;
import 'package:restage/restage.dart';

/// The current state of a [CatalogShowcase].
enum CatalogShowcaseStatus {
  /// The catalog item is ready for interaction.
  ready,

  /// The catalog item is processing a change.
  processing,
}

/// Customer-owned structured information displayed by a [CatalogShowcase].
class CatalogShowcaseData {
  /// Creates customer-owned showcase information.
  const CatalogShowcaseData({required this.note, required this.count});

  /// Supporting customer text.
  final String note;

  /// Customer-owned count.
  final int count;
}

/// A customer catalog widget proving one source can feed every enabled target.
/// It combines ordinary scalar state, an enum, callback write-back, native
/// child slots, and customer-owned structured data.
///
/// The second paragraph is retained in generated property metadata so
/// multi-paragraph Dart documentation is never reduced to its first line.
@a2ui.Config(
  usage: 'Use to verify a customer catalog across RFW, A2UI, and Widgetbook.',
)
@RestageWidget(
  name: 'CatalogShowcase',
  library: WidgetLibrary.custom('restage_widgetbook_example.widgets'),
  category: WidgetCategory.input,
  childrenSlot: ChildrenSlot.list,
)
class CatalogShowcase extends StatelessWidget {
  /// Creates a catalog showcase.
  const CatalogShowcase({
    super.key,
    required this.title,
    this.enabled = true,
    required this.status,
    required this.onChanged,
    required this.header,
    required this.children,
    required this.data,
  });

  /// Visible customer title.
  final String title;

  /// Whether the customer control is enabled.
  final bool enabled;

  /// Current customer state.
  final CatalogShowcaseStatus status;

  /// Reports changes to [enabled].
  @a2ui.Config.writeBackValue('enabled')
  final ValueChanged<bool> onChanged;

  /// Customer widget shown before the content list.
  final Widget header;

  /// Customer widgets shown in source order.
  final List<Widget> children;

  /// Customer-owned structured information.
  final CatalogShowcaseData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Text(title),
        Text('${status.name}: ${data.note} (${data.count})'),
        Switch(value: enabled, onChanged: onChanged),
        ...children,
      ],
    );
  }
}
