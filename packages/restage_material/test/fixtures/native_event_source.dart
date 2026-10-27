import 'package:flutter/material.dart' as f;
import 'package:restage_core/restage_core.dart' as r;
import 'package:restage_shared/restage_shared.dart' as s;

part 'native_event_source.g.dart';

class NativeEventSource extends f.StatelessWidget {
  const NativeEventSource({
    super.key,
    required this.tabs,
    required this.scroll,
    required this.borrowed,
  });
  final f.TabController tabs;
  final f.ScrollController scroll;
  final f.VoidCallback? borrowed;

  @override
  f.Widget build(f.BuildContext context) => f.Column(children: [
        f.FilledButton(
            onPressed: () => tabs.animateTo(1), child: const f.Text('Tab')),
        f.GestureDetector(
            onTap: () => scroll.jumpTo(80), child: const f.Text('Scroll')),
        f.FilledButton(onPressed: borrowed, child: const f.Text('Borrowed')),
      ]);
}

class NativeLexicalEventSource extends f.StatelessWidget {
  const NativeLexicalEventSource({super.key, required this.observer});
  final f.ValueChanged<int> observer;
  @override
  f.Widget build(f.BuildContext context) =>
      f.LayoutBuilder(builder: (context, constraints) {
        var count = 0;
        return f.FilledButton(
            onPressed: () => observer(count++), child: const f.Text('Count'));
      });
}
