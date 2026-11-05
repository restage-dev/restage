part of '../guarded_features.dart';

// ignore_for_file: type=lint, unnecessary_cast

final _guardedFeaturesPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'guarded_features',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'guarded_features',
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
        '_h910af17de6': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h021e9aa637': <String, Object?>{
                'kind': 'string',
                'label': 'feature'
              }
            }
          }
        },
        '_hb54f053d71': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              '_h4d982a08d3': <String, Object?>{
                'kind': 'string',
                'label': 'part'
              }
            }
          }
        },
        '_hef3a9a8bb1': <String, Object?>{
          'kind': 'bool',
          'label': 'title != null'
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
        '_h87d35472ce': <Object?>[false, true],
        '_hef3a9a8bb1': <Object?>[false, true]
      },
      'values': <String, Object?>{
        '_h021e9aa637': <String, Object?>{
          '_h87d35472ce': <Object?>[true]
        },
        '_h4d982a08d3': <String, Object?>{
          '_hef3a9a8bb1': <Object?>[true]
        },
        '_h910af17de6': <String, Object?>{
          '_h87d35472ce': <Object?>[true]
        },
        '_hb54f053d71': <String, Object?>{
          '_hef3a9a8bb1': <Object?>[true]
        }
      },
      'build': 'GuardedFeatures.build',
      'when': <String, Object?>{
        '_h87d35472ce': <String, Object?>{
          'false': <String, Object?>{
            'source': 'offer == null',
            'plain': 'when `offer == null`',
            'location': 'lib/surfaces/guarded_features.dart:31:13'
          },
          'true': <String, Object?>{
            'source': 'offer != null',
            'plain': 'when there\'s an offer',
            'location': 'lib/surfaces/guarded_features.dart:31:13'
          }
        },
        '_hef3a9a8bb1': <String, Object?>{
          'false': <String, Object?>{
            'source': 'title == null',
            'plain': 'when `title == null`',
            'location': 'lib/surfaces/guarded_features.dart:35:13'
          },
          'true': <String, Object?>{
            'source': 'title != null',
            'plain': 'when there\'s a title',
            'location': 'lib/surfaces/guarded_features.dart:35:13'
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
  surfaceWidget: 'GuardedFeaturesSurface',
);

final guardedFeaturesPlacementDefinition =
    () => _guardedFeaturesPlacementDefinitionValue;

final class GuardedFeaturesSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const GuardedFeaturesSurface({
    super.key,
    GuardedOffer? offer,
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
  /// Use [GuardedFeaturesSurface] for the default placement; no name is needed.
  const GuardedFeaturesSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    GuardedOffer? offer,
    String? title,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  })  : _restageStored1 = offer,
        _restageStored2 = title,
        _restagePlacementName = restagePlacementId;

  final GuardedOffer? _restageStored1;
  GuardedOffer? get _restageArgument1 => _restageStored1;

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
            'Column': buildColumn,
            'Text': buildText,
          },
        ),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'guarded_features',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: guardedFeaturesPlacementDefinition,
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

    return (() => _restageDesign(Column(children: [
          const Text('Features'),
          if (_restageArgument1 != null)
            ..._restageRecording.mark('_h87d35472ce', true, [
              for (final feature in _restageRecording.items(
                  '_h910af17de6', _restageArgument1!.features))
                Text(_restageRecording.value(
                    '_h021e9aa637', feature, '_h910af17de6'))
            ])
          else
            ..._restageRecording
                .mark('_h87d35472ce', false, [const Text('No offer')]),
          if (_restageArgument2 != null)
            ..._restageRecording.mark('_hef3a9a8bb1', true, [
              for (final part in _restageRecording.items(
                  '_hb54f053d71', _restageArgument2!.split(',')))
                Text(_restageRecording.value(
                    '_h4d982a08d3', part, '_hb54f053d71'))
            ])
          else
            ..._restageRecording
                .mark('_hef3a9a8bb1', false, [const Text('No title')]),
        ])))();
  }
}
