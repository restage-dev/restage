part of '../custom_badge.dart';

// ignore_for_file: type=lint, unnecessary_cast

final _customBadgePaywallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'custom_badge',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'custom_badge',
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
        '_h424be0f587': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': true},
          'label': 'widget.onContinue'
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
        'Center': buildCenter,
        'Column': buildColumn,
        'Container': buildContainer,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'SafeArea': buildSafeArea,
        'SizedBox': buildSizedBox,
        'Spacer': buildSpacer,
        'Text': buildText,
        'TextRich': buildTextRich,
      },
      material: {
        'Scaffold': buildScaffold,
      },
    ),
    libraries: [
      restageSplit$StreakBadge,
    ],
  ),
  surfaceWidget: 'CustomBadgePaywallSurface',
);

final customBadgePaywallPlacementDefinition =
    () => _customBadgePaywallPlacementDefinitionValue;

final class CustomBadgePaywallSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const CustomBadgePaywallSurface({
    super.key,
    VoidCallback? onContinue,
    String? placement,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored1 = onContinue,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [CustomBadgePaywallSurface] for the default placement; no name is needed.
  const CustomBadgePaywallSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    VoidCallback? onContinue,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored1 = onContinue,
        _restagePlacementName = restagePlacementId;

  final VoidCallback? _restageStored1;
  VoidCallback? get _restageArgument1 => _restageStored1;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final WidgetBuilder? loadingBuilder;

  final WidgetBuilder? fallbackBuilder;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

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
            'Container': buildContainer,
            'GestureDetector': buildGestureDetector,
            'Padding': buildPadding,
            'SafeArea': buildSafeArea,
            'SizedBox': buildSizedBox,
            'Spacer': buildSpacer,
            'Text': buildText,
            'TextRich': buildTextRich,
          },
          material: {
            'Scaffold': buildScaffold,
          },
        ),
        libraries: [
          restageSplit$StreakBadge,
        ],
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) =>
                switch (key.split('#').first) { _ => throw StateError(key) },
            {
              '_h424be0f587': NativeBinding(
                  contract:
                      NativeBindingContract(type: '()->void', nullable: true),
                  value: _restageArgument1),
            }),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h424be0f587': 'widget.onContinue',
              },
        child: RestagePaywall(
          id: 'custom_badge',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: customBadgePaywallPlacementDefinition,
            name: _restagePlacementName,
            eventOwner: context,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            '_h424be0f587': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h424be0f587',
              "type": '()->void',
              "nullable": true
            },
          },
          fallbackBuilder: fallbackBuilder ?? ((_) => _restageBuilt),
          errorBuilder: errorBuilder,
          onEvent: onEvent,
          resolver: resolver,
          loadingBuilder: loadingBuilder,
        ),
      );
      return RestageIslandScope(
          owner: context,
          explicitEvents: true,
          builders: {},
          child: restageContent);
    }

    return (() {
      return _restageDesign(Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(
                  'Your streaks',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                    child: _restageRecording.island(
                        'custom__badge_StreakBadge_0',
                        StreakBadge(label: 'Streak', count: 9),
                        place: restageSplitApp$StreakBadge)),
                const SizedBox(height: 12),
                Center(
                    child: _restageRecording.island(
                        'custom__badge_StreakBadge_1',
                        StreakBadge(label: 'Saved', count: 3),
                        place: restageSplitApp$StreakBadge)),
                const Spacer(),
                GestureDetector(
                  onTap: _restageArgument1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Continue',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
    })();
  }
}
