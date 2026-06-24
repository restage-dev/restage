import 'package:flutter/material.dart';
import 'package:restage_core/restage_core.dart';

/// A segmented button (single- or multi-select) expressed as a purely
/// declarative surface.
///
/// Each entry in [items] becomes one segment (a `ButtonSegment`); the segments
/// whose [RestageSelectionOption.value] are in [selected] are shown selected.
/// Choosing a segment fires [onChanged] with the **whole settled selection** as
/// a `List<String>` in **segment order** (never tap/insertion order and never
/// `Set`-iteration order — the fired list is deterministic so the event wire is
/// stable). The selection wiring (a `Set<T>` the framework `SegmentedButton`
/// drives) lives inside this compiled widget; a declarative composition supplies
/// only the inert [items] / [selected] values and names the [onChanged] event,
/// never the `Set` machinery — a `Set` is not a wire-safe value, so the
/// selection rides as a `List` and the `Set` is materialized here.
///
/// The wrapper owns every constructor-precondition fail-safe the framework
/// `SegmentedButton` asserts, so a corrupt / hostile / stale wire degrades
/// rather than crashing the render:
///
///  * empty [items] renders nothing (`assert(segments.length > 0)`);
///  * a [selected] value absent from [items] is dropped
///    (`segments` carries no phantom selection);
///  * duplicate-value items are de-duped, first occurrence wins
///    (`ButtonSegment.value` must be unique);
///  * a [selected] with 2+ values while [multiSelectionEnabled] is false is
///    clamped to the first (in segment order)
///    (`assert(selected.length < 2 || multiSelectionEnabled)`);
///  * an empty effective selection always passes `emptySelectionAllowed: true`
///    to the framework widget so it never trips
///    `assert(selected.length > 0 || emptySelectionAllowed)`, regardless of the
///    authored [emptySelectionAllowed].
///
/// The canonical instantiation is `RestageSegmentedButton<String>` (the
/// wire-comparable value type); the value casts below are runtime identities for
/// that instantiation.
class RestageSegmentedButton<T> extends StatelessWidget {
  /// Creates a declarative segmented button.
  const RestageSegmentedButton({
    super.key,
    required this.items,
    this.selected,
    this.onChanged,
    this.multiSelectionEnabled = false,
    this.emptySelectionAllowed = false,
    this.showSelectedIcon = true,
  });

  /// The selectable segments, in display order. Each becomes one segment. An
  /// empty list renders nothing.
  final List<RestageSelectionOption> items;

  /// The currently-selected segment values. Segments whose value is in this
  /// list are shown selected; values absent from [items] are ignored. In
  /// single-select mode (the default) only the first (in segment order) is
  /// honored. `null` (or an empty list) is no initial selection.
  final List<T>? selected;

  /// Fires with the whole settled selection — a `List<T>` in **segment order**
  /// — when the user changes the selection. `null` leaves the button
  /// non-interactive (it renders the initial selection but does not respond).
  final ValueChanged<List<T>>? onChanged;

  /// Whether more than one segment may be selected at once. Defaults to
  /// `false` (single-select — the dominant case).
  final bool multiSelectionEnabled;

  /// Whether the user may deselect down to an empty selection. Defaults to
  /// `false`. (A degenerate wire whose effective selection is already empty is
  /// always tolerated regardless of this flag — see the class docs.)
  final bool emptySelectionAllowed;

  /// Whether a checkmark icon is shown on selected segments. Defaults to
  /// `true` (the framework default).
  final bool showSelectedIcon;

  @override
  Widget build(BuildContext context) {
    // De-duplicate by value (first occurrence wins) so the unique-value
    // requirement holds: a duplicate-value wire (a corruption / tamper case the
    // build-time recognition rejects) would otherwise carry two segments with
    // the same value.
    final options = dedupeSelectionOptionsByValue(items);
    if (options.isEmpty) return const SizedBox.shrink();

    // Resolve the selected set in SEGMENT order, dropping any value not present
    // in the (de-duped) segments. Iterating `options` (not `selected`) keeps the
    // result deterministic and ordered, and naturally de-dupes a repeated
    // selected value.
    final selectedValues = (selected ?? const []).toSet();
    var effective = <T>[
      for (final option in options)
        if (selectedValues.contains(option.value as T)) option.value as T,
    ];
    // Single-select clamp: keep only the first selected value (in segment
    // order). Guards `assert(selected.length < 2 || multiSelectionEnabled)`.
    if (!multiSelectionEnabled && effective.length > 1) {
      effective = <T>[effective.first];
    }

    return SegmentedButton<T>(
      segments: <ButtonSegment<T>>[
        for (final option in options)
          ButtonSegment<T>(
            value: option.value as T,
            label: Text(option.label),
          ),
      ],
      selected: effective.toSet(),
      multiSelectionEnabled: multiSelectionEnabled,
      // Always tolerate an already-empty effective selection so a stale /
      // hostile / unmatched `selected` never trips
      // `assert(selected.length > 0 || emptySelectionAllowed)`. When the
      // selection is non-empty the authored flag governs whether the user may
      // clear it.
      emptySelectionAllowed: emptySelectionAllowed || effective.isEmpty,
      showSelectedIcon: showSelectedIcon,
      // `null` leaves the button non-interactive. A non-null callback receives
      // the framework's `Set<T>` and forwards the whole selection as a
      // SEGMENT-ORDERED `List<T>` — deterministic, so the event wire is stable.
      onSelectionChanged: onChanged == null
          ? null
          : (Set<T> newSelection) => onChanged!(
                <T>[
                  for (final option in options)
                    if (newSelection.contains(option.value as T))
                      option.value as T,
                ],
              ),
    );
  }
}
