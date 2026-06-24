import 'package:flutter/material.dart';

/// A horizontal set of mutually-independent toggle buttons expressed as a
/// purely declarative surface.
///
/// Each entry in [children] is one toggle button's label; the parallel
/// [isSelected] list gives each button's pressed state by index. Pressing a
/// button fires [onPressed] with that button's index — the settled toggle
/// event. A declarative composition supplies only the inert [children] /
/// [isSelected] values and names the [onPressed] event; the press/highlight
/// machinery lives inside Flutter's `ToggleButtons`, which this widget builds.
///
/// **Cross-slot length reconciliation (the fail-safe).** Flutter's
/// `ToggleButtons` asserts `children.length == isSelected.length`; the two
/// lists arrive as independently-decoded slots, so a corrupt or tampered wire
/// could deliver mismatched lengths. Rather than let that trip the framework
/// assert (which would crash the render), this widget reconciles them: a short
/// [isSelected] is padded with `false` (unselected) up to [children]'s length,
/// and a long one is truncated to it — never a throw. The leading flags are
/// preserved, so a well-formed wire (equal lengths, which the build-time
/// recognition enforces) is untouched; only a malformed wire is degraded
/// safely. When [children] is empty it renders nothing (the fail-safe), never a
/// broken or partial set.
class RestageToggleButtons extends StatelessWidget {
  /// Creates a declarative toggle-button set.
  const RestageToggleButtons({
    super.key,
    required this.children,
    required this.isSelected,
    this.onPressed,
  });

  /// The per-button labels, in display order. Each becomes one toggle button.
  /// An empty list renders nothing.
  final List<Widget> children;

  /// Each button's pressed state, by index, parallel to [children]. Reconciled
  /// to [children]'s length when the two differ (pad-with-false / truncate),
  /// so a mismatched wire never trips the framework's length assert.
  final List<bool> isSelected;

  /// Fires with the pressed button's index when the user presses a button.
  /// `null` disables the set (the buttons render but do not respond).
  final ValueChanged<int>? onPressed;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return ToggleButtons(
      isSelected: _reconciledSelection,
      onPressed: onPressed,
      children: children,
    );
  }

  /// [isSelected] reconciled to [children]'s length: padded with `false` when
  /// shorter, truncated when longer, returned as-is when equal. This is the
  /// cross-slot fail-safe that keeps a mismatched-length wire off the
  /// `ToggleButtons` length assert.
  List<bool> get _reconciledSelection {
    final count = children.length;
    if (isSelected.length == count) return isSelected;
    return <bool>[
      for (var i = 0; i < count; i++) i < isSelected.length && isSelected[i],
    ];
  }
}
