part of '../minimal_paywall.dart';

// ignore_for_file: type=lint

final _minimalPaywallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'minimal_paywall',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'minimal_paywall',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'single',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'inputs': <String, Object?>{},
      'schemaVersion': 1
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
        'Container': buildContainer,
        'Expanded': buildExpanded,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'Row': buildRow,
        'SafeArea': buildSafeArea,
        'SizedBox': buildSizedBox,
        'Spacer': buildSpacer,
        'Text': buildText,
      },
      material: {
        'AppBar': buildAppBar,
        'Scaffold': buildScaffold,
      },
    ),
  ),
);

final minimalPaywallPlacementDefinition =
    () => _minimalPaywallPlacementDefinitionValue;

final class MinimalPaywallSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const MinimalPaywallSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.errorBuilder,
    this.loadingBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [MinimalPaywallSurface] for the default placement; no name is needed.
  const MinimalPaywallSurface.atPlacement(
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
    const SurfaceVocabulary(
      widgets: RestageWidgetLibraries.fromVocabulary(
        core: {
          'Column': buildColumn,
          'Container': buildContainer,
          'Expanded': buildExpanded,
          'GestureDetector': buildGestureDetector,
          'Padding': buildPadding,
          'Row': buildRow,
          'SafeArea': buildSafeArea,
          'SizedBox': buildSizedBox,
          'Spacer': buildSpacer,
          'Text': buildText,
        },
        material: {
          'AppBar': buildAppBar,
          'Scaffold': buildScaffold,
        },
      ),
    ).addToInstalled();
    return RestagePaywall(
      id: 'minimal_paywall',
      placementBinding: RestagePaywall.generatedPlacementBinding(
        definition: minimalPaywallPlacementDefinition,
        name: _restagePlacementName,
      ),
      fallbackBuilder: (context) => MinimalPaywall(),
      onEvent: onEvent,
      resolver: resolver,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
    );
  }
}
