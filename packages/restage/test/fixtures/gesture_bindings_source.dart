import 'package:flutter/gestures.dart' as g;
import 'package:flutter/widgets.dart' as f;
import 'package:restage_core/restage_core.dart' as r;
import 'package:restage/restage.dart' as app;
import 'package:restage_shared/restage_shared.dart' as s;

part 'gesture_bindings_source.g.dart';
part 'gesture_measurement.g.dart';

@app.Screen()
class GestureTapScreen extends f.StatelessWidget {
  const GestureTapScreen({super.key, required this.seen, required this.up});
  final void Function(String, Object) seen;
  final g.GestureTapUpCallback up;
  @override
  f.Widget build(f.BuildContext context) => f.Text.rich(f.TextSpan(
      text: 'Tap',
      recognizer: g.TapGestureRecognizer()
        ..onTapDown = ((details) => seen('down', details))
        ..onTapMove = ((details) => seen('move', details))
        ..onSecondaryTapDown = ((details) => seen('secondary.down', details))
        ..onSecondaryTapUp = ((details) => seen('secondary.up', details))
        ..onTertiaryTapDown = ((details) => seen('tertiary.down', details))
        ..onTertiaryTapUp = ((details) => seen('tertiary.up', details))
        ..onTapUp = up));
}

class GestureDoubleScreen extends f.StatelessWidget {
  const GestureDoubleScreen({super.key, required this.seen});
  final void Function(String, Object) seen;
  @override
  f.Widget build(f.BuildContext context) => f.Text.rich(f.TextSpan(
      text: 'Tap',
      recognizer: g.DoubleTapGestureRecognizer()
        ..onDoubleTapDown = ((details) => seen('down', details))));
}

class GestureLongScreen extends f.StatelessWidget {
  const GestureLongScreen({super.key, required this.seen});
  final void Function(String, Object) seen;
  @override
  f.Widget build(f.BuildContext context) => f.Text.rich(f.TextSpan(
      text: 'Tap',
      recognizer: g.LongPressGestureRecognizer(
          duration: const Duration(milliseconds: 80))
        ..onLongPressDown = ((details) => seen('down', details))
        ..onLongPressStart = ((details) => seen('start', details))
        ..onLongPressMoveUpdate = ((details) => seen('move', details))
        ..onLongPressEnd = ((details) => seen('end', details))
        ..onSecondaryLongPressDown =
            ((details) => seen('secondary.down', details))
        ..onSecondaryLongPressStart =
            ((details) => seen('secondary.start', details))
        ..onSecondaryLongPressMoveUpdate =
            ((details) => seen('secondary.move', details))
        ..onSecondaryLongPressEnd =
            ((details) => seen('secondary.end', details))
        ..onTertiaryLongPressDown =
            ((details) => seen('tertiary.down', details))
        ..onTertiaryLongPressStart =
            ((details) => seen('tertiary.start', details))
        ..onTertiaryLongPressMoveUpdate =
            ((details) => seen('tertiary.move', details))
        ..onTertiaryLongPressEnd =
            ((details) => seen('tertiary.end', details))));
}

@app.Screen()
class GestureBorrowedScreen extends f.StatelessWidget {
  const GestureBorrowedScreen({super.key, required this.recognizer});
  final g.GestureRecognizer recognizer;
  @override
  f.Widget build(f.BuildContext context) => f.Text.rich(f.TextSpan(children: [
        f.TextSpan(text: 'First', recognizer: recognizer),
        f.TextSpan(text: 'Second', recognizer: recognizer),
      ]));
}

class GestureLiveScreen extends f.StatelessWidget {
  const GestureLiveScreen({super.key, required this.seen});
  final void Function(int, Object) seen;
  @override
  f.Widget build(f.BuildContext context) =>
      f.LayoutBuilder(builder: (context, constraints) {
        var count = 0;
        return f.Text.rich(f.TextSpan(children: [
          f.TextSpan(
              text: 'First',
              recognizer: g.TapGestureRecognizer()
                ..onTapDown = ((details) => seen(count++, details))
                ..onTapUp = ((details) => seen(count++, details))),
          f.TextSpan(
              text: 'Second',
              recognizer: g.TapGestureRecognizer()
                ..onTapDown = ((details) => seen(count++, details))
                ..onTapUp = ((details) => seen(count++, details))),
        ]));
      });
}

void Function(g.TapDownDetails)? gestureTearoffSeen;
void recordGestureDown(g.TapDownDetails details) =>
    gestureTearoffSeen?.call(details);

class GestureTearoffScreen extends f.StatelessWidget {
  const GestureTearoffScreen({super.key});
  @override
  f.Widget build(f.BuildContext context) => f.Text.rich(f.TextSpan(
      text: 'Tap',
      recognizer: g.TapGestureRecognizer()..onTapDown = recordGestureDown));
}

class GestureContextScreen extends f.StatelessWidget {
  const GestureContextScreen({super.key, required this.seen});
  final void Function(f.BuildContext, g.TapDownDetails) seen;
  @override
  f.Widget build(f.BuildContext context) => f.LayoutBuilder(
      builder: (context, constraints) => f.Text.rich(f.TextSpan(
          text: 'Tap',
          recognizer: g.TapGestureRecognizer()
            ..onTapDown = ((details) => seen(context, details)))));
}
