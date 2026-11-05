part of '../guarded_reads.dart';

// ignore_for_file: type=lint, unnecessary_cast

final _readAndLocalPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_and_local',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_and_local',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadAndLocal.build takes'
        },
        '_hb63f5b2f51': <String, Object?>{
          'kind': 'string',
          'label': 'o.features.first'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_hb63f5b2f51': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadAndLocal.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'o != null && o.features.isNotEmpty',
            'plain': 'when `o != null && o.features.isNotEmpty`',
            'location': 'lib/surfaces/guarded_reads.dart:1183:9'
          },
          '1': <String, Object?>{
            'source': '!(o != null && o.features.isNotEmpty)',
            'plain': 'when `!(o != null && o.features.isNotEmpty)`',
            'location': 'lib/surfaces/guarded_reads.dart:1183:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadAndLocalSurface',
);

final readAndLocalPlacementDefinition =
    () => _readAndLocalPlacementDefinitionValue;

final class ReadAndLocalSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadAndLocalSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadAndLocalSurface] for the default placement; no name is needed.
  const ReadAndLocalSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_and_local',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readAndLocalPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      final o = _restageArgument1;
      if (o != null && o.features.isNotEmpty)
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_hb63f5b2f51', o.features.first))));
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readBlockContextPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_block_context',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_block_context',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadBlockContext.build takes'
        },
        '_he7c25867b2': <String, Object?>{'kind': 'string', 'label': 'context'},
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_he7c25867b2': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadBlockContext.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:651:9'
          },
          '1': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:651:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Padding': buildPadding,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadBlockContextSurface',
);

final readBlockContextPlacementDefinition =
    () => _readBlockContextPlacementDefinitionValue;

final class ReadBlockContextSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadBlockContextSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadBlockContextSurface] for the default placement; no name is needed.
  const ReadBlockContextSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Padding': buildPadding,
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_block_context',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readBlockContextPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 != null) {
        final context = _restageArgument1!.features.first;
        return _restageDesign(_restageRecording.branch(
            '_h34a704d316',
            0,
            _Framed(
                child:
                    Text(_restageRecording.value('_he7c25867b2', context)))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readBlockDestructurePlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_block_destructure',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_block_destructure',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadBlockDestructure.build takes'
        },
        '_h9e40506b49': <String, Object?>{
          'kind': 'string',
          'label': '\'\$count \$first\''
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h9e40506b49': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadBlockDestructure.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:796:9'
          },
          '1': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:796:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
        'TextRich': buildTextRich,
      },
    ),
  ),
  surfaceWidget: 'ReadBlockDestructureSurface',
);

final readBlockDestructurePlacementDefinition =
    () => _readBlockDestructurePlacementDefinitionValue;

final class ReadBlockDestructureSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadBlockDestructureSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadBlockDestructureSurface] for the default placement; no name is needed.
  const ReadBlockDestructureSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
            'TextRich': buildTextRich,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_block_destructure',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readBlockDestructurePlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 != null) {
        final (count, first) = (
          _restageArgument1!.features.length,
          _restageArgument1!.features.first
        );
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_h9e40506b49', '$count $first'))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readBlockFramedPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_block_framed',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_block_framed',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadBlockFramed.build takes'
        },
        '_h3a4c33dc33': <String, Object?>{
          'kind': 'string',
          'label': 'features.first'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h3a4c33dc33': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadBlockFramed.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:437:9'
          },
          '1': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:437:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Padding': buildPadding,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadBlockFramedSurface',
);

final readBlockFramedPlacementDefinition =
    () => _readBlockFramedPlacementDefinitionValue;

final class ReadBlockFramedSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadBlockFramedSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadBlockFramedSurface] for the default placement; no name is needed.
  const ReadBlockFramedSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Padding': buildPadding,
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_block_framed',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readBlockFramedPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 != null) {
        final features = _restageArgument1!.features;
        return _restageDesign(_restageRecording.branch(
            '_h34a704d316',
            0,
            _Framed(
                child: Text(
                    _restageRecording.value('_h3a4c33dc33', features.first)))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readBlockLoopPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_block_loop',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_block_loop',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadBlockLoop.build takes'
        },
        '_h49e8512e19': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_hc99a4c3b13': <String, Object?>{'kind': 'string', 'label': 'f'}
            }
          }
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h49e8512e19': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        },
        '_hc99a4c3b13': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadBlockLoop.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:456:9'
          },
          '1': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:456:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadBlockLoopSurface',
);

final readBlockLoopPlacementDefinition =
    () => _readBlockLoopPlacementDefinitionValue;

final class ReadBlockLoopSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadBlockLoopSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadBlockLoopSurface] for the default placement; no name is needed.
  const ReadBlockLoopSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
        id: 'read_block_loop',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readBlockLoopPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 != null) {
        final features = _restageArgument1!.features;
        return _restageDesign(_restageRecording.branch(
            '_h34a704d316',
            0,
            Column(children: [
              for (final f in _restageRecording.items('_h49e8512e19', features))
                Text(_restageRecording.value('_hc99a4c3b13', f, '_h49e8512e19'))
            ])));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readBlockSameNamePlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_block_same_name',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_block_same_name',
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
        '_h1ec0995fee': <String, Object?>{'kind': 'string', 'label': 'label'},
        '_h24e4b444a0': <String, Object?>{'kind': 'string', 'label': 'label'},
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadBlockSameName.build takes'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        },
        'title': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{'kind': 'string'}
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1, 2]
      },
      'values': <String, Object?>{
        '_h1ec0995fee': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        },
        '_h24e4b444a0': <String, Object?>{
          '_h34a704d316': <Object?>[1]
        }
      },
      'build': 'ReadBlockSameName.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:497:9'
          },
          '1': <String, Object?>{
            'source': 'title != null',
            'plain': 'when there\'s a title',
            'location': 'lib/surfaces/guarded_reads.dart:501:9'
          },
          '2': <String, Object?>{
            'source': 'title == null',
            'plain': 'when `title == null`',
            'location': 'lib/surfaces/guarded_reads.dart:501:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadBlockSameNameSurface',
);

final readBlockSameNamePlacementDefinition =
    () => _readBlockSameNamePlacementDefinitionValue;

final class ReadBlockSameNameSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadBlockSameNameSurface({
    super.key,
    ReadOffer? offer,
    String? title,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restageStored2 = title,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadBlockSameNameSurface] for the default placement; no name is needed.
  const ReadBlockSameNameSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    String? title,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restageStored2 = title,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;

  final String? _restageStored2;
  String? get _restageArgument2 => _restageStored2;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_block_same_name',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readBlockSameNamePlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
          'title': _restageArgument2,
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

    return (() {
      if (_restageArgument1 != null) {
        final label = _restageArgument1!.features.first;
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_h1ec0995fee', label))));
      }
      if (_restageArgument2 != null) {
        final label = _restageArgument2!;
        return _restageDesign(_restageRecording.branch('_h34a704d316', 1,
            Text(_restageRecording.value('_h24e4b444a0', label))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 2, const Text('none')));
    })();
  }
}

final _readBlockShadowPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_block_shadow',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_block_shadow',
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
        '_h24e4b444a0': <String, Object?>{'kind': 'string', 'label': 'label'},
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadBlockShadow.build takes'
        },
        '_h9b30c11823': <String, Object?>{'kind': 'string', 'label': 'label'},
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h24e4b444a0': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        },
        '_h9b30c11823': <String, Object?>{
          '_h34a704d316': <Object?>[1]
        }
      },
      'build': 'ReadBlockShadow.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:521:9'
          },
          '1': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:521:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadBlockShadowSurface',
);

final readBlockShadowPlacementDefinition =
    () => _readBlockShadowPlacementDefinitionValue;

final class ReadBlockShadowSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadBlockShadowSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadBlockShadowSurface] for the default placement; no name is needed.
  const ReadBlockShadowSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_block_shadow',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readBlockShadowPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      final label = _fallbackLabel();
      if (_restageArgument1 != null) {
        final label = _restageArgument1!.features.first;
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_h24e4b444a0', label))));
      }
      return _restageDesign(_restageRecording.branch('_h34a704d316', 1,
          Text(_restageRecording.value('_h9b30c11823', label))));
    })();
  }
}

final _readBlockTextPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_block_text',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_block_text',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadBlockText.build takes'
        },
        '_h3a4c33dc33': <String, Object?>{
          'kind': 'string',
          'label': 'features.first'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h3a4c33dc33': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadBlockText.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:475:9'
          },
          '1': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:475:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadBlockTextSurface',
);

final readBlockTextPlacementDefinition =
    () => _readBlockTextPlacementDefinitionValue;

final class ReadBlockTextSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadBlockTextSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadBlockTextSurface] for the default placement; no name is needed.
  const ReadBlockTextSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_block_text',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readBlockTextPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 != null) {
        final features = _restageArgument1!.features;
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_h3a4c33dc33', features.first))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readBuildContextPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_build_context',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_build_context',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadBuildContext.build takes'
        },
        '_he6ee8cebda': <String, Object?>{'kind': 'string', 'label': 'context'},
        'flag': <String, Object?>{'kind': 'bool'},
        'title': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{'kind': 'string'}
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_he6ee8cebda': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadBuildContext.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'flag',
            'plain': 'when flag is on',
            'location': 'lib/surfaces/guarded_reads.dart:674:9'
          },
          '1': <String, Object?>{
            'source': '!flag',
            'plain': 'when flag is off',
            'location': 'lib/surfaces/guarded_reads.dart:674:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Padding': buildPadding,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadBuildContextSurface',
);

final readBuildContextPlacementDefinition =
    () => _readBuildContextPlacementDefinitionValue;

const bool _readBuildContextMountDefault2 = false;

final class ReadBuildContextSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadBuildContextSurface({
    super.key,
    String? title,
    bool flag = _readBuildContextMountDefault2,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restageStored2 = flag,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadBuildContextSurface] for the default placement; no name is needed.
  const ReadBuildContextSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    String? title,
    bool flag = _readBuildContextMountDefault2,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restageStored2 = flag,
        _restagePlacementName = restagePlacementId;

  final String? _restageStored1;
  String? get _restageArgument1 => _restageStored1;

  final bool _restageStored2;
  bool get _restageArgument2 => _restageStored2;
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
            'Padding': buildPadding,
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_build_context',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readBuildContextPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'title': _restageArgument1,
          'flag': _restageArgument2,
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

    return (() {
      final context = _restageArgument1 ?? 'Untitled';
      if (_restageArgument2) {
        return _restageDesign(_restageRecording.branch(
            '_h34a704d316',
            0,
            _Framed(
                child:
                    Text(_restageRecording.value('_he6ee8cebda', context)))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readBuilderRerunPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_builder_rerun',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_builder_rerun',
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
        '_h2946ebb379': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{'kind': 'string'},
          'label': 'names'
        },
        '_h4b2be16b04': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h7fa9756b72': <String, Object?>{
                'kind': 'string',
                'label': '_shoutName(name)'
              }
            }
          }
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
  surfaceWidget: 'ReadBuilderRerunSurface',
);

final readBuilderRerunPlacementDefinition =
    () => _readBuilderRerunPlacementDefinitionValue;

final class ReadBuilderRerunSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadBuilderRerunSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadBuilderRerunSurface] for the default placement; no name is needed.
  const ReadBuilderRerunSurface.atPlacement(
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
        id: 'read_builder_rerun',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readBuilderRerunPlacementDefinition,
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

    return (() => ValueListenableBuilder<List<String>>(
          valueListenable: readNames,
          builder: (context, names, child) =>
              (_restageRecording..frame(0)).exposing(
                  {'_h2946ebb379': names},
                  _restageDesign(Column(children: [
                    for (final name
                        in _restageRecording.items('_h4b2be16b04', names))
                      Text(_restageRecording.value(
                          '_h7fa9756b72', _shoutName(name), '_h4b2be16b04')),
                  ]))),
        ))();
  }
}

final _readBuilderRowsPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_builder_rows',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_builder_rows',
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
      'restage_example.islands:read__builder__rows__Repeat_0': 'w97801272'
    }
  },
  vocabulary: const SurfaceVocabulary(
    libraries: [restageIslands$read__builder__rows__Repeat_0],
  ),
  surfaceWidget: 'ReadBuilderRowsSurface',
);

final readBuilderRowsPlacementDefinition =
    () => _readBuilderRowsPlacementDefinitionValue;

const restageIslands$read__builder__rows__Repeat_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'read__builder__rows__Repeat_0',
              builder: _restageIsland$read__builder__rows__Repeat_0)
        ],
        islands: true);

Widget _restageIsland$read__builder__rows__Repeat_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'read__builder__rows__Repeat_0',
        '`_Repeat` (lib/surfaces/guarded_reads.dart:1749:7) needs app code that only `ReadBuilderRowsSurface` provides. Try using `ReadBuilderRowsSurface` to build this screen.',
        context,
        source);

Widget restagePreview$read__builder__rows__Repeat_0(
        BuildContext restageContext, DataSource restageSource) =>
    _Repeat(builder: (context, index) => Text(_labelFor(index)));

final class ReadBuilderRowsSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadBuilderRowsSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadBuilderRowsSurface] for the default placement; no name is needed.
  const ReadBuilderRowsSurface.atPlacement(
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
        libraries: [restageIslands$read__builder__rows__Repeat_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_builder_rows',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readBuilderRowsPlacementDefinition,
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
            'read__builder__rows__Repeat_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'read__builder__rows__Repeat_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(_restageRecording.island(
        'read__builder__rows__Repeat_0',
        _Repeat(builder: (context, index) => Text(_labelFor(index))))))();
  }
}

final _readBuilderSlotPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_builder_slot',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_builder_slot',
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
      'restage_example.islands:read__builder__slot__Signal_0': 'w266851711'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Expanded': buildExpanded,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$read__builder__slot__Signal_0],
  ),
  surfaceWidget: 'ReadBuilderSlotSurface',
);

final readBuilderSlotPlacementDefinition =
    () => _readBuilderSlotPlacementDefinitionValue;

const restageIslands$read__builder__slot__Signal_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'read__builder__slot__Signal_0',
              builder: _restageIsland$read__builder__slot__Signal_0)
        ],
        islands: true);

Widget _restageIsland$read__builder__slot__Signal_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'read__builder__slot__Signal_0',
        '`_Signal` (lib/surfaces/guarded_reads.dart:1731:18) needs app code that only `ReadBuilderSlotSurface` provides. Try using `ReadBuilderSlotSurface` to build this screen.',
        context,
        source);

Widget restagePreview$read__builder__slot__Signal_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageIslandPlaceholder(label: '_Signal', children: []);

final class ReadBuilderSlotSurface extends StatefulWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadBuilderSlotSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadBuilderSlotSurface] for the default placement; no name is needed.
  const ReadBuilderSlotSurface.atPlacement(
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
  _ReadBuilderSlotSurfaceState createState() => _ReadBuilderSlotSurfaceState();
}

final class _ReadBuilderSlotSurfaceState extends State<ReadBuilderSlotSurface> {
  // ignore: unused_element
  final ScrollController _scroll = ScrollController();

  // ignore: unused_element
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'Expanded': buildExpanded,
            'Text': buildText,
          },
        ),
        libraries: [restageIslands$read__builder__slot__Signal_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_builder_slot',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readBuilderSlotPlacementDefinition,
          name: widget._restagePlacementName,
        ),
        fallbackBuilder: (_) => _restageBuilt,
        onEvent: widget.onEvent,
        resolver: widget.resolver,
        errorBuilder: widget.errorBuilder,
        loadingBuilder: widget.loadingBuilder,
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {
            'read__builder__slot__Signal_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'read__builder__slot__Signal_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          const Text('head'),
          Expanded(
            child: _restageRecording.island('read__builder__slot__Signal_0',
                _Signal(builder: (context, count) {
              final ink = _ink();
              return ListView(controller: _scroll, children: [
                Text('count $count', style: TextStyle(color: ink)),
              ]);
            })),
          ),
        ])))();
  }
}

final _readBuilderValuesPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_builder_values',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_builder_values',
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
        '_h2e087fce61': <String, Object?>{
          'kind': 'string',
          'label': '\'count \$count\''
        },
        '_h2e5a45b5e6': <String, Object?>{'kind': 'int', 'label': 'count'},
        '_h35ffc24007': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'flutter.Color',
            'nullable': false
          },
          'label': '_muted()'
        },
        '_h8604b300d0': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'flutter.ScrollController',
            'nullable': false
          },
          'label': '_scroll'
        },
        '_hdbe6fdefdf': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'flutter.Color',
            'nullable': false
          },
          'label': '_ink()'
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
        'ListView': buildListView,
        'Padding': buildPadding,
        'Text': buildText,
        'TextRich': buildTextRich,
      },
    ),
  ),
  surfaceWidget: 'ReadBuilderValuesSurface',
);

final readBuilderValuesPlacementDefinition =
    () => _readBuilderValuesPlacementDefinitionValue;

final class ReadBuilderValuesSurface extends StatefulWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadBuilderValuesSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadBuilderValuesSurface] for the default placement; no name is needed.
  const ReadBuilderValuesSurface.atPlacement(
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
  _ReadBuilderValuesSurfaceState createState() =>
      _ReadBuilderValuesSurfaceState();
}

final class _ReadBuilderValuesSurfaceState
    extends State<ReadBuilderValuesSurface> {
  // ignore: unused_element
  final ScrollController _scroll = ScrollController();

  // ignore: unused_element
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'ListView': buildListView,
            'Padding': buildPadding,
            'Text': buildText,
            'TextRich': buildTextRich,
          },
        ),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) => switch (key.split('#').first) {
                  '_h35ffc24007' => NativeBindingContract(
                      type: 'flutter.Color', nullable: false),
                  '_h8604b300d0' => NativeBindingContract(
                      type: 'flutter.ScrollController', nullable: false),
                  '_hdbe6fdefdf' => NativeBindingContract(
                      type: 'flutter.Color', nullable: false),
                  _ => throw StateError(key)
                },
            {}),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h35ffc24007': '_muted()',
                '_h8604b300d0': '_scroll',
                '_hdbe6fdefdf': '_ink()',
              },
        child: RestagePaywall(
          id: 'read_builder_values',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: readBuilderValuesPlacementDefinition,
            name: widget._restagePlacementName,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            '_h35ffc24007': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h35ffc24007',
              "type": 'flutter.Color',
              "nullable": false
            },
            '_h8604b300d0': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h8604b300d0',
              "type": 'flutter.ScrollController',
              "nullable": false
            },
            '_hdbe6fdefdf': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hdbe6fdefdf',
              "type": 'flutter.Color',
              "nullable": false
            },
          },
          fallbackBuilder: (_) => _restageBuilt,
          onEvent: widget.onEvent,
          resolver: widget.resolver,
          errorBuilder: widget.errorBuilder,
          loadingBuilder: widget.loadingBuilder,
        ),
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => SafeArea(
          child: _Listen(
            listener: (context, count) => guardedCalls.add('listen $count'),
            child: _Signal(builder: (context, count) {
              _restageRecording.frame(0);
              _restageRecording.exposing({'_h2e5a45b5e6': count}, null);
              final ink = _restageRecording.native('_hdbe6fdefdf', _ink(),
                  type: 'flutter.Color', nullable: false);
              final muted = _restageRecording.native('_h35ffc24007', _muted(),
                  type: 'flutter.Color', nullable: false);
              return _restageDesign(Padding(
                padding: const EdgeInsets.all(8),
                child: ListView(
                    controller: _restageRecording.native(
                        '_h8604b300d0', _scroll,
                        type: 'flutter.ScrollController', nullable: false),
                    children: [
                      Text(
                          _restageRecording.value(
                              '_h2e087fce61', 'count $count'),
                          style: TextStyle(color: ink)),
                      Text('muted', style: TextStyle(color: muted)),
                    ]),
              ));
            }),
          ),
        ))();
  }
}

final _readCaseFramedPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_case_framed',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_case_framed',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadCaseFramed.build takes'
        },
        '_hec9ea80feb': <String, Object?>{
          'kind': 'string',
          'label': 'o.features.first'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_hec9ea80feb': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadCaseFramed.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer case final o?',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:558:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Padding': buildPadding,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadCaseFramedSurface',
);

final readCaseFramedPlacementDefinition =
    () => _readCaseFramedPlacementDefinitionValue;

final class ReadCaseFramedSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadCaseFramedSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadCaseFramedSurface] for the default placement; no name is needed.
  const ReadCaseFramedSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Padding': buildPadding,
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_case_framed',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readCaseFramedPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 case final o?) {
        return _restageDesign(_restageRecording.branch(
            '_h34a704d316',
            0,
            _Framed(
                child: Text(_restageRecording.value(
                    '_hec9ea80feb', o.features.first)))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readCaseLoopPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_case_loop',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_case_loop',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadCaseLoop.build takes'
        },
        '_h4296377c19': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h6b0331d578': <String, Object?>{'kind': 'string', 'label': 'f'}
            }
          }
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h4296377c19': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        },
        '_h6b0331d578': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadCaseLoop.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer case final o?',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:576:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadCaseLoopSurface',
);

final readCaseLoopPlacementDefinition =
    () => _readCaseLoopPlacementDefinitionValue;

final class ReadCaseLoopSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadCaseLoopSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadCaseLoopSurface] for the default placement; no name is needed.
  const ReadCaseLoopSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
        id: 'read_case_loop',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readCaseLoopPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 case final o?) {
        return _restageDesign(_restageRecording.branch(
            '_h34a704d316',
            0,
            Column(children: [
              for (final f
                  in _restageRecording.items('_h4296377c19', o.features))
                Text(_restageRecording.value('_h6b0331d578', f, '_h4296377c19'))
            ])));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readCaseScorePlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_case_score',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_case_score',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadCaseScore.build takes'
        },
        '_hf3b000fb6d': <String, Object?>{'kind': 'string', 'label': '\'\$s\''},
        'score': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{'kind': 'string'}
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_hf3b000fb6d': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadCaseScore.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'double.tryParse(score ?? \'\') case final s?',
            'plain': 'when `double.tryParse(score ?? \'\') case final s?`',
            'location': 'lib/surfaces/guarded_reads.dart:815:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadCaseScoreSurface',
);

final readCaseScorePlacementDefinition =
    () => _readCaseScorePlacementDefinitionValue;

final class ReadCaseScoreSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadCaseScoreSurface({
    super.key,
    String? score,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = score,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadCaseScoreSurface] for the default placement; no name is needed.
  const ReadCaseScoreSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    String? score,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = score,
        _restagePlacementName = restagePlacementId;

  final String? _restageStored1;
  String? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_case_score',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readCaseScorePlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'score': _restageArgument1,
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

    return (() {
      if (double.tryParse(_restageArgument1 ?? '') case final s?) {
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_hf3b000fb6d', '$s'))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readCaseTextPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_case_text',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_case_text',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadCaseText.build takes'
        },
        '_hec9ea80feb': <String, Object?>{
          'kind': 'string',
          'label': 'o.features.first'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_hec9ea80feb': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadCaseText.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer case final o?',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:540:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadCaseTextSurface',
);

final readCaseTextPlacementDefinition =
    () => _readCaseTextPlacementDefinitionValue;

final class ReadCaseTextSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadCaseTextSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadCaseTextSurface] for the default placement; no name is needed.
  const ReadCaseTextSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_case_text',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readCaseTextPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 case final o?) {
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_hec9ea80feb', o.features.first))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readCaseWhenPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_case_when',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_case_when',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadCaseWhen.build takes'
        },
        '_hf8d90614a1': <String, Object?>{
          'kind': 'string',
          'label': 'o.features[1]'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_hf8d90614a1': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadCaseWhen.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer case final o?',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:594:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadCaseWhenSurface',
);

final readCaseWhenPlacementDefinition =
    () => _readCaseWhenPlacementDefinitionValue;

final class ReadCaseWhenSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadCaseWhenSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadCaseWhenSurface] for the default placement; no name is needed.
  const ReadCaseWhenSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_case_when',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readCaseWhenPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 case final o? when o.features.length > 1) {
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_hf8d90614a1', o.features[1]))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readCatchParameterPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_catch_parameter',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_catch_parameter',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadCatchParameter.build takes'
        },
        '_h7f4ee7a834': <String, Object?>{'kind': 'string', 'label': 'd'},
        '_hcfac37ca67': <String, Object?>{
          'kind': 'string',
          'label': '\'caught \${e.runtimeType} \${s.toString().isNotEmpty}\''
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_hcfac37ca67': <String, Object?>{
          '_h34a704d316': <Object?>[1]
        }
      },
      'build': 'ReadCatchParameter.build'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
        'TextRich': buildTextRich,
      },
    ),
  ),
  surfaceWidget: 'ReadCatchParameterSurface',
);

final readCatchParameterPlacementDefinition =
    () => _readCatchParameterPlacementDefinitionValue;

final class ReadCatchParameterSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadCatchParameterSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadCatchParameterSurface] for the default placement; no name is needed.
  const ReadCatchParameterSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
            'TextRich': buildTextRich,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_catch_parameter',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readCatchParameterPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      try {
        final d = _describe(_restageArgument1!);
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_h7f4ee7a834', d))));
      } on TypeError catch (e, s) {
        return _restageDesign(_restageRecording.branch(
            '_h34a704d316',
            1,
            Text(_restageRecording.value('_hcfac37ca67',
                'caught ${e.runtimeType} ${s.toString().isNotEmpty}'))));
      }
    })();
  }
}

final _readClassicLoopPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_classic_loop',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_classic_loop',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadClassicLoop.build takes'
        },
        '_h58f267435f': <String, Object?>{
          'kind': 'string',
          'label': 'plans[i].name'
        },
        'plans': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'name': <String, Object?>{'kind': 'string'}
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h58f267435f': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadClassicLoop.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'plans[i].name.startsWith(\'Y\')',
            'plain': 'when `plans[i].name.startsWith(\'Y\')`',
            'location': 'lib/surfaces/guarded_reads.dart:834:11'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadClassicLoopSurface',
);

final readClassicLoopPlacementDefinition =
    () => _readClassicLoopPlacementDefinitionValue;

const List<ReadPlan> _readClassicLoopMountDefault1 = const [];

final class ReadClassicLoopSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadClassicLoopSurface({
    super.key,
    List<ReadPlan> plans = _readClassicLoopMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadClassicLoopSurface] for the default placement; no name is needed.
  const ReadClassicLoopSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadPlan> plans = _readClassicLoopMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restagePlacementName = restagePlacementId;

  final List<ReadPlan> _restageStored1;
  List<ReadPlan> get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_classic_loop',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readClassicLoopPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'plans': <Object?>[
            for (final restageValue0 in _restageArgument1)
              <String, Object?>{'name': restageValue0.name}
          ],
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

    return (() {
      for (var i = 0; i < _restageArgument1.length; i++) {
        if (_restageArgument1[i].name.startsWith('Y'))
          return _restageDesign(_restageRecording.branch(
              '_h34a704d316',
              0,
              Text(_restageRecording.value(
                  '_h58f267435f', _restageArgument1[i].name))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readConditionalCallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_conditional_call',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_conditional_call',
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
        '_h4bf74ab976': <String, Object?>{
          'kind': 'bool',
          'label': 'offer == null'
        },
        '_hab5638fb7b': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_hed6fecfdad': <String, Object?>{
                'kind': 'string',
                'label': 'feature'
              }
            }
          }
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h4bf74ab976': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_hab5638fb7b': <String, Object?>{
          '_h4bf74ab976': <Object?>[false]
        },
        '_hed6fecfdad': <String, Object?>{
          '_h4bf74ab976': <Object?>[false]
        }
      },
      'build': 'ReadConditionalCall.build',
      'when': <String, Object?>{
        '_h4bf74ab976': <String, Object?>{
          'false': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:128:7'
          },
          'true': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:128:7'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadConditionalCallSurface',
);

final readConditionalCallPlacementDefinition =
    () => _readConditionalCallPlacementDefinitionValue;

final class ReadConditionalCallSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadConditionalCallSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadConditionalCallSurface] for the default placement; no name is needed.
  const ReadConditionalCallSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
        id: 'read_conditional_call',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readConditionalCallPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() => _restageDesign(_restageArgument1 == null
        ? _restageRecording.taken('_h4bf74ab976', true, const Text('No offer'))
        : _restageRecording.taken(
            '_h4bf74ab976',
            false,
            ((ReadOffer offer) => Column(children: [
                  for (final feature in _restageRecording.items(
                      '_hab5638fb7b', offer.features))
                    Text(_restageRecording.value(
                        '_hed6fecfdad', feature, '_hab5638fb7b'))
                ]))(_restageArgument1!))))();
  }
}

final _readCx1PlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_cx1',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_cx1',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadCx1.build takes'
        },
        '_h89f2535d01': <String, Object?>{
          'kind': 'string',
          'label': '\'\$restageBranch\''
        },
        'flag': <String, Object?>{'kind': 'bool'}
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h89f2535d01': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadCx1.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'flag',
            'plain': 'when flag is on',
            'location': 'lib/surfaces/guarded_reads.dart:1031:9'
          },
          '1': <String, Object?>{
            'source': '!flag',
            'plain': 'when flag is off',
            'location': 'lib/surfaces/guarded_reads.dart:1031:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadCx1Surface',
);

final readCx1PlacementDefinition = () => _readCx1PlacementDefinitionValue;

const bool _readCx1MountDefault1 = false;

final class ReadCx1Surface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadCx1Surface({
    super.key,
    bool flag = _readCx1MountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = flag,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadCx1Surface] for the default placement; no name is needed.
  const ReadCx1Surface.atPlacement(
    String restagePlacementId, {
    super.key,
    bool flag = _readCx1MountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = flag,
        _restagePlacementName = restagePlacementId;

  final bool _restageStored1;
  bool get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_cx1',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readCx1PlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'flag': _restageArgument1,
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

    return (() {
      if (_restageArgument1)
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_h89f2535d01', '${restageBranch}'))));
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readEarlyPlansPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_early_plans',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_early_plans',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadEarlyPlans.build takes'
        },
        '_h896c14b077': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_ha52758f82a': <String, Object?>{
                'kind': 'string',
                'label': 'p.name'
              }
            }
          }
        },
        'plans': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'name': <String, Object?>{'kind': 'string'}
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h896c14b077': <String, Object?>{
          '_h34a704d316': <Object?>[1]
        },
        '_ha52758f82a': <String, Object?>{
          '_h34a704d316': <Object?>[1]
        }
      },
      'build': 'ReadEarlyPlans.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'plans.isEmpty',
            'plain': 'when there are no plans',
            'location': 'lib/surfaces/guarded_reads.dart:142:9'
          },
          '1': <String, Object?>{
            'source': '!plans.isEmpty',
            'plain': 'when there are plans',
            'location': 'lib/surfaces/guarded_reads.dart:142:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadEarlyPlansSurface',
);

final readEarlyPlansPlacementDefinition =
    () => _readEarlyPlansPlacementDefinitionValue;

const List<ReadPlan> _readEarlyPlansMountDefault1 = const [];

final class ReadEarlyPlansSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadEarlyPlansSurface({
    super.key,
    List<ReadPlan> plans = _readEarlyPlansMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadEarlyPlansSurface] for the default placement; no name is needed.
  const ReadEarlyPlansSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadPlan> plans = _readEarlyPlansMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restagePlacementName = restagePlacementId;

  final List<ReadPlan> _restageStored1;
  List<ReadPlan> get _restageArgument1 => _restageStored1;
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
        id: 'read_early_plans',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readEarlyPlansPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'plans': <Object?>[
            for (final restageValue0 in _restageArgument1)
              <String, Object?>{'name': restageValue0.name}
          ],
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

    return (() {
      if (_restageArgument1.isEmpty)
        return _restageDesign(_restageRecording.branch(
            '_h34a704d316', 0, const Text('No plans')));
      return _restageDesign(_restageRecording.branch(
          '_h34a704d316',
          1,
          Column(children: [
            for (final p
                in _restageRecording.items('_h896c14b077', _loadPlans()))
              Text(_restageRecording.value(
                  '_ha52758f82a', p.name, '_h896c14b077'))
          ])));
    })();
  }
}

final _readEarlyReturnPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_early_return',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_early_return',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadEarlyReturn.build takes'
        },
        '_hf3b8a99ee0': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h80c0320810': <String, Object?>{'kind': 'string', 'label': 'f'}
            }
          }
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h80c0320810': <String, Object?>{
          '_h34a704d316': <Object?>[1]
        },
        '_hf3b8a99ee0': <String, Object?>{
          '_h34a704d316': <Object?>[1]
        }
      },
      'build': 'ReadEarlyReturn.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:60:9'
          },
          '1': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:60:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadEarlyReturnSurface',
);

final readEarlyReturnPlacementDefinition =
    () => _readEarlyReturnPlacementDefinitionValue;

final class ReadEarlyReturnSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadEarlyReturnSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadEarlyReturnSurface] for the default placement; no name is needed.
  const ReadEarlyReturnSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
        id: 'read_early_return',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readEarlyReturnPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 == null)
        return _restageDesign(_restageRecording.branch(
            '_h34a704d316', 0, const Text('No offer')));
      return _restageDesign(_restageRecording.branch(
          '_h34a704d316',
          1,
          Column(children: [
            for (final f in _restageRecording.items(
                '_hf3b8a99ee0', _restageArgument1!.features))
              Text(_restageRecording.value('_h80c0320810', f, '_hf3b8a99ee0'))
          ])));
    })();
  }
}

final _readFlaggedCallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_flagged_call',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_flagged_call',
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
        '_habf26442a0': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_hd614121e31': <String, Object?>{
                'kind': 'string',
                'label': 'plan.name'
              }
            }
          }
        },
        '_hf575215cf4': <String, Object?>{'kind': 'bool', 'label': 'flag'},
        'flag': <String, Object?>{'kind': 'bool'}
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_hf575215cf4': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_habf26442a0': <String, Object?>{
          '_hf575215cf4': <Object?>[true]
        },
        '_hd614121e31': <String, Object?>{
          '_hf575215cf4': <Object?>[true]
        }
      },
      'build': 'ReadFlaggedCall.build',
      'when': <String, Object?>{
        '_hf575215cf4': <String, Object?>{
          'false': <String, Object?>{
            'source': '!flag',
            'plain': 'when flag is off',
            'location': 'lib/surfaces/guarded_reads.dart:159:13'
          },
          'true': <String, Object?>{
            'source': 'flag',
            'plain': 'when flag is on',
            'location': 'lib/surfaces/guarded_reads.dart:159:13'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadFlaggedCallSurface',
);

final readFlaggedCallPlacementDefinition =
    () => _readFlaggedCallPlacementDefinitionValue;

const bool _readFlaggedCallMountDefault1 = false;

final class ReadFlaggedCallSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadFlaggedCallSurface({
    super.key,
    bool flag = _readFlaggedCallMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = flag,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadFlaggedCallSurface] for the default placement; no name is needed.
  const ReadFlaggedCallSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    bool flag = _readFlaggedCallMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = flag,
        _restagePlacementName = restagePlacementId;

  final bool _restageStored1;
  bool get _restageArgument1 => _restageStored1;
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
        id: 'read_flagged_call',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readFlaggedCallPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'flag': _restageArgument1,
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
          const Text('Plans'),
          if (_restageArgument1)
            ..._restageRecording.mark('_hf575215cf4', true, [
              (() => Column(children: [
                    for (final plan in _restageRecording.items(
                        '_habf26442a0', _loadPlans()))
                      Text(_restageRecording.value(
                          '_hd614121e31', plan.name, '_habf26442a0'))
                  ]))()
            ])
          else
            ..._restageRecording.mark('_hf575215cf4', false, const []),
        ])))();
  }
}

final _readFlaggedCheckPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_flagged_check',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_flagged_check',
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
        '_h0322e52f11': <String, Object?>{
          'kind': 'bool',
          'label': '_eligible()'
        },
        '_h896c14b077': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_ha52758f82a': <String, Object?>{
                'kind': 'string',
                'label': 'p.name'
              }
            }
          }
        },
        '_hf575215cf4': <String, Object?>{'kind': 'bool', 'label': 'flag'},
        'flag': <String, Object?>{'kind': 'bool'}
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h0322e52f11': <Object?>[false, true],
        '_hf575215cf4': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_h0322e52f11': <String, Object?>{
          '_hf575215cf4': <Object?>[true]
        },
        '_h896c14b077': <String, Object?>{
          '_h0322e52f11': <Object?>[true],
          '_hf575215cf4': <Object?>[true]
        },
        '_ha52758f82a': <String, Object?>{
          '_h0322e52f11': <Object?>[true],
          '_hf575215cf4': <Object?>[true]
        }
      },
      'build': 'ReadFlaggedCheck.build',
      'when': <String, Object?>{
        '_h0322e52f11': <String, Object?>{
          'false': <String, Object?>{
            'source': '!(_eligible())',
            'plain': 'when `!(_eligible())`',
            'location': 'lib/surfaces/guarded_reads.dart:112:15'
          },
          'true': <String, Object?>{
            'source': '_eligible()',
            'plain': 'when `_eligible()`',
            'location': 'lib/surfaces/guarded_reads.dart:112:15'
          }
        },
        '_hf575215cf4': <String, Object?>{
          'false': <String, Object?>{
            'source': '!flag',
            'plain': 'when flag is off',
            'location': 'lib/surfaces/guarded_reads.dart:111:13'
          },
          'true': <String, Object?>{
            'source': 'flag',
            'plain': 'when flag is on',
            'location': 'lib/surfaces/guarded_reads.dart:111:13'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadFlaggedCheckSurface',
);

final readFlaggedCheckPlacementDefinition =
    () => _readFlaggedCheckPlacementDefinitionValue;

const bool _readFlaggedCheckMountDefault1 = false;

final class ReadFlaggedCheckSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadFlaggedCheckSurface({
    super.key,
    bool flag = _readFlaggedCheckMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = flag,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadFlaggedCheckSurface] for the default placement; no name is needed.
  const ReadFlaggedCheckSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    bool flag = _readFlaggedCheckMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = flag,
        _restagePlacementName = restagePlacementId;

  final bool _restageStored1;
  bool get _restageArgument1 => _restageStored1;
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
        id: 'read_flagged_check',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readFlaggedCheckPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'flag': _restageArgument1,
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
          const Text('Plans'),
          if (_restageArgument1)
            ..._restageRecording.mark('_hf575215cf4', true, [
              if (_eligible())
                ..._restageRecording.mark('_h0322e52f11', true, [
                  for (final p
                      in _restageRecording.items('_h896c14b077', _loadPlans()))
                    Text(_restageRecording.value(
                        '_ha52758f82a', p.name, '_h896c14b077'))
                ])
              else
                ..._restageRecording.mark('_h0322e52f11', false, const [])
            ])
          else
            ..._restageRecording.mark('_hf575215cf4', false, const []),
        ])))();
  }
}

final _readGuardedCallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_guarded_call',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_guarded_call',
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
        '_h87d35472ce': <String, Object?>{
          'kind': 'bool',
          'label': 'offer != null'
        },
        '_hab5638fb7b': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_hed6fecfdad': <String, Object?>{
                'kind': 'string',
                'label': 'feature'
              }
            }
          }
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h87d35472ce': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_hab5638fb7b': <String, Object?>{
          '_h87d35472ce': <Object?>[true]
        },
        '_hed6fecfdad': <String, Object?>{
          '_h87d35472ce': <Object?>[true]
        }
      },
      'build': 'ReadGuardedCall.build',
      'when': <String, Object?>{
        '_h87d35472ce': <String, Object?>{
          'false': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:77:13'
          },
          'true': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:77:13'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadGuardedCallSurface',
);

final readGuardedCallPlacementDefinition =
    () => _readGuardedCallPlacementDefinitionValue;

final class ReadGuardedCallSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadGuardedCallSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadGuardedCallSurface] for the default placement; no name is needed.
  const ReadGuardedCallSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
        id: 'read_guarded_call',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readGuardedCallPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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
          const Text('Features'),
          if (_restageArgument1 != null)
            ..._restageRecording.mark('_h87d35472ce', true, [
              ((ReadOffer offer) => Column(children: [
                    for (final feature in _restageRecording.items(
                        '_hab5638fb7b', offer.features))
                      Text(_restageRecording.value(
                          '_hed6fecfdad', feature, '_hab5638fb7b'))
                  ]))(_restageArgument1!)
            ])
          else
            ..._restageRecording.mark('_h87d35472ce', false, const []),
        ])))();
  }
}

final _readHelperTwicePlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_helper_twice',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_helper_twice',
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
      'restage_example.islands:read__helper__twice__insetCard0__Inset_0':
          'w81152101',
      'restage_example.islands:read__helper__twice__insetCard1__Inset_0':
          'w210731763'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$read__helper__twice__insetCard0__Inset_0],
  ),
  surfaceWidget: 'ReadHelperTwiceSurface',
);

final readHelperTwicePlacementDefinition =
    () => _readHelperTwicePlacementDefinitionValue;

const restageIslands$read__helper__twice__insetCard0__Inset_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'read__helper__twice__insetCard0__Inset_0',
              builder: _restageIsland$read__helper__twice__insetCard0__Inset_0),
          RestageWidgetFactory(
              name: 'read__helper__twice__insetCard1__Inset_0',
              builder: _restageIsland$read__helper__twice__insetCard1__Inset_0)
        ],
        islands: true);

Widget _restageIsland$read__helper__twice__insetCard0__Inset_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'read__helper__twice__insetCard0__Inset_0',
        '`_Inset` (lib/surfaces/guarded_reads.dart:1598:5) needs app code that only `ReadHelperTwiceSurface` provides. Try using `ReadHelperTwiceSurface` to build this screen.',
        context,
        source);

Widget restagePreview$read__helper__twice__insetCard0__Inset_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageIslandPlaceholder(label: '_Inset', children: [
      restageSource.child(const <Object>['child'])
    ]);

Widget _restageIsland$read__helper__twice__insetCard1__Inset_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'read__helper__twice__insetCard1__Inset_0',
        '`_Inset` (lib/surfaces/guarded_reads.dart:1598:5) needs app code that only `ReadHelperTwiceSurface` provides. Try using `ReadHelperTwiceSurface` to build this screen.',
        context,
        source);

Widget restagePreview$read__helper__twice__insetCard1__Inset_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageIslandPlaceholder(label: '_Inset', children: [
      restageSource.child(const <Object>['child'])
    ]);

final class ReadHelperTwiceSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadHelperTwiceSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadHelperTwiceSurface] for the default placement; no name is needed.
  const ReadHelperTwiceSurface.atPlacement(
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
        libraries: [restageIslands$read__helper__twice__insetCard0__Inset_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_helper_twice',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readHelperTwicePlacementDefinition,
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
            'read__helper__twice__insetCard0__Inset_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'read__helper__twice__insetCard0__Inset_0',
                    [],
                    _restageContext,
                    _restageSource),
            'read__helper__twice__insetCard1__Inset_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'read__helper__twice__insetCard1__Inset_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          ((String label) => _restageRecording.island(
              'read__helper__twice__insetCard0__Inset_0',
              _restageRecording.built(
                  _Inset(inset: label.length, child: Text(label)),
                  (_restageContext, _restageSource) => _Inset(
                      inset: label.length,
                      child: _restageSource
                          .child(const <Object>['child'])))))('monthly'),
          ((String label) => _restageRecording.island(
              'read__helper__twice__insetCard1__Inset_0',
              _restageRecording.built(
                  _Inset(inset: label.length, child: Text(label)),
                  (_restageContext, _restageSource) => _Inset(
                      inset: label.length,
                      child: _restageSource
                          .child(const <Object>['child'])))))('yearly')
        ])))();
  }
}

final _readImpureTwicePlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_impure_twice',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_impure_twice',
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
        '_h99939019d9': <String, Object?>{
          'kind': 'string',
          'label': '\'\${_tick()}\''
        },
        '_h99939019d9_1': <String, Object?>{
          'kind': 'string',
          'label': '\'\${_tick()}\''
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
  surfaceWidget: 'ReadImpureTwiceSurface',
);

final readImpureTwicePlacementDefinition =
    () => _readImpureTwicePlacementDefinitionValue;

final class ReadImpureTwiceSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadImpureTwiceSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadImpureTwiceSurface] for the default placement; no name is needed.
  const ReadImpureTwiceSurface.atPlacement(
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
        id: 'read_impure_twice',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readImpureTwicePlacementDefinition,
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
          Text(_restageRecording.value('_h99939019d9', '${_tick()}')),
          Text(_restageRecording.value('_h99939019d9_1', '${_tick()}'))
        ])))();
  }
}

final _readIslandArgsPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_island_args',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_island_args',
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
        '_h1479a572a1': <String, Object?>{'kind': 'string', 'label': 'label'},
        'label': <String, Object?>{'kind': 'string'}
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'islands': <String, Object?>{
      'restage_example.islands:read__island__args__Inset_0': 'w107645712'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$read__island__args__Inset_0],
  ),
  surfaceWidget: 'ReadIslandArgsSurface',
);

final readIslandArgsPlacementDefinition =
    () => _readIslandArgsPlacementDefinitionValue;

const restageIslands$read__island__args__Inset_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'read__island__args__Inset_0',
              builder: _restageIsland$read__island__args__Inset_0)
        ],
        islands: true);

Widget _restageIsland$read__island__args__Inset_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'read__island__args__Inset_0',
        '`_Inset` (lib/surfaces/guarded_reads.dart:1444:9) needs app code that only `ReadIslandArgsSurface` provides. Try using `ReadIslandArgsSurface` to build this screen.',
        context,
        source);

Widget restagePreview$read__island__args__Inset_0(
        BuildContext restageContext, DataSource restageSource) =>
    _Inset(
        inset: _inset(), child: restageSource.child(const <Object>['child']));

const String _readIslandArgsMountDefault1 = 'Pro';

final class ReadIslandArgsSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadIslandArgsSurface({
    super.key,
    String label = _readIslandArgsMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = label,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadIslandArgsSurface] for the default placement; no name is needed.
  const ReadIslandArgsSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    String label = _readIslandArgsMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = label,
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
        libraries: [restageIslands$read__island__args__Inset_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_island_args',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readIslandArgsPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'label': _restageArgument1,
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
            'read__island__args__Inset_0': (_restageContext, _restageSource) =>
                _restageRecording.islandAt('read__island__args__Inset_0', [],
                    _restageContext, _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          _restageRecording.island(
              'read__island__args__Inset_0',
              restageOnce<(int,), Widget>(
                  (_inset(),),
                  (_restageArgs) => _restageRecording.built(
                      _Inset(
                          inset: _restageArgs.$1,
                          child: Text(_restageRecording.value(
                              '_h1479a572a1', _restageArgument1))),
                      (_restageContext, _restageSource) => _Inset(
                          inset: _restageArgs.$1,
                          child:
                              _restageSource.child(const <Object>['child']))))),
        ])))();
  }
}

final _readIslandBuilderArgsPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_island_builder_args',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_island_builder_args',
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
      'restage_example.islands:read__island__builder__args__InsetBuilder_0':
          'w61430867'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
      },
    ),
    libraries: [restageIslands$read__island__builder__args__InsetBuilder_0],
  ),
  surfaceWidget: 'ReadIslandBuilderArgsSurface',
);

final readIslandBuilderArgsPlacementDefinition =
    () => _readIslandBuilderArgsPlacementDefinitionValue;

const restageIslands$read__island__builder__args__InsetBuilder_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'read__island__builder__args__InsetBuilder_0',
              builder:
                  _restageIsland$read__island__builder__args__InsetBuilder_0)
        ],
        islands: true);

Widget _restageIsland$read__island__builder__args__InsetBuilder_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'read__island__builder__args__InsetBuilder_0',
        '`_InsetBuilder` (lib/surfaces/guarded_reads.dart:1622:9) needs app code that only `ReadIslandBuilderArgsSurface` provides. Try using `ReadIslandBuilderArgsSurface` to build this screen.',
        context,
        source);

Widget restagePreview$read__island__builder__args__InsetBuilder_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageIslandPlaceholder(label: '_InsetBuilder', children: []);

const String _readIslandBuilderArgsMountDefault1 = 'Pro';

final class ReadIslandBuilderArgsSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadIslandBuilderArgsSurface({
    super.key,
    String label = _readIslandBuilderArgsMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = label,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadIslandBuilderArgsSurface] for the default placement; no name is needed.
  const ReadIslandBuilderArgsSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    String label = _readIslandBuilderArgsMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = label,
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
          },
        ),
        libraries: [restageIslands$read__island__builder__args__InsetBuilder_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_island_builder_args',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readIslandBuilderArgsPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'label': _restageArgument1,
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
            'read__island__builder__args__InsetBuilder_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'read__island__builder__args__InsetBuilder_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          _restageRecording.island(
              'read__island__builder__args__InsetBuilder_0',
              _InsetBuilder(
                  inset: _inset(),
                  builder: (context) => Text(_restageArgument1))),
        ])))();
  }
}

final _readIslandImplicitPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_island_implicit',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_island_implicit',
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
        '_h957a7e854c': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{'kind': 'string'},
          'label': '[...const ReadNames()]'
        },
        '_hbc089081cd': <String, Object?>{
          'kind': 'string',
          'label': '\'\${const ReadNamed(\'n\')}\''
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'islands': <String, Object?>{
      'restage_example.islands:read__island__implicit__Titled_0': 'w120885975'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$read__island__implicit__Titled_0],
  ),
  surfaceWidget: 'ReadIslandImplicitSurface',
);

final readIslandImplicitPlacementDefinition =
    () => _readIslandImplicitPlacementDefinitionValue;

const restageIslands$read__island__implicit__Titled_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'read__island__implicit__Titled_0',
              builder: _restageIsland$read__island__implicit__Titled_0)
        ],
        islands: true);

Widget _restageIsland$read__island__implicit__Titled_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'read__island__implicit__Titled_0',
        '`_Titled` (lib/surfaces/guarded_reads.dart:1498:9) needs app code that only `ReadIslandImplicitSurface` provides. Try using `ReadIslandImplicitSurface` to build this screen.',
        context,
        source);

Widget restagePreview$read__island__implicit__Titled_0(
        BuildContext restageContext, DataSource restageSource) =>
    _Titled(
      title: (RestageDecoders.string(restageSource, const <Object>['title'],
              context: restageContext) ??
          '${const ReadNamed('n')}'),
      names:
          (RestageDecoders.stringList(restageSource, const <Object>['names']) ??
              [...const ReadNames()]),
      child: restageSource.child(const <Object>['child']),
    );

final class ReadIslandImplicitSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadIslandImplicitSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadIslandImplicitSurface] for the default placement; no name is needed.
  const ReadIslandImplicitSurface.atPlacement(
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
        libraries: [restageIslands$read__island__implicit__Titled_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_island_implicit',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readIslandImplicitPlacementDefinition,
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
          builders: {
            'read__island__implicit__Titled_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'read__island__implicit__Titled_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          _restageRecording.island(
              'read__island__implicit__Titled_0',
              restageOnce<
                      (
                        String,
                        List<String>,
                      ),
                      Widget>(
                  (
                    _restageRecording.value(
                        '_hbc089081cd', '${const ReadNamed('n')}'),
                    _restageRecording
                        .value('_h957a7e854c', [...const ReadNames()]),
                  ),
                  (_restageArgs) => _restageRecording.built(
                      _Titled(
                        title: _restageRecording.value(
                            '_hbc089081cd', _restageArgs.$1),
                        names: _restageRecording.value(
                            '_h957a7e854c', _restageArgs.$2),
                        child: const Text('body'),
                      ),
                      (_restageContext, _restageSource) => _Titled(
                            title: (RestageDecoders.string(
                                    _restageSource, const <Object>['title'],
                                    context: _restageContext) ??
                                _restageArgs.$1),
                            names: (RestageDecoders.stringList(
                                    _restageSource, const <Object>['names']) ??
                                _restageArgs.$2),
                            child:
                                _restageSource.child(const <Object>['child']),
                          )))),
        ])))();
  }
}

final _readItemCheckPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_item_check',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_item_check',
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
        '_hb2581b6b54': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h7ed81391a9': <String, Object?>{
                'kind': 'bool',
                'label': '_hasFeatures(h.offer!)'
              },
              '_ha643cf1627': <String, Object?>{
                'kind': 'bool',
                'label': 'h.offer != null'
              },
              '_hcfd42659ba': <String, Object?>{
                'kind': 'string',
                'label': '_describe(h.offer!)'
              }
            }
          }
        },
        'holders': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'offer': <String, Object?>{
                'kind': 'nullable',
                'value': <String, Object?>{
                  'kind': 'object',
                  'fields': <String, Object?>{
                    'features': <String, Object?>{
                      'kind': 'list',
                      'items': <String, Object?>{'kind': 'string'}
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h7ed81391a9': <Object?>[false, true],
        '_ha643cf1627': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_h7ed81391a9': <String, Object?>{
          '_ha643cf1627': <Object?>[true]
        },
        '_hcfd42659ba': <String, Object?>{
          '_h7ed81391a9': <Object?>[true],
          '_ha643cf1627': <Object?>[true]
        }
      },
      'build': 'ReadItemCheck.build',
      'when': <String, Object?>{
        '_h7ed81391a9': <String, Object?>{
          'false': <String, Object?>{
            'source': '!(_hasFeatures(h.offer!))',
            'plain': 'when `!(_hasFeatures(h.offer!))`',
            'location': 'lib/surfaces/guarded_reads.dart:207:34'
          },
          'true': <String, Object?>{
            'source': '_hasFeatures(h.offer!)',
            'plain': 'when `_hasFeatures(h.offer!)`',
            'location': 'lib/surfaces/guarded_reads.dart:207:34'
          }
        },
        '_ha643cf1627': <String, Object?>{
          'false': <String, Object?>{
            'source': 'h.offer == null',
            'plain': 'when `h.offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:207:15'
          },
          'true': <String, Object?>{
            'source': 'h.offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:207:15'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadItemCheckSurface',
);

final readItemCheckPlacementDefinition =
    () => _readItemCheckPlacementDefinitionValue;

const List<ReadHolder> _readItemCheckMountDefault1 = const [];

final class ReadItemCheckSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadItemCheckSurface({
    super.key,
    List<ReadHolder> holders = _readItemCheckMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = holders,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadItemCheckSurface] for the default placement; no name is needed.
  const ReadItemCheckSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadHolder> holders = _readItemCheckMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = holders,
        _restagePlacementName = restagePlacementId;

  final List<ReadHolder> _restageStored1;
  List<ReadHolder> get _restageArgument1 => _restageStored1;
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
        id: 'read_item_check',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readItemCheckPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'holders': <Object?>[
            for (final restageValue0 in _restageArgument1)
              <String, Object?>{
                'offer': switch (restageValue0.offer) {
                  final restagePresent2? => <String, Object?>{
                      'features': restagePresent2.features
                    },
                  null => null
                }
              }
          ],
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
          const Text('Offers'),
          for (final h
              in _restageRecording.items('_hb2581b6b54', _restageArgument1))
            if (((h.offer != null ||
                        (_restageRecording.value(
                                '_ha643cf1627', false, '_hb2581b6b54') &&
                            false)) &&
                    (_restageRecording.value(
                            '_ha643cf1627', true, '_hb2581b6b54') ||
                        true)) &&
                ((_hasFeatures(h.offer!) ||
                        (_restageRecording.value(
                                '_h7ed81391a9', false, '_hb2581b6b54') &&
                            false)) &&
                    (_restageRecording.value(
                            '_h7ed81391a9', true, '_hb2581b6b54') ||
                        true)))
              Text(_restageRecording.value(
                  '_hcfd42659ba', _describe(h.offer!), '_hb2581b6b54')),
        ])))();
  }
}

final _readItemEligiblePlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_item_eligible',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_item_eligible',
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
        '_h0322e52f11': <String, Object?>{
          'kind': 'bool',
          'label': '_eligible()'
        },
        '_hb2581b6b54': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_ha643cf1627': <String, Object?>{
                'kind': 'bool',
                'label': 'h.offer != null'
              },
              '_hcfd42659ba': <String, Object?>{
                'kind': 'string',
                'label': '_describe(h.offer!)'
              }
            }
          }
        },
        'holders': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'offer': <String, Object?>{
                'kind': 'nullable',
                'value': <String, Object?>{
                  'kind': 'object',
                  'fields': <String, Object?>{
                    'features': <String, Object?>{
                      'kind': 'list',
                      'items': <String, Object?>{'kind': 'string'}
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h0322e52f11': <Object?>[false, true],
        '_ha643cf1627': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_ha643cf1627': <String, Object?>{
          '_h0322e52f11': <Object?>[true]
        },
        '_hcfd42659ba': <String, Object?>{
          '_h0322e52f11': <Object?>[true],
          '_ha643cf1627': <Object?>[true]
        }
      },
      'build': 'ReadItemEligible.build',
      'when': <String, Object?>{
        '_h0322e52f11': <String, Object?>{
          'false': <String, Object?>{
            'source': '!(_eligible())',
            'plain': 'when `!(_eligible())`',
            'location': 'lib/surfaces/guarded_reads.dart:225:15'
          },
          'true': <String, Object?>{
            'source': '_eligible()',
            'plain': 'when `_eligible()`',
            'location': 'lib/surfaces/guarded_reads.dart:225:15'
          }
        },
        '_ha643cf1627': <String, Object?>{
          'false': <String, Object?>{
            'source': 'h.offer == null',
            'plain': 'when `h.offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:225:30'
          },
          'true': <String, Object?>{
            'source': 'h.offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:225:30'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadItemEligibleSurface',
);

final readItemEligiblePlacementDefinition =
    () => _readItemEligiblePlacementDefinitionValue;

const List<ReadHolder> _readItemEligibleMountDefault1 = const [];

final class ReadItemEligibleSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadItemEligibleSurface({
    super.key,
    List<ReadHolder> holders = _readItemEligibleMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = holders,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadItemEligibleSurface] for the default placement; no name is needed.
  const ReadItemEligibleSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadHolder> holders = _readItemEligibleMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = holders,
        _restagePlacementName = restagePlacementId;

  final List<ReadHolder> _restageStored1;
  List<ReadHolder> get _restageArgument1 => _restageStored1;
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
        id: 'read_item_eligible',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readItemEligiblePlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'holders': <Object?>[
            for (final restageValue0 in _restageArgument1)
              <String, Object?>{
                'offer': switch (restageValue0.offer) {
                  final restagePresent2? => <String, Object?>{
                      'features': restagePresent2.features
                    },
                  null => null
                }
              }
          ],
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
          const Text('Offers'),
          for (final h
              in _restageRecording.items('_hb2581b6b54', _restageArgument1))
            if (((_eligible() ||
                        (_restageRecording.value('_h0322e52f11', false) &&
                            false)) &&
                    (_restageRecording.value('_h0322e52f11', true) || true)) &&
                ((h.offer != null ||
                        (_restageRecording.value(
                                '_ha643cf1627', false, '_hb2581b6b54') &&
                            false)) &&
                    (_restageRecording.value(
                            '_ha643cf1627', true, '_hb2581b6b54') ||
                        true)))
              Text(_restageRecording.value(
                  '_hcfd42659ba', _describe(h.offer!), '_hb2581b6b54')),
        ])))();
  }
}

final _readItemKeysPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_item_keys',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_item_keys',
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
        '_h7434918939': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h4a8245f979': <String, Object?>{
                'kind': 'nativeBinding',
                'contract': <String, Object?>{
                  'type': 'flutter.Key',
                  'nullable': false
                },
                'label': 'ValueKey(p.name)'
              },
              '_hf50eeef22d': <String, Object?>{
                'kind': 'string',
                'label': 'p.name'
              }
            }
          }
        },
        '_h87d35472ce': <String, Object?>{
          'kind': 'bool',
          'label': 'offer != null'
        },
        '_hf3b8a99ee0': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h80c0320810': <String, Object?>{'kind': 'string', 'label': 'f'},
              '_hb870c530a8': <String, Object?>{
                'kind': 'nativeBinding',
                'contract': <String, Object?>{
                  'type': 'flutter.Key',
                  'nullable': false
                },
                'label': 'ValueKey(f)'
              }
            }
          }
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        },
        'plans': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'name': <String, Object?>{'kind': 'string'}
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h87d35472ce': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_h80c0320810': <String, Object?>{
          '_h87d35472ce': <Object?>[true]
        },
        '_hb870c530a8': <String, Object?>{
          '_h87d35472ce': <Object?>[true]
        },
        '_hf3b8a99ee0': <String, Object?>{
          '_h87d35472ce': <Object?>[true]
        }
      },
      'build': 'ReadItemKeys.build',
      'when': <String, Object?>{
        '_h87d35472ce': <String, Object?>{
          'false': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:405:13'
          },
          'true': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:405:13'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
      material: {
        'ElevatedButton': buildElevatedButton,
      },
    ),
  ),
  surfaceWidget: 'ReadItemKeysSurface',
);

final readItemKeysPlacementDefinition =
    () => _readItemKeysPlacementDefinitionValue;

const List<ReadPlan> _readItemKeysMountDefault1 = const [];

final class ReadItemKeysSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadItemKeysSurface({
    super.key,
    List<ReadPlan> plans = _readItemKeysMountDefault1,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restageStored2 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadItemKeysSurface] for the default placement; no name is needed.
  const ReadItemKeysSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadPlan> plans = _readItemKeysMountDefault1,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restageStored2 = offer,
        _restagePlacementName = restagePlacementId;

  final List<ReadPlan> _restageStored1;
  List<ReadPlan> get _restageArgument1 => _restageStored1;

  final ReadOffer? _restageStored2;
  ReadOffer? get _restageArgument2 => _restageStored2;
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
            'ElevatedButton': buildElevatedButton,
          },
        ),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) => switch (key.split('#').first) {
                  '_h4a8245f979' =>
                    NativeBindingContract(type: 'flutter.Key', nullable: false),
                  '_hb870c530a8' =>
                    NativeBindingContract(type: 'flutter.Key', nullable: false),
                  _ => throw StateError(key)
                },
            {}),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h4a8245f979': 'ValueKey(p.name)',
                '_hb870c530a8': 'ValueKey(f)',
              },
        child: RestagePaywall(
          id: 'read_item_keys',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: readItemKeysPlacementDefinition,
            name: _restagePlacementName,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            'plans': <Object?>[
              for (final restageValue0 in _restageArgument1)
                <String, Object?>{'name': restageValue0.name}
            ],
            'offer': switch (_restageArgument2) {
              final restagePresent0? => <String, Object?>{
                  'features': restagePresent0.features
                },
              null => null
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
          for (final p
              in _restageRecording.items('_h7434918939', _restageArgument1))
            ElevatedButton(
                key: _restageRecording.native('_h4a8245f979', ValueKey(p.name),
                    items: '_h7434918939',
                    type: 'flutter.Key',
                    nullable: false),
                onPressed: null,
                child: Text(_restageRecording.value(
                    '_hf50eeef22d', p.name, '_h7434918939'))),
          if (_restageArgument2 != null)
            ..._restageRecording.mark('_h87d35472ce', true, [
              for (final f in _restageRecording.items(
                  '_hf3b8a99ee0', _restageArgument2!.features))
                ElevatedButton(
                    key: _restageRecording.native('_hb870c530a8', ValueKey(f),
                        items: '_hf3b8a99ee0',
                        type: 'flutter.Key',
                        nullable: false),
                    onPressed: null,
                    child: Text(_restageRecording.value(
                        '_h80c0320810', f, '_hf3b8a99ee0')))
            ])
          else
            ..._restageRecording.mark('_h87d35472ce', false, const []),
        ])))();
  }
}

final _readItemListPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_item_list',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_item_list',
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
        '_hb2581b6b54': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h7ed81391a9': <String, Object?>{
                'kind': 'bool',
                'label': '_hasFeatures(h.offer!)'
              },
              '_ha4509a56c3': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{
                  'kind': 'object',
                  'fields': <String, Object?>{
                    '_h4d745fb77f': <String, Object?>{
                      'kind': 'string',
                      'label': 'f'
                    }
                  }
                }
              },
              '_ha643cf1627': <String, Object?>{
                'kind': 'bool',
                'label': 'h.offer != null'
              }
            }
          }
        },
        'holders': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'offer': <String, Object?>{
                'kind': 'nullable',
                'value': <String, Object?>{
                  'kind': 'object',
                  'fields': <String, Object?>{
                    'features': <String, Object?>{
                      'kind': 'list',
                      'items': <String, Object?>{'kind': 'string'}
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h7ed81391a9': <Object?>[false, true],
        '_ha643cf1627': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_h4d745fb77f': <String, Object?>{
          '_h7ed81391a9': <Object?>[true],
          '_ha643cf1627': <Object?>[true]
        },
        '_h7ed81391a9': <String, Object?>{
          '_ha643cf1627': <Object?>[true]
        },
        '_ha4509a56c3': <String, Object?>{
          '_h7ed81391a9': <Object?>[true],
          '_ha643cf1627': <Object?>[true]
        }
      },
      'build': 'ReadItemList.build',
      'when': <String, Object?>{
        '_h7ed81391a9': <String, Object?>{
          'false': <String, Object?>{
            'source': '!(_hasFeatures(h.offer!))',
            'plain': 'when `!(_hasFeatures(h.offer!))`',
            'location': 'lib/surfaces/guarded_reads.dart:383:34'
          },
          'true': <String, Object?>{
            'source': '_hasFeatures(h.offer!)',
            'plain': 'when `_hasFeatures(h.offer!)`',
            'location': 'lib/surfaces/guarded_reads.dart:383:34'
          }
        },
        '_ha643cf1627': <String, Object?>{
          'false': <String, Object?>{
            'source': 'h.offer == null',
            'plain': 'when `h.offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:383:15'
          },
          'true': <String, Object?>{
            'source': 'h.offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:383:15'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadItemListSurface',
);

final readItemListPlacementDefinition =
    () => _readItemListPlacementDefinitionValue;

const List<ReadHolder> _readItemListMountDefault1 = const [];

final class ReadItemListSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadItemListSurface({
    super.key,
    List<ReadHolder> holders = _readItemListMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = holders,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadItemListSurface] for the default placement; no name is needed.
  const ReadItemListSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadHolder> holders = _readItemListMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = holders,
        _restagePlacementName = restagePlacementId;

  final List<ReadHolder> _restageStored1;
  List<ReadHolder> get _restageArgument1 => _restageStored1;
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
        id: 'read_item_list',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readItemListPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'holders': <Object?>[
            for (final restageValue0 in _restageArgument1)
              <String, Object?>{
                'offer': switch (restageValue0.offer) {
                  final restagePresent2? => <String, Object?>{
                      'features': restagePresent2.features
                    },
                  null => null
                }
              }
          ],
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
          const Text('Offers'),
          for (final h
              in _restageRecording.items('_hb2581b6b54', _restageArgument1))
            if (((h.offer != null ||
                        (_restageRecording.value(
                                '_ha643cf1627', false, '_hb2581b6b54') &&
                            false)) &&
                    (_restageRecording.value(
                            '_ha643cf1627', true, '_hb2581b6b54') ||
                        true)) &&
                ((_hasFeatures(h.offer!) ||
                        (_restageRecording.value(
                                '_h7ed81391a9', false, '_hb2581b6b54') &&
                            false)) &&
                    (_restageRecording.value(
                            '_h7ed81391a9', true, '_hb2581b6b54') ||
                        true)))
              for (final f in _restageRecording.items(
                  '_ha4509a56c3', h.offer!.features, '_hb2581b6b54'))
                Text(
                    _restageRecording.value('_h4d745fb77f', f, '_ha4509a56c3')),
        ])))();
  }
}

final _readJ3PlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_j3',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_j3',
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
        '_h2564b21525': <String, Object?>{
          'kind': 'string',
          'label': '_describe(offer!)'
        },
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadJ3.build takes'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
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
        'Padding': buildPadding,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadJ3Surface',
);

final readJ3PlacementDefinition = () => _readJ3PlacementDefinitionValue;

final class ReadJ3Surface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadJ3Surface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadJ3Surface] for the default placement; no name is needed.
  const ReadJ3Surface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Padding': buildPadding,
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_j3',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readJ3PlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      try {
        return _restageDesign(_restageRecording.branch(
            '_h34a704d316',
            0,
            _Framed(
                child: Text(_restageRecording.value(
                    '_h2564b21525', _describe(_restageArgument1!))))));
      } catch (e) {
        return _restageDesign(
            _restageRecording.branch('_h34a704d316', 1, const Text('error')));
      }
    })();
  }
}

final _readKeptStatePlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_kept_state',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_kept_state',
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
      'restage_example.islands:read__kept__state__Tally_0': 'w41320074'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$read__kept__state__Tally_0],
  ),
  surfaceWidget: 'ReadKeptStateSurface',
);

final readKeptStatePlacementDefinition =
    () => _readKeptStatePlacementDefinitionValue;

const restageIslands$read__kept__state__Tally_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'read__kept__state__Tally_0',
              builder: _restageIsland$read__kept__state__Tally_0)
        ],
        islands: true);

Widget _restageIsland$read__kept__state__Tally_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'read__kept__state__Tally_0',
        '`_Tally` (lib/surfaces/guarded_reads.dart:1281:45) needs app code that only `ReadKeptStateSurface` provides. Try using `ReadKeptStateSurface` to build this screen.',
        context,
        source);

Widget restagePreview$read__kept__state__Tally_0(
        BuildContext restageContext, DataSource restageSource) =>
    _Tally();

final class ReadKeptStateSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadKeptStateSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadKeptStateSurface] for the default placement; no name is needed.
  const ReadKeptStateSurface.atPlacement(
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
        libraries: [restageIslands$read__kept__state__Tally_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_kept_state',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readKeptStatePlacementDefinition,
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
            'read__kept__state__Tally_0': (_restageContext, _restageSource) =>
                _restageRecording.islandAt('read__kept__state__Tally_0', [],
                    _restageContext, _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          Text('kept'),
          _restageRecording.island('read__kept__state__Tally_0', _Tally())
        ])))();
  }
}

final _readKeyedLoopPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_keyed_loop',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_keyed_loop',
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
      'restage_example.islands:read__keyed__loop__Counted_0': 'w264267228'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
      },
    ),
    libraries: [restageIslands$read__keyed__loop__Counted_0],
  ),
  surfaceWidget: 'ReadKeyedLoopSurface',
);

final readKeyedLoopPlacementDefinition =
    () => _readKeyedLoopPlacementDefinitionValue;

const restageIslands$read__keyed__loop__Counted_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'read__keyed__loop__Counted_0',
              builder: _restageIsland$read__keyed__loop__Counted_0)
        ],
        islands: true);

Widget _restageIsland$read__keyed__loop__Counted_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'read__keyed__loop__Counted_0',
        '`_Counted` (lib/surfaces/guarded_reads.dart:1593:35) needs app code that only `ReadKeyedLoopSurface` provides. Try using `ReadKeyedLoopSurface` to build this screen.',
        context,
        source);

Widget restagePreview$read__keyed__loop__Counted_0(
        BuildContext restageContext, DataSource restageSource) =>
    RestageIslandPlaceholder(label: '_Counted', children: []);

const List<String> _readKeyedLoopMountDefault1 = const ['a', 'b'];

final class ReadKeyedLoopSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadKeyedLoopSurface({
    super.key,
    List<String> names = _readKeyedLoopMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = names,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadKeyedLoopSurface] for the default placement; no name is needed.
  const ReadKeyedLoopSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<String> names = _readKeyedLoopMountDefault1,
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
          },
        ),
        libraries: [restageIslands$read__keyed__loop__Counted_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_keyed_loop',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readKeyedLoopPlacementDefinition,
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
            'read__keyed__loop__Counted_0': (_restageContext, _restageSource) =>
                _restageRecording.islandAt(
                    'read__keyed__loop__Counted_0',
                    [
                      _restageSource.v<int>(const <Object>['restageItems', 0])!
                    ],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          for (final name in _restageRecording
              .items('_h936348a2cc', _restageArgument1, null, ['_hdde93e85c5']))
            _restageRecording.island('read__keyed__loop__Counted_0',
                _Counted(key: ValueKey(name), label: name),
                items: '_h936348a2cc'),
        ])))();
  }
}

final _readLocalizedPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_localized',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_localized',
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
        '_h4c135d911b': <String, Object?>{
          'kind': 'string',
          'label': 'ReadStrings.of(context).title'
        },
        '_h7bb6443234': <String, Object?>{
          'kind': 'string',
          'label': '_greeting()'
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
  surfaceWidget: 'ReadLocalizedSurface',
);

final readLocalizedPlacementDefinition =
    () => _readLocalizedPlacementDefinitionValue;

final class ReadLocalizedSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadLocalizedSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadLocalizedSurface] for the default placement; no name is needed.
  const ReadLocalizedSurface.atPlacement(
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
        id: 'read_localized',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readLocalizedPlacementDefinition,
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
          Text(_restageRecording.value(
              '_h4c135d911b', ReadStrings.of(context).title)),
          Text(_restageRecording.value('_h7bb6443234', _greeting())),
        ])))();
  }
}

final _readLoopCallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_loop_call',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_loop_call',
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
        '_h2564b21525': <String, Object?>{
          'kind': 'string',
          'label': '_describe(offer!)'
        },
        '_h7434918939': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{'kind': 'jsonValue'}
        },
        '_h8d30211a08': <String, Object?>{
          'kind': 'bool',
          'label': '_hasFeatures(offer!)'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        },
        'plans': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'name': <String, Object?>{'kind': 'string'}
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h8d30211a08': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_h2564b21525': <String, Object?>{
          '_h8d30211a08': <Object?>[true]
        }
      },
      'build': 'ReadLoopCall.build',
      'when': <String, Object?>{
        '_h8d30211a08': <String, Object?>{
          'false': <String, Object?>{
            'source': '!(_hasFeatures(offer!))',
            'plain': 'when `!(_hasFeatures(offer!))`',
            'location': 'lib/surfaces/guarded_reads.dart:344:15'
          },
          'true': <String, Object?>{
            'source': '_hasFeatures(offer!)',
            'plain': 'when `_hasFeatures(offer!)`',
            'location': 'lib/surfaces/guarded_reads.dart:344:15'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadLoopCallSurface',
);

final readLoopCallPlacementDefinition =
    () => _readLoopCallPlacementDefinitionValue;

const List<ReadPlan> _readLoopCallMountDefault1 = const [];

final class ReadLoopCallSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadLoopCallSurface({
    super.key,
    List<ReadPlan> plans = _readLoopCallMountDefault1,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restageStored2 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadLoopCallSurface] for the default placement; no name is needed.
  const ReadLoopCallSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadPlan> plans = _readLoopCallMountDefault1,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restageStored2 = offer,
        _restagePlacementName = restagePlacementId;

  final List<ReadPlan> _restageStored1;
  List<ReadPlan> get _restageArgument1 => _restageStored1;

  final ReadOffer? _restageStored2;
  ReadOffer? get _restageArgument2 => _restageStored2;
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
        id: 'read_loop_call',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readLoopCallPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'plans': <Object?>[
            for (final restageValue0 in _restageArgument1)
              <String, Object?>{'name': restageValue0.name}
          ],
          'offer': switch (_restageArgument2) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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
          // ignore: unused_local_variable
          for (final p
              in _restageRecording.items('_h7434918939', _restageArgument1))
            if (_hasFeatures(_restageArgument2!))
              ..._restageRecording.mark('_h8d30211a08', true, [
                Text(_restageRecording.value(
                    '_h2564b21525', _describe(_restageArgument2!)))
              ])
            else
              ..._restageRecording.mark('_h8d30211a08', false, const []),
        ])))();
  }
}

final _readLoopCheckPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_loop_check',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_loop_check',
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
        '_h2564b21525': <String, Object?>{
          'kind': 'string',
          'label': '_describe(offer!)'
        },
        '_h68c1541ce9': <String, Object?>{
          'kind': 'bool',
          'label': 'offer!.features.isNotEmpty'
        },
        '_h7434918939': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{'kind': 'jsonValue'}
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        },
        'plans': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'name': <String, Object?>{'kind': 'string'}
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h68c1541ce9': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_h2564b21525': <String, Object?>{
          '_h68c1541ce9': <Object?>[true]
        }
      },
      'build': 'ReadLoopCheck.build',
      'when': <String, Object?>{
        '_h68c1541ce9': <String, Object?>{
          'false': <String, Object?>{
            'source': '!offer!.features.isNotEmpty',
            'plain': 'when there are no features',
            'location': 'lib/surfaces/guarded_reads.dart:324:15'
          },
          'true': <String, Object?>{
            'source': 'offer!.features.isNotEmpty',
            'plain': 'when there are features',
            'location': 'lib/surfaces/guarded_reads.dart:324:15'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadLoopCheckSurface',
);

final readLoopCheckPlacementDefinition =
    () => _readLoopCheckPlacementDefinitionValue;

const List<ReadPlan> _readLoopCheckMountDefault1 = const [];

final class ReadLoopCheckSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadLoopCheckSurface({
    super.key,
    List<ReadPlan> plans = _readLoopCheckMountDefault1,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restageStored2 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadLoopCheckSurface] for the default placement; no name is needed.
  const ReadLoopCheckSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadPlan> plans = _readLoopCheckMountDefault1,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restageStored2 = offer,
        _restagePlacementName = restagePlacementId;

  final List<ReadPlan> _restageStored1;
  List<ReadPlan> get _restageArgument1 => _restageStored1;

  final ReadOffer? _restageStored2;
  ReadOffer? get _restageArgument2 => _restageStored2;
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
        id: 'read_loop_check',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readLoopCheckPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'plans': <Object?>[
            for (final restageValue0 in _restageArgument1)
              <String, Object?>{'name': restageValue0.name}
          ],
          'offer': switch (_restageArgument2) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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
          // ignore: unused_local_variable
          for (final p
              in _restageRecording.items('_h7434918939', _restageArgument1))
            if (_restageArgument2!.features.isNotEmpty)
              ..._restageRecording.mark('_h68c1541ce9', true, [
                Text(_restageRecording.value(
                    '_h2564b21525', _describe(_restageArgument2!)))
              ])
            else
              ..._restageRecording.mark('_h68c1541ce9', false, const []),
        ])))();
  }
}

final _readLoopIndexedPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_loop_indexed',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_loop_indexed',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadLoopIndexed.build takes'
        },
        '_h426707cc06': <String, Object?>{'kind': 'string', 'label': 'p.name'},
        'plans': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'name': <String, Object?>{'kind': 'string'}
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h426707cc06': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadLoopIndexed.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'i == 1',
            'plain': 'when `i == 1`',
            'location': 'lib/surfaces/guarded_reads.dart:972:11'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadLoopIndexedSurface',
);

final readLoopIndexedPlacementDefinition =
    () => _readLoopIndexedPlacementDefinitionValue;

const List<ReadPlan> _readLoopIndexedMountDefault1 = const [];

final class ReadLoopIndexedSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadLoopIndexedSurface({
    super.key,
    List<ReadPlan> plans = _readLoopIndexedMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadLoopIndexedSurface] for the default placement; no name is needed.
  const ReadLoopIndexedSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadPlan> plans = _readLoopIndexedMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restagePlacementName = restagePlacementId;

  final List<ReadPlan> _restageStored1;
  List<ReadPlan> get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_loop_indexed',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readLoopIndexedPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'plans': <Object?>[
            for (final restageValue0 in _restageArgument1)
              <String, Object?>{'name': restageValue0.name}
          ],
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

    return (() {
      for (final (i, p) in _restageArgument1.indexed) {
        if (i == 1)
          return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
              Text(_restageRecording.value('_h426707cc06', p.name))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readLoopListPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_loop_list',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_loop_list',
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
        '_h7434918939': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{'kind': 'jsonValue'}
        },
        '_h8d30211a08': <String, Object?>{
          'kind': 'bool',
          'label': '_hasFeatures(offer!)'
        },
        '_hf3b8a99ee0': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h80c0320810': <String, Object?>{'kind': 'string', 'label': 'f'}
            }
          }
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        },
        'plans': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'name': <String, Object?>{'kind': 'string'}
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h8d30211a08': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_h80c0320810': <String, Object?>{
          '_h8d30211a08': <Object?>[true]
        },
        '_hf3b8a99ee0': <String, Object?>{
          '_h8d30211a08': <Object?>[true]
        }
      },
      'build': 'ReadLoopList.build',
      'when': <String, Object?>{
        '_h8d30211a08': <String, Object?>{
          'false': <String, Object?>{
            'source': '!(_hasFeatures(offer!))',
            'plain': 'when `!(_hasFeatures(offer!))`',
            'location': 'lib/surfaces/guarded_reads.dart:365:15'
          },
          'true': <String, Object?>{
            'source': '_hasFeatures(offer!)',
            'plain': 'when `_hasFeatures(offer!)`',
            'location': 'lib/surfaces/guarded_reads.dart:365:15'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadLoopListSurface',
);

final readLoopListPlacementDefinition =
    () => _readLoopListPlacementDefinitionValue;

const List<ReadPlan> _readLoopListMountDefault1 = const [];

final class ReadLoopListSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadLoopListSurface({
    super.key,
    List<ReadPlan> plans = _readLoopListMountDefault1,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restageStored2 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadLoopListSurface] for the default placement; no name is needed.
  const ReadLoopListSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadPlan> plans = _readLoopListMountDefault1,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restageStored2 = offer,
        _restagePlacementName = restagePlacementId;

  final List<ReadPlan> _restageStored1;
  List<ReadPlan> get _restageArgument1 => _restageStored1;

  final ReadOffer? _restageStored2;
  ReadOffer? get _restageArgument2 => _restageStored2;
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
        id: 'read_loop_list',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readLoopListPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'plans': <Object?>[
            for (final restageValue0 in _restageArgument1)
              <String, Object?>{'name': restageValue0.name}
          ],
          'offer': switch (_restageArgument2) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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
          // ignore: unused_local_variable
          for (final p
              in _restageRecording.items('_h7434918939', _restageArgument1))
            if (_hasFeatures(_restageArgument2!))
              ..._restageRecording.mark('_h8d30211a08', true, [
                for (final f in _restageRecording.items(
                    '_hf3b8a99ee0', _restageArgument2!.features))
                  Text(_restageRecording.value(
                      '_h80c0320810', f, '_hf3b8a99ee0'))
              ])
            else
              ..._restageRecording.mark('_h8d30211a08', false, const []),
        ])))();
  }
}

final _readLoopLocalPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_loop_local',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_loop_local',
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
        '_h0482b57d49': <String, Object?>{'kind': 'string', 'label': 'n'},
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadLoopLocal.build takes'
        },
        'plans': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'name': <String, Object?>{'kind': 'string'}
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h0482b57d49': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadLoopLocal.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'n.startsWith(\'Y\')',
            'plain': 'when `n.startsWith(\'Y\')`',
            'location': 'lib/surfaces/guarded_reads.dart:615:11'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadLoopLocalSurface',
);

final readLoopLocalPlacementDefinition =
    () => _readLoopLocalPlacementDefinitionValue;

const List<ReadPlan> _readLoopLocalMountDefault1 = const [];

final class ReadLoopLocalSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadLoopLocalSurface({
    super.key,
    List<ReadPlan> plans = _readLoopLocalMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadLoopLocalSurface] for the default placement; no name is needed.
  const ReadLoopLocalSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadPlan> plans = _readLoopLocalMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restagePlacementName = restagePlacementId;

  final List<ReadPlan> _restageStored1;
  List<ReadPlan> get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_loop_local',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readLoopLocalPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'plans': <Object?>[
            for (final restageValue0 in _restageArgument1)
              <String, Object?>{'name': restageValue0.name}
          ],
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

    return (() {
      for (final p in _restageArgument1) {
        final n = p.name;
        if (n.startsWith('Y'))
          return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
              Text(_restageRecording.value('_h0482b57d49', n))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readLoopVariablePlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_loop_variable',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_loop_variable',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadLoopVariable.build takes'
        },
        '_h426707cc06': <String, Object?>{'kind': 'string', 'label': 'p.name'},
        'plans': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'name': <String, Object?>{'kind': 'string'}
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h426707cc06': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadLoopVariable.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'p.name.isNotEmpty',
            'plain': 'when `p.name.isNotEmpty`',
            'location': 'lib/surfaces/guarded_reads.dart:633:11'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadLoopVariableSurface',
);

final readLoopVariablePlacementDefinition =
    () => _readLoopVariablePlacementDefinitionValue;

const List<ReadPlan> _readLoopVariableMountDefault1 = const [];

final class ReadLoopVariableSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadLoopVariableSurface({
    super.key,
    List<ReadPlan> plans = _readLoopVariableMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadLoopVariableSurface] for the default placement; no name is needed.
  const ReadLoopVariableSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadPlan> plans = _readLoopVariableMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restagePlacementName = restagePlacementId;

  final List<ReadPlan> _restageStored1;
  List<ReadPlan> get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_loop_variable',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readLoopVariablePlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'plans': <Object?>[
            for (final restageValue0 in _restageArgument1)
              <String, Object?>{'name': restageValue0.name}
          ],
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

    return (() {
      for (final p in _restageArgument1) {
        if (p.name.isNotEmpty)
          return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
              Text(_restageRecording.value('_h426707cc06', p.name))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readNestedGuardPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_nested_guard',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_nested_guard',
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
        '_h87d35472ce': <String, Object?>{
          'kind': 'bool',
          'label': 'offer != null'
        },
        '_h8d30211a08': <String, Object?>{
          'kind': 'bool',
          'label': '_hasFeatures(offer!)'
        },
        '_hf3b8a99ee0': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h80c0320810': <String, Object?>{'kind': 'string', 'label': 'f'}
            }
          }
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h87d35472ce': <Object?>[false, true],
        '_h8d30211a08': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_h80c0320810': <String, Object?>{
          '_h87d35472ce': <Object?>[true],
          '_h8d30211a08': <Object?>[true]
        },
        '_h8d30211a08': <String, Object?>{
          '_h87d35472ce': <Object?>[true]
        },
        '_hf3b8a99ee0': <String, Object?>{
          '_h87d35472ce': <Object?>[true],
          '_h8d30211a08': <Object?>[true]
        }
      },
      'build': 'ReadNestedGuard.build',
      'when': <String, Object?>{
        '_h87d35472ce': <String, Object?>{
          'false': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:93:13'
          },
          'true': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:93:13'
          }
        },
        '_h8d30211a08': <String, Object?>{
          'false': <String, Object?>{
            'source': '!(_hasFeatures(offer!))',
            'plain': 'when `!(_hasFeatures(offer!))`',
            'location': 'lib/surfaces/guarded_reads.dart:94:15'
          },
          'true': <String, Object?>{
            'source': '_hasFeatures(offer!)',
            'plain': 'when `_hasFeatures(offer!)`',
            'location': 'lib/surfaces/guarded_reads.dart:94:15'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadNestedGuardSurface',
);

final readNestedGuardPlacementDefinition =
    () => _readNestedGuardPlacementDefinitionValue;

final class ReadNestedGuardSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadNestedGuardSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadNestedGuardSurface] for the default placement; no name is needed.
  const ReadNestedGuardSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
        id: 'read_nested_guard',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readNestedGuardPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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
          const Text('Features'),
          if (_restageArgument1 != null)
            ..._restageRecording.mark('_h87d35472ce', true, [
              if (_hasFeatures(_restageArgument1!))
                ..._restageRecording.mark('_h8d30211a08', true, [
                  for (final f in _restageRecording.items(
                      '_hf3b8a99ee0', _restageArgument1!.features))
                    Text(_restageRecording.value(
                        '_h80c0320810', f, '_hf3b8a99ee0'))
                ])
              else
                ..._restageRecording.mark('_h8d30211a08', false, const [])
            ])
          else
            ..._restageRecording.mark('_h87d35472ce', false, const []),
        ])))();
  }
}

final _readNestedKeysPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_nested_keys',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_nested_keys',
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
        '_h24de973b6c': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h0559c2078d': <String, Object?>{
                'kind': 'string',
                'label': 's.name'
              },
              '_h63d82c701c': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{
                  'kind': 'object',
                  'fields': <String, Object?>{
                    '_h2dca370356': <String, Object?>{
                      'kind': 'nativeBinding',
                      'contract': <String, Object?>{
                        'type': 'flutter.Key',
                        'nullable': false
                      },
                      'label': 'ValueKey(t)'
                    },
                    '_hc1b7101851': <String, Object?>{
                      'kind': 'nativeBinding',
                      'contract': <String, Object?>{
                        'type': 'flutter.Key',
                        'nullable': false
                      },
                      'label': 'ValueKey(\'\${s.name}/\$t\')'
                    },
                    '_hf2a050e16c': <String, Object?>{
                      'kind': 'string',
                      'label': 't'
                    }
                  }
                }
              }
            }
          }
        },
        'sections': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'name': <String, Object?>{'kind': 'string'},
              'tags': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
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
        'TextRich': buildTextRich,
      },
      material: {
        'ElevatedButton': buildElevatedButton,
      },
    ),
  ),
  surfaceWidget: 'ReadNestedKeysSurface',
);

final readNestedKeysPlacementDefinition =
    () => _readNestedKeysPlacementDefinitionValue;

const List<ReadSection> _readNestedKeysMountDefault1 = const [];

final class ReadNestedKeysSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadNestedKeysSurface({
    super.key,
    List<ReadSection> sections = _readNestedKeysMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = sections,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadNestedKeysSurface] for the default placement; no name is needed.
  const ReadNestedKeysSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadSection> sections = _readNestedKeysMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = sections,
        _restagePlacementName = restagePlacementId;

  final List<ReadSection> _restageStored1;
  List<ReadSection> get _restageArgument1 => _restageStored1;
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
            'TextRich': buildTextRich,
          },
          material: {
            'ElevatedButton': buildElevatedButton,
          },
        ),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) => switch (key.split('#').first) {
                  '_h2dca370356' =>
                    NativeBindingContract(type: 'flutter.Key', nullable: false),
                  '_hc1b7101851' =>
                    NativeBindingContract(type: 'flutter.Key', nullable: false),
                  _ => throw StateError(key)
                },
            {}),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h2dca370356': 'ValueKey(t)',
                '_hc1b7101851': 'ValueKey(\'\${s.name}/\$t\')',
              },
        child: RestagePaywall(
          id: 'read_nested_keys',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: readNestedKeysPlacementDefinition,
            name: _restagePlacementName,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            'sections': <Object?>[
              for (final restageValue0 in _restageArgument1)
                <String, Object?>{
                  'name': restageValue0.name,
                  'tags': restageValue0.tags
                }
            ],
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
          for (final s
              in _restageRecording.items('_h24de973b6c', _restageArgument1))
            for (final t in _restageRecording.items(
                '_h63d82c701c', s.tags, '_h24de973b6c'))
              ElevatedButton(
                  key: _restageRecording.native('_h2dca370356', ValueKey(t),
                      items: '_h63d82c701c',
                      type: 'flutter.Key',
                      nullable: false),
                  onPressed: null,
                  child: Text(_restageRecording.value(
                      '_hf2a050e16c', t, '_h63d82c701c'))),
          for (final s
              in _restageRecording.items('_h24de973b6c', _restageArgument1))
            for (final t in _restageRecording.items(
                '_h63d82c701c', s.tags, '_h24de973b6c'))
              ElevatedButton(
                  key: _restageRecording.native(
                      '_hc1b7101851', ValueKey('${s.name}/$t'),
                      items: '_h63d82c701c',
                      type: 'flutter.Key',
                      nullable: false),
                  onPressed: null,
                  child: Text(
                      '${_restageRecording.value('_h0559c2078d', s.name, '_h24de973b6c')}/${_restageRecording.value('_hf2a050e16c', t, '_h63d82c701c')}')),
        ])))();
  }
}

final _readNullCheckPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_null_check',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_null_check',
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
        '_h7136efcd65': <String, Object?>{
          'kind': 'bool',
          'label': 'title!.isNotEmpty'
        },
        '_h8e9f27cd4a': <String, Object?>{'kind': 'string', 'label': 'title!'},
        '_hef3a9a8bb1': <String, Object?>{
          'kind': 'bool',
          'label': 'title != null'
        },
        'title': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{'kind': 'string'}
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h7136efcd65': <Object?>[false, true],
        '_hef3a9a8bb1': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_h7136efcd65': <String, Object?>{
          '_hef3a9a8bb1': <Object?>[true]
        },
        '_h8e9f27cd4a': <String, Object?>{
          '_h7136efcd65': <Object?>[true],
          '_hef3a9a8bb1': <Object?>[true]
        }
      },
      'build': 'ReadNullCheck.build',
      'when': <String, Object?>{
        '_h7136efcd65': <String, Object?>{
          'false': <String, Object?>{
            'source': '!title!.isNotEmpty',
            'plain': 'when `!title!.isNotEmpty`',
            'location': 'lib/surfaces/guarded_reads.dart:175:30'
          },
          'true': <String, Object?>{
            'source': 'title!.isNotEmpty',
            'plain': 'when `title!.isNotEmpty`',
            'location': 'lib/surfaces/guarded_reads.dart:175:30'
          }
        },
        '_hef3a9a8bb1': <String, Object?>{
          'false': <String, Object?>{
            'source': 'title == null',
            'plain': 'when `title == null`',
            'location': 'lib/surfaces/guarded_reads.dart:175:13'
          },
          'true': <String, Object?>{
            'source': 'title != null',
            'plain': 'when there\'s a title',
            'location': 'lib/surfaces/guarded_reads.dart:175:13'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadNullCheckSurface',
);

final readNullCheckPlacementDefinition =
    () => _readNullCheckPlacementDefinitionValue;

final class ReadNullCheckSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadNullCheckSurface({
    super.key,
    String? title,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadNullCheckSurface] for the default placement; no name is needed.
  const ReadNullCheckSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    String? title,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = title,
        _restagePlacementName = restagePlacementId;

  final String? _restageStored1;
  String? get _restageArgument1 => _restageStored1;
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
        id: 'read_null_check',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readNullCheckPlacementDefinition,
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
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          const Text('Title'),
          if (((_restageArgument1 != null ||
                      (_restageRecording.value('_hef3a9a8bb1', false) &&
                          false)) &&
                  (_restageRecording.value('_hef3a9a8bb1', true) || true)) &&
              ((_restageArgument1!.isNotEmpty ||
                      (_restageRecording.value('_h7136efcd65', false) &&
                          false)) &&
                  (_restageRecording.value('_h7136efcd65', true) || true)))
            Text(_restageRecording.value('_h8e9f27cd4a', _restageArgument1!)),
        ])))();
  }
}

final _readOrLocalPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_or_local',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_or_local',
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
        '_h4bf74ab976': <String, Object?>{'kind': 'bool', 'label': 'o == null'},
        '_h8821fa8df4': <String, Object?>{
          'kind': 'string',
          'label': 'o.features.first'
        },
        '_hd9311c4508': <String, Object?>{
          'kind': 'bool',
          'label': 'o.features.isEmpty'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h4bf74ab976': <Object?>[false, true],
        '_hd9311c4508': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_h8821fa8df4': <String, Object?>{
          '_h4bf74ab976': <Object?>[false],
          '_hd9311c4508': <Object?>[false]
        },
        '_hd9311c4508': <String, Object?>{
          '_h4bf74ab976': <Object?>[false]
        }
      },
      'build': 'ReadOrLocal.build',
      'when': <String, Object?>{
        '_h4bf74ab976': <String, Object?>{
          'false': <String, Object?>{
            'source': 'o != null',
            'plain': 'when there\'s an o',
            'location': 'lib/surfaces/guarded_reads.dart:1201:11'
          },
          'true': <String, Object?>{
            'source': 'o == null',
            'plain': 'when `o == null`',
            'location': 'lib/surfaces/guarded_reads.dart:1201:11'
          }
        },
        '_hd9311c4508': <String, Object?>{
          'false': <String, Object?>{
            'source': '!o.features.isEmpty',
            'plain': 'when there are features',
            'location': 'lib/surfaces/guarded_reads.dart:1201:24'
          },
          'true': <String, Object?>{
            'source': 'o.features.isEmpty',
            'plain': 'when there are no features',
            'location': 'lib/surfaces/guarded_reads.dart:1201:24'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadOrLocalSurface',
);

final readOrLocalPlacementDefinition =
    () => _readOrLocalPlacementDefinitionValue;

final class ReadOrLocalSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadOrLocalSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadOrLocalSurface] for the default placement; no name is needed.
  const ReadOrLocalSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
        id: 'read_or_local',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readOrLocalPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      final o = _restageArgument1;
      return _restageDesign(Column(children: [
        if (((o == null ||
                    (_restageRecording.value('_h4bf74ab976', false) &&
                        false)) &&
                (_restageRecording.value('_h4bf74ab976', true) || true)) ||
            ((o.features.isEmpty ||
                    (_restageRecording.value('_hd9311c4508', false) &&
                        false)) &&
                (_restageRecording.value('_hd9311c4508', true) || true)))
          const Text('none')
        else
          Text(_restageRecording.value('_h8821fa8df4', o.features.first)),
      ]));
    })();
  }
}

final _readPlanFeaturesPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_plan_features',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_plan_features',
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
        '_h7434918939': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h813ee0559a': <String, Object?>{
                'kind': 'bool',
                'label': 'p.name.isNotEmpty'
              }
            }
          }
        },
        '_hf3b8a99ee0': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h80c0320810': <String, Object?>{'kind': 'string', 'label': 'f'}
            }
          }
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        },
        'plans': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'name': <String, Object?>{'kind': 'string'}
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h813ee0559a': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_h80c0320810': <String, Object?>{
          '_h813ee0559a': <Object?>[true]
        },
        '_hf3b8a99ee0': <String, Object?>{
          '_h813ee0559a': <Object?>[true]
        }
      },
      'build': 'ReadPlanFeatures.build',
      'when': <String, Object?>{
        '_h813ee0559a': <String, Object?>{
          'false': <String, Object?>{
            'source': '!p.name.isNotEmpty',
            'plain': 'when `!p.name.isNotEmpty`',
            'location': 'lib/surfaces/guarded_reads.dart:303:15'
          },
          'true': <String, Object?>{
            'source': 'p.name.isNotEmpty',
            'plain': 'when `p.name.isNotEmpty`',
            'location': 'lib/surfaces/guarded_reads.dart:303:15'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadPlanFeaturesSurface',
);

final readPlanFeaturesPlacementDefinition =
    () => _readPlanFeaturesPlacementDefinitionValue;

const List<ReadPlan> _readPlanFeaturesMountDefault1 = const [];

final class ReadPlanFeaturesSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadPlanFeaturesSurface({
    super.key,
    List<ReadPlan> plans = _readPlanFeaturesMountDefault1,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restageStored2 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadPlanFeaturesSurface] for the default placement; no name is needed.
  const ReadPlanFeaturesSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadPlan> plans = _readPlanFeaturesMountDefault1,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restageStored2 = offer,
        _restagePlacementName = restagePlacementId;

  final List<ReadPlan> _restageStored1;
  List<ReadPlan> get _restageArgument1 => _restageStored1;

  final ReadOffer? _restageStored2;
  ReadOffer? get _restageArgument2 => _restageStored2;
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
        id: 'read_plan_features',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readPlanFeaturesPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'plans': <Object?>[
            for (final restageValue0 in _restageArgument1)
              <String, Object?>{'name': restageValue0.name}
          ],
          'offer': switch (_restageArgument2) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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
          const Text('Plans'),
          for (final p
              in _restageRecording.items('_h7434918939', _restageArgument1))
            if (p.name.isNotEmpty)
              ..._restageRecording.mark(
                  '_h813ee0559a',
                  true,
                  [
                    for (final f in _restageRecording.items(
                        '_hf3b8a99ee0', _restageArgument2!.features))
                      Text(_restageRecording.value(
                          '_h80c0320810', f, '_hf3b8a99ee0'))
                  ],
                  '_h7434918939')
            else
              ..._restageRecording.mark(
                  '_h813ee0559a', false, const [], '_h7434918939'),
        ])))();
  }
}

final _readPrintActionPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_print_action',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_print_action',
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
        '_h1479a572a1': <String, Object?>{'kind': 'string', 'label': 'label'},
        '_h539361afea': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': false},
          'label': '() => debugPrint(\'pressed \$label\')'
        },
        'label': <String, Object?>{'kind': 'string'}
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
        'TextButton': buildTextButton,
      },
    ),
  ),
  surfaceWidget: 'ReadPrintActionSurface',
);

final readPrintActionPlacementDefinition =
    () => _readPrintActionPlacementDefinitionValue;

const String _readPrintActionMountDefault1 = 'Hi';

final class ReadPrintActionSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadPrintActionSurface({
    super.key,
    String label = _readPrintActionMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = label,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadPrintActionSurface] for the default placement; no name is needed.
  const ReadPrintActionSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    String label = _readPrintActionMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = label,
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
            'TextButton': buildTextButton,
          },
        ),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) => switch (key.split('#').first) {
                  '_h539361afea' =>
                    NativeBindingContract(type: '()->void', nullable: false),
                  _ => throw StateError(key)
                },
            {}),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h539361afea': '() => debugPrint(\'pressed \$label\')',
              },
        child: RestagePaywall(
          id: 'read_print_action',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: readPrintActionPlacementDefinition,
            name: _restagePlacementName,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            'label': _restageArgument1,
            '_h539361afea': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h539361afea',
              "type": '()->void',
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
          TextButton(
              onPressed: _restageRecording.native('_h539361afea',
                  () => debugPrint('pressed ${_restageArgument1}'),
                  type: '()->void', nullable: false),
              child: Text(
                  _restageRecording.value('_h1479a572a1', _restageArgument1))),
        ])))();
  }
}

final _readReturnInIfPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_return_in_if',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_return_in_if',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadReturnInIf.build takes'
        },
        '_hf3b8a99ee0': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h80c0320810': <String, Object?>{'kind': 'string', 'label': 'f'}
            }
          }
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h80c0320810': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        },
        '_hf3b8a99ee0': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadReturnInIf.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:240:9'
          },
          '1': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:240:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadReturnInIfSurface',
);

final readReturnInIfPlacementDefinition =
    () => _readReturnInIfPlacementDefinitionValue;

final class ReadReturnInIfSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadReturnInIfSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadReturnInIfSurface] for the default placement; no name is needed.
  const ReadReturnInIfSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
        id: 'read_return_in_if',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readReturnInIfPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 != null) {
        return _restageDesign(_restageRecording.branch(
            '_h34a704d316',
            0,
            Column(children: [
              for (final f in _restageRecording.items(
                  '_hf3b8a99ee0', _restageArgument1!.features))
                Text(_restageRecording.value('_h80c0320810', f, '_hf3b8a99ee0'))
            ])));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readReturnNestedPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_return_nested',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_return_nested',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadReturnNested.build takes'
        },
        '_hf3b8a99ee0': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h80c0320810': <String, Object?>{'kind': 'string', 'label': 'f'}
            }
          }
        },
        'flag': <String, Object?>{'kind': 'bool'},
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h80c0320810': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        },
        '_hf3b8a99ee0': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadReturnNested.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:279:11'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadReturnNestedSurface',
);

final readReturnNestedPlacementDefinition =
    () => _readReturnNestedPlacementDefinitionValue;

const bool _readReturnNestedMountDefault1 = false;

final class ReadReturnNestedSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadReturnNestedSurface({
    super.key,
    bool flag = _readReturnNestedMountDefault1,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = flag,
        _restageStored2 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadReturnNestedSurface] for the default placement; no name is needed.
  const ReadReturnNestedSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    bool flag = _readReturnNestedMountDefault1,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = flag,
        _restageStored2 = offer,
        _restagePlacementName = restagePlacementId;

  final bool _restageStored1;
  bool get _restageArgument1 => _restageStored1;

  final ReadOffer? _restageStored2;
  ReadOffer? get _restageArgument2 => _restageStored2;
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
        id: 'read_return_nested',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readReturnNestedPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'flag': _restageArgument1,
          'offer': switch (_restageArgument2) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1) {
        if (_restageArgument2 != null) {
          return _restageDesign(_restageRecording.branch(
              '_h34a704d316',
              0,
              Column(children: [
                for (final f in _restageRecording.items(
                    '_hf3b8a99ee0', _restageArgument2!.features))
                  Text(_restageRecording.value(
                      '_h80c0320810', f, '_hf3b8a99ee0'))
              ])));
        }
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readReturnNoBracesPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_return_no_braces',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_return_no_braces',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadReturnNoBraces.build takes'
        },
        '_hf3b8a99ee0': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h80c0320810': <String, Object?>{'kind': 'string', 'label': 'f'}
            }
          }
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h80c0320810': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        },
        '_hf3b8a99ee0': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadReturnNoBraces.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:258:9'
          },
          '1': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:258:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadReturnNoBracesSurface',
);

final readReturnNoBracesPlacementDefinition =
    () => _readReturnNoBracesPlacementDefinitionValue;

final class ReadReturnNoBracesSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadReturnNoBracesSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadReturnNoBracesSurface] for the default placement; no name is needed.
  const ReadReturnNoBracesSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
        id: 'read_return_no_braces',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readReturnNoBracesPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 != null)
        return _restageDesign(_restageRecording.branch(
            '_h34a704d316',
            0,
            Column(children: [
              for (final f in _restageRecording.items(
                  '_hf3b8a99ee0', _restageArgument1!.features))
                Text(_restageRecording.value('_h80c0320810', f, '_hf3b8a99ee0'))
            ])));
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readS11PlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_s11',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_s11',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadS11.build takes'
        },
        '_h6d2590b1ad': <String, Object?>{'kind': 'string', 'label': 'first'},
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h6d2590b1ad': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadS11.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer case ReadOffer(features: [final first, ...])',
            'plain':
                'when `offer case ReadOffer(features: [final first, ...])`',
            'location': 'lib/surfaces/guarded_reads.dart:1049:12'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
        'TextRich': buildTextRich,
      },
    ),
  ),
  surfaceWidget: 'ReadS11Surface',
);

final readS11PlacementDefinition = () => _readS11PlacementDefinitionValue;

final class ReadS11Surface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadS11Surface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadS11Surface] for the default placement; no name is needed.
  const ReadS11Surface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
            'TextRich': buildTextRich,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_s11',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readS11PlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      switch (_restageArgument1) {
        case ReadOffer(features: [final first, ...]) when first.isEmpty:
        case ReadOffer(features: [final first, ...]):
          return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
              Text('first ${_restageRecording.value('_h6d2590b1ad', first)}')));
        default:
          return _restageDesign(
              _restageRecording.branch('_h34a704d316', 1, const Text('none')));
      }
    })();
  }
}

final _readS18PlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_s18',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_s18',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadS18.build takes'
        },
        '_hec9ea80feb': <String, Object?>{
          'kind': 'string',
          'label': 'o.features.first'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1, 2]
      },
      'values': <String, Object?>{
        '_hec9ea80feb': <String, Object?>{
          '_h34a704d316': <Object?>[2]
        }
      },
      'build': 'ReadS18.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer case null',
            'plain': 'when `offer case null`',
            'location': 'lib/surfaces/guarded_reads.dart:1127:9'
          },
          '1': <String, Object?>{
            'source': 'offer case ReadOffer(features: [])',
            'plain': 'when `offer case ReadOffer(features: [])`',
            'location': 'lib/surfaces/guarded_reads.dart:1128:9'
          },
          '2': <String, Object?>{
            'source': 'offer case final o',
            'plain': 'when `offer case final o`',
            'location': 'lib/surfaces/guarded_reads.dart:1129:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadS18Surface',
);

final readS18PlacementDefinition = () => _readS18PlacementDefinitionValue;

final class ReadS18Surface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadS18Surface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadS18Surface] for the default placement; no name is needed.
  const ReadS18Surface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_s18',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readS18PlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() => switch (_restageArgument1) {
          null => _restageDesign(
              _restageRecording.branch('_h34a704d316', 0, const Text('none'))),
          ReadOffer(features: []) => _restageDesign(_restageRecording.branch(
              '_h34a704d316', 1, throw StateError('empty'))),
          final o => _restageDesign(_restageRecording.branch('_h34a704d316', 2,
              Text(_restageRecording.value('_hec9ea80feb', o.features.first)))),
        })();
  }
}

final _readS24PlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_s24',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_s24',
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
        '_h1dab698814': <String, Object?>{'kind': 'string', 'label': 'f'},
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadS24.build takes'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h1dab698814': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadS24.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source':
                'offer case ReadOffer(features: [final f]) || ReadOffer(features: [final f, _, ...])',
            'plain':
                'when `offer case ReadOffer(features: [final f]) || ReadOffer(features: [final f, _, ...])`',
            'location': 'lib/surfaces/guarded_reads.dart:1089:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadS24Surface',
);

final readS24PlacementDefinition = () => _readS24PlacementDefinitionValue;

final class ReadS24Surface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadS24Surface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadS24Surface] for the default placement; no name is needed.
  const ReadS24Surface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_s24',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readS24PlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1
          case ReadOffer(features: [final f]) ||
              ReadOffer(features: [final f, _, ...])) {
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_h1dab698814', f))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readScrolledPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_scrolled',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_scrolled',
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
        '_h8604b300d0': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'flutter.ScrollController',
            'nullable': false
          },
          'label': '_scroll'
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
        'ListView': buildListView,
        'SizedBox': buildSizedBox,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadScrolledSurface',
);

final readScrolledPlacementDefinition =
    () => _readScrolledPlacementDefinitionValue;

final class ReadScrolledSurface extends StatefulWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadScrolledSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadScrolledSurface] for the default placement; no name is needed.
  const ReadScrolledSurface.atPlacement(
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
  _ReadScrolledSurfaceState createState() => _ReadScrolledSurfaceState();
}

final class _ReadScrolledSurfaceState extends State<ReadScrolledSurface> {
  // ignore: unused_element
  final ScrollController _scroll = ScrollController();

  // ignore: unused_element
  bool _listening = true;

  // ignore: unused_element
  @override
  void initState() {
    super.initState();
    // The app reads its controller's offset every frame it has a list.
    void read(Duration _) {
      if (!_listening) return;
      if (_scroll.hasClients) scrolledOffsets.add(_scroll.offset);
      WidgetsBinding.instance.addPostFrameCallback(read);
    }

    WidgetsBinding.instance.addPostFrameCallback(read);
  }

  // ignore: unused_element
  @override
  void dispose() {
    _listening = false;
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording(owner: context);
    Widget _restageDesign(Widget _restageBuilt) {
      const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'ListView': buildListView,
            'SizedBox': buildSizedBox,
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) => switch (key.split('#').first) {
                  '_h8604b300d0' => NativeBindingContract(
                      type: 'flutter.ScrollController', nullable: false),
                  _ => throw StateError(key)
                },
            {}),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h8604b300d0': '_scroll',
              },
        child: RestagePaywall(
          id: 'read_scrolled',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: readScrolledPlacementDefinition,
            name: widget._restagePlacementName,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            '_h8604b300d0': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h8604b300d0',
              "type": 'flutter.ScrollController',
              "nullable": false
            },
          },
          fallbackBuilder: (_) => _restageBuilt,
          onEvent: widget.onEvent,
          resolver: widget.resolver,
          errorBuilder: widget.errorBuilder,
          loadingBuilder: widget.loadingBuilder,
        ),
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() => _restageDesign(SizedBox(
          height: 200,
          child: ListView(
              controller: _restageRecording.native('_h8604b300d0', _scroll,
                  type: 'flutter.ScrollController', nullable: false),
              children: const [
                Text('row a'),
                Text('row b'),
              ]),
        )))();
  }
}

final _readShadowConstPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_shadow_const',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_shadow_const',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadShadowConst.build takes'
        },
        '_hb945acf7a2': <String, Object?>{
          'kind': 'string',
          'label': '_bannerConst'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_hb945acf7a2': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadShadowConst.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:741:9'
          },
          '1': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:741:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadShadowConstSurface',
);

final readShadowConstPlacementDefinition =
    () => _readShadowConstPlacementDefinitionValue;

final class ReadShadowConstSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadShadowConstSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadShadowConstSurface] for the default placement; no name is needed.
  const ReadShadowConstSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_shadow_const',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readShadowConstPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 != null) {
        // ignore: no_leading_underscores_for_local_identifiers
        final _bannerConst = _restageArgument1!.features.first;
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_hb945acf7a2', _bannerConst))));
      }
      return _restageDesign(_restageRecording.branch(
          '_h34a704d316', 1, const Text(_bannerConst)));
    })();
  }
}

final _readShadowFinalPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_shadow_final',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_shadow_final',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadShadowFinal.build takes'
        },
        '_hb68c9bc23c': <String, Object?>{'kind': 'string', 'label': '_banner'},
        '_hf8b7812f87': <String, Object?>{'kind': 'string', 'label': '_banner'},
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_hb68c9bc23c': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        },
        '_hf8b7812f87': <String, Object?>{
          '_h34a704d316': <Object?>[1]
        }
      },
      'build': 'ReadShadowFinal.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:721:9'
          },
          '1': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:721:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadShadowFinalSurface',
);

final readShadowFinalPlacementDefinition =
    () => _readShadowFinalPlacementDefinitionValue;

final class ReadShadowFinalSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadShadowFinalSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadShadowFinalSurface] for the default placement; no name is needed.
  const ReadShadowFinalSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_shadow_final',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readShadowFinalPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 != null) {
        // ignore: no_leading_underscores_for_local_identifiers
        final _banner = _restageArgument1!.features.first;
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_hb68c9bc23c', _banner))));
      }
      return _restageDesign(_restageRecording.branch('_h34a704d316', 1,
          Text(_restageRecording.value('_hf8b7812f87', _banner))));
    })();
  }
}

final _readShadowFunctionPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_shadow_function',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_shadow_function',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadShadowFunction.build takes'
        },
        '_h95f859fbe7': <String, Object?>{
          'kind': 'string',
          'label': '_readHeadline'
        },
        '_hda8e4dd3fc': <String, Object?>{
          'kind': 'string',
          'label': '_readHeadline()'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h95f859fbe7': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        },
        '_hda8e4dd3fc': <String, Object?>{
          '_h34a704d316': <Object?>[1]
        }
      },
      'build': 'ReadShadowFunction.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_reads.dart:701:9'
          },
          '1': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:701:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadShadowFunctionSurface',
);

final readShadowFunctionPlacementDefinition =
    () => _readShadowFunctionPlacementDefinitionValue;

final class ReadShadowFunctionSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadShadowFunctionSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadShadowFunctionSurface] for the default placement; no name is needed.
  const ReadShadowFunctionSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_shadow_function',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readShadowFunctionPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      if (_restageArgument1 != null) {
        // ignore: no_leading_underscores_for_local_identifiers
        final _readHeadline = _restageArgument1!.features.first;
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_h95f859fbe7', _readHeadline))));
      }
      return _restageDesign(_restageRecording.branch('_h34a704d316', 1,
          Text(_restageRecording.value('_hda8e4dd3fc', _readHeadline()))));
    })();
  }
}

final _readSwitchFlagPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_switch_flag',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_switch_flag',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadSwitchFlag.build takes'
        },
        'flag': <String, Object?>{'kind': 'bool'}
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
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadSwitchFlagSurface',
);

final readSwitchFlagPlacementDefinition =
    () => _readSwitchFlagPlacementDefinitionValue;

const bool _readSwitchFlagMountDefault1 = false;

final class ReadSwitchFlagSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadSwitchFlagSurface({
    super.key,
    bool flag = _readSwitchFlagMountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = flag,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadSwitchFlagSurface] for the default placement; no name is needed.
  const ReadSwitchFlagSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    bool flag = _readSwitchFlagMountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = flag,
        _restagePlacementName = restagePlacementId;

  final bool _restageStored1;
  bool get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_switch_flag',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readSwitchFlagPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'flag': _restageArgument1,
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

    return (() {
      switch (_restageArgument1) {
        case true:
          return _restageDesign(
              _restageRecording.branch('_h34a704d316', 0, const Text('on')));
        case false:
          return _restageDesign(
              _restageRecording.branch('_h34a704d316', 1, const Text('off')));
      }
    })();
  }
}

final _readSwitchOfferPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_switch_offer',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_switch_offer',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadSwitchOffer.build takes'
        },
        '_h49e8512e19': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_hc99a4c3b13': <String, Object?>{'kind': 'string', 'label': 'f'}
            }
          }
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h49e8512e19': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        },
        '_hc99a4c3b13': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadSwitchOffer.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer case ReadOffer(: final features)',
            'plain': 'when `offer case ReadOffer(: final features)`',
            'location': 'lib/surfaces/guarded_reads.dart:872:9'
          },
          '1': <String, Object?>{
            'source': 'offer case _',
            'plain': 'when `offer case _`',
            'location': 'lib/surfaces/guarded_reads.dart:874:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadSwitchOfferSurface',
);

final readSwitchOfferPlacementDefinition =
    () => _readSwitchOfferPlacementDefinitionValue;

final class ReadSwitchOfferSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadSwitchOfferSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadSwitchOfferSurface] for the default placement; no name is needed.
  const ReadSwitchOfferSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
        id: 'read_switch_offer',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readSwitchOfferPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() => switch (_restageArgument1) {
          ReadOffer(:final features) => _restageDesign(_restageRecording.branch(
              '_h34a704d316',
              0,
              Column(children: [
                for (final f
                    in _restageRecording.items('_h49e8512e19', features))
                  Text(_restageRecording.value(
                      '_hc99a4c3b13', f, '_h49e8512e19'))
              ]))),
          _ => _restageDesign(
              _restageRecording.branch('_h34a704d316', 1, const Text('none'))),
        })();
  }
}

final _readSwitchTierPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_switch_tier',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_switch_tier',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadSwitchTier.build takes'
        },
        '_h8a5eb2f561': <String, Object?>{'kind': 'string', 'label': 'name'},
        'plan': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{'kind': 'string'}
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1, 2]
      },
      'values': <String, Object?>{
        '_h8a5eb2f561': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadSwitchTier.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': '_tierOf(plan) case ReadPaid(: final name)',
            'plain': 'when `_tierOf(plan) case ReadPaid(: final name)`',
            'location': 'lib/surfaces/guarded_reads.dart:934:9'
          },
          '1': <String, Object?>{
            'source': '_tierOf(plan) case ReadPaid()',
            'plain': 'when `_tierOf(plan) case ReadPaid()`',
            'location': 'lib/surfaces/guarded_reads.dart:935:9'
          },
          '2': <String, Object?>{
            'source': '_tierOf(plan) case ReadFree()',
            'plain': 'when `_tierOf(plan) case ReadFree()`',
            'location': 'lib/surfaces/guarded_reads.dart:936:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadSwitchTierSurface',
);

final readSwitchTierPlacementDefinition =
    () => _readSwitchTierPlacementDefinitionValue;

final class ReadSwitchTierSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadSwitchTierSurface({
    super.key,
    String? plan,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plan,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadSwitchTierSurface] for the default placement; no name is needed.
  const ReadSwitchTierSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    String? plan,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plan,
        _restagePlacementName = restagePlacementId;

  final String? _restageStored1;
  String? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_switch_tier',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readSwitchTierPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'plan': _restageArgument1,
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

    return (() => switch (_tierOf(_restageArgument1)) {
          ReadPaid(:final name) when name.length > 3 => _restageDesign(
              _restageRecording.branch('_h34a704d316', 0,
                  Text(_restageRecording.value('_h8a5eb2f561', name)))),
          ReadPaid() => _restageDesign(
              _restageRecording.branch('_h34a704d316', 1, const Text('paid'))),
          ReadFree() => _restageDesign(
              _restageRecording.branch('_h34a704d316', 2, const Text('free'))),
        })();
  }
}

final _readSwitchTierStatementPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_switch_tier_statement',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_switch_tier_statement',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadSwitchTierStatement.build takes'
        },
        '_h8a5eb2f561': <String, Object?>{'kind': 'string', 'label': 'name'},
        'plan': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{'kind': 'string'}
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h8a5eb2f561': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadSwitchTierStatement.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': '_tierOf(plan) case ReadPaid(: final name)',
            'plain': 'when `_tierOf(plan) case ReadPaid(: final name)`',
            'location': 'lib/surfaces/guarded_reads.dart:952:12'
          },
          '1': <String, Object?>{
            'source': '_tierOf(plan) case ReadFree()',
            'plain': 'when `_tierOf(plan) case ReadFree()`',
            'location': 'lib/surfaces/guarded_reads.dart:954:12'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadSwitchTierStatementSurface',
);

final readSwitchTierStatementPlacementDefinition =
    () => _readSwitchTierStatementPlacementDefinitionValue;

final class ReadSwitchTierStatementSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadSwitchTierStatementSurface({
    super.key,
    String? plan,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plan,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadSwitchTierStatementSurface] for the default placement; no name is needed.
  const ReadSwitchTierStatementSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    String? plan,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plan,
        _restagePlacementName = restagePlacementId;

  final String? _restageStored1;
  String? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_switch_tier_statement',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readSwitchTierStatementPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'plan': _restageArgument1,
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

    return (() {
      switch (_tierOf(_restageArgument1)) {
        case ReadPaid(:final name):
          return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
              Text(_restageRecording.value('_h8a5eb2f561', name))));
        case ReadFree():
          return _restageDesign(
              _restageRecording.branch('_h34a704d316', 1, const Text('free')));
      }
    })();
  }
}

final _readSx10PlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_sx10',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_sx10',
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
        '_h1dab698814': <String, Object?>{'kind': 'string', 'label': 'f'},
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadSx10.build takes'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h1dab698814': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadSx10.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source':
                'offer case ReadOffer(features: [final f]) || ReadOffer(features: [final f, _, ...])',
            'plain':
                'when `offer case ReadOffer(features: [final f]) || ReadOffer(features: [final f, _, ...])`',
            'location': 'lib/surfaces/guarded_reads.dart:1109:9'
          },
          '1': <String, Object?>{
            'source': 'offer case _',
            'plain': 'when `offer case _`',
            'location': 'lib/surfaces/guarded_reads.dart:1112:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadSx10Surface',
);

final readSx10PlacementDefinition = () => _readSx10PlacementDefinitionValue;

final class ReadSx10Surface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadSx10Surface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadSx10Surface] for the default placement; no name is needed.
  const ReadSx10Surface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_sx10',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readSx10PlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() => switch (_restageArgument1) {
          ReadOffer(features: [final f]) ||
          ReadOffer(features: [final f, _, ...]) =>
            _restageDesign(_restageRecording.branch('_h34a704d316', 0,
                Text(_restageRecording.value('_h1dab698814', f)))),
          _ => _restageDesign(
              _restageRecording.branch('_h34a704d316', 1, const Text('none'))),
        })();
  }
}

final _readSx2PlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_sx2',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_sx2',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadSx2.build takes'
        },
        '_h450fa69cfa': <String, Object?>{
          'kind': 'string',
          'label': 'offer!.features.first'
        },
        'flag': <String, Object?>{'kind': 'bool'},
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1, 2]
      },
      'values': <String, Object?>{
        '_h450fa69cfa': <String, Object?>{
          '_h34a704d316': <Object?>[1]
        }
      },
      'build': 'ReadSx2.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_reads.dart:1223:9'
          },
          '1': <String, Object?>{
            'source': 'flag case true',
            'plain': 'when `flag case true`',
            'location': 'lib/surfaces/guarded_reads.dart:1225:7'
          },
          '2': <String, Object?>{
            'source': 'flag case false',
            'plain': 'when `flag case false`',
            'location': 'lib/surfaces/guarded_reads.dart:1226:7'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadSx2Surface',
);

final readSx2PlacementDefinition = () => _readSx2PlacementDefinitionValue;

const bool _readSx2MountDefault2 = false;

final class ReadSx2Surface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadSx2Surface({
    super.key,
    ReadOffer? offer,
    bool flag = _readSx2MountDefault2,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restageStored2 = flag,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadSx2Surface] for the default placement; no name is needed.
  const ReadSx2Surface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    bool flag = _readSx2MountDefault2,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restageStored2 = flag,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;

  final bool _restageStored2;
  bool get _restageArgument2 => _restageStored2;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_sx2',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readSx2PlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
          'flag': _restageArgument2,
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

    return (() {
      if (_restageArgument1 == null)
        return _restageDesign(
            _restageRecording.branch('_h34a704d316', 0, const Text('none')));
      return switch (_restageArgument2) {
        true => _restageDesign(_restageRecording.branch(
            '_h34a704d316',
            1,
            Text(_restageRecording.value(
                '_h450fa69cfa', _restageArgument1!.features.first)))),
        false => _restageDesign(
            _restageRecording.branch('_h34a704d316', 2, const Text('off'))),
      };
    })();
  }
}

final _readSx8PlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_sx8',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_sx8',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadSx8.build takes'
        },
        '_hec9ea80feb': <String, Object?>{
          'kind': 'string',
          'label': 'o.features.first'
        },
        'flag': <String, Object?>{'kind': 'bool'},
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1, 2]
      },
      'values': <String, Object?>{
        '_hec9ea80feb': <String, Object?>{
          '_h34a704d316': <Object?>[1]
        }
      },
      'build': 'ReadSx8.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer case null',
            'plain': 'when `offer case null`',
            'location': 'lib/surfaces/guarded_reads.dart:1246:13'
          },
          '1': <String, Object?>{
            'source': 'offer case final o',
            'plain': 'when `offer case final o`',
            'location': 'lib/surfaces/guarded_reads.dart:1247:13'
          },
          '2': <String, Object?>{
            'source': 'flag case false',
            'plain': 'when `flag case false`',
            'location': 'lib/surfaces/guarded_reads.dart:1249:9'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadSx8Surface',
);

final readSx8PlacementDefinition = () => _readSx8PlacementDefinitionValue;

const bool _readSx8MountDefault2 = false;

final class ReadSx8Surface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadSx8Surface({
    super.key,
    ReadOffer? offer,
    bool flag = _readSx8MountDefault2,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restageStored2 = flag,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadSx8Surface] for the default placement; no name is needed.
  const ReadSx8Surface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    bool flag = _readSx8MountDefault2,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restageStored2 = flag,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;

  final bool _restageStored2;
  bool get _restageArgument2 => _restageStored2;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_sx8',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readSx8PlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
          'flag': _restageArgument2,
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

    return (() => switch (_restageArgument2) {
          true => switch (_restageArgument1) {
              null => _restageDesign(_restageRecording.branch(
                  '_h34a704d316', 0, const Text('none'))),
              final o => _restageDesign(_restageRecording.branch(
                  '_h34a704d316',
                  1,
                  Text(_restageRecording.value(
                      '_hec9ea80feb', o.features.first)))),
            },
          false => _restageDesign(
              _restageRecording.branch('_h34a704d316', 2, const Text('off'))),
        })();
  }
}

final _readSx9PlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_sx9',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_sx9',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadSx9.build takes'
        },
        '_h8a5eb2f561': <String, Object?>{'kind': 'string', 'label': 'name'},
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_h8a5eb2f561': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadSx9.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'offer case ReadOffer(features: [final name, _, ...])',
            'plain':
                'when `offer case ReadOffer(features: [final name, _, ...])`',
            'location': 'lib/surfaces/guarded_reads.dart:1070:12'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadSx9Surface',
);

final readSx9PlacementDefinition = () => _readSx9PlacementDefinitionValue;

final class ReadSx9Surface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadSx9Surface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadSx9Surface] for the default placement; no name is needed.
  const ReadSx9Surface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_sx9',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readSx9PlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      switch (_restageArgument1) {
        case ReadOffer(features: [final name]):
        case ReadOffer(features: [final name, _, ...]):
          return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
              Text(_restageRecording.value('_h8a5eb2f561', name))));
        default:
          return _restageDesign(
              _restageRecording.branch('_h34a704d316', 1, const Text('none')));
      }
    })();
  }
}

final _readTryLocalPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_try_local',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_try_local',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadTryLocal.build takes'
        },
        '_hf174cc7164': <String, Object?>{'kind': 'string', 'label': 't'},
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_hf174cc7164': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadTryLocal.build'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadTryLocalSurface',
);

final readTryLocalPlacementDefinition =
    () => _readTryLocalPlacementDefinitionValue;

final class ReadTryLocalSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadTryLocalSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadTryLocalSurface] for the default placement; no name is needed.
  const ReadTryLocalSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_try_local',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readTryLocalPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      try {
        final t = _describe(_restageArgument1!);
        return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
            Text(_restageRecording.value('_hf174cc7164', t))));
      } on Object {
        // Without an offer there is nothing to describe.
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readTryReturnPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_try_return',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_try_return',
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
        '_h2564b21525': <String, Object?>{
          'kind': 'string',
          'label': '_describe(offer!)'
        },
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadTryReturn.build takes'
        },
        'offer': <String, Object?>{
          'kind': 'nullable',
          'value': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'features': <String, Object?>{
                'kind': 'list',
                'items': <String, Object?>{'kind': 'string'}
              }
            }
          }
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
        'Text': buildText,
      },
    ),
  ),
  surfaceWidget: 'ReadTryReturnSurface',
);

final readTryReturnPlacementDefinition =
    () => _readTryReturnPlacementDefinitionValue;

final class ReadTryReturnSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadTryReturnSurface({
    super.key,
    ReadOffer? offer,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadTryReturnSurface] for the default placement; no name is needed.
  const ReadTryReturnSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ReadOffer? offer,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restagePlacementName = restagePlacementId;

  final ReadOffer? _restageStored1;
  ReadOffer? get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_try_return',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readTryReturnPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'offer': switch (_restageArgument1) {
            final restagePresent0? => <String, Object?>{
                'features': restagePresent0.features
              },
            null => null
          },
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

    return (() {
      try {
        return _restageDesign(_restageRecording.branch(
            '_h34a704d316',
            0,
            Text(_restageRecording.value(
                '_h2564b21525', _describe(_restageArgument1!)))));
      } on TypeError {
        return _restageDesign(
            _restageRecording.branch('_h34a704d316', 1, const Text('caught')));
      }
    })();
  }
}

final _readTwiceFramedPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_twice_framed',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_twice_framed',
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
      'restage_example.islands:read__twice__framed__twice0_w0__Tally_0':
          'w194925794',
      'restage_example.islands:read__twice__framed__twice0_w1__Tally_0':
          'w224584797'
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
    libraries: [restageIslands$read__twice__framed__twice0_w0__Tally_0],
  ),
  surfaceWidget: 'ReadTwiceFramedSurface',
);

final readTwiceFramedPlacementDefinition =
    () => _readTwiceFramedPlacementDefinitionValue;

const restageIslands$read__twice__framed__twice0_w0__Tally_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'read__twice__framed__twice0_w0__Tally_0',
              builder: _restageIsland$read__twice__framed__twice0_w0__Tally_0),
          RestageWidgetFactory(
              name: 'read__twice__framed__twice0_w1__Tally_0',
              builder: _restageIsland$read__twice__framed__twice0_w1__Tally_0)
        ],
        islands: true);

Widget _restageIsland$read__twice__framed__twice0_w0__Tally_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'read__twice__framed__twice0_w0__Tally_0',
        '`_Tally` (lib/surfaces/guarded_reads.dart:1304:63) needs app code that only `ReadTwiceFramedSurface` provides. Try using `ReadTwiceFramedSurface` to build this screen.',
        context,
        source);

Widget restagePreview$read__twice__framed__twice0_w0__Tally_0(
        BuildContext restageContext, DataSource restageSource) =>
    _Tally();

Widget _restageIsland$read__twice__framed__twice0_w1__Tally_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'read__twice__framed__twice0_w1__Tally_0',
        '`_Tally` (lib/surfaces/guarded_reads.dart:1304:63) needs app code that only `ReadTwiceFramedSurface` provides. Try using `ReadTwiceFramedSurface` to build this screen.',
        context,
        source);

Widget restagePreview$read__twice__framed__twice0_w1__Tally_0(
        BuildContext restageContext, DataSource restageSource) =>
    _Tally();

final class ReadTwiceFramedSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadTwiceFramedSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadTwiceFramedSurface] for the default placement; no name is needed.
  const ReadTwiceFramedSurface.atPlacement(
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
        libraries: [restageIslands$read__twice__framed__twice0_w0__Tally_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_twice_framed',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readTwiceFramedPlacementDefinition,
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
            'read__twice__framed__twice0_w0__Tally_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'read__twice__framed__twice0_w0__Tally_0',
                    [],
                    _restageContext,
                    _restageSource),
            'read__twice__framed__twice0_w1__Tally_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'read__twice__framed__twice0_w1__Tally_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          const Text('framed'),
          ((Widget w) => Row(children: [
                    _restageRecording.spot(0, w),
                    _restageRecording.spot(1, w)
                  ]))(
              Padding(
                  padding: EdgeInsets.zero,
                  child: _restageRecording.island(
                      'read__twice__framed__twice0_w0__Tally_0',
                      _restageRecording.island(
                          'read__twice__framed__twice0_w1__Tally_0', _Tally(),
                          spots: [1]),
                      spots: [0]))),
        ])))();
  }
}

final _readTwicePlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_twice',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_twice',
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
      'restage_example.islands:read__twice__twice0_w0__Tally_0': 'w81583596',
      'restage_example.islands:read__twice__twice0_w1__Tally_0': 'w232595842'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
        'Row': buildRow,
        'Text': buildText,
      },
    ),
    libraries: [restageIslands$read__twice__twice0_w0__Tally_0],
  ),
  surfaceWidget: 'ReadTwiceSurface',
);

final readTwicePlacementDefinition = () => _readTwicePlacementDefinitionValue;

const restageIslands$read__twice__twice0_w0__Tally_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'read__twice__twice0_w0__Tally_0',
              builder: _restageIsland$read__twice__twice0_w0__Tally_0),
          RestageWidgetFactory(
              name: 'read__twice__twice0_w1__Tally_0',
              builder: _restageIsland$read__twice__twice0_w1__Tally_0)
        ],
        islands: true);

Widget _restageIsland$read__twice__twice0_w0__Tally_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'read__twice__twice0_w0__Tally_0',
        '`_Tally` (lib/surfaces/guarded_reads.dart:1292:53) needs app code that only `ReadTwiceSurface` provides. Try using `ReadTwiceSurface` to build this screen.',
        context,
        source);

Widget restagePreview$read__twice__twice0_w0__Tally_0(
        BuildContext restageContext, DataSource restageSource) =>
    const _Tally();

Widget _restageIsland$read__twice__twice0_w1__Tally_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'read__twice__twice0_w1__Tally_0',
        '`_Tally` (lib/surfaces/guarded_reads.dart:1292:53) needs app code that only `ReadTwiceSurface` provides. Try using `ReadTwiceSurface` to build this screen.',
        context,
        source);

Widget restagePreview$read__twice__twice0_w1__Tally_0(
        BuildContext restageContext, DataSource restageSource) =>
    const _Tally();

final class ReadTwiceSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadTwiceSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadTwiceSurface] for the default placement; no name is needed.
  const ReadTwiceSurface.atPlacement(
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
            'Row': buildRow,
            'Text': buildText,
          },
        ),
        libraries: [restageIslands$read__twice__twice0_w0__Tally_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_twice',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readTwicePlacementDefinition,
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
            'read__twice__twice0_w0__Tally_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'read__twice__twice0_w0__Tally_0',
                    [],
                    _restageContext,
                    _restageSource),
            'read__twice__twice0_w1__Tally_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'read__twice__twice0_w1__Tally_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          const Text('twice'),
          ((Widget w) => Row(children: [
                _restageRecording.island('read__twice__twice0_w0__Tally_0', w),
                _restageRecording.island('read__twice__twice0_w1__Tally_0', w)
              ]))(const _Tally())
        ])))();
  }
}

final _readU1PlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_u1',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_u1',
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
        '_h34a704d316': <String, Object?>{
          'kind': 'int',
          'label': 'which return ReadU1.build takes'
        },
        '_hf99032dd13': <String, Object?>{
          'kind': 'string',
          'label': '\'at \$i\''
        },
        'plans': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'name': <String, Object?>{'kind': 'string'}
            }
          }
        }
      }
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': null,
    'layouts': <String, Object?>{
      'domains': <String, Object?>{
        '_h34a704d316': <Object?>[0, 1]
      },
      'values': <String, Object?>{
        '_hf99032dd13': <String, Object?>{
          '_h34a704d316': <Object?>[0]
        }
      },
      'build': 'ReadU1.build',
      'when': <String, Object?>{
        '_h34a704d316': <String, Object?>{
          '0': <String, Object?>{
            'source': 'plans[i].name == \'Yearly\'',
            'plain': 'when `plans[i].name == \'Yearly\'`',
            'location': 'lib/surfaces/guarded_reads.dart:1146:11'
          }
        }
      }
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Text': buildText,
        'TextRich': buildTextRich,
      },
    ),
  ),
  surfaceWidget: 'ReadU1Surface',
);

final readU1PlacementDefinition = () => _readU1PlacementDefinitionValue;

const List<ReadPlan> _readU1MountDefault1 = const [];

final class ReadU1Surface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadU1Surface({
    super.key,
    List<ReadPlan> plans = _readU1MountDefault1,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadU1Surface] for the default placement; no name is needed.
  const ReadU1Surface.atPlacement(
    String restagePlacementId, {
    super.key,
    List<ReadPlan> plans = _readU1MountDefault1,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = plans,
        _restagePlacementName = restagePlacementId;

  final List<ReadPlan> _restageStored1;
  List<ReadPlan> get _restageArgument1 => _restageStored1;
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
            'Text': buildText,
            'TextRich': buildTextRich,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_u1',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readU1PlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'plans': <Object?>[
            for (final restageValue0 in _restageArgument1)
              <String, Object?>{'name': restageValue0.name}
          ],
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

    return (() {
      for (var i = 0; i < _restageArgument1.length; i++) {
        if (_restageArgument1[i].name.isEmpty) i++;
        if (_restageArgument1[i].name == 'Yearly')
          return _restageDesign(_restageRecording.branch('_h34a704d316', 0,
              Text(_restageRecording.value('_hf99032dd13', 'at $i'))));
      }
      return _restageDesign(
          _restageRecording.branch('_h34a704d316', 1, const Text('none')));
    })();
  }
}

final _readUniqueKeyedPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'read_unique_keyed',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'read_unique_keyed',
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
      'restage_example.islands:read__unique__keyed__Counted_0': 'w125342129'
    }
  },
  vocabulary: const SurfaceVocabulary(
    widgets: RestageWidgetLibraries.fromVocabulary(
      core: {
        'Column': buildColumn,
      },
    ),
    libraries: [restageIslands$read__unique__keyed__Counted_0],
  ),
  surfaceWidget: 'ReadUniqueKeyedSurface',
);

final readUniqueKeyedPlacementDefinition =
    () => _readUniqueKeyedPlacementDefinitionValue;

const restageIslands$read__unique__keyed__Counted_0 =
    RestageWidgetLibraryRegistration.constant(
        library: WidgetLibrary.custom('restage_example.islands'),
        widgets: [
          RestageWidgetFactory(
              name: 'read__unique__keyed__Counted_0',
              builder: _restageIsland$read__unique__keyed__Counted_0)
        ],
        islands: true);

Widget _restageIsland$read__unique__keyed__Counted_0(
        BuildContext context, DataSource source) =>
    RestageIslandScope.build(
        'read__unique__keyed__Counted_0',
        '`_Counted` (lib/surfaces/guarded_reads.dart:1514:25) needs app code that only `ReadUniqueKeyedSurface` provides. Try using `ReadUniqueKeyedSurface` to build this screen.',
        context,
        source);

Widget restagePreview$read__unique__keyed__Counted_0(
        BuildContext restageContext, DataSource restageSource) =>
    _Counted(
        key: UniqueKey(),
        label: (RestageDecoders.string(restageSource, const <Object>['label'],
                context: restageContext) ??
            'u'));

final class ReadUniqueKeyedSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const ReadUniqueKeyedSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [ReadUniqueKeyedSurface] for the default placement; no name is needed.
  const ReadUniqueKeyedSurface.atPlacement(
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
        libraries: [restageIslands$read__unique__keyed__Counted_0],
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'read_unique_keyed',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: readUniqueKeyedPlacementDefinition,
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
            'read__unique__keyed__Counted_0':
                (_restageContext, _restageSource) => _restageRecording.islandAt(
                    'read__unique__keyed__Counted_0',
                    [],
                    _restageContext,
                    _restageSource),
          },
          child: restageContent);
    }

    return (() => _restageDesign(Column(children: [
          _restageRecording.island(
              'read__unique__keyed__Counted_0',
              _restageRecording.built(
                  _Counted(key: UniqueKey(), label: 'u'),
                  (_restageContext, _restageSource) => _Counted(
                      key: UniqueKey(),
                      label: (RestageDecoders.string(
                              _restageSource, const <Object>['label'],
                              context: _restageContext) ??
                          'u'))))
        ])))();
  }
}
