part of '../app_widgets.dart';

// ignore_for_file: type=lint, unnecessary_cast

final _appWidgetsCountFramedTwicePlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_count_framed_twice',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_count_framed_twice',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'islands': <String, Object?>{
      'restage_example.islands:app__widgets__count__framed__twice__framedTwice0_framed0_AppCount_0':
          'w62183521',
      'restage_example.islands:app__widgets__count__framed__twice__framedTwice0_framed1_AppCount_0':
          'w150362223'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Padding': buildPadding,
        'Row': buildRow,
        'Text': buildText,
      },
    ),
    libraries: [
      restageIslands$app__widgets__count__framed__twice__framedTwice0_framed0_AppCount_0
    ],
  ),
  surfaceWidget: 'AppWidgetsCountFramedTwiceSurface',
);

final appWidgetsCountFramedTwicePlacementDefinition =
    () => _appWidgetsCountFramedTwicePlacementDefinitionValue;

const restageIslands$app__widgets__count__framed__twice__framedTwice0_framed0_AppCount_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name:
                  'app__widgets__count__framed__twice__framedTwice0_framed0_AppCount_0',
              builder:
                  _restageIsland$app__widgets__count__framed__twice__framedTwice0_framed0_AppCount_0),
          RestageWidgetFactory(
              name:
                  'app__widgets__count__framed__twice__framedTwice0_framed1_AppCount_0',
              builder:
                  _restageIsland$app__widgets__count__framed__twice__framedTwice0_framed1_AppCount_0)
        ],
        islands: true);

Widget _restageIsland$app__widgets__count__framed__twice__framedTwice0_framed0_AppCount_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__count__framed__twice__framedTwice0_framed0_AppCount_0',
        '`AppCount` (lib/surfaces/app_widgets.dart:333:60) needs app code that only `AppWidgetsCountFramedTwiceSurface` provides. Try using `AppWidgetsCountFramedTwiceSurface` to build this screen.',
        context,
        source);

Widget
    restagePreview$app__widgets__count__framed__twice__framedTwice0_framed0_AppCount_0(
            BuildContext restageContext, DataSource restageSource) =>
        AppCount();

Widget _restageIsland$app__widgets__count__framed__twice__framedTwice0_framed1_AppCount_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__count__framed__twice__framedTwice0_framed1_AppCount_0',
        '`AppCount` (lib/surfaces/app_widgets.dart:333:60) needs app code that only `AppWidgetsCountFramedTwiceSurface` provides. Try using `AppWidgetsCountFramedTwiceSurface` to build this screen.',
        context,
        source);

Widget
    restagePreview$app__widgets__count__framed__twice__framedTwice0_framed1_AppCount_0(
            BuildContext restageContext, DataSource restageSource) =>
        AppCount();

final class AppWidgetsCountFramedTwiceSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsCountFramedTwiceSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsCountFramedTwiceSurface] for the default placement; no name is needed.
  const AppWidgetsCountFramedTwiceSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'Padding': buildPadding,
            'Row': buildRow,
            'Text': buildText,
          },
        ),
        libraries: [
          restageIslands$app__widgets__count__framed__twice__framedTwice0_framed0_AppCount_0
        ],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_count_framed_twice',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsCountFramedTwicePlacementDefinition,
          name: _restagePlacementName,
        ),
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {
            'app__widgets__count__framed__twice__framedTwice0_framed0_AppCount_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__count__framed__twice__framedTwice0_framed0_AppCount_0',
                    [],
                    _restageContext,
                    _restageSource),
            'app__widgets__count__framed__twice__framedTwice0_framed1_AppCount_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__count__framed__twice__framedTwice0_framed1_AppCount_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          const Text('framed'),
          ((Widget framed) => Row(children: [
                    _restageRecording.spot(0, framed),
                    _restageRecording.spot(1, framed)
                  ]))(
              Padding(
                  padding: EdgeInsets.zero,
                  child: _restageRecording.island(
                      'app__widgets__count__framed__twice__framedTwice0_framed0_AppCount_0',
                      _restageRecording.island('app__widgets__count__framed__twice__framedTwice0_framed1_AppCount_0', AppCount(), spots: [1]),
                      spots: [0]))),
        ])))();
  }
}

final _appWidgetsCountRowsPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_count_rows',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_count_rows',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        '_h936348a2cc': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_hdde93e85c5': <String, Object?>{'kind': 'int'}
            }
          }
        },
        'names': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{'kind': 'string'}
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'islands': <String, Object?>{
      'restage_example.islands:app__widgets__count__rows_AppCount_0':
          'w104482111'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Padding': buildPadding,
        'Row': buildRow,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$app__widgets__count__rows_AppCount_0],
  ),
  surfaceWidget: 'AppWidgetsCountRowsSurface',
);

final appWidgetsCountRowsPlacementDefinition =
    () => _appWidgetsCountRowsPlacementDefinitionValue;

const restageIslands$app__widgets__count__rows_AppCount_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'app__widgets__count__rows_AppCount_0',
              builder: _restageIsland$app__widgets__count__rows_AppCount_0)
        ],
        islands: true);

Widget _restageIsland$app__widgets__count__rows_AppCount_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__count__rows_AppCount_0',
        '`AppCount` (lib/surfaces/app_widgets.dart:351:50) needs app code that only `AppWidgetsCountRowsSurface` provides. Try using `AppWidgetsCountRowsSurface` to build this screen.',
        context,
        source);

Widget restagePreview$app__widgets__count__rows_AppCount_0(
        BuildContext restageContext, DataSource restageSource) =>
    AppCount();

final class AppWidgetsCountRowsSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsCountRowsSurface({
    super.key,
    required List<String> names,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = names,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsCountRowsSurface] for the default placement; no name is needed.
  const AppWidgetsCountRowsSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    required List<String> names,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = names,
        _restagePlacementName = restagePlacementId;

  final List<String> _restageStored1;
  List<String> get _restageArgument1 => _restageStored1;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'Padding': buildPadding,
            'Row': buildRow,
            'Text': buildText,
          },
        ),
        libraries: [restageIslands$app__widgets__count__rows_AppCount_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_count_rows',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsCountRowsPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'names': _restageArgument1,
        },
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {
            'app__widgets__count__rows_AppCount_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__count__rows_AppCount_0',
                    [
                      _restageSource.v<int>(const <Object>['restageItems', 0])!
                    ],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() {
      final row = Row(children: [
        for (final name in _restageRecording
            .items('_h936348a2cc', _restageArgument1, null, ['_hdde93e85c5']))
          Padding(
              padding: EdgeInsets.zero,
              child: _restageRecording.island(
                  'app__widgets__count__rows_AppCount_0',
                  AppCount(key: ValueKey(name)),
                  items: '_h936348a2cc')),
      ]);
      return _restageDesign(Column(children: [const Text('rows'), row]));
    })();
  }
}

final _appWidgetsCountSpreadPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_count_spread',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_count_spread',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'islands': <String, Object?>{
      'restage_example.islands:app__widgets__count__spread_counts0_AppCount_0':
          'w238718238',
      'restage_example.islands:app__widgets__count__spread_counts1_AppCount_0':
          'w168575834'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$app__widgets__count__spread_counts0_AppCount_0],
  ),
  surfaceWidget: 'AppWidgetsCountSpreadSurface',
);

final appWidgetsCountSpreadPlacementDefinition =
    () => _appWidgetsCountSpreadPlacementDefinitionValue;

const restageIslands$app__widgets__count__spread_counts0_AppCount_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'app__widgets__count__spread_counts0_AppCount_0',
              builder:
                  _restageIsland$app__widgets__count__spread_counts0_AppCount_0),
          RestageWidgetFactory(
              name: 'app__widgets__count__spread_counts1_AppCount_0',
              builder:
                  _restageIsland$app__widgets__count__spread_counts1_AppCount_0)
        ],
        islands: true);

Widget _restageIsland$app__widgets__count__spread_counts0_AppCount_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__count__spread_counts0_AppCount_0',
        '`AppCount` (lib/surfaces/app_widgets.dart:315:29) needs app code that only `AppWidgetsCountSpreadSurface` provides. Try using `AppWidgetsCountSpreadSurface` to build this screen.',
        context,
        source);

Widget restagePreview$app__widgets__count__spread_counts0_AppCount_0(
        BuildContext restageContext, DataSource restageSource) =>
    const AppCount();

Widget _restageIsland$app__widgets__count__spread_counts1_AppCount_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__count__spread_counts1_AppCount_0',
        '`AppCount` (lib/surfaces/app_widgets.dart:315:29) needs app code that only `AppWidgetsCountSpreadSurface` provides. Try using `AppWidgetsCountSpreadSurface` to build this screen.',
        context,
        source);

Widget restagePreview$app__widgets__count__spread_counts1_AppCount_0(
        BuildContext restageContext, DataSource restageSource) =>
    const AppCount();

final class AppWidgetsCountSpreadSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsCountSpreadSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsCountSpreadSurface] for the default placement; no name is needed.
  const AppWidgetsCountSpreadSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'Text': buildText,
          },
        ),
        libraries: [
          restageIslands$app__widgets__count__spread_counts0_AppCount_0
        ],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_count_spread',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsCountSpreadPlacementDefinition,
          name: _restagePlacementName,
        ),
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {
            'app__widgets__count__spread_counts0_AppCount_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__count__spread_counts0_AppCount_0',
                    [],
                    _restageContext,
                    _restageSource),
            'app__widgets__count__spread_counts1_AppCount_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__count__spread_counts1_AppCount_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() {
      final counts = <Widget>[
        _restageRecording.island(
            'app__widgets__count__spread_counts0_AppCount_0',
            _restageRecording.island(
                'app__widgets__count__spread_counts1_AppCount_0',
                const AppCount(),
                spots: [1]),
            spots: [0])
      ];
      return _restageDesign(Column(children: [
        ..._restageRecording.spotEach(0, counts),
        const Text('between'),
        ..._restageRecording.spotEach(1, counts)
      ]));
    })();
  }
}

final _appWidgetsCountTwicePlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_count_twice',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_count_twice',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'islands': <String, Object?>{
      'restage_example.islands:app__widgets__count__twice_count0_AppCount_0':
          'w85825176',
      'restage_example.islands:app__widgets__count__twice_count1_AppCount_0':
          'w63560180'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$app__widgets__count__twice_count0_AppCount_0],
  ),
  surfaceWidget: 'AppWidgetsCountTwiceSurface',
);

final appWidgetsCountTwicePlacementDefinition =
    () => _appWidgetsCountTwicePlacementDefinitionValue;

const restageIslands$app__widgets__count__twice_count0_AppCount_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'app__widgets__count__twice_count0_AppCount_0',
              builder:
                  _restageIsland$app__widgets__count__twice_count0_AppCount_0),
          RestageWidgetFactory(
              name: 'app__widgets__count__twice_count1_AppCount_0',
              builder:
                  _restageIsland$app__widgets__count__twice_count1_AppCount_0)
        ],
        islands: true);

Widget _restageIsland$app__widgets__count__twice_count0_AppCount_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__count__twice_count0_AppCount_0',
        '`AppCount` (lib/surfaces/app_widgets.dart:302:19) needs app code that only `AppWidgetsCountTwiceSurface` provides. Try using `AppWidgetsCountTwiceSurface` to build this screen.',
        context,
        source);

Widget restagePreview$app__widgets__count__twice_count0_AppCount_0(
        BuildContext restageContext, DataSource restageSource) =>
    AppCount();

Widget _restageIsland$app__widgets__count__twice_count1_AppCount_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__count__twice_count1_AppCount_0',
        '`AppCount` (lib/surfaces/app_widgets.dart:302:19) needs app code that only `AppWidgetsCountTwiceSurface` provides. Try using `AppWidgetsCountTwiceSurface` to build this screen.',
        context,
        source);

Widget restagePreview$app__widgets__count__twice_count1_AppCount_0(
        BuildContext restageContext, DataSource restageSource) =>
    AppCount();

final class AppWidgetsCountTwiceSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsCountTwiceSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsCountTwiceSurface] for the default placement; no name is needed.
  const AppWidgetsCountTwiceSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'Text': buildText,
          },
        ),
        libraries: [
          restageIslands$app__widgets__count__twice_count0_AppCount_0
        ],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_count_twice',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsCountTwicePlacementDefinition,
          name: _restagePlacementName,
        ),
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {
            'app__widgets__count__twice_count0_AppCount_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__count__twice_count0_AppCount_0',
                    [],
                    _restageContext,
                    _restageSource),
            'app__widgets__count__twice_count1_AppCount_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__count__twice_count1_AppCount_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() {
      // ignore: prefer_const_declarations
      final count = AppCount();
      return _restageDesign(Column(children: [
        _restageRecording.island(
            'app__widgets__count__twice_count0_AppCount_0', count),
        const Text('between'),
        _restageRecording.island(
            'app__widgets__count__twice_count1_AppCount_0', count)
      ]));
    })();
  }
}

final _appWidgetsCountedPairPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_counted_pair',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_counted_pair',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'islands': <String, Object?>{
      'restage_example.islands:app__widgets__counted__pair__Counted_0':
          'w239393858',
      'restage_example.islands:app__widgets__counted__pair__Counted_1':
          'w240822543'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
      },
    ),
    libraries: [restageIslands$app__widgets__counted__pair__Counted_0],
  ),
  surfaceWidget: 'AppWidgetsCountedPairSurface',
);

final appWidgetsCountedPairPlacementDefinition =
    () => _appWidgetsCountedPairPlacementDefinitionValue;

const restageIslands$app__widgets__counted__pair__Counted_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'app__widgets__counted__pair__Counted_0',
              builder: _restageIsland$app__widgets__counted__pair__Counted_0),
          RestageWidgetFactory(
              name: 'app__widgets__counted__pair__Counted_1',
              builder: _restageIsland$app__widgets__counted__pair__Counted_1)
        ],
        islands: true);

Widget _restageIsland$app__widgets__counted__pair__Counted_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__counted__pair__Counted_0',
        '`_Counted` (lib/surfaces/app_widgets.dart:195:31) needs app code that only `AppWidgetsCountedPairSurface` provides. Try using `AppWidgetsCountedPairSurface` to build this screen.',
        context,
        source);

Widget restagePreview$app__widgets__counted__pair__Counted_0(
        BuildContext restageContext, DataSource restageSource) =>
    _Counted();

Widget _restageIsland$app__widgets__counted__pair__Counted_1(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__counted__pair__Counted_1',
        '`_Counted` (lib/surfaces/app_widgets.dart:195:43) needs app code that only `AppWidgetsCountedPairSurface` provides. Try using `AppWidgetsCountedPairSurface` to build this screen.',
        context,
        source);

Widget restagePreview$app__widgets__counted__pair__Counted_1(
        BuildContext restageContext, DataSource restageSource) =>
    _Counted();

final class AppWidgetsCountedPairSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsCountedPairSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsCountedPairSurface] for the default placement; no name is needed.
  const AppWidgetsCountedPairSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
          },
        ),
        libraries: [restageIslands$app__widgets__counted__pair__Counted_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_counted_pair',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsCountedPairPlacementDefinition,
          name: _restagePlacementName,
        ),
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {
            'app__widgets__counted__pair__Counted_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__counted__pair__Counted_0',
                    [],
                    _restageContext,
                    _restageSource),
            'app__widgets__counted__pair__Counted_1':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__counted__pair__Counted_1',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          _restageRecording.island(
              'app__widgets__counted__pair__Counted_0', _Counted()),
          _restageRecording.island(
              'app__widgets__counted__pair__Counted_1', _Counted())
        ])))();
  }
}

final _appWidgetsDirectTapPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_direct_tap',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_direct_tap',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        '_h20557f6d58': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'installed.call',
            'nullable': false,
            'call': <String, Object?>{
              'inputs': <Object?>[
                <String, Object?>{
                  'kind': 'native',
                  'nativeType': 'dart:core#String'
                }
              ],
              'captures': <String, Object?>{},
              'result': <String, Object?>{
                'kind': 'native',
                'nativeType': '()->void'
              },
              'implementation':
                  '20557f6d5810939635bdb1d7f854ccfcd9ff8918ebeb2cc71e57219529b1e55c'
            }
          }
        },
        '_h45c8b52c97': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'installed.call',
            'nullable': false,
            'call': <String, Object?>{
              'inputs': <Object?>[
                <String, Object?>{
                  'kind': 'native',
                  'nativeType': 'dart:core#String'
                }
              ],
              'captures': <String, Object?>{},
              'result': <String, Object?>{
                'kind': 'native',
                'nativeType': '()->void'
              },
              'implementation':
                  '45c8b52c97b4cc189d9a6fb79790e8ceaaa9fef99004ff25757692e884bb0ec3'
            }
          }
        },
        '_h470877215f': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'installed.call',
            'nullable': false,
            'call': <String, Object?>{
              'inputs': <Object?>[
                <String, Object?>{
                  'kind': 'native',
                  'nativeType': 'dart:core#String'
                }
              ],
              'captures': <String, Object?>{},
              'result': <String, Object?>{
                'kind': 'native',
                'nativeType': '()->void'
              },
              'implementation':
                  '470877215f3a0df1f5a0bf875ffae04add9c07b53041329f88192b151af71fb8'
            }
          }
        },
        '_ha4e130695a': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'dart:core#String',
            'nullable': false
          },
          'label': 'title'
        },
        'title': <String, Object?>{'kind': 'string'}
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'GestureDetector': buildGestureDetector,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'AppWidgetsDirectTapSurface',
);

final appWidgetsDirectTapPlacementDefinition =
    () => _appWidgetsDirectTapPlacementDefinitionValue;

final _restageAppWidgetsDirectTapSurface_h20557f6d58Contract =
    NativeBindingContract.fromJson(<String, Object?>{
  "type": "installed.call",
  "nullable": false,
  "call": <String, Object?>{
    "inputs": <Object?>[
      <String, Object?>{"kind": "native", "nativeType": "dart:core#String"}
    ],
    "captures": <String, Object?>{},
    "result": <String, Object?>{"kind": "native", "nativeType": "()->void"},
    "implementation":
        "20557f6d5810939635bdb1d7f854ccfcd9ff8918ebeb2cc71e57219529b1e55c"
  }
});
final _restageAppWidgetsDirectTapSurface_h45c8b52c97Contract =
    NativeBindingContract.fromJson(<String, Object?>{
  "type": "installed.call",
  "nullable": false,
  "call": <String, Object?>{
    "inputs": <Object?>[
      <String, Object?>{"kind": "native", "nativeType": "dart:core#String"}
    ],
    "captures": <String, Object?>{},
    "result": <String, Object?>{"kind": "native", "nativeType": "()->void"},
    "implementation":
        "45c8b52c97b4cc189d9a6fb79790e8ceaaa9fef99004ff25757692e884bb0ec3"
  }
});
final _restageAppWidgetsDirectTapSurface_h470877215fContract =
    NativeBindingContract.fromJson(<String, Object?>{
  "type": "installed.call",
  "nullable": false,
  "call": <String, Object?>{
    "inputs": <Object?>[
      <String, Object?>{"kind": "native", "nativeType": "dart:core#String"}
    ],
    "captures": <String, Object?>{},
    "result": <String, Object?>{"kind": "native", "nativeType": "()->void"},
    "implementation":
        "470877215f3a0df1f5a0bf875ffae04add9c07b53041329f88192b151af71fb8"
  }
});
final NativeCallAdapter _restageAppWidgetsDirectTapSurface_h20557f6d58Native =
    NativeCallAdapter(_restageAppWidgetsDirectTapSurface_h20557f6d58Contract,
        (_restageInputs, _restageCells) {
  T _restageAs<T>(Object? value) => value as T;
  final String _restageInput0 =
      _restageAs<String>((_restageInputs[0] as ValueNative).value);
  final void Function() _restageResult =
      () => appWidgetCalls.add('braced ${_restageInput0}');
  return NativeBinding<void Function()>(
      contract: NativeBindingContract(type: "()->void", nullable: false),
      value: _restageResult);
});
final NativeCallAdapter _restageAppWidgetsDirectTapSurface_h45c8b52c97Native =
    NativeCallAdapter(_restageAppWidgetsDirectTapSurface_h45c8b52c97Contract,
        (_restageInputs, _restageCells) {
  T _restageAs<T>(Object? value) => value as T;
  final String _restageInput0 =
      _restageAs<String>((_restageInputs[0] as ValueNative).value);
  final void Function() _restageResult =
      () => appWidgetCalls.add('tap ${_restageInput0}');
  return NativeBinding<void Function()>(
      contract: NativeBindingContract(type: "()->void", nullable: false),
      value: _restageResult);
});
final NativeCallAdapter _restageAppWidgetsDirectTapSurface_h470877215fNative =
    NativeCallAdapter(_restageAppWidgetsDirectTapSurface_h470877215fContract,
        (_restageInputs, _restageCells) {
  T _restageAs<T>(Object? value) => value as T;
  final String _restageInput0 =
      _restageAs<String>((_restageInputs[0] as ValueNative).value);
  final void Function() _restageResult =
      () => appWidgetCalls.add('${_restageInput0}!');
  return NativeBinding<void Function()>(
      contract: NativeBindingContract(type: "()->void", nullable: false),
      value: _restageResult);
});

final class AppWidgetsDirectTapSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsDirectTapSurface({
    super.key,
    required String title,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsDirectTapSurface] for the default placement; no name is needed.
  const AppWidgetsDirectTapSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    required String title,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restagePlacementName = restagePlacementId;

  final String _restageStored1;
  String get _restageArgument1 => _restageStored1;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'GestureDetector': buildGestureDetector,
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) =>
                switch (key.split('#').first) { _ => throw StateError(key) },
            {
              '_h20557f6d58': NativeBinding(
                  contract:
                      _restageAppWidgetsDirectTapSurface_h20557f6d58Contract,
                  value: _restageAppWidgetsDirectTapSurface_h20557f6d58Native),
              '_h45c8b52c97': NativeBinding(
                  contract:
                      _restageAppWidgetsDirectTapSurface_h45c8b52c97Contract,
                  value: _restageAppWidgetsDirectTapSurface_h45c8b52c97Native),
              '_h470877215f': NativeBinding(
                  contract:
                      _restageAppWidgetsDirectTapSurface_h470877215fContract,
                  value: _restageAppWidgetsDirectTapSurface_h470877215fNative),
              '_ha4e130695a': NativeBinding(
                  contract: NativeBindingContract(
                      type: 'dart:core#String', nullable: false),
                  value: _restageArgument1),
            }),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h20557f6d58':
                    '() => appWidgetCalls.add(\'braced \${_restageInput0}\')',
                '_h45c8b52c97':
                    '() => appWidgetCalls.add(\'tap \${_restageInput0}\')',
                '_h470877215f':
                    '() => appWidgetCalls.add(\'\${_restageInput0}!\')',
                '_ha4e130695a': 'title',
              },
        child: RestagePaywall(
          id: 'app_widgets_direct_tap',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: appWidgetsDirectTapPlacementDefinition,
            name: _restagePlacementName,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            'title': _restageArgument1,
            '_h20557f6d58': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h20557f6d58',
              "type": 'installed.call',
              "nullable": false
            },
            '_h45c8b52c97': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h45c8b52c97',
              "type": 'installed.call',
              "nullable": false
            },
            '_h470877215f': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h470877215f',
              "type": 'installed.call',
              "nullable": false
            },
            '_ha4e130695a': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_ha4e130695a',
              "type": 'dart:core#String',
              "nullable": false
            },
          },
          fallbackBuilder: (_) => _restageBuilt,
          onEvent: onEvent,
          resolver: resolver,
          errorBuilder: errorBuilder,
          loadingBuilder: loadingBuilder,
        ),
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          GestureDetector(
            onTap: () => appWidgetCalls.add('tap ${_restageArgument1}'),
            child: const Text('Go'),
          ),
          GestureDetector(
            onTap: () => appWidgetCalls.add('braced ${_restageArgument1}'),
            child: const Text('Braced'),
          ),
          GestureDetector(
            onTap: () => appWidgetCalls.add('${_restageArgument1}!'),
            child: const Text('Bang'),
          ),
        ])))();
  }
}

final _appWidgetsDirectTogglePlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_direct_toggle',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_direct_toggle',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        '_hfb7369e2d4': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': '(dart:core#bool)->void',
            'nullable': false
          },
          'label': '(on) => appWidgetCalls.add(\'switch \$title \$on\')'
        },
        'title': <String, Object?>{'kind': 'string'}
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
      material: {
        'Switch': buildSwitch,
      },
    ),
  ),
  surfaceWidget: 'AppWidgetsDirectToggleSurface',
);

final appWidgetsDirectTogglePlacementDefinition =
    () => _appWidgetsDirectTogglePlacementDefinitionValue;

final class AppWidgetsDirectToggleSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsDirectToggleSurface({
    super.key,
    required String title,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsDirectToggleSurface] for the default placement; no name is needed.
  const AppWidgetsDirectToggleSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    required String title,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restagePlacementName = restagePlacementId;

  final String _restageStored1;
  String get _restageArgument1 => _restageStored1;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'Text': buildText,
          },
          material: {
            'Switch': buildSwitch,
          },
        ),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) => switch (key.split('#').first) {
                  '_hfb7369e2d4' => NativeBindingContract(
                      type: '(dart:core#bool)->void', nullable: false),
                  _ => throw StateError(key)
                },
            {}),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_hfb7369e2d4':
                    '(on) => appWidgetCalls.add(\'switch \$title \$on\')',
              },
        child: RestagePaywall(
          id: 'app_widgets_direct_toggle',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: appWidgetsDirectTogglePlacementDefinition,
            name: _restagePlacementName,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            'title': _restageArgument1,
            '_hfb7369e2d4': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hfb7369e2d4',
              "type": '(dart:core#bool)->void',
              "nullable": false
            },
          },
          fallbackBuilder: (_) => _restageBuilt,
          onEvent: onEvent,
          resolver: resolver,
          errorBuilder: errorBuilder,
          loadingBuilder: loadingBuilder,
        ),
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          Text(_restageArgument1),
          Switch(
            value: false,
            onChanged: _restageRecording.native('_hfb7369e2d4',
                (on) => appWidgetCalls.add('switch ${_restageArgument1} $on'),
                type: '(dart:core#bool)->void', nullable: false),
          ),
        ])))();
  }
}

final _appWidgetsFactoryTallyPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_factory_tally',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_factory_tally',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
      },
    ),
  ),
  surfaceWidget: 'AppWidgetsFactoryTallySurface',
);

final appWidgetsFactoryTallyPlacementDefinition =
    () => _appWidgetsFactoryTallyPlacementDefinitionValue;

final class AppWidgetsFactoryTallySurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsFactoryTallySurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsFactoryTallySurface] for the default placement; no name is needed.
  const AppWidgetsFactoryTallySurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_factory_tally',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsFactoryTallyPlacementDefinition,
          name: _restagePlacementName,
        ),
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          _restageRecording.island(
              'app__widgets__factory__tally_FactoryTallyChip_0',
              FactoryTallyChip(label: 'A'),
              place: RestageRecording.itself),
          _restageRecording.island(
              'app__widgets__factory__tally_FactoryTallyChip_1',
              FactoryTallyChip(label: 'B'),
              place: RestageRecording.itself),
        ])))();
  }
}

final _appWidgetsForwardedPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_forwarded',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_forwarded',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        '_h4fc4a381bb': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'flutter.Key',
            'nullable': false
          },
          'label': 'ValueKey(\'tag \$title\')'
        },
        '_h6518239966': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': '(dart:core#bool)->void',
            'nullable': false
          },
          'label': '(on) => appWidgetCalls.add(\'toggle \$title \$on\')'
        },
        'title': <String, Object?>{'kind': 'string'}
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
      material: {
        'Switch': buildSwitch,
      },
    ),
  ),
  surfaceWidget: 'AppWidgetsForwardedSurface',
);

final appWidgetsForwardedPlacementDefinition =
    () => _appWidgetsForwardedPlacementDefinitionValue;

final class AppWidgetsForwardedSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsForwardedSurface({
    super.key,
    required String title,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsForwardedSurface] for the default placement; no name is needed.
  const AppWidgetsForwardedSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    required String title,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restagePlacementName = restagePlacementId;

  final String _restageStored1;
  String get _restageArgument1 => _restageStored1;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'Text': buildText,
          },
          material: {
            'Switch': buildSwitch,
          },
        ),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) => switch (key.split('#').first) {
                  '_h4fc4a381bb' =>
                    NativeBindingContract(type: 'flutter.Key', nullable: false),
                  '_h6518239966' => NativeBindingContract(
                      type: '(dart:core#bool)->void', nullable: false),
                  _ => throw StateError(key)
                },
            {}),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h4fc4a381bb': 'ValueKey(\'tag \$title\')',
                '_h6518239966':
                    '(on) => appWidgetCalls.add(\'toggle \$title \$on\')',
              },
        child: RestagePaywall(
          id: 'app_widgets_forwarded',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: appWidgetsForwardedPlacementDefinition,
            name: _restagePlacementName,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            'title': _restageArgument1,
            '_h4fc4a381bb': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h4fc4a381bb',
              "type": 'flutter.Key',
              "nullable": false
            },
            '_h6518239966': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h6518239966',
              "type": '(dart:core#bool)->void',
              "nullable": false
            },
          },
          fallbackBuilder: (_) => _restageBuilt,
          onEvent: onEvent,
          resolver: resolver,
          errorBuilder: errorBuilder,
          loadingBuilder: loadingBuilder,
        ),
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          AppToggle(
              onChanged: _restageRecording.native('_h6518239966',
                  (on) => appWidgetCalls.add('toggle ${_restageArgument1} $on'),
                  type: '(dart:core#bool)->void', nullable: false)),
          AppKeyed(
              tag: _restageRecording.native(
                  '_h4fc4a381bb', ValueKey('tag ${_restageArgument1}'),
                  type: 'flutter.Key', nullable: false),
              label: 'Keyed'),
        ])))();
  }
}

final _appWidgetsGetterArgPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_getter_arg',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_getter_arg',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        'title': <String, Object?>{'kind': 'string'}
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'islands': <String, Object?>{
      'restage_example.islands:app__widgets__getter__arg__Inset_0': 'w6728181'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$app__widgets__getter__arg__Inset_0],
  ),
  surfaceWidget: 'AppWidgetsGetterArgSurface',
);

final appWidgetsGetterArgPlacementDefinition =
    () => _appWidgetsGetterArgPlacementDefinitionValue;

const restageIslands$app__widgets__getter__arg__Inset_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'app__widgets__getter__arg__Inset_0',
              builder: _restageIsland$app__widgets__getter__arg__Inset_0)
        ],
        islands: true);

Widget _restageIsland$app__widgets__getter__arg__Inset_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__getter__arg__Inset_0',
        '`_Inset` (lib/surfaces/app_widgets.dart:509:9) needs app code that only `AppWidgetsGetterArgSurface` provides. Try using `AppWidgetsGetterArgSurface` to build this screen.',
        context,
        source);

Widget restagePreview$app__widgets__getter__arg__Inset_0(
        BuildContext restageContext, DataSource restageSource) =>
    _Inset(
        inset: appWidgetMeter.inset,
        child: restageSource.child(const <Object>['child']));

final class AppWidgetsGetterArgSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsGetterArgSurface({
    super.key,
    required String title,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsGetterArgSurface] for the default placement; no name is needed.
  const AppWidgetsGetterArgSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    required String title,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restagePlacementName = restagePlacementId;

  final String _restageStored1;
  String get _restageArgument1 => _restageStored1;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'Text': buildText,
          },
        ),
        libraries: [restageIslands$app__widgets__getter__arg__Inset_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_getter_arg',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsGetterArgPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'title': _restageArgument1,
        },
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {
            'app__widgets__getter__arg__Inset_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__getter__arg__Inset_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          _restageRecording.island(
              'app__widgets__getter__arg__Inset_0',
              restageOnce<(int,), Widget>(
                  (appWidgetMeter.inset,),
                  (_restageArgs) => _restageRecording.built(
                      _Inset(
                          inset: _restageArgs.$1,
                          child: Text(_restageArgument1)),
                      (_restageContext, _restageSource) => _Inset(
                          inset: _restageArgs.$1,
                          child:
                              _restageSource.child(const <Object>['child']))))),
        ])))();
  }
}

final _appWidgetsInitFieldPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_init_field',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_init_field',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        '_h2eebd85693': <String, Object?>{'kind': 'string', 'label': '_label'},
        '_hcbc62b0f45': <String, Object?>{
          'kind': 'string',
          'label': 'Theme.of(context).brightness.name'
        },
        'count': <String, Object?>{'kind': 'int'}
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'AppWidgetsInitFieldSurface',
);

final appWidgetsInitFieldPlacementDefinition =
    () => _appWidgetsInitFieldPlacementDefinitionValue;

final class AppWidgetsInitFieldSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsInitFieldSurface({
    super.key,
    required int count,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = count,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsInitFieldSurface] for the default placement; no name is needed.
  const AppWidgetsInitFieldSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    required int count,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = count,
        _restagePlacementName = restagePlacementId;

  final int _restageStored1;
  int get _restageArgument1 => _restageStored1;
  static final _restageSurfaces = Expando<AppWidgetsInitField>();
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    final _restageSurface = _restageSurfaces[this] ??=
        AppWidgetsInitField(count: _restageArgument1);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_init_field',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsInitFieldPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'count': _restageArgument1,
        },
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          Text(_restageRecording.value('_h2eebd85693', _restageSurface._label)),
          Text(_restageRecording.value(
              '_hcbc62b0f45', Theme.of(context).brightness.name)),
        ])))();
  }
}

final _appWidgetsInlinePlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_inline',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_inline',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        '_h4804cfbfb1': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'installed.call',
            'nullable': false,
            'call': <String, Object?>{
              'inputs': <Object?>[
                <String, Object?>{
                  'kind': 'native',
                  'nativeType': 'dart:core#String'
                }
              ],
              'captures': <String, Object?>{},
              'result': <String, Object?>{
                'kind': 'native',
                'nativeType': '()->void'
              },
              'implementation':
                  '4804cfbfb1daef6dd5d1672c294cb4d8c7bd8f5aa06cea93fce2eb70fd2c46ac'
            }
          }
        },
        '_ha4e130695a': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'dart:core#String',
            'nullable': false
          },
          'label': 'title'
        },
        'title': <String, Object?>{'kind': 'string'}
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Center': buildCenter,
        'Column': buildColumn,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'SizedBox': buildSizedBox,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'AppWidgetsInlineSurface',
);

final appWidgetsInlinePlacementDefinition =
    () => _appWidgetsInlinePlacementDefinitionValue;

final _restageAppWidgetsInlineSurface_h4804cfbfb1Contract =
    NativeBindingContract.fromJson(<String, Object?>{
  "type": "installed.call",
  "nullable": false,
  "call": <String, Object?>{
    "inputs": <Object?>[
      <String, Object?>{"kind": "native", "nativeType": "dart:core#String"}
    ],
    "captures": <String, Object?>{},
    "result": <String, Object?>{"kind": "native", "nativeType": "()->void"},
    "implementation":
        "4804cfbfb1daef6dd5d1672c294cb4d8c7bd8f5aa06cea93fce2eb70fd2c46ac"
  }
});
final NativeCallAdapter _restageAppWidgetsInlineSurface_h4804cfbfb1Native =
    NativeCallAdapter(_restageAppWidgetsInlineSurface_h4804cfbfb1Contract,
        (_restageInputs, _restageCells) {
  T _restageAs<T>(Object? value) => value as T;
  final String _restageInput0 =
      _restageAs<String>((_restageInputs[0] as ValueNative).value);
  final void Function() _restageResult =
      () => appWidgetCalls.add('tap ${_restageInput0}');
  return NativeBinding<void Function()>(
      contract: NativeBindingContract(type: "()->void", nullable: false),
      value: _restageResult);
});

final class AppWidgetsInlineSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsInlineSurface({
    super.key,
    required String title,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsInlineSurface] for the default placement; no name is needed.
  const AppWidgetsInlineSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    required String title,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restagePlacementName = restagePlacementId;

  final String _restageStored1;
  String get _restageArgument1 => _restageStored1;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Center': buildCenter,
            'Column': buildColumn,
            'GestureDetector': buildGestureDetector,
            'Padding': buildPadding,
            'SizedBox': buildSizedBox,
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) =>
                switch (key.split('#').first) { _ => throw StateError(key) },
            {
              '_h4804cfbfb1': NativeBinding(
                  contract: _restageAppWidgetsInlineSurface_h4804cfbfb1Contract,
                  value: _restageAppWidgetsInlineSurface_h4804cfbfb1Native),
              '_ha4e130695a': NativeBinding(
                  contract: NativeBindingContract(
                      type: 'dart:core#String', nullable: false),
                  value: _restageArgument1),
            }),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h4804cfbfb1':
                    '() => appWidgetCalls.add(\'tap \${_restageInput0}\')',
                '_ha4e130695a': 'title',
              },
        child: RestagePaywall(
          id: 'app_widgets_inline',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: appWidgetsInlinePlacementDefinition,
            name: _restagePlacementName,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            'title': _restageArgument1,
            '_h4804cfbfb1': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h4804cfbfb1',
              "type": 'installed.call',
              "nullable": false
            },
            '_ha4e130695a': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_ha4e130695a',
              "type": 'dart:core#String',
              "nullable": false
            },
          },
          fallbackBuilder: (_) => _restageBuilt,
          onEvent: onEvent,
          resolver: resolver,
          errorBuilder: errorBuilder,
          loadingBuilder: loadingBuilder,
        ),
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          AppPill(label: _restageArgument1),
          _Boxed(child: AppCard(heading: 'Plans', label: _restageArgument1)),
          AppTap(
            onTap: () => appWidgetCalls.add('tap ${_restageArgument1}'),
            child: const AppPill(label: 'Go'),
          ),
        ])))();
  }
}

final _appWidgetsIslandPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_island',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_island',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'islands': <String, Object?>{
      'restage_example.islands:app__widgets__island__Counted_0': 'w23426565'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Center': buildCenter,
        'Column': buildColumn,
        'Padding': buildPadding,
        'SizedBox': buildSizedBox,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$app__widgets__island__Counted_0],
  ),
  surfaceWidget: 'AppWidgetsIslandSurface',
);

final appWidgetsIslandPlacementDefinition =
    () => _appWidgetsIslandPlacementDefinitionValue;

const restageIslands$app__widgets__island__Counted_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'app__widgets__island__Counted_0',
              builder: _restageIsland$app__widgets__island__Counted_0)
        ],
        islands: true);

Widget _restageIsland$app__widgets__island__Counted_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__island__Counted_0',
        '`_Counted` (lib/surfaces/app_widgets.dart:168:23) needs app code that only `AppWidgetsIslandSurface` provides. Try using `AppWidgetsIslandSurface` to build this screen.',
        context,
        source);

Widget restagePreview$app__widgets__island__Counted_0(
        BuildContext restageContext, DataSource restageSource) =>
    _Counted();

final class AppWidgetsIslandSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsIslandSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsIslandSurface] for the default placement; no name is needed.
  const AppWidgetsIslandSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Center': buildCenter,
            'Column': buildColumn,
            'Padding': buildPadding,
            'SizedBox': buildSizedBox,
            'Text': buildText,
          },
        ),
        libraries: [restageIslands$app__widgets__island__Counted_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_island',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsIslandPlacementDefinition,
          name: _restagePlacementName,
        ),
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {
            'app__widgets__island__Counted_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__island__Counted_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          AppPill(label: 'Pro'),
          _Boxed(
              child: _restageRecording.island(
                  'app__widgets__island__Counted_0', _Counted())),
        ])))();
  }
}

final _appWidgetsKeyedTallyPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_keyed_tally',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_keyed_tally',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        '_h936348a2cc': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h6d77105b3d': <String, Object?>{
                'kind': 'nativeBinding',
                'contract': <String, Object?>{
                  'type': 'flutter.Key',
                  'nullable': false
                },
                'label': 'ValueKey(name)'
              },
              '_hdde93e85c5': <String, Object?>{'kind': 'int'},
              '_hec510a767b': <String, Object?>{
                'kind': 'string',
                'label': 'name'
              }
            }
          }
        },
        'names': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{'kind': 'string'}
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'GestureDetector': buildGestureDetector,
        'TextRich': buildTextRich,
      },
    ),
    libraries: [
      restageSplit$TallyChip,
    ],
  ),
  surfaceWidget: 'AppWidgetsKeyedTallySurface',
);

final appWidgetsKeyedTallyPlacementDefinition =
    () => _appWidgetsKeyedTallyPlacementDefinitionValue;

final class AppWidgetsKeyedTallySurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsKeyedTallySurface({
    super.key,
    required List<String> names,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = names,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsKeyedTallySurface] for the default placement; no name is needed.
  const AppWidgetsKeyedTallySurface.atPlacement(
    String restagePlacementId, {
    super.key,
    required List<String> names,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = names,
        _restagePlacementName = restagePlacementId;

  final List<String> _restageStored1;
  List<String> get _restageArgument1 => _restageStored1;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'GestureDetector': buildGestureDetector,
            'TextRich': buildTextRich,
          },
        ),
        libraries: [
          restageSplit$TallyChip,
        ],
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) => switch (key.split('#').first) {
                  '_h6d77105b3d' =>
                    NativeBindingContract(type: 'flutter.Key', nullable: false),
                  _ => throw StateError(key)
                },
            {}),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h6d77105b3d': 'ValueKey(name)',
              },
        child: RestagePaywall(
          id: 'app_widgets_keyed_tally',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: appWidgetsKeyedTallyPlacementDefinition,
            name: _restagePlacementName,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            'names': _restageArgument1,
          },
          fallbackBuilder: (_) => _restageBuilt,
          onEvent: onEvent,
          resolver: resolver,
          errorBuilder: errorBuilder,
          loadingBuilder: loadingBuilder,
        ),
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          for (final name in _restageRecording
              .items('_h936348a2cc', _restageArgument1, null, ['_hdde93e85c5']))
            _restageRecording.island(
                'app__widgets__keyed__tally_TallyChip_0',
                TallyChip(
                    key: _restageRecording.native(
                        '_h6d77105b3d', ValueKey(name),
                        items: '_h936348a2cc',
                        type: 'flutter.Key',
                        nullable: false),
                    label: _restageRecording.value(
                        '_hec510a767b', name, '_h936348a2cc')),
                place: restageSplitApp$TallyChip,
                items: '_h936348a2cc'),
        ])))();
  }
}

final _appWidgetsLocalFnPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_local_fn',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_local_fn',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'islands': <String, Object?>{
      'restage_example.islands:app__widgets__local__fn_row_0': 'w123099644',
      'restage_example.islands:app__widgets__local__fn_row_1': 'w153859639'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
      },
    ),
    libraries: [restageIslands$app__widgets__local__fn_row_0],
  ),
  surfaceWidget: 'AppWidgetsLocalFnSurface',
);

final appWidgetsLocalFnPlacementDefinition =
    () => _appWidgetsLocalFnPlacementDefinitionValue;

const restageIslands$app__widgets__local__fn_row_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'app__widgets__local__fn_row_0',
              builder: _restageIsland$app__widgets__local__fn_row_0),
          RestageWidgetFactory(
              name: 'app__widgets__local__fn_row_1',
              builder: _restageIsland$app__widgets__local__fn_row_1)
        ],
        islands: true);

Widget _restageIsland$app__widgets__local__fn_row_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__local__fn_row_0',
        '`row` (lib/surfaces/app_widgets.dart:409:30) needs app code that only `AppWidgetsLocalFnSurface` provides. Try using `AppWidgetsLocalFnSurface` to build this screen.',
        context,
        source);

Widget restagePreview$app__widgets__local__fn_row_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageIslandPlaceholder(label: 'row', children: []);

Widget _restageIsland$app__widgets__local__fn_row_1(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__local__fn_row_1',
        '`row` (lib/surfaces/app_widgets.dart:409:40) needs app code that only `AppWidgetsLocalFnSurface` provides. Try using `AppWidgetsLocalFnSurface` to build this screen.',
        context,
        source);

Widget restagePreview$app__widgets__local__fn_row_1(
        BuildContext restageContext, DataSource restageSource) =>
    RestageIslandPlaceholder(label: 'row', children: []);

final class AppWidgetsLocalFnSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsLocalFnSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsLocalFnSurface] for the default placement; no name is needed.
  const AppWidgetsLocalFnSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
          },
        ),
        libraries: [restageIslands$app__widgets__local__fn_row_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_local_fn',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsLocalFnPlacementDefinition,
          name: _restagePlacementName,
        ),
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {
            'app__widgets__local__fn_row_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__local__fn_row_0',
                    [],
                    _restageContext,
                    _restageSource),
            'app__widgets__local__fn_row_1':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__local__fn_row_1',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() {
      Widget row(String text) => Text(appWidgetShout(text));
      return _restageDesign(Column(children: [
        _restageRecording.island('app__widgets__local__fn_row_0', row('a')),
        _restageRecording.island('app__widgets__local__fn_row_1', row('b'))
      ]));
    })();
  }
}

final _appWidgetsNamedCardPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_named_card',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_named_card',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        '_ha4e130695a': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'dart:core#String',
            'nullable': false
          },
          'label': 'title'
        },
        '_he93121413d': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'installed.call',
            'nullable': false,
            'call': <String, Object?>{
              'inputs': <Object?>[
                <String, Object?>{
                  'kind': 'native',
                  'nativeType': 'dart:core#String'
                }
              ],
              'captures': <String, Object?>{},
              'result': <String, Object?>{
                'kind': 'native',
                'nativeType': '()->void'
              },
              'implementation':
                  'e93121413d573bea9c5059f81838815d7dbe11cb8367f07ca3b60b449d772830'
            }
          }
        },
        'title': <String, Object?>{'kind': 'string'}
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'Text': buildText,
      },
      material: {
        'Card': buildCard,
      },
    ),
  ),
  surfaceWidget: 'AppWidgetsNamedCardSurface',
);

final appWidgetsNamedCardPlacementDefinition =
    () => _appWidgetsNamedCardPlacementDefinitionValue;

final _restageAppWidgetsNamedCardSurface_he93121413dContract =
    NativeBindingContract.fromJson(<String, Object?>{
  "type": "installed.call",
  "nullable": false,
  "call": <String, Object?>{
    "inputs": <Object?>[
      <String, Object?>{"kind": "native", "nativeType": "dart:core#String"}
    ],
    "captures": <String, Object?>{},
    "result": <String, Object?>{"kind": "native", "nativeType": "()->void"},
    "implementation":
        "e93121413d573bea9c5059f81838815d7dbe11cb8367f07ca3b60b449d772830"
  }
});
final NativeCallAdapter _restageAppWidgetsNamedCardSurface_he93121413dNative =
    NativeCallAdapter(_restageAppWidgetsNamedCardSurface_he93121413dContract,
        (_restageInputs, _restageCells) {
  T _restageAs<T>(Object? value) => value as T;
  final String _restageInput0 =
      _restageAs<String>((_restageInputs[0] as ValueNative).value);
  final void Function() _restageResult =
      () => appWidgetCalls.add('tap ${_restageInput0}');
  return NativeBinding<void Function()>(
      contract: NativeBindingContract(type: "()->void", nullable: false),
      value: _restageResult);
});

final class AppWidgetsNamedCardSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsNamedCardSurface({
    super.key,
    required String title,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsNamedCardSurface] for the default placement; no name is needed.
  const AppWidgetsNamedCardSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    required String title,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restagePlacementName = restagePlacementId;

  final String _restageStored1;
  String get _restageArgument1 => _restageStored1;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'GestureDetector': buildGestureDetector,
            'Padding': buildPadding,
            'Text': buildText,
          },
          material: {
            'Card': buildCard,
          },
        ),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) =>
                switch (key.split('#').first) { _ => throw StateError(key) },
            {
              '_ha4e130695a': NativeBinding(
                  contract: NativeBindingContract(
                      type: 'dart:core#String', nullable: false),
                  value: _restageArgument1),
              '_he93121413d': NativeBinding(
                  contract:
                      _restageAppWidgetsNamedCardSurface_he93121413dContract,
                  value: _restageAppWidgetsNamedCardSurface_he93121413dNative),
            }),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_ha4e130695a': 'title',
                '_he93121413d':
                    '() => appWidgetCalls.add(\'tap \${_restageInput0}\')',
              },
        child: RestagePaywall(
          id: 'app_widgets_named_card',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: appWidgetsNamedCardPlacementDefinition,
            name: _restagePlacementName,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            'title': _restageArgument1,
            '_ha4e130695a': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_ha4e130695a',
              "type": 'dart:core#String',
              "nullable": false
            },
            '_he93121413d': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_he93121413d',
              "type": 'installed.call',
              "nullable": false
            },
          },
          fallbackBuilder: (_) => _restageBuilt,
          onEvent: onEvent,
          resolver: resolver,
          errorBuilder: errorBuilder,
          loadingBuilder: loadingBuilder,
        ),
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          app.Card(
            heading: _restageArgument1,
            child: AppTap(
              onTap: () => appWidgetCalls.add('tap ${_restageArgument1}'),
              child: const AppPill(label: 'Go'),
            ),
          ),
          const Card(child: Text('Framework')),
        ])))();
  }
}

final _appWidgetsOwnKeysPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_own_keys',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_own_keys',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'islands': <String, Object?>{
      'restage_example.islands:app__widgets__own__keys_AppOwnKey_0':
          'w178866253'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [
      ...[
        restageIslands$OwnKeyChip__OwnKeyCount_0,
        restageSplit$OwnKeyChip,
      ],
      restageIslands$app__widgets__own__keys_AppOwnKey_0
    ],
  ),
  surfaceWidget: 'AppWidgetsOwnKeysSurface',
);

final appWidgetsOwnKeysPlacementDefinition =
    () => _appWidgetsOwnKeysPlacementDefinitionValue;

const restageIslands$app__widgets__own__keys_AppOwnKey_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'app__widgets__own__keys_AppOwnKey_0',
              builder: _restageIsland$app__widgets__own__keys_AppOwnKey_0)
        ],
        islands: true);

Widget _restageIsland$app__widgets__own__keys_AppOwnKey_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__own__keys_AppOwnKey_0',
        '`AppOwnKey` (lib/surfaces/app_widgets.dart:581:45) needs app code that only `AppWidgetsOwnKeysSurface` provides. Try using `AppWidgetsOwnKeysSurface` to build this screen.',
        context,
        source);

Widget restagePreview$app__widgets__own__keys_AppOwnKey_0(
        BuildContext restageContext, DataSource restageSource) =>
    AppOwnKey();

final class AppWidgetsOwnKeysSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsOwnKeysSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsOwnKeysSurface] for the default placement; no name is needed.
  const AppWidgetsOwnKeysSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'Text': buildText,
          },
        ),
        libraries: [
          ...[
            restageIslands$OwnKeyChip__OwnKeyCount_0,
            restageSplit$OwnKeyChip,
          ],
          restageIslands$app__widgets__own__keys_AppOwnKey_0
        ],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_own_keys',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsOwnKeysPlacementDefinition,
          name: _restagePlacementName,
        ),
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {
            'app__widgets__own__keys_AppOwnKey_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__own__keys_AppOwnKey_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          Text('keys'),
          _restageRecording.island(
              'app__widgets__own__keys_AppOwnKey_0', AppOwnKey()),
          _restageRecording.island(
              'app__widgets__own__keys_OwnKeyChip_0', OwnKeyChip(),
              place: restageSplitApp$OwnKeyChip)
        ])))();
  }
}

final _appWidgetsScaledPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_scaled',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_scaled',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [
      restageSplit$ScaledChip,
    ],
  ),
  surfaceWidget: 'AppWidgetsScaledSurface',
);

final appWidgetsScaledPlacementDefinition =
    () => _appWidgetsScaledPlacementDefinitionValue;

final class AppWidgetsScaledSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsScaledSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsScaledSurface] for the default placement; no name is needed.
  const AppWidgetsScaledSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'Text': buildText,
          },
        ),
        libraries: [
          restageSplit$ScaledChip,
        ],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_scaled',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsScaledPlacementDefinition,
          name: _restagePlacementName,
        ),
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          _restageRecording.island(
              'app__widgets__scaled_ScaledChip_0', ScaledChip(label: 'Scaled'),
              place: restageSplitApp$ScaledChip)
        ])))();
  }
}

final _appWidgetsScreenTallyEvents =
    const SurfaceScreenEventContract<Never>.none(
  hash:
      'sha256:de41f956f53085c222576ac5f4c25b26644aa34a3e33830c3b5f04cce6656ab5',
);

final _appWidgetsScreenTallyProvenance =
    SurfaceScreenRuntimeProvenance.generated(
  surface: Surface.general,
  slug: 'app_widgets_screen_tally',
  contractVersion: 1,
  capabilities: CapabilityManifest(
    builtInFloor: 24,
    requiredLibraries: const [
      LibraryRequirement(
        namespace: 'restage_example.widgets',
        minVersion: 5,
        minGenerated: 3,
      ),
    ],
  ),
  eventSchemaJson: '{"schemaVersion":1,"events":[]}',
  bundle: SurfaceScreenBundleLocator(
    assetKey: 'assets/restage/bundles/lib/surfaces/app_widgets.rsbundle',
    packageName: 'restage_example',
    authoredLibraryPath: 'lib/surfaces/app_widgets.dart',
    entries: [
      SurfaceScreenBundleEntryReference(
        logicalPath: 'assets/general/screens/app_widgets_screen_tally.rfw',
        role: RestageBundleEntryRole.screenBlob,
        byteLength: 2312,
        sha256:
            'sha256:4dc97418b765c18e39de0b1a37ca4e3429897bff043a2b22dceddca7a37e19be',
      ),
      SurfaceScreenBundleEntryReference(
        logicalPath:
            'assets/general/screens/app_widgets_screen_tally.capability.json',
        role: RestageBundleEntryRole.capabilitySidecar,
        byteLength: 213,
        sha256:
            'sha256:12022fe3f96e5a42f8e3ecab1a9cbe52c0995c7972f41ab73f756c76ad13795f',
      ),
    ],
  ),
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'GestureDetector': buildGestureDetector,
        'TextRich': buildTextRich,
      },
    ),
    libraries: [
      restageSplit$TallyChip,
    ],
  ),
);

final appWidgetsScreenTallyRef =
    SurfaceScreenRef<Never>.generatedWithMeasurementPublicationDraftDigest(
  provenance: _appWidgetsScreenTallyProvenance,
  eventContract: _appWidgetsScreenTallyEvents,
  measurementPublicationDraftDigest:
      '16ccefdf34508a2c25c6475b5226dff7b1e81d557da89b0e8b3aa397abb99278',
);

final _appWidgetsScreenTallyPlacementDefinitionValue =
    RestageScreen.generatedPlacementDefinition(
  defaultSurface: appWidgetsScreenTallyRef,
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'general',
    'slug': 'app_widgets_screen_tally',
    'family': <String, Object?>{'kind': 'screenContract', 'contractVersion': 1}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null
  },
  vocabulary: appWidgetsScreenTallyRef.provenance.vocabulary,
  surfaceWidget: 'AppWidgetsScreenTallySurface',
);

final appWidgetsScreenTallyPlacementDefinition =
    () => _appWidgetsScreenTallyPlacementDefinitionValue;

final class AppWidgetsScreenTallySurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsScreenTallySurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsScreenTallySurface] for the default placement; no name is needed.
  const AppWidgetsScreenTallySurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.unavailable,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<Never>? onEvent;

  final SurfaceScreenResolver? resolver;

  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  final WidgetBuilder? loadingBuilder;

  final SurfaceScreenUnavailablePolicy? unavailable;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      final restageContent = RestageScreen<Never>(
        screen: appWidgetsScreenTallyRef,
        placementBinding: RestageScreen.generatedPlacementBinding(
          definition: appWidgetsScreenTallyPlacementDefinition,
          name: _restagePlacementName,
        ),
        unavailable: unavailable ??
            SurfaceScreenUnavailablePolicy.fallback(
              builder: (_, error) => _restageBuilt,
            ),
        onEvent: onEvent,
        resolver: resolver,
        onUnavailable: onUnavailable,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context, builders: {}, child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          _restageRecording.island(
              'app__widgets__screen__tally_TallyChip_0', TallyChip(label: 'A'),
              place: restageSplitApp$TallyChip),
          _restageRecording.island(
              'app__widgets__screen__tally_TallyChip_1', TallyChip(label: 'B'),
              place: restageSplitApp$TallyChip),
        ])))();
  }
}

final _appWidgetsSliderPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_slider',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_slider',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        '_h459b52601b': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': '(dart:core#double)->void',
            'nullable': false
          },
          'label': '(value) => appWidgetCalls.add(\'slide \$value\')'
        },
        '_hbb4adffd38': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': '(dart:core#double)->dart:core#String',
            'nullable': false
          },
          'label': '(value) => appWidgetDescribe(value)'
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      material: {
        'Slider': buildSlider,
      },
    ),
  ),
  surfaceWidget: 'AppWidgetsSliderSurface',
);

final appWidgetsSliderPlacementDefinition =
    () => _appWidgetsSliderPlacementDefinitionValue;

final class AppWidgetsSliderSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsSliderSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsSliderSurface] for the default placement; no name is needed.
  const AppWidgetsSliderSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          material: {
            'Slider': buildSlider,
          },
        ),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) => switch (key.split('#').first) {
                  '_h459b52601b' => NativeBindingContract(
                      type: '(dart:core#double)->void', nullable: false),
                  '_hbb4adffd38' => NativeBindingContract(
                      type: '(dart:core#double)->dart:core#String',
                      nullable: false),
                  _ => throw StateError(key)
                },
            {}),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h459b52601b':
                    '(value) => appWidgetCalls.add(\'slide \$value\')',
                '_hbb4adffd38': '(value) => appWidgetDescribe(value)',
              },
        child: RestagePaywall(
          id: 'app_widgets_slider',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: appWidgetsSliderPlacementDefinition,
            name: _restagePlacementName,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            '_h459b52601b': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h459b52601b',
              "type": '(dart:core#double)->void',
              "nullable": false
            },
            '_hbb4adffd38': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hbb4adffd38',
              "type": '(dart:core#double)->dart:core#String',
              "nullable": false
            },
          },
          fallbackBuilder: (_) => _restageBuilt,
          onEvent: onEvent,
          resolver: resolver,
          errorBuilder: errorBuilder,
          loadingBuilder: loadingBuilder,
        ),
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(Slider(
          value: 0.25,
          onChanged: _restageRecording.native(
              '_h459b52601b', (value) => appWidgetCalls.add('slide $value'),
              type: '(dart:core#double)->void', nullable: false),
          semanticFormatterCallback: _restageRecording.native(
              '_hbb4adffd38', (value) => appWidgetDescribe(value),
              type: '(dart:core#double)->dart:core#String', nullable: false),
        )))();
  }
}

final _appWidgetsSpreadComputedPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_spread_computed',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_spread_computed',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        'names': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{'kind': 'string'}
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'islands': <String, Object?>{
      'restage_example.islands:app__widgets__spread__computed_Column_0':
          'w167941162'
    }
  },
  vocabulary: const SurfaceVocabulary(
    libraries: [restageIslands$app__widgets__spread__computed_Column_0],
  ),
  surfaceWidget: 'AppWidgetsSpreadComputedSurface',
);

final appWidgetsSpreadComputedPlacementDefinition =
    () => _appWidgetsSpreadComputedPlacementDefinitionValue;

const restageIslands$app__widgets__spread__computed_Column_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'app__widgets__spread__computed_Column_0',
              builder: _restageIsland$app__widgets__spread__computed_Column_0)
        ],
        islands: true);

Widget _restageIsland$app__widgets__spread__computed_Column_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'app__widgets__spread__computed_Column_0',
        '`Column` (lib/surfaces/app_widgets.dart:466:41) needs app code that only `AppWidgetsSpreadComputedSurface` provides. Try using `AppWidgetsSpreadComputedSurface` to build this screen.',
        context,
        source);

Widget restagePreview$app__widgets__spread__computed_Column_0(
        BuildContext restageContext, DataSource restageSource) =>
    Column();

final class AppWidgetsSpreadComputedSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsSpreadComputedSurface({
    super.key,
    required List<String> names,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = names,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsSpreadComputedSurface] for the default placement; no name is needed.
  const AppWidgetsSpreadComputedSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    required List<String> names,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = names,
        _restagePlacementName = restagePlacementId;

  final List<String> _restageStored1;
  List<String> get _restageArgument1 => _restageStored1;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        libraries: [restageIslands$app__widgets__spread__computed_Column_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_spread_computed',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsSpreadComputedPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'names': _restageArgument1,
        },
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {
            'app__widgets__spread__computed_Column_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'app__widgets__spread__computed_Column_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(_restageRecording.island(
        'app__widgets__spread__computed_Column_0',
        Column(children: [
          const Text('h'),
          ...appWidgetRows([
            for (final n in _restageArgument1)
              if (n != 'a') n
          ]),
        ]))))();
  }
}

final _appWidgetsSpreadInputPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_spread_input',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_spread_input',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        '_h936348a2cc': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h9aea57c772': <String, Object?>{
                'kind': 'string',
                'label': 'appWidgetShout(name)'
              },
              '_hfcadd13883': <String, Object?>{
                'kind': 'string',
                'label': 'appWidgetShout(\'m\$name\')'
              }
            }
          }
        },
        '_hf2f7fa1cde': <String, Object?>{
          'kind': 'string',
          'label': 'appWidgetShout(name)'
        },
        'names': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{'kind': 'string'}
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'AppWidgetsSpreadInputSurface',
);

final appWidgetsSpreadInputPlacementDefinition =
    () => _appWidgetsSpreadInputPlacementDefinitionValue;

final class AppWidgetsSpreadInputSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsSpreadInputSurface({
    super.key,
    required List<String> names,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = names,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsSpreadInputSurface] for the default placement; no name is needed.
  const AppWidgetsSpreadInputSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    required List<String> names,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = names,
        _restagePlacementName = restagePlacementId;

  final List<String> _restageStored1;
  List<String> get _restageArgument1 => _restageStored1;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_spread_input',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsSpreadInputPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'names': _restageArgument1,
        },
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          const Text('h'),
          ...((List<String> names) => [
                for (final name
                    in _restageRecording.items('_h936348a2cc', names))
                  Text(_restageRecording.value(
                      '_hfcadd13883', appWidgetShout('m$name'), '_h936348a2cc'))
              ])(_restageArgument1),
          ...((List<String> names) => [
                for (final name
                    in _restageRecording.items('_h936348a2cc', names))
                  Text(_restageRecording.value(
                      '_h9aea57c772', appWidgetShout(name), '_h936348a2cc'))
              ])(_restageArgument1),
          ...((List<String> names) => [
                for (final name in _restageRecording.unrolled(0, names))
                  Text(_restageRecording.value(
                      _restageRecording
                          .unrolledKey(const {'0': '_hf2f7fa1cde'}, const [0]),
                      appWidgetShout(name)))
              ])(const ['c']),
        ])))();
  }
}

final _appWidgetsSpreadPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_spread',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_spread',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        '_h54b1cca6e8': <String, Object?>{
          'kind': 'string',
          'label': 'appWidgetShout(name)'
        },
        '_hfe709c87b8': <String, Object?>{
          'kind': 'string',
          'label': 'appWidgetShout(name)'
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'AppWidgetsSpreadSurface',
);

final appWidgetsSpreadPlacementDefinition =
    () => _appWidgetsSpreadPlacementDefinitionValue;

final class AppWidgetsSpreadSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsSpreadSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsSpreadSurface] for the default placement; no name is needed.
  const AppWidgetsSpreadSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_spread',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsSpreadPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
        },
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          const Text('h'),
          ...((List<String> names) => [
                for (final name in _restageRecording.unrolled(0, names))
                  Text(_restageRecording.value(
                      _restageRecording.unrolledKey(
                          const {'0': '_h54b1cca6e8', '1': '_hfe709c87b8'},
                          const [0]),
                      appWidgetShout(name)))
              ])(const ['a', 'b'])
        ])))();
  }
}

final _appWidgetsTallyPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'app_widgets_tally',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'app_widgets_tally',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'GestureDetector': buildGestureDetector,
        'TextRich': buildTextRich,
      },
    ),
    libraries: [
      restageSplit$TallyChip,
    ],
  ),
  surfaceWidget: 'AppWidgetsTallySurface',
);

final appWidgetsTallyPlacementDefinition =
    () => _appWidgetsTallyPlacementDefinitionValue;

final class AppWidgetsTallySurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const AppWidgetsTallySurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [AppWidgetsTallySurface] for the default placement; no name is needed.
  const AppWidgetsTallySurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'GestureDetector': buildGestureDetector,
            'TextRich': buildTextRich,
          },
        ),
        libraries: [
          restageSplit$TallyChip,
        ],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'app_widgets_tally',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: appWidgetsTallyPlacementDefinition,
          name: _restagePlacementName,
        ),
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: onEvent,
        resolver: resolver,
        errorBuilder: errorBuilder,
        loadingBuilder: loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          _restageRecording.island(
              'app__widgets__tally_TallyChip_0', TallyChip(label: 'A'),
              place: restageSplitApp$TallyChip),
          _restageRecording.island(
              'app__widgets__tally_TallyChip_1', TallyChip(label: 'B'),
              place: restageSplitApp$TallyChip),
        ])))();
  }
}
