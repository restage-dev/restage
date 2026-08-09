import 'package:flutter/material.dart';
import 'package:restage/a2ui.dart' as a2ui;
import 'package:restage/restage.dart';

/// A compact executable proof that all generated targets invoke Dart's
/// constructor contract rather than merely emitting source bytes.
@a2ui.Config(
  usage: 'Use to verify generated constructor binding and callback write-back.',
  writeBackValues: <String, String>{'onChanged': 'enabled'},
)
@RestageWidget(
  name: 'ConstructorFidelityProof',
  library: WidgetLibrary.custom('restage_widgetbook_example.widgets'),
  category: WidgetCategory.input,
)
class ConstructorFidelityProof extends StatelessWidget {
  /// Creates the cross-target proof widget.
  const ConstructorFidelityProof(
    this.label, {
    super.key,
    this.enabled = true,
    this.optionalText = 'constructor-default',
    required this.onChanged,
  });

  /// Required positional label.
  final String label;

  /// Optional named value whose omission preserves the Dart default.
  final bool enabled;

  /// Optional text used to distinguish authored values from defaults.
  final String optionalText;

  /// Arbitrarily named one-argument callback paired with [enabled].
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label|$enabled|$optionalText'),
        TextButton(
          key: const ValueKey('constructor-fidelity-toggle'),
          onPressed: () => onChanged(!enabled),
          child: const Text('Toggle proof value'),
        ),
      ],
    );
  }
}
