part of 'builder_binding.dart';

/// Runs a compiled callback against an RFW-owned data source.
Widget buildRestageBuilderContinuation(
    BuildContext context, DataSource source) {
  final frame = context
      .dependOnInheritedWidgetOfExactType<_BuilderInvocationScope>()
      ?.frame;
  if (frame == null) {
    throw StateError('Builder continuation requires an invocation');
  }
  frame.complete(source);
  return const _BuilderContinuationLeaf();
}

final class _BuilderContinuation {
  _BuilderContinuation(this.helper);
  final Widget helper;
  final _contexts = <Element>{};
  BuildOwner? _owner;
  RootElement? _root;
  bool _invoking = false;
  bool _disposed = false;

  T invoke<T>(BuildContext context, T Function(DataSource) evaluate) {
    if (_disposed) throw StateError('Builder binding is disposed');
    if (_invoking) throw StateError('Builder invocation is already running');
    _contexts.removeWhere((element) => !element.mounted);
    _contexts.add(context as Element);
    final frame = _BuilderInvocationFrame(evaluate);
    final owner = _owner ??= BuildOwner(
      focusManager: context.owner!.focusManager,
      onBuildScheduled: _invalidate,
    );
    _invoking = true;
    try {
      _root = RootWidget(
              child: _BuilderInvocationScope(frame: frame, child: helper))
          .attach(owner, _root);
      owner.buildScope(_root!);
      if (!frame.completed) {
        throw StateError('Builder continuation did not execute');
      }
      if (frame.error case final error?) {
        Error.throwWithStackTrace(error, frame.stack!);
      }
      return frame.result as T;
    } finally {
      frame.release();
      _invoking = false;
    }
  }

  void _invalidate() {
    if (_invoking || _disposed) return;
    _contexts.removeWhere((element) => !element.mounted);
    for (final context in _contexts) {
      context.markNeedsBuild();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final owner = _owner;
    final root = _root;
    if (owner != null && root != null) {
      const RootWidget().attach(owner, root);
      owner.buildScope(root);
      owner.finalizeTree();
    }
    _contexts.clear();
    _owner = null;
    _root = null;
  }
}

final class _BuilderInvocationFrame {
  _BuilderInvocationFrame(this.evaluate);
  Object? Function(DataSource)? evaluate;
  bool completed = false;
  Object? result;
  Object? error;
  StackTrace? stack;

  void complete(DataSource source) {
    try {
      result = evaluate!(source);
    } catch (caught, trace) {
      error = caught;
      stack = trace;
    }
    completed = true;
  }

  void release() {
    evaluate = null;
    result = null;
    error = null;
    stack = null;
  }
}

final class _BuilderInvocationScope extends InheritedWidget {
  const _BuilderInvocationScope({required this.frame, required super.child});
  final _BuilderInvocationFrame frame;

  @override
  bool updateShouldNotify(_BuilderInvocationScope oldWidget) => true;
}

final class _BuilderContinuationLeaf extends Widget {
  const _BuilderContinuationLeaf();

  @override
  Element createElement() => _BuilderContinuationElement(this);
}

final class _BuilderContinuationElement extends Element {
  _BuilderContinuationElement(super.widget);

  @override
  bool get debugDoingBuild => false;

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    rebuild();
  }
}
