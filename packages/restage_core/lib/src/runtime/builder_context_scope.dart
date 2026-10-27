part of 'builder_binding.dart';

final class _BuilderContextFrame {
  const _BuilderContextFrame(this.context, this.parent,
      [this.locals, this.nativeBindings]);
  final BuildContext context;
  final _BuilderContextFrame? parent;
  final ValueLocalFrame? locals;
  final Map<String, NativeBinding<Object?>>? nativeBindings;

  factory _BuilderContextFrame.callback(BuildContext context) =>
      _BuilderContextFrame(context, _BuilderContextScope.maybeOf(context));

  factory _BuilderContextFrame.borrow(BuildContext context) =>
      _BuilderContextScope.maybeOf(context) ??
      _BuilderContextFrame(context, null);

  BuildContext at(int depth) {
    var frame = this;
    for (var index = 0; index < depth; index++) {
      final ancestor = frame.parent;
      if (ancestor == null) {
        throw const FormatException('Native callback context is unavailable');
      }
      frame = ancestor;
    }
    if (!frame.context.mounted) {
      throw StateError('Native callback context is unmounted');
    }
    return frame.context;
  }
}

final class _BuilderContextScope extends InheritedWidget {
  const _BuilderContextScope({required this.frame, required super.child});
  final _BuilderContextFrame frame;

  static _BuilderContextFrame? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BuilderContextScope>()?.frame;

  @override
  bool updateShouldNotify(_BuilderContextScope oldWidget) =>
      !identical(frame, oldWidget.frame);
}

ValueOperationContext _lexicalContext(
    BuildContext? context, Map<String, ValueOperation> operations,
    {DataSource? source}) {
  final frame = source is _ValueDataSource
      ? source.frame
      : context == null
          ? null
          : _BuilderContextScope.maybeOf(context)?.locals;
  return ValueOperationContext(
      operations: operations,
      locals: frame?.visibleTypes ?? const {},
      frame: frame);
}
