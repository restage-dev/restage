part of '../revenuecat_upgrade.dart';

// ignore_for_file: type=lint, unnecessary_cast

final _revenueCatPaywallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'revenuecat_upgrade',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'revenuecat_upgrade',
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
        'packages': <String, Object?>{
          'kind': 'list',
          'items': <String, Object?>{
            'kind': 'object',
            'fields': <String, Object?>{
              'identifier': <String, Object?>{'kind': 'string'},
              'priceString': <String, Object?>{'kind': 'string'}
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
  surfaceWidget: 'RevenueCatPaywallSurface',
);

final revenueCatPaywallPlacementDefinition =
    () => _revenueCatPaywallPlacementDefinitionValue;

final class RevenueCatPaywallSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const RevenueCatPaywallSurface({
    required List<PaywallPackage> packages,
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored0 = packages,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [RevenueCatPaywallSurface] for the default placement; no name is needed.
  const RevenueCatPaywallSurface.atPlacement(
    String restagePlacementId, {
    required List<PaywallPackage> packages,
    super.key,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored0 = packages,
        _restagePlacementName = restagePlacementId;

  final List<PaywallPackage> _restageStored0;
  List<PaywallPackage> get _restageArgument0 => _restageStored0;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final WidgetBuilder? loadingBuilder;

  final WidgetBuilder? fallbackBuilder;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final _restageRecording = RestageRecording();
    Widget _restageDesign(Widget _restageBuilt) {
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
        id: 'revenuecat_upgrade',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: revenueCatPaywallPlacementDefinition,
          name: _restagePlacementName,
        ),
        context: <String, Object?>{
          ..._restageRecording.values,
          'packages': <Object?>[
            for (final restageValue0 in _restageArgument0)
              <String, Object?>{
                'identifier': restageValue0.identifier,
                'priceString': restageValue0.priceString
              }
          ],
        },
        fallbackBuilder: fallbackBuilder ?? ((_) => _restageBuilt),
        errorBuilder: errorBuilder,
        onEvent: onEvent,
        resolver: resolver,
        loadingBuilder: loadingBuilder,
      );
    }

    return (() =>
        _restageDesign(RevenueCatPaywall(packages: _restageArgument0)))();
  }
}
