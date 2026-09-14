import 'package:flutter/material.dart';
import 'package:restage_core/restage_core.dart';

/// A single-select dropdown with menu behavior compiled into your app.
///
/// Each entry in [items] becomes one menu option (a `DropdownMenuItem`); the
/// option whose [RestageSelectionOption.value] equals [selected] is shown as
/// the current value. Tapping the field opens the menu; choosing an option
/// fires [onChanged] with that option's value — the settled selection event.
/// The menu overlay (an imperative pop-up route in Flutter's own
/// `DropdownButton`) lives inside this widget, compiled into your app. The
/// surface configures [items] and [selected], and binds the [onChanged] event.
///
/// The catalog maps dropdowns to this wrapper, which owns Flutter's overlay
/// route and exposes its configuration through constructor properties.
/// When [items] is empty it renders nothing.
class RestageDropdown<T> extends StatelessWidget {
  /// Creates a declarative dropdown.
  const RestageDropdown({
    super.key,
    required this.items,
    this.selected,
    this.onChanged,
    this.hint,
    this.isExpanded = false,
    this.elevation = 8,
    this.dropdownColor,
    this.borderRadius,
  });

  /// The selectable options, in menu order. Each becomes one menu item. An
  /// empty list renders nothing.
  final List<RestageSelectionOption> items;

  /// The currently-selected option value, shown as the field's current value.
  /// `null` (or a value matching no option) shows the [hint].
  final T? selected;

  /// Fires with the newly-selected value when the user picks an option. `null`
  /// disables the dropdown (it renders but does not open).
  final ValueChanged<T?>? onChanged;

  /// Placeholder text shown when nothing is selected. Null shows an empty
  /// field.
  final String? hint;

  /// Whether the field expands to fill its horizontal space. Defaults to
  /// `false` (the field sizes to its content).
  final bool isExpanded;

  /// The menu's Material elevation. Defaults to `8` (the `DropdownButton`
  /// default).
  final int elevation;

  /// The menu's background color. Null defers to the theme default.
  final Color? dropdownColor;

  /// The menu's corner radius. Null defers to the `DropdownButton` default.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    // De-duplicate by value (first occurrence wins). `DropdownButton` asserts
    // that each value appears in at most one item; a duplicate-value wire (a
    // corruption / tamper case the build-time recognition rejects) would trip
    // that assert, so the widget defends itself rather than crashing.
    final options = dedupeSelectionOptionsByValue(items);
    if (options.isEmpty) return const SizedBox.shrink();
    // `DropdownButton` asserts that `value` matches exactly zero or one item.
    // A `selected` that matches no option (a stale or hostile value) would
    // trip that assert; coerce it to null (show the hint) so a bad selection
    // degrades to "nothing selected" rather than crashing the render.
    final effectiveValue =
        options.any((o) => o.value == selected) ? selected : null;
    return DropdownButton<T>(
      // The option value is a String on the wire; the canonical instantiation
      // is `RestageDropdown<String>`, so this cast is an identity at runtime.
      // A non-String specialization would require a value coercion the
      // compiled instantiation supplies.
      value: effectiveValue,
      isExpanded: isExpanded,
      elevation: elevation,
      dropdownColor: dropdownColor,
      borderRadius: borderRadius,
      hint: hint == null ? null : Text(hint!),
      // `null` disables the button (Flutter's convention); a non-null callback
      // forwards the settled value.
      onChanged: onChanged,
      items: <DropdownMenuItem<T>>[
        for (final option in options)
          DropdownMenuItem<T>(
            value: option.value as T,
            child: Text(option.label),
          ),
      ],
    );
  }
}
