import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Calls [onInteraction] when the user drags or scrolls anything [child]
/// shows, or focuses a text field in it, so a host never replaces state
/// the user built up. A tap alone is not counted. Adds no render object, so a
/// parent-data child keeps its parent.
@internal
final class UserInteractionWatch extends StatefulWidget {
  /// Watches [child] for user interaction.
  const UserInteractionWatch({
    required this.onInteraction,
    required this.child,
    super.key,
  });

  /// Called on each interaction.
  final VoidCallback onInteraction;

  /// What the user interacts with.
  final Widget child;

  @override
  State<UserInteractionWatch> createState() => _UserInteractionWatchState();
}

class _UserInteractionWatchState extends State<UserInteractionWatch> {
  // Where each pointer that went down inside [child] started.
  final _downs = <int, Offset>{};

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
    FocusManager.instance.removeListener(_focusChanged);
    super.dispose();
  }

  void _route(PointerEvent event) {
    if (!mounted) return;
    switch (event) {
      case PointerDownEvent():
        if (_inside(event)) _downs[event.pointer] = event.position;
      case PointerMoveEvent():
        final start = _downs[event.pointer];
        // A pointer that moves past the slop drags, as a gesture would.
        final slop = computeHitSlop(
            event.kind, MediaQuery.maybeGestureSettingsOf(context));
        if (start != null && (event.position - start).distance > slop) {
          _downs.remove(event.pointer);
          widget.onInteraction();
        }
      case PointerUpEvent() || PointerCancelEvent():
        _downs.remove(event.pointer);
      case PointerSignalEvent() || PointerPanZoomStartEvent():
        if (_inside(event)) widget.onInteraction();
      default:
    }
  }

  bool _inside(PointerEvent event) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, event.position, event.viewId);
    return result.path.any((entry) => identical(entry.target, box));
  }

  // A text field focused inside [child] is where the user types; a button
  // a tap focuses is not.
  void _focusChanged() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (!mounted ||
        focused == null ||
        focused.findAncestorStateOfType<EditableTextState>() == null) {
      return;
    }
    var inside = identical(focused, context);
    focused.visitAncestorElements((element) {
      if (identical(element, context)) inside = true;
      return !inside;
    });
    if (inside) widget.onInteraction();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<UserScrollNotification>(
        onNotification: (_) {
          widget.onInteraction();
          return false;
        },
        child: widget.child,
      );
}
