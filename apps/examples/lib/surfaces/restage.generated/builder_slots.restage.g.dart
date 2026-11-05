part of '../builder_slots.dart';

// ignore_for_file: type=lint, unnecessary_cast

final _slotAndPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'slot_and',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'slot_and',
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
      'restage_example.islands:slot__and_ValueListenableBuilder_0': 'w144725382'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$slot__and_ValueListenableBuilder_0],
  ),
  surfaceWidget: 'SlotAndSurface',
);

final slotAndPlacementDefinition = () => _slotAndPlacementDefinitionValue;

const restageIslands$slot__and_ValueListenableBuilder_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'slot__and_ValueListenableBuilder_0',
              builder: _restageIsland$slot__and_ValueListenableBuilder_0)
        ],
        islands: true);

Widget _restageIsland$slot__and_ValueListenableBuilder_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'slot__and_ValueListenableBuilder_0',
        '`ValueListenableBuilder` (lib/surfaces/builder_slots.dart:194:7) needs app code that only `SlotAndSurface` provides. Try using `SlotAndSurface` to build this screen.',
        context,
        source);

Widget restagePreview$slot__and_ValueListenableBuilder_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageBuilderBinding.construct((_restageBindings) {
      final _restageBinding$builder = RestageBuilderBinding(
          RestageValueBinding.dataSource(restageSource, restageContext),
          const <Object>['builder'],
          contract: const WidgetBuilderContract(parameters: [
            WidgetBuilderParameter.buildContext,
            WidgetBuilderParameter.data,
            WidgetBuilderParameter.child
          ]),
          data: const <String, ValueType>{'arg1': ValueType('int')});
      _restageBindings.add(_restageBinding$builder);
      return ValueListenableBuilder<int>(
        valueListenable: slotCount,
        builder: (_restageArg0, _restageArg1, _restageArg2) =>
            _restageBinding$builder
                .build(_restageArg0, <String, Object?>{'arg1': _restageArg1}),
      );
    });

final class SlotAndSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const SlotAndSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [SlotAndSurface] for the default placement; no name is needed.
  const SlotAndSurface.atPlacement(
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
        libraries: [restageIslands$slot__and_ValueListenableBuilder_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'slot_and',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: slotAndPlacementDefinition,
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
            'slot__and_ValueListenableBuilder_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'slot__and_ValueListenableBuilder_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() {
      final shown = slotShown();
      return _restageDesign(Column(children: [
        const Text('and'),
        _restageRecording.island(
            'slot__and_ValueListenableBuilder_0',
            _restageRecording.built(
                RestageBuilderBinding.retain(const [],
                    child: ValueListenableBuilder<int>(
                      valueListenable: slotCount,
                      builder: (context, count, child) => Column(
                          children: [if (shown && count > 1) Text('a $count')]),
                    )),
                (_restageContext, _restageSource) =>
                    RestageBuilderBinding.construct((_restageBindings) {
                      final _restageBinding$builder = RestageBuilderBinding(
                          RestageValueBinding.dataSource(
                              _restageSource, _restageContext),
                          const <Object>['builder'],
                          contract: const WidgetBuilderContract(parameters: [
                            WidgetBuilderParameter.buildContext,
                            WidgetBuilderParameter.data,
                            WidgetBuilderParameter.child
                          ]),
                          data: const <String, ValueType>{
                            'arg1': ValueType('int')
                          });
                      _restageBindings.add(_restageBinding$builder);
                      return ValueListenableBuilder<int>(
                        valueListenable: slotCount,
                        builder: (context, count, child) {
                          final _restageSlotRecording = RestageRecording();
                          _restageRender(Object? _) =>
                              _restageBinding$builder.build(
                                  context, <String, Object?>{'arg1': count},
                                  recorded: _restageSlotRecording.values);
                          return _restageRender(Column(children: [
                            if (shown && count > 1) Text('a $count')
                          ]));
                        },
                      );
                    }))),
      ]));
    })();
  }
}

final _slotChildPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'slot_child',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'slot_child',
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
      'restage_example.islands:slot__child_ValueListenableBuilder_0':
          'w67394883'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$slot__child_ValueListenableBuilder_0],
  ),
  surfaceWidget: 'SlotChildSurface',
);

final slotChildPlacementDefinition = () => _slotChildPlacementDefinitionValue;

const restageIslands$slot__child_ValueListenableBuilder_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'slot__child_ValueListenableBuilder_0',
              builder: _restageIsland$slot__child_ValueListenableBuilder_0)
        ],
        islands: true);

Widget _restageIsland$slot__child_ValueListenableBuilder_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'slot__child_ValueListenableBuilder_0',
        '`ValueListenableBuilder` (lib/surfaces/builder_slots.dart:88:9) needs app code that only `SlotChildSurface` provides. Try using `SlotChildSurface` to build this screen.',
        context,
        source);

Widget restagePreview$slot__child_ValueListenableBuilder_0(
        BuildContext restageContext, DataSource restageSource) =>
    ValueListenableBuilder<int>(
      valueListenable: slotCount,
      builder: (context, count, child) =>
          Row(children: [Text('n $count'), child!]),
      child: restageSource.child(const <Object>['child']),
    );

final class SlotChildSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const SlotChildSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [SlotChildSurface] for the default placement; no name is needed.
  const SlotChildSurface.atPlacement(
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
        libraries: [restageIslands$slot__child_ValueListenableBuilder_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'slot_child',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: slotChildPlacementDefinition,
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
            'slot__child_ValueListenableBuilder_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'slot__child_ValueListenableBuilder_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          const Text('child'),
          _restageRecording.island(
              'slot__child_ValueListenableBuilder_0',
              _restageRecording.built(
                  ValueListenableBuilder<int>(
                    valueListenable: slotCount,
                    builder: (context, count, child) =>
                        Row(children: [Text('n $count'), child!]),
                    child: const Text('kept'),
                  ),
                  (_restageContext, _restageSource) =>
                      ValueListenableBuilder<int>(
                        valueListenable: slotCount,
                        builder: (context, count, child) =>
                            Row(children: [Text('n $count'), child!]),
                        child: _restageSource.child(const <Object>['child']),
                      ))),
        ])))();
  }
}

final _slotCountPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'slot_count',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'slot_count',
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
      'restage_example.islands:slot__count_ValueListenableBuilder_0':
          'w215394815'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$slot__count_ValueListenableBuilder_0],
  ),
  surfaceWidget: 'SlotCountSurface',
);

final slotCountPlacementDefinition = () => _slotCountPlacementDefinitionValue;

const restageIslands$slot__count_ValueListenableBuilder_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'slot__count_ValueListenableBuilder_0',
              builder: _restageIsland$slot__count_ValueListenableBuilder_0)
        ],
        islands: true);

Widget _restageIsland$slot__count_ValueListenableBuilder_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'slot__count_ValueListenableBuilder_0',
        '`ValueListenableBuilder` (lib/surfaces/builder_slots.dart:52:9) needs app code that only `SlotCountSurface` provides. Try using `SlotCountSurface` to build this screen.',
        context,
        source);

Widget restagePreview$slot__count_ValueListenableBuilder_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageBuilderBinding.construct((_restageBindings) {
      final _restageBinding$builder = RestageBuilderBinding(
          RestageValueBinding.dataSource(restageSource, restageContext),
          const <Object>['builder'],
          contract: const WidgetBuilderContract(parameters: [
            WidgetBuilderParameter.buildContext,
            WidgetBuilderParameter.data,
            WidgetBuilderParameter.child
          ]),
          data: const <String, ValueType>{'arg1': ValueType('int')});
      _restageBindings.add(_restageBinding$builder);
      return ValueListenableBuilder<int>(
        valueListenable: slotCount,
        builder: (_restageArg0, _restageArg1, _restageArg2) =>
            _restageBinding$builder
                .build(_restageArg0, <String, Object?>{'arg1': _restageArg1}),
      );
    });

final class SlotCountSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const SlotCountSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [SlotCountSurface] for the default placement; no name is needed.
  const SlotCountSurface.atPlacement(
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
        libraries: [restageIslands$slot__count_ValueListenableBuilder_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'slot_count',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: slotCountPlacementDefinition,
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
            'slot__count_ValueListenableBuilder_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'slot__count_ValueListenableBuilder_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          const Text('header'),
          _restageRecording.island(
              'slot__count_ValueListenableBuilder_0',
              _restageRecording.built(
                  RestageBuilderBinding.retain(const [],
                      child: ValueListenableBuilder<int>(
                        valueListenable: slotCount,
                        builder: (context, count, child) =>
                            Text('count $count'),
                      )),
                  (_restageContext, _restageSource) =>
                      RestageBuilderBinding.construct((_restageBindings) {
                        final _restageBinding$builder = RestageBuilderBinding(
                            RestageValueBinding.dataSource(
                                _restageSource, _restageContext),
                            const <Object>['builder'],
                            contract: const WidgetBuilderContract(parameters: [
                              WidgetBuilderParameter.buildContext,
                              WidgetBuilderParameter.data,
                              WidgetBuilderParameter.child
                            ]),
                            data: const <String, ValueType>{
                              'arg1': ValueType('int')
                            });
                        _restageBindings.add(_restageBinding$builder);
                        return ValueListenableBuilder<int>(
                          valueListenable: slotCount,
                          builder: (context, count, child) {
                            final _restageSlotRecording = RestageRecording();
                            _restageRender(Object? _) =>
                                _restageBinding$builder.build(
                                    context, <String, Object?>{'arg1': count},
                                    recorded: _restageSlotRecording.values);
                            return _restageRender(Text('count $count'));
                          },
                        );
                      }))),
        ])))();
  }
}

final _slotFlagPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'slot_flag',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'slot_flag',
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
      'restage_example.islands:slot__flag_ValueListenableBuilder_0':
          'w114342887'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
        'Visibility': buildVisibility,
      },
    ),
    libraries: [restageIslands$slot__flag_ValueListenableBuilder_0],
  ),
  surfaceWidget: 'SlotFlagSurface',
);

final slotFlagPlacementDefinition = () => _slotFlagPlacementDefinitionValue;

const restageIslands$slot__flag_ValueListenableBuilder_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'slot__flag_ValueListenableBuilder_0',
              builder: _restageIsland$slot__flag_ValueListenableBuilder_0)
        ],
        islands: true);

Widget _restageIsland$slot__flag_ValueListenableBuilder_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'slot__flag_ValueListenableBuilder_0',
        '`ValueListenableBuilder` (lib/surfaces/builder_slots.dart:154:7) needs app code that only `SlotFlagSurface` provides. Try using `SlotFlagSurface` to build this screen.',
        context,
        source);

Widget restagePreview$slot__flag_ValueListenableBuilder_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageBuilderBinding.construct((_restageBindings) {
      final _restageBinding$builder = RestageBuilderBinding(
          RestageValueBinding.dataSource(restageSource, restageContext),
          const <Object>['builder'],
          contract: const WidgetBuilderContract(parameters: [
            WidgetBuilderParameter.buildContext,
            WidgetBuilderParameter.data,
            WidgetBuilderParameter.child
          ]),
          data: const <String, ValueType>{'arg1': ValueType('int')});
      _restageBindings.add(_restageBinding$builder);
      return ValueListenableBuilder<int>(
        valueListenable: slotCount,
        builder: (_restageArg0, _restageArg1, _restageArg2) =>
            _restageBinding$builder
                .build(_restageArg0, <String, Object?>{'arg1': _restageArg1}),
      );
    });

final class SlotFlagSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const SlotFlagSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [SlotFlagSurface] for the default placement; no name is needed.
  const SlotFlagSurface.atPlacement(
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
            'Visibility': buildVisibility,
          },
        ),
        libraries: [restageIslands$slot__flag_ValueListenableBuilder_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'slot_flag',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: slotFlagPlacementDefinition,
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
            'slot__flag_ValueListenableBuilder_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'slot__flag_ValueListenableBuilder_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() {
      final shown = slotShown();
      return _restageDesign(Column(children: [
        const Text('flag'),
        _restageRecording.island(
            'slot__flag_ValueListenableBuilder_0',
            _restageRecording.built(
                RestageBuilderBinding.retain(const [],
                    child: ValueListenableBuilder<int>(
                      valueListenable: slotCount,
                      builder: (context, count, child) =>
                          Visibility(visible: shown, child: Text('f $count')),
                    )),
                (_restageContext, _restageSource) =>
                    RestageBuilderBinding.construct((_restageBindings) {
                      final _restageBinding$builder = RestageBuilderBinding(
                          RestageValueBinding.dataSource(
                              _restageSource, _restageContext),
                          const <Object>['builder'],
                          contract: const WidgetBuilderContract(parameters: [
                            WidgetBuilderParameter.buildContext,
                            WidgetBuilderParameter.data,
                            WidgetBuilderParameter.child
                          ]),
                          data: const <String, ValueType>{
                            'arg1': ValueType('int')
                          });
                      _restageBindings.add(_restageBinding$builder);
                      return ValueListenableBuilder<int>(
                        valueListenable: slotCount,
                        builder: (context, count, child) {
                          final _restageSlotRecording = RestageRecording();
                          _restageRender(Object? _) =>
                              _restageBinding$builder.build(
                                  context, <String, Object?>{'arg1': count},
                                  recorded: _restageSlotRecording.values);
                          return _restageRender(Visibility(
                              visible: shown, child: Text('f $count')));
                        },
                      );
                    }))),
      ]));
    })();
  }
}

final _slotIfPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'slot_if',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'slot_if',
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
      'restage_example.islands:slot__if_ValueListenableBuilder_0': 'w248289153'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$slot__if_ValueListenableBuilder_0],
  ),
  surfaceWidget: 'SlotIfSurface',
);

final slotIfPlacementDefinition = () => _slotIfPlacementDefinitionValue;

const restageIslands$slot__if_ValueListenableBuilder_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'slot__if_ValueListenableBuilder_0',
              builder: _restageIsland$slot__if_ValueListenableBuilder_0)
        ],
        islands: true);

Widget _restageIsland$slot__if_ValueListenableBuilder_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'slot__if_ValueListenableBuilder_0',
        '`ValueListenableBuilder` (lib/surfaces/builder_slots.dart:174:7) needs app code that only `SlotIfSurface` provides. Try using `SlotIfSurface` to build this screen.',
        context,
        source);

Widget restagePreview$slot__if_ValueListenableBuilder_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageBuilderBinding.construct((_restageBindings) {
      final _restageBinding$builder = RestageBuilderBinding(
          RestageValueBinding.dataSource(restageSource, restageContext),
          const <Object>['builder'],
          contract: const WidgetBuilderContract(parameters: [
            WidgetBuilderParameter.buildContext,
            WidgetBuilderParameter.data,
            WidgetBuilderParameter.child
          ]),
          data: const <String, ValueType>{'arg1': ValueType('int')});
      _restageBindings.add(_restageBinding$builder);
      return ValueListenableBuilder<int>(
        valueListenable: slotCount,
        builder: (_restageArg0, _restageArg1, _restageArg2) =>
            _restageBinding$builder
                .build(_restageArg0, <String, Object?>{'arg1': _restageArg1}),
      );
    });

final class SlotIfSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const SlotIfSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [SlotIfSurface] for the default placement; no name is needed.
  const SlotIfSurface.atPlacement(
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
        libraries: [restageIslands$slot__if_ValueListenableBuilder_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'slot_if',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: slotIfPlacementDefinition,
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
            'slot__if_ValueListenableBuilder_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'slot__if_ValueListenableBuilder_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() {
      final shown = slotShown();
      return _restageDesign(Column(children: [
        const Text('if'),
        _restageRecording.island(
            'slot__if_ValueListenableBuilder_0',
            _restageRecording.built(
                RestageBuilderBinding.retain(const [],
                    child: ValueListenableBuilder<int>(
                      valueListenable: slotCount,
                      builder: (context, count, child) =>
                          Column(children: [if (shown) Text('i $count')]),
                    )),
                (_restageContext, _restageSource) =>
                    RestageBuilderBinding.construct((_restageBindings) {
                      final _restageBinding$builder = RestageBuilderBinding(
                          RestageValueBinding.dataSource(
                              _restageSource, _restageContext),
                          const <Object>['builder'],
                          contract: const WidgetBuilderContract(parameters: [
                            WidgetBuilderParameter.buildContext,
                            WidgetBuilderParameter.data,
                            WidgetBuilderParameter.child
                          ]),
                          data: const <String, ValueType>{
                            'arg1': ValueType('int')
                          });
                      _restageBindings.add(_restageBinding$builder);
                      return ValueListenableBuilder<int>(
                        valueListenable: slotCount,
                        builder: (context, count, child) {
                          final _restageSlotRecording = RestageRecording();
                          _restageRender(Object? _) =>
                              _restageBinding$builder.build(
                                  context, <String, Object?>{'arg1': count},
                                  recorded: _restageSlotRecording.values);
                          return _restageRender(
                              Column(children: [if (shown) Text('i $count')]));
                        },
                      );
                    }))),
      ]));
    })();
  }
}

final _slotLocalPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'slot_local',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'slot_local',
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
        'label': <String, Object?>{'kind': 'string'}
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'islands': <String, Object?>{
      'restage_example.islands:slot__local_ValueListenableBuilder_0':
          'w67885074'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$slot__local_ValueListenableBuilder_0],
  ),
  surfaceWidget: 'SlotLocalSurface',
);

final slotLocalPlacementDefinition = () => _slotLocalPlacementDefinitionValue;

const restageIslands$slot__local_ValueListenableBuilder_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'slot__local_ValueListenableBuilder_0',
              builder: _restageIsland$slot__local_ValueListenableBuilder_0)
        ],
        islands: true);

Widget _restageIsland$slot__local_ValueListenableBuilder_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'slot__local_ValueListenableBuilder_0',
        '`ValueListenableBuilder` (lib/surfaces/builder_slots.dart:132:7) needs app code that only `SlotLocalSurface` provides. Try using `SlotLocalSurface` to build this screen.',
        context,
        source);

Widget restagePreview$slot__local_ValueListenableBuilder_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageBuilderBinding.construct((_restageBindings) {
      final _restageBinding$builder = RestageBuilderBinding(
          RestageValueBinding.dataSource(restageSource, restageContext),
          const <Object>['builder'],
          contract: const WidgetBuilderContract(parameters: [
            WidgetBuilderParameter.buildContext,
            WidgetBuilderParameter.data,
            WidgetBuilderParameter.child
          ]),
          data: const <String, ValueType>{'arg1': ValueType('int')});
      _restageBindings.add(_restageBinding$builder);
      return ValueListenableBuilder<int>(
        valueListenable: slotCount,
        builder: (_restageArg0, _restageArg1, _restageArg2) =>
            _restageBinding$builder
                .build(_restageArg0, <String, Object?>{'arg1': _restageArg1}),
      );
    });

final class SlotLocalSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const SlotLocalSurface({
    required String label,
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored0 = label,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [SlotLocalSurface] for the default placement; no name is needed.
  const SlotLocalSurface.atPlacement(
    String restagePlacementId, {
    required String label,
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored0 = label,
        _restagePlacementName = restagePlacementId;

  final String _restageStored0;
  String get _restageArgument0 => _restageStored0;
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
        libraries: [restageIslands$slot__local_ValueListenableBuilder_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'slot_local',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: slotLocalPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'label': _restageArgument0,
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
            'slot__local_ValueListenableBuilder_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'slot__local_ValueListenableBuilder_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() {
      final shown = _shout(_restageArgument0);
      return _restageDesign(Column(children: [
        const Text('local'),
        _restageRecording.island(
            'slot__local_ValueListenableBuilder_0',
            _restageRecording.built(
                RestageBuilderBinding.retain(const [],
                    child: ValueListenableBuilder<int>(
                      valueListenable: slotCount,
                      builder: (context, count, child) => Text('$shown $count'),
                    )),
                (_restageContext, _restageSource) =>
                    RestageBuilderBinding.construct((_restageBindings) {
                      final _restageBinding$builder = RestageBuilderBinding(
                          RestageValueBinding.dataSource(
                              _restageSource, _restageContext),
                          const <Object>['builder'],
                          contract: const WidgetBuilderContract(parameters: [
                            WidgetBuilderParameter.buildContext,
                            WidgetBuilderParameter.data,
                            WidgetBuilderParameter.child
                          ]),
                          data: const <String, ValueType>{
                            'arg1': ValueType('int')
                          });
                      _restageBindings.add(_restageBinding$builder);
                      return ValueListenableBuilder<int>(
                        valueListenable: slotCount,
                        builder: (context, count, child) {
                          final _restageSlotRecording = RestageRecording();
                          _restageRender(Object? _) =>
                              _restageBinding$builder.build(
                                  context, <String, Object?>{'arg1': count},
                                  recorded: _restageSlotRecording.values);
                          return _restageRender(Text(
                              '${_restageSlotRecording.value('_hff3591907e', shown)} $count'));
                        },
                      );
                    }))),
      ]));
    })();
  }
}

final _slotMixedPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'slot_mixed',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'slot_mixed',
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
        'label': <String, Object?>{'kind': 'string'}
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'islands': <String, Object?>{
      'restage_example.islands:slot__mixed_ValueListenableBuilder_0':
          'w11186054'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$slot__mixed_ValueListenableBuilder_0],
  ),
  surfaceWidget: 'SlotMixedSurface',
);

final slotMixedPlacementDefinition = () => _slotMixedPlacementDefinitionValue;

const restageIslands$slot__mixed_ValueListenableBuilder_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'slot__mixed_ValueListenableBuilder_0',
              builder: _restageIsland$slot__mixed_ValueListenableBuilder_0)
        ],
        islands: true);

Widget _restageIsland$slot__mixed_ValueListenableBuilder_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'slot__mixed_ValueListenableBuilder_0',
        '`ValueListenableBuilder` (lib/surfaces/builder_slots.dart:109:9) needs app code that only `SlotMixedSurface` provides. Try using `SlotMixedSurface` to build this screen.',
        context,
        source);

Widget restagePreview$slot__mixed_ValueListenableBuilder_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageBuilderBinding.construct((_restageBindings) {
      final _restageBinding$builder = RestageBuilderBinding(
          RestageValueBinding.dataSource(restageSource, restageContext),
          const <Object>['builder'],
          contract: const WidgetBuilderContract(parameters: [
            WidgetBuilderParameter.buildContext,
            WidgetBuilderParameter.data,
            WidgetBuilderParameter.child
          ]),
          data: const <String, ValueType>{'arg1': ValueType('int')});
      _restageBindings.add(_restageBinding$builder);
      return ValueListenableBuilder<int>(
        valueListenable: slotCount,
        builder: (_restageArg0, _restageArg1, _restageArg2) =>
            _restageBinding$builder
                .build(_restageArg0, <String, Object?>{'arg1': _restageArg1}),
      );
    });

final class SlotMixedSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const SlotMixedSurface({
    required String label,
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored0 = label,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [SlotMixedSurface] for the default placement; no name is needed.
  const SlotMixedSurface.atPlacement(
    String restagePlacementId, {
    required String label,
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored0 = label,
        _restagePlacementName = restagePlacementId;

  final String _restageStored0;
  String get _restageArgument0 => _restageStored0;
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
        libraries: [restageIslands$slot__mixed_ValueListenableBuilder_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'slot_mixed',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: slotMixedPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'label': _restageArgument0,
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
            'slot__mixed_ValueListenableBuilder_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'slot__mixed_ValueListenableBuilder_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          const Text('mixed'),
          _restageRecording.island(
              'slot__mixed_ValueListenableBuilder_0',
              _restageRecording.built(
                  RestageBuilderBinding.retain(const [],
                      child: ValueListenableBuilder<int>(
                        valueListenable: slotCount,
                        builder: (context, count, child) =>
                            Text('${_restageArgument0} $count'),
                      )),
                  (_restageContext, _restageSource) =>
                      RestageBuilderBinding.construct((_restageBindings) {
                        final _restageBinding$builder = RestageBuilderBinding(
                            RestageValueBinding.dataSource(
                                _restageSource, _restageContext),
                            const <Object>['builder'],
                            contract: const WidgetBuilderContract(parameters: [
                              WidgetBuilderParameter.buildContext,
                              WidgetBuilderParameter.data,
                              WidgetBuilderParameter.child
                            ]),
                            data: const <String, ValueType>{
                              'arg1': ValueType('int')
                            });
                        _restageBindings.add(_restageBinding$builder);
                        return ValueListenableBuilder<int>(
                          valueListenable: slotCount,
                          builder: (context, count, child) {
                            final _restageSlotRecording = RestageRecording();
                            _restageRender(Object? _) =>
                                _restageBinding$builder.build(
                                    context, <String, Object?>{'arg1': count},
                                    recorded: _restageSlotRecording.values);
                            return _restageRender(
                                Text('${_restageArgument0} $count'));
                          },
                        );
                      }))),
        ])))();
  }
}

final _slotPlanCardPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'slot_plan',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'slot_plan',
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
      'restage_example.islands:slot__plan_ValueListenableBuilder_0':
          'w118236790'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$slot__plan_ValueListenableBuilder_0],
  ),
  surfaceWidget: 'SlotPlanCardSurface',
);

final slotPlanCardPlacementDefinition =
    () => _slotPlanCardPlacementDefinitionValue;

const restageIslands$slot__plan_ValueListenableBuilder_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'slot__plan_ValueListenableBuilder_0',
              builder: _restageIsland$slot__plan_ValueListenableBuilder_0)
        ],
        islands: true);

Widget _restageIsland$slot__plan_ValueListenableBuilder_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'slot__plan_ValueListenableBuilder_0',
        '`ValueListenableBuilder` (lib/surfaces/builder_slots.dart:68:9) needs app code that only `SlotPlanCardSurface` provides. Try using `SlotPlanCardSurface` to build this screen.',
        context,
        source);

Widget restagePreview$slot__plan_ValueListenableBuilder_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageBuilderBinding.construct((_restageBindings) {
      final _restageBinding$builder = RestageBuilderBinding(
          RestageValueBinding.dataSource(restageSource, restageContext),
          const <Object>['builder'],
          contract: const WidgetBuilderContract(parameters: [
            WidgetBuilderParameter.buildContext,
            WidgetBuilderParameter.data,
            WidgetBuilderParameter.child
          ]),
          data: const <String, ValueType>{
            'arg1': ValueType('record', fields: {
              'name': ValueType('String'),
              'price': ValueType('int'),
              'tier': ValueType('String'),
              'features': ValueType('list', item: ValueType('String')),
              'accent': ValueType('record', fields: {
                'a': ValueType('double'),
                'r': ValueType('double'),
                'g': ValueType('double'),
                'b': ValueType('double'),
                'colorSpace': ValueType('String'),
                'material': ValueType('String')
              })
            })
          });
      _restageBindings.add(_restageBinding$builder);
      return ValueListenableBuilder<SlotPlan>(
        valueListenable: slotPlan,
        builder: (_restageArg0, _restageArg1, _restageArg2) =>
            _restageBinding$builder.build(_restageArg0, <String, Object?>{
          'arg1': <String, Object?>{
            'name': _restageArg1.name,
            'price': _restageArg1.price,
            'tier': _restageArg1.tier.name,
            'features': <Object?>[
              for (final _restageItem1 in _restageArg1.features) _restageItem1
            ],
            'accent': RestageBuilderBinding.color(_restageArg1.accent)
          }
        }),
      );
    });

final class SlotPlanCardSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const SlotPlanCardSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [SlotPlanCardSurface] for the default placement; no name is needed.
  const SlotPlanCardSurface.atPlacement(
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
        libraries: [restageIslands$slot__plan_ValueListenableBuilder_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'slot_plan',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: slotPlanCardPlacementDefinition,
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
            'slot__plan_ValueListenableBuilder_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'slot__plan_ValueListenableBuilder_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          const Text('plans'),
          _restageRecording.island(
              'slot__plan_ValueListenableBuilder_0',
              _restageRecording.built(
                  RestageBuilderBinding.retain(const [],
                      child: ValueListenableBuilder<SlotPlan>(
                        valueListenable: slotPlan,
                        builder: (context, plan, child) => Column(children: [
                          Text('${plan.name} ${plan.price} ${plan.tier.name}',
                              style: TextStyle(color: plan.accent)),
                          Text('${plan.features.length} features'),
                        ]),
                      )),
                  (_restageContext, _restageSource) =>
                      RestageBuilderBinding.construct((_restageBindings) {
                        final _restageBinding$builder = RestageBuilderBinding(
                            RestageValueBinding.dataSource(
                                _restageSource, _restageContext),
                            const <Object>['builder'],
                            contract: const WidgetBuilderContract(parameters: [
                              WidgetBuilderParameter.buildContext,
                              WidgetBuilderParameter.data,
                              WidgetBuilderParameter.child
                            ]),
                            data: const <String, ValueType>{
                              'arg1': ValueType('record', fields: {
                                'name': ValueType('String'),
                                'price': ValueType('int'),
                                'tier': ValueType('String'),
                                'features': ValueType('list',
                                    item: ValueType('String')),
                                'accent': ValueType('record', fields: {
                                  'a': ValueType('double'),
                                  'r': ValueType('double'),
                                  'g': ValueType('double'),
                                  'b': ValueType('double'),
                                  'colorSpace': ValueType('String'),
                                  'material': ValueType('String')
                                })
                              })
                            });
                        _restageBindings.add(_restageBinding$builder);
                        return ValueListenableBuilder<SlotPlan>(
                          valueListenable: slotPlan,
                          builder: (context, plan, child) {
                            final _restageSlotRecording = RestageRecording();
                            _restageRender(Object? _) =>
                                _restageBinding$builder.build(
                                    context,
                                    <String, Object?>{
                                      'arg1': <String, Object?>{
                                        'name': plan.name,
                                        'price': plan.price,
                                        'tier': plan.tier.name,
                                        'features': <Object?>[
                                          for (final _restageItem1
                                              in plan.features)
                                            _restageItem1
                                        ],
                                        'accent': RestageBuilderBinding.color(
                                            plan.accent)
                                      }
                                    },
                                    recorded: _restageSlotRecording.values);
                            return _restageRender(Column(children: [
                              Text(
                                  '${plan.name} ${plan.price} ${plan.tier.name}',
                                  style: TextStyle(color: plan.accent)),
                              Text('${plan.features.length} features'),
                            ]));
                          },
                        );
                      }))),
        ])))();
  }
}

final _slotTweenEndPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'slot_tween_end',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'slot_tween_end',
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
      'restage_example.islands:slot__tween__end_TweenAnimationBuilder_0':
          'w231241861'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$slot__tween__end_TweenAnimationBuilder_0],
  ),
  surfaceWidget: 'SlotTweenEndSurface',
);

final slotTweenEndPlacementDefinition =
    () => _slotTweenEndPlacementDefinitionValue;

const restageIslands$slot__tween__end_TweenAnimationBuilder_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'slot__tween__end_TweenAnimationBuilder_0',
              builder: _restageIsland$slot__tween__end_TweenAnimationBuilder_0)
        ],
        islands: true);

Widget _restageIsland$slot__tween__end_TweenAnimationBuilder_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'slot__tween__end_TweenAnimationBuilder_0',
        '`TweenAnimationBuilder` (lib/surfaces/builder_slots.dart:222:9) needs app code that only `SlotTweenEndSurface` provides. Try using `SlotTweenEndSurface` to build this screen.',
        context,
        source);

Widget restagePreview$slot__tween__end_TweenAnimationBuilder_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageBuilderBinding.construct((_restageBindings) {
      final _restageBinding$builder = RestageBuilderBinding(
          RestageValueBinding.dataSource(restageSource, restageContext),
          const <Object>['builder'],
          contract: const WidgetBuilderContract(parameters: [
            WidgetBuilderParameter.buildContext,
            WidgetBuilderParameter.data,
            WidgetBuilderParameter.child
          ]),
          data: const <String, ValueType>{'arg1': ValueType('double')});
      _restageBindings.add(_restageBinding$builder);
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: slotEnd()),
        duration: (RestageDecoders.duration(
                restageSource, const <Object>['duration']) ??
            const Duration(seconds: 1)),
        builder: (_restageArg0, _restageArg1, _restageArg2) =>
            _restageBinding$builder
                .build(_restageArg0, <String, Object?>{'arg1': _restageArg1}),
      );
    });

final class SlotTweenEndSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const SlotTweenEndSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [SlotTweenEndSurface] for the default placement; no name is needed.
  const SlotTweenEndSurface.atPlacement(
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
        libraries: [restageIslands$slot__tween__end_TweenAnimationBuilder_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'slot_tween_end',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: slotTweenEndPlacementDefinition,
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
            'slot__tween__end_TweenAnimationBuilder_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'slot__tween__end_TweenAnimationBuilder_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          const Text('tween end'),
          _restageRecording.island(
              'slot__tween__end_TweenAnimationBuilder_0',
              restageOnce<(Tween<double>,), Widget>(
                  (Tween(begin: 0, end: slotEnd()),),
                  (_restageArgs) => _restageRecording.built(
                      RestageBuilderBinding.retain(const [],
                          child: TweenAnimationBuilder<double>(
                            tween: _restageArgs.$1,
                            duration: const Duration(seconds: 1),
                            builder: (context, value, child) =>
                                Text('t ${value.round()}'),
                          )),
                      (_restageContext, _restageSource) =>
                          RestageBuilderBinding.construct((_restageBindings) {
                            final _restageBinding$builder =
                                RestageBuilderBinding(
                                    RestageValueBinding.dataSource(
                                        _restageSource, _restageContext),
                                    const <Object>['builder'],
                                    contract: const WidgetBuilderContract(
                                        parameters: [
                                          WidgetBuilderParameter.buildContext,
                                          WidgetBuilderParameter.data,
                                          WidgetBuilderParameter.child
                                        ]),
                                    data: const <String, ValueType>{
                                      'arg1': ValueType('double')
                                    });
                            _restageBindings.add(_restageBinding$builder);
                            return TweenAnimationBuilder<double>(
                              tween: _restageArgs.$1,
                              duration: (RestageDecoders.duration(
                                      _restageSource,
                                      const <Object>['duration']) ??
                                  const Duration(seconds: 1)),
                              builder: (context, value, child) {
                                final _restageSlotRecording =
                                    RestageRecording();
                                _restageRender(Object? _) =>
                                    _restageBinding$builder.build(context,
                                        <String, Object?>{'arg1': value},
                                        recorded: _restageSlotRecording.values);
                                return _restageRender(
                                    Text('t ${value.round()}'));
                              },
                            );
                          })))),
        ])))();
  }
}

final _slotTweenPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'slot_tween',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'slot_tween',
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
      'restage_example.islands:slot__tween_TweenAnimationBuilder_0':
          'w233074544'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$slot__tween_TweenAnimationBuilder_0],
  ),
  surfaceWidget: 'SlotTweenSurface',
);

final slotTweenPlacementDefinition = () => _slotTweenPlacementDefinitionValue;

const restageIslands$slot__tween_TweenAnimationBuilder_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'slot__tween_TweenAnimationBuilder_0',
              builder: _restageIsland$slot__tween_TweenAnimationBuilder_0)
        ],
        islands: true);

Widget _restageIsland$slot__tween_TweenAnimationBuilder_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'slot__tween_TweenAnimationBuilder_0',
        '`TweenAnimationBuilder` (lib/surfaces/builder_slots.dart:239:9) needs app code that only `SlotTweenSurface` provides. Try using `SlotTweenSurface` to build this screen.',
        context,
        source);

Widget restagePreview$slot__tween_TweenAnimationBuilder_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageBuilderBinding.construct((_restageBindings) {
      final _restageBinding$builder = RestageBuilderBinding(
          RestageValueBinding.dataSource(restageSource, restageContext),
          const <Object>['builder'],
          contract: const WidgetBuilderContract(parameters: [
            WidgetBuilderParameter.buildContext,
            WidgetBuilderParameter.data,
            WidgetBuilderParameter.child
          ]),
          data: const <String, ValueType>{'arg1': ValueType('double')});
      _restageBindings.add(_restageBinding$builder);
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 100),
        duration: (RestageDecoders.duration(
                restageSource, const <Object>['duration']) ??
            const Duration(seconds: 1)),
        builder: (_restageArg0, _restageArg1, _restageArg2) =>
            _restageBinding$builder
                .build(_restageArg0, <String, Object?>{'arg1': _restageArg1}),
      );
    });

final class SlotTweenSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const SlotTweenSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [SlotTweenSurface] for the default placement; no name is needed.
  const SlotTweenSurface.atPlacement(
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
        libraries: [restageIslands$slot__tween_TweenAnimationBuilder_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'slot_tween',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: slotTweenPlacementDefinition,
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
            'slot__tween_TweenAnimationBuilder_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'slot__tween_TweenAnimationBuilder_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          const Text('tween'),
          _restageRecording.island(
              'slot__tween_TweenAnimationBuilder_0',
              _restageRecording.built(
                  RestageBuilderBinding.retain(const [],
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 100),
                        duration: const Duration(seconds: 1),
                        builder: (context, value, child) =>
                            Text('t ${value.round()}'),
                      )),
                  (_restageContext, _restageSource) =>
                      RestageBuilderBinding.construct((_restageBindings) {
                        final _restageBinding$builder = RestageBuilderBinding(
                            RestageValueBinding.dataSource(
                                _restageSource, _restageContext),
                            const <Object>['builder'],
                            contract: const WidgetBuilderContract(parameters: [
                              WidgetBuilderParameter.buildContext,
                              WidgetBuilderParameter.data,
                              WidgetBuilderParameter.child
                            ]),
                            data: const <String, ValueType>{
                              'arg1': ValueType('double')
                            });
                        _restageBindings.add(_restageBinding$builder);
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 100),
                          duration: (RestageDecoders.duration(
                                  _restageSource, const <Object>['duration']) ??
                              const Duration(seconds: 1)),
                          builder: (context, value, child) {
                            final _restageSlotRecording = RestageRecording();
                            _restageRender(Object? _) =>
                                _restageBinding$builder.build(
                                    context, <String, Object?>{'arg1': value},
                                    recorded: _restageSlotRecording.values);
                            return _restageRender(Text('t ${value.round()}'));
                          },
                        );
                      }))),
        ])))();
  }
}
