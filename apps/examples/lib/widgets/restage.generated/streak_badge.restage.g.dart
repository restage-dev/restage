part of '../streak_badge.dart';

// ignore_for_file: type=lint, unnecessary_cast

Widget _restageBuild$StreakBadge__split(
        BuildContext context, DataSource source) =>
    RestageIslandScope.split(
        context, source, () => _restageWidget$StreakBadge(source: source));

/// [widget], placed by the app, as the design places it.
Widget restageSplitApp$StreakBadge(StreakBadge widget) =>
    _restageWidget$StreakBadge.app(widget);

final class _restageWidget$StreakBadge extends StatefulWidget {
  const _restageWidget$StreakBadge({required DataSource this.source})
      : app = null;
  const _restageWidget$StreakBadge.app(StreakBadge this.app) : source = null;

  final DataSource? source;
  final StreakBadge? app;

  @override
  __restageWidget$StreakBadgeState createState() =>
      __restageWidget$StreakBadgeState();
}

final class __restageWidget$StreakBadgeState
    extends State<_restageWidget$StreakBadge> {
  StreakBadge get _restageWidget =>
      widget.app ??
      StreakBadge(
          label: (RestageDecoders.string(
              widget.source!, const <Object>['label'], context: context))!,
          count: (RestageValueBinding.read<int>(
              widget.source!, const <Object>['count'], context))!);

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    // ignore: unused_local_variable
    final _restageSurface = _restageWidget;
    Widget _restageDesign(Widget _restageBuilt) => RestageNativeValues(
        bindings:
            _restageRecording.bindings((key) => switch (key.split('#').first) {
                  '_hfb1540f856' => NativeBindingContract(
                      type: 'flutter.Color', nullable: false),
                  _ => throw StateError(key)
                }),
        child: Builder(
            builder: (context) =>
                RestageBuilderBinding.construct((_restageBindings) {
                  final _restageSource = widget.source;
                  if (_restageSource == null) return _restageBuilt;
                  final _restageBody = RestageBuilderBinding.optional(
                      _restageSource, const <Object>['restageWidget'],
                      context: context);
                  if (_restageBody == null) return _restageBuilt;
                  _restageBindings.add(_restageBody);
                  return _restageBody
                          .buildNullable(context, const {}, recorded: {
                        ..._restageRecording.values,
                        '_hfb1540f856': <String, Object?>{
                          "kind": "nativeBinding",
                          "key": '_hfb1540f856',
                          "type": 'flutter.Color',
                          "nullable": false
                        }
                      }) ??
                      const SizedBox.shrink();
                })));
    return (() {
      final scheme = Theme.of(context).colorScheme;
      // A runtime computation, so this widget renders from app code.
      final intensity = _restageSurface.count.clamp(0, 10) / 10.0;
      return _restageDesign(Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _restageRecording.native(
              '_hfb1540f856', scheme.primary.withValues(alpha: intensity),
              type: 'flutter.Color', nullable: false),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          _restageRecording.value('_h06a44c7422',
              '${_restageSurface.label}: ${_restageSurface.count}'),
          style: TextStyle(
            color: scheme.onPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ));
    })();
  }
}

const restageSplit$StreakBadge = RestageWidgetLibraryRegistration.constant(
    library: WidgetLibrary.custom('restage_example.widgets'),
    generatedVersion: 3,
    widgets: [
      RestageWidgetFactory(
          name: 'StreakBadge__split', builder: _restageBuild$StreakBadge__split)
    ]);

/// The hash of the delivered definition this wrapper renders.
const restageSplitDefinition$StreakBadge = 'e114eba979cbaa19';
