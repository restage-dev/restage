part of '../store_upgrade.dart';

// ignore_for_file: type=lint

final _storePaywallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
      id: 'store_upgrade',
      defaultSurfaceLocatorJson: <String, Object?>{
        'surfaceType': 'paywall',
        'slug': 'store_upgrade',
        'family': <String, Object?>{'kind': 'general'},
      },
      hostContractJson: <String, Object?>{
        'schemaVersion': 1,
        'hosting': <String, Object?>{
          'contentKind': 'single',
          'presentation': 'inline',
        },
        'providedContext': <String, Object?>{
          'inputs': <String, Object?>{
            'packages': <String, Object?>{
              'items': <String, Object?>{
                'fields': <String, Object?>{
                  'billingTerms': <String, Object?>{'kind': 'string'},
                  'identifier': <String, Object?>{'kind': 'string'},
                  'priceString': <String, Object?>{'kind': 'string'},
                },
                'kind': 'object',
              },
              'kind': 'list',
            },
          },
          'schemaVersion': 1,
        },
        'handledEvents': <String, Object?>{
          'schemaVersion': 1,
          'events': <Object?>[],
        },
        'flowBoundary': null,
      },
      vocabulary: const SurfaceVocabulary(
        widgets: RestageWidgetLibraries.fromVocabulary(
          core: {
            'Column': buildColumn,
            'Padding': buildPadding,
            'SizedBox': buildSizedBox,
            'Text': buildText,
          },
          material: {
            'FilledButton': buildFilledButton,
            'TextButton': buildTextButton,
          },
        ),
      ),
    );

final storePaywallPlacementDefinition = () =>
    _storePaywallPlacementDefinitionValue;

final class StorePaywallSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const StorePaywallSurface({
    required List<PaywallPackage> packages,
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restageArgument0 = packages,
       _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [StorePaywallSurface] for the default placement; no name is needed.
  const StorePaywallSurface.atPlacement(
    String restagePlacementId, {
    required List<PaywallPackage> packages,
    super.key,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restageArgument0 = packages,
       _restagePlacementName = restagePlacementId;

  final List<PaywallPackage> _restageArgument0;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    const SurfaceVocabulary(
      widgets: RestageWidgetLibraries.fromVocabulary(
        core: {
          'Column': buildColumn,
          'Padding': buildPadding,
          'SizedBox': buildSizedBox,
          'Text': buildText,
        },
        material: {
          'FilledButton': buildFilledButton,
          'TextButton': buildTextButton,
        },
      ),
    ).addToInstalled();
    return RestagePaywall(
      id: 'store_upgrade',
      placementBinding: RestagePaywall.generatedPlacementBinding(
        definition: storePaywallPlacementDefinition,
        name: _restagePlacementName,
      ),
      context: <String, Object?>{
        'packages': <Object?>[
          for (final restageValue0 in _restageArgument0)
            <String, Object?>{
              'identifier': restageValue0.identifier,
              'priceString': restageValue0.priceString,
              'billingTerms': restageValue0.billingTerms,
            },
        ],
      },
      fallbackBuilder: (context) => StorePaywall(packages: _restageArgument0),
      onEvent: onEvent,
      resolver: resolver,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
    );
  }
}
