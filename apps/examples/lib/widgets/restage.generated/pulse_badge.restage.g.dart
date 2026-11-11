part of '../pulse_badge.dart';

// ignore_for_file: type=lint, unnecessary_cast

Widget _restageBuild$PulseBadge__split(
        BuildContext context, DataSource source) =>
    RestageIslandScope.split(
        context, source, () => _restageWidget$PulseBadge(source: source));

/// [widget], placed by the app, as the design places it.
Widget restageSplitApp$PulseBadge(PulseBadge widget) =>
    _restageWidget$PulseBadge.app(widget);

final class _restageWidget$PulseBadge extends StatefulWidget {
  const _restageWidget$PulseBadge({required DataSource this.source})
      : app = null;
  const _restageWidget$PulseBadge.app(PulseBadge this.app) : source = null;

  final DataSource? source;
  final PulseBadge? app;

  @override
  __restageWidget$PulseBadgeState createState() =>
      __restageWidget$PulseBadgeState();
}

final class __restageWidget$PulseBadgeState
    extends State<_restageWidget$PulseBadge>
    with SingleTickerProviderStateMixin {
  PulseBadge get _restageWidget =>
      widget.app ??
      PulseBadge(
          label: (RestageDecoders.string(
              widget.source!, const <Object>['label'], context: context))!,
          count: (RestageValueBinding.read<int>(
              widget.source!, const <Object>['count'], context))!);

  // ignore: unused_element
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  // ignore: unused_element
  @override
  void initState() {
    super.initState();
    // A one-shot imperative scale entrance, driven by the controller.
    _controller.forward();
  }

  // ignore: unused_element
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    // ignore: unused_local_variable
    final _restageSurface = _restageWidget;
    Widget _restageDesign(Widget _restageBuilt) =>
        RestageBuilderBinding.construct((_restageBindings) {
          final _restageSource = widget.source;
          if (_restageSource == null) return _restageBuilt;
          final _restageBody = RestageBuilderBinding.optional(
              _restageSource, const <Object>['restageWidget'],
              context: context);
          if (_restageBody == null) return _restageBuilt;
          _restageBindings.add(_restageBody);
          return _restageBody.buildNullable(context, const {},
                  recorded: _restageRecording.values) ??
              const SizedBox.shrink();
        });
    return (() {
      final scheme = Theme.of(context).colorScheme;
      return ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(_controller),
        child: _restageDesign(Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.primary,
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
        )),
      );
    })();
  }
}

const restageSplit$PulseBadge = RestageWidgetLibraryRegistration.constant(
    library: WidgetLibrary.custom('restage_example.widgets'),
    generatedVersion: 3,
    widgets: [
      RestageWidgetFactory(
          name: 'PulseBadge__split', builder: _restageBuild$PulseBadge__split)
    ]);

/// The hash of the delivered definition this wrapper renders.
const restageSplitDefinition$PulseBadge = 'd9f61993591831b2';
