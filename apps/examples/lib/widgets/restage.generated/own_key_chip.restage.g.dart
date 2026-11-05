part of '../own_key_chip.dart';

// ignore_for_file: type=lint, unnecessary_cast

const restageIslands$OwnKeyChip__OwnKeyCount_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'OwnKeyChip__OwnKeyCount_0',
              builder: _restageIsland$OwnKeyChip__OwnKeyCount_0)
        ],
        islands: true);

Widget _restageIsland$OwnKeyChip__OwnKeyCount_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'OwnKeyChip__OwnKeyCount_0',
        '`_OwnKeyCount` (lib/widgets/own_key_chip.dart:22:7) needs app code that only `OwnKeyChip__split` provides. Try using `OwnKeyChip__split` to build this screen.',
        context,
        source);

Widget restagePreview$OwnKeyChip__OwnKeyCount_0(
        BuildContext restageContext, DataSource restageSource) =>
    const _OwnKeyCount(key: ValueKey<String>('chip'));

Widget _restageBuild$OwnKeyChip__split(
        BuildContext context, DataSource source) =>
    RestageIslandScope.split(
        context, source, () => _restageWidget$OwnKeyChip(source: source));

/// [widget], placed by the app, as the design places it.
Widget restageSplitApp$OwnKeyChip(OwnKeyChip widget) =>
    _restageWidget$OwnKeyChip.app(widget);

final class _restageWidget$OwnKeyChip extends StatefulWidget {
  const _restageWidget$OwnKeyChip({required DataSource this.source})
      : app = null;
  const _restageWidget$OwnKeyChip.app(OwnKeyChip this.app) : source = null;

  final DataSource? source;
  final OwnKeyChip? app;

  @override
  __restageWidget$OwnKeyChipState createState() =>
      __restageWidget$OwnKeyChipState();
}

final class __restageWidget$OwnKeyChipState
    extends State<_restageWidget$OwnKeyChip> {
  OwnKeyChip get _restageWidget => widget.app ?? OwnKeyChip();

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    // ignore: unused_local_variable
    final _restageSurface = _restageWidget;
    Widget _restageDesign(Widget _restageBuilt) => RestageIslandScope(
        owner: context,
        builders: {
          'OwnKeyChip__OwnKeyCount_0': (_restageContext, _restageSource) =>
              _restageRecording.islandAt('OwnKeyChip__OwnKeyCount_0', [],
                  _restageContext, _restageSource)
        },
        child: RestageBuilderBinding.construct((_restageBindings) {
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
        }));
    return (() => _restageDesign(_restageRecording.island(
        'OwnKeyChip__OwnKeyCount_0',
        const _OwnKeyCount(key: ValueKey<String>('chip')))))();
  }
}

const restageSplit$OwnKeyChip = RestageWidgetLibraryRegistration.constant(
    library: WidgetLibrary.custom('restage_example.widgets'),
    generatedVersion: 3,
    widgets: [
      RestageWidgetFactory(
          name: 'OwnKeyChip__split', builder: _restageBuild$OwnKeyChip__split)
    ]);

/// The hash of the delivered definition this wrapper renders.
const restageSplitDefinition$OwnKeyChip = '8cd90e98ff58f566';
