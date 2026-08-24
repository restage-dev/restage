import 'package:flutter/widgets.dart';

/// @nodoc
typedef RestagePagerPageSinkHandler = void Function(
  int pageIndex,
  int pageCount,
);

/// @nodoc
final class RestagePagerEventSink {
  /// @nodoc
  const RestagePagerEventSink({
    required Object stageToken,
    required bool Function(Object stageToken) isCurrent,
    required RestagePagerPageSinkHandler onPageChanged,
  })  : _stageToken = stageToken,
        _isCurrent = isCurrent,
        _onPageChanged = onPageChanged;

  final Object _stageToken;
  final bool Function(Object stageToken) _isCurrent;
  final RestagePagerPageSinkHandler _onPageChanged;

  /// @nodoc
  void reportPageChanged(int pageIndex, int pageCount) {
    try {
      if (!_isCurrent(_stageToken)) return;
      _onPageChanged(pageIndex, pageCount);
    } on Object {
      return;
    }
  }
}

/// @nodoc
final class RestagePagerEventScope extends InheritedWidget {
  /// @nodoc
  const RestagePagerEventScope({
    super.key,
    required this.sink,
    required super.child,
  });

  final RestagePagerEventSink sink;

  /// @nodoc
  static RestagePagerEventSink? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<RestagePagerEventScope>()
      ?.sink;

  @override
  bool updateShouldNotify(RestagePagerEventScope oldWidget) =>
      !identical(sink, oldWidget.sink);
}
