part of '../pricing_table_showcase.dart';

// ignore_for_file: type=lint, unnecessary_cast

final _pricingTableShowcasePlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'pricing_table_showcase',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'pricing_table_showcase',
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
          'label': 'onContinue'
        },
        '_hbb09c834d3': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': true},
          'label': 'onClose'
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
        'Container': buildContainer,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'Row': buildRow,
        'SafeArea': buildSafeArea,
        'SizedBox': buildSizedBox,
        'Spacer': buildSpacer,
        'Text': buildText,
      },
      material: {
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf647: IconData(0xf647, fontFamily: 'MaterialIcons'),
      },
    }),
  ),
  surfaceWidget: 'PricingTableShowcaseSurface',
);

final pricingTableShowcasePlacementDefinition =
    () => _pricingTableShowcasePlacementDefinitionValue;

final class PricingTableShowcaseSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const PricingTableShowcaseSurface({
    super.key,
    VoidCallback? onClose,
    VoidCallback? onContinue,
    String? placement,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored1 = onClose,
        _restageStored2 = onContinue,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [PricingTableShowcaseSurface] for the default placement; no name is needed.
  const PricingTableShowcaseSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    VoidCallback? onClose,
    VoidCallback? onContinue,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored1 = onClose,
        _restageStored2 = onContinue,
        _restagePlacementName = restagePlacementId;

  final VoidCallback? _restageStored1;
  VoidCallback? get _restageArgument1 => _restageStored1;

  final VoidCallback? _restageStored2;
  VoidCallback? get _restageArgument2 => _restageStored2;
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
            'Column': buildColumn,
            'Container': buildContainer,
            'GestureDetector': buildGestureDetector,
            'Padding': buildPadding,
            'Row': buildRow,
            'SafeArea': buildSafeArea,
            'SizedBox': buildSizedBox,
            'Spacer': buildSpacer,
            'Text': buildText,
          },
          material: {
            'Icon': buildIcon,
            'Scaffold': buildScaffold,
          },
        ),
        icons: RestageIconTable.fromFamilies(families: {
          'MaterialIcons': {
            0xf647: IconData(0xf647, fontFamily: 'MaterialIcons'),
          },
        }),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) =>
                switch (key.split('#').first) { _ => throw StateError(key) },
            {
              '_h424be0f587': NativeBinding(
                  contract:
                      NativeBindingContract(type: '()->void', nullable: true),
                  value: _restageArgument2),
              '_hbb09c834d3': NativeBinding(
                  contract:
                      NativeBindingContract(type: '()->void', nullable: true),
                  value: _restageArgument1),
            }),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h424be0f587': 'onContinue',
                '_hbb09c834d3': 'onClose',
              },
        child: RestagePaywall(
          id: 'pricing_table_showcase',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: pricingTableShowcasePlacementDefinition,
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
            '_hbb09c834d3': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hbb09c834d3',
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
                Row(
                  children: [
                    GestureDetector(
                      onTap: _restageArgument1,
                      child: Icon(
                        Icons.close_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Compare plans',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 24),
                _restageRecording.island(
                    'pricing__table__showcase_PricingTable_0',
                    const PricingTable(
                      plans: [
                        Plan(
                          name: 'Pro',
                          price: Price(1999, currency: 'USD'),
                          badge: 'Most popular',
                          tier: PlanTier.pro,
                        ),
                        Plan(
                          name: 'Starter',
                          price: Price(999),
                        ),
                      ],
                    ),
                    place: RestageRecording.itself),
                const Spacer(),
                GestureDetector(
                  onTap: _restageArgument2,
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
