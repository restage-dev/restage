part of '../pulse_paywall.dart';

// ignore_for_file: type=lint, unnecessary_cast

final _pulsePaywallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'pulse_paywall',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'pulse_paywall',
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
      restageSplit$PulseBadge,
    ],
  ),
  surfaceWidget: 'PulsePaywallSurface',
);

final pulsePaywallPlacementDefinition =
    () => _pulsePaywallPlacementDefinitionValue;

final class PulsePaywallSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const PulsePaywallSurface({
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
  /// Use [PulsePaywallSurface] for the default placement; no name is needed.
  const PulsePaywallSurface.atPlacement(
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
          restageSplit$PulseBadge,
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
          id: 'pulse_paywall',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: pulsePaywallPlacementDefinition,
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
                  'Keep your streak alive',
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
                        'pulse__paywall_PulseBadge_0',
                        PulseBadge(label: 'Streak', count: 12),
                        place: restageSplitApp$PulseBadge)),
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
