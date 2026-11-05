part of '../scaled_chip.dart';

// ignore_for_file: type=lint, unnecessary_cast

Widget _restageBuild$ScaledChip__split(
        BuildContext context, DataSource source) =>
    RestageIslandScope.split(
        context, source, () => _restageWidget$ScaledChip(source: source));

/// [widget], placed by the app, as the design places it.
Widget restageSplitApp$ScaledChip(ScaledChip widget) =>
    _restageWidget$ScaledChip.app(widget);

final class _restageWidget$ScaledChip extends StatefulWidget {
  const _restageWidget$ScaledChip({required DataSource this.source})
      : app = null;
  const _restageWidget$ScaledChip.app(ScaledChip this.app) : source = null;

  final DataSource? source;
  final ScaledChip? app;

  @override
  __restageWidget$ScaledChipState createState() =>
      __restageWidget$ScaledChipState();
}

final class __restageWidget$ScaledChipState
    extends State<_restageWidget$ScaledChip> {
  ScaledChip get _restageWidget =>
      widget.app ??
      ScaledChip(
          label: (RestageDecoders.string(
              widget.source!, const <Object>['label'],
              context: context))!);

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording();
    // ignore: unused_local_variable
    final _restageSurface = _restageWidget;
    Widget _restageDesign(Widget _restageBuilt) => RestageNativeValues(
        textScalers: _restageRecording.scalers,
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
                        '_ha864ed9cff': <String, Object?>{
                          "kind": "native",
                          "key": '_ha864ed9cff'
                        }
                      }) ??
                      const SizedBox.shrink();
                })));
    return (() => _restageDesign(Text(
        _restageRecording.value('_h1479a572a1', _restageSurface.label),
        textScaler: _restageRecording.scaler('_ha864ed9cff',
            MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5)))))();
  }
}

const restageSplit$ScaledChip = RestageWidgetLibraryRegistration.constant(
    library: WidgetLibrary.custom('restage_example.widgets'),
    generatedVersion: 3,
    widgets: [
      RestageWidgetFactory(
          name: 'ScaledChip__split', builder: _restageBuild$ScaledChip__split)
    ]);

/// The hash of the delivered definition this wrapper renders.
const restageSplitDefinition$ScaledChip = '8cea1f13e7aca9d6';
