part of '../tally_chip.dart';

// ignore_for_file: type=lint, unnecessary_cast

Widget _restageBuild$TallyChip__split(
        BuildContext context, DataSource source) =>
    RestageIslandScope.split(
        context, source, () => _restageWidget$TallyChip(source: source));

/// [widget], placed by the app, as the design places it.
Widget restageSplitApp$TallyChip(TallyChip widget) =>
    _restageWidget$TallyChip.app(widget);

final class _restageWidget$TallyChip extends StatefulWidget {
  const _restageWidget$TallyChip({required DataSource this.source})
      : app = null;
  const _restageWidget$TallyChip.app(TallyChip this.app) : source = null;

  final DataSource? source;
  final TallyChip? app;

  @override
  __restageWidget$TallyChipState createState() =>
      __restageWidget$TallyChipState();
}

final class __restageWidget$TallyChipState
    extends State<_restageWidget$TallyChip> {
  TallyChip get _restageWidget =>
      widget.app ??
      TallyChip(
          label: (RestageDecoders.string(
              widget.source!, const <Object>['label'],
              context: context))!);

  // ignore: unused_element
  late final int _id = ++tallyChipStates;

  // ignore: unused_element
  var _taps = 0;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording();
    // ignore: unused_local_variable
    final _restageSurface = _restageWidget;
    Widget _restageDesign(Widget _restageBuilt) => RestageNativeValues(
        bindings:
            _restageRecording.bindings((key) => switch (key.split('#').first) {
                  '_h41a85f2863' =>
                    NativeBindingContract(type: '()->void', nullable: false),
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
                        '_h41a85f2863': <String, Object?>{
                          "kind": "nativeBinding",
                          "key": '_h41a85f2863',
                          "type": '()->void',
                          "nullable": false
                        }
                      }) ??
                      const SizedBox.shrink();
                })));
    return (() => _restageDesign(GestureDetector(
          onTap: _restageRecording.native(
              '_h41a85f2863', () => setState(() => _taps++),
              type: '()->void', nullable: false),
          child: Text(_restageRecording.value(
              '_h47e3a74f88', '${_restageSurface.label} #$_id: $_taps')),
        )))();
  }
}

const restageSplit$TallyChip = RestageWidgetLibraryRegistration.constant(
    library: WidgetLibrary.custom('restage_example.widgets'),
    generatedVersion: 3,
    widgets: [
      RestageWidgetFactory(
          name: 'TallyChip__split', builder: _restageBuild$TallyChip__split)
    ]);

/// The hash of the delivered definition this wrapper renders.
const restageSplitDefinition$TallyChip = '3939dbfea2b0c525';
