import 'package:flutter/widgets.dart' as f;
import 'package:restage_core/restage_core.dart' as r;
import 'package:restage_shared/restage_shared.dart' as s;

part 'callback_context_source.g.dart';

final contextCallbacks = <String, f.BuildContext Function()>{};

class ContextProbe extends f.StatelessWidget {
  const ContextProbe(this.name, this.callback, {this.child, super.key});
  final String name;
  final f.BuildContext Function() callback;
  final f.Widget? child;
  @override
  f.Widget build(f.BuildContext context) {
    contextCallbacks[name] = callback;
    return child ?? const f.SizedBox();
  }
}

f.Widget authoredDirect() => f.LayoutBuilder(
    builder: (context, constraints) => ContextProbe('direct', () => context));

f.Widget authoredAlias() => f.Builder(builder: (context) {
      final alias = context;
      return ContextProbe('alias', () => alias);
    });

f.Widget forwardContext(f.BuildContext forwarded) =>
    ContextProbe('helper', () => forwarded);

f.Widget authoredHelper() =>
    f.LayoutBuilder(builder: (context, constraints) => forwardContext(context));

f.Widget authoredNested() => f.LayoutBuilder(builder: (outer, constraints) {
      final alias = outer;
      return ContextProbe('outer', () => alias,
          child: f.LayoutBuilder(builder: (inner, constraints) {
        var selected = inner;
        final saved = () => selected;
        selected = alias;
        return ContextProbe('inner', () => inner,
            child: ContextProbe('retainedOuter', () => alias,
                child: ContextProbe('mutable', saved)));
      }));
    });
