import 'package:flutter/material.dart';
import 'package:restage_core/restage_core.dart';

/// A single-select radio group expressed as a purely declarative surface.
///
/// Each entry in [items] becomes one selectable row (a `RadioListTile`); the
/// row whose [RestageSelectionOption.value] equals [selected] is checked.
/// Tapping a row fires [onChanged] with that row's value — the settled
/// selection event. The radio-selection wiring (the `RadioGroup` ancestor that
/// flows the group value through the descendant rows) lives inside this
/// compiled widget; a declarative composition supplies only the inert
/// [items] / [selected] values and names the [onChanged] event, never the
/// selection machinery.
///
/// Unlike a bare Flutter `Radio` (which is inert without a `RadioGroup`
/// ancestor and a value-management callback), this is a self-contained widget:
/// it owns its `RadioGroup` and renders the rows itself, so it needs no host
/// wiring. When [items] is empty it renders nothing (the fail-safe), never a
/// broken or partial group.
class RestageRadioGroup<T> extends StatelessWidget {
  /// Creates a declarative radio group.
  const RestageRadioGroup({
    super.key,
    required this.items,
    this.selected,
    this.onChanged,
    this.activeColor,
    this.contentPadding,
    this.dense,
  });

  /// The selectable options, in display order. Each becomes one radio row.
  /// An empty list renders nothing.
  final List<RestageSelectionOption> items;

  /// The currently-selected option value. The row whose value equals this is
  /// checked; `null` (or a value matching no row) leaves the group unselected.
  final T? selected;

  /// Fires with the newly-selected value when the user taps a row. `null`
  /// disables selection (the rows render but do not respond).
  final ValueChanged<T?>? onChanged;

  /// The fill color of the selected radio. Null defers to the theme default.
  final Color? activeColor;

  /// Padding around each row's content. Null defers to the `RadioListTile`
  /// default.
  final EdgeInsetsGeometry? contentPadding;

  /// Whether each row uses the dense vertical layout. Null defers to the
  /// `RadioListTile` default.
  final bool? dense;

  @override
  Widget build(BuildContext context) {
    // De-duplicate by value (first occurrence wins) so the single-select
    // invariant holds: a duplicate-value wire (a corruption / tamper case the
    // build-time recognition rejects) would otherwise check more than one row.
    final options = dedupeSelectionOptionsByValue(items);
    if (options.isEmpty) return const SizedBox.shrink();
    return RadioGroup<T>(
      groupValue: selected,
      onChanged: onChanged ?? (_) {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final option in options)
            RadioListTile<T>(
              // The option value is a String on the wire; the canonical
              // instantiation is `RestageRadioGroup<String>`, so this cast is
              // an identity at runtime. A non-String specialization would
              // require a value coercion the compiled instantiation supplies.
              value: option.value as T,
              title: Text(option.label),
              activeColor: activeColor,
              contentPadding: contentPadding,
              dense: dense,
            ),
        ],
      ),
    );
  }
}
