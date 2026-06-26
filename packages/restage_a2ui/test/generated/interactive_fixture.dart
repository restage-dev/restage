// A real, hand-written customer widget library of INTERACTIVE controlled
// components — the kind a developer writes and annotates with `@RestageWidget`.
// The interactivity proof resolves THIS source with the analyzer, reflects each
// widget's callback parameters into callback signatures (the event seam) and
// reads each callback field's `@RestageProperty(writeBackValue:)` annotation
// metadata (the pairing seam), runs the catalog through the production A2UI
// emitter, and renders the generated catalog against real genui — then drives
// interaction (tap -> write-back -> re-render; tap -> dispatch). Each widget is
// a CONTROLLED COMPONENT: a value property + a `ValueChanged` callback that
// writes it (the genui data model is the state store), or a `VoidCallback` that
// dispatches an outward action. (The `@RestageWidget` class annotation itself is
// build-phase discovery — a tracked follow-up — and is not needed to reflect the
// callback types or read the property annotations.)
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A QuickCheck-style single-answer selector — the acceptance-bar shape
/// (Cagatay Ulusoy's "select an answer -> mark correct" two-way binding).
///
/// A controlled component: an `int selected` value + a `ValueChanged<int>
/// onSelected` callback. Auto single-pair (exactly one value-changing callback
/// and one matching-type value property) wires them with NO annotation.
class QuickCheckFixture extends StatelessWidget {
  /// Creates a QuickCheck selector bound to [selected], reporting taps via
  /// [onSelected].
  const QuickCheckFixture({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The index of the currently selected answer (the two-way-bound value).
  final int selected;

  /// Fired with the tapped answer's index — the write-back callback.
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('quickcheck-selected:$selected'),
        for (var i = 0; i < 3; i++)
          GestureDetector(
            key: ValueKey('quickcheck-option-$i'),
            onTap: () => onSelected(i),
            child: Text('quickcheck-option-$i'),
          ),
      ],
    );
  }
}

/// A multi-select chip group — the list write-back shape.
///
/// A controlled component: a `List<String> chosen` value + a
/// `ValueChanged<List<String>> onChosen` callback that writes the settled list.
/// Auto single-pair wires them with NO annotation; the list element is a scalar
/// (the `#L` element-scalar guarantee), so the settled list is `List<String>`.
class MultiSelectFixture extends StatelessWidget {
  /// Creates a multi-select bound to [chosen], reporting changes via [onChosen].
  const MultiSelectFixture({
    required this.chosen,
    required this.onChosen,
    super.key,
  });

  /// The currently chosen values (the two-way-bound list).
  final List<String> chosen;

  /// Fired with the new settled list — the list write-back callback.
  final ValueChanged<List<String>> onChosen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('multiselect-chosen:${chosen.join(',')}'),
        GestureDetector(
          key: const ValueKey('multiselect-add-b'),
          onTap: () => onChosen([...chosen, 'b']),
          child: const Text('multiselect-add-b'),
        ),
      ],
    );
  }
}

/// An action button — the dispatch shape.
///
/// A `String label` value + a `VoidCallback onPressed` that dispatches an
/// outward `UserActionEvent` (no value to control). The event name is
/// compile-fixed from the callback property name.
class ActionButtonFixture extends StatelessWidget {
  /// Creates an action button labelled [label], dispatching via [onPressed].
  const ActionButtonFixture({
    required this.label,
    required this.onPressed,
    super.key,
  });

  /// The button label (a plain catalog-fed value property).
  final String label;

  /// Fired on tap — the dispatch callback (an outward action, no value).
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('actionbutton'),
      onTap: onPressed,
      child: Text('actionbutton:$label'),
    );
  }
}

/// A range control — the multi-control shape that auto single-pair cannot
/// resolve (two value-changing callbacks), so each callback declares its target
/// value property explicitly via `@RestageProperty(writeBackValue:)`.
///
/// Two independent `int` controls, each with its own value property and
/// `ValueChanged<int>` callback. The explicit pairings wire `onLow -> low` and
/// `onHigh -> high` to two DISTINCT data paths (no cross-wiring).
class RangeFixture extends StatelessWidget {
  /// Creates a range bound to [low] and [high], reporting changes via [onLow]
  /// and [onHigh].
  const RangeFixture({
    required this.low,
    required this.high,
    required this.onLow,
    required this.onHigh,
    super.key,
  });

  /// The low bound (two-way-bound, paired with [onLow]).
  final int low;

  /// The high bound (two-way-bound, paired with [onHigh]).
  final int high;

  /// Writes the low bound — explicitly paired to `low`.
  @RestageProperty(
    description: 'Reports a new low bound.',
    writeBackValue: 'low',
  )
  final ValueChanged<int> onLow;

  /// Writes the high bound — explicitly paired to `high`.
  @RestageProperty(
    description: 'Reports a new high bound.',
    writeBackValue: 'high',
  )
  final ValueChanged<int> onHigh;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('range-low:$low'),
        Text('range-high:$high'),
        GestureDetector(
          key: const ValueKey('range-low-inc'),
          onTap: () => onLow(low + 1),
          child: const Text('range-low-inc'),
        ),
        GestureDetector(
          key: const ValueKey('range-high-inc'),
          onTap: () => onHigh(high + 1),
          child: const Text('range-high-inc'),
        ),
      ],
    );
  }
}
