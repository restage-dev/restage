part of '../minimal_paywall.dart';

// ignore_for_file: type=lint, unnecessary_cast

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
      'schemaVersion': 1,
      'inputs': <String, Object?>{
        '_h0507fee626': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'flutter.Color',
            'nullable': false
          },
          'label':
              'annualSelected ? Theme.of(context).colorScheme.outlineVariant : Theme.of(context).colorScheme.primary'
        },
        '_h47c626b423': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': false},
          'label':
              '() => widget.onContinue?.call(annualSelected ? \'annual\' : \'monthly\')'
        },
        '_h8ce94b61c2': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': false},
          'label': 'selectAnnual'
        },
        '_hac39969bdc': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': false},
          'label': 'selectMonthly'
        },
        '_he38a670278': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'flutter.Color',
            'nullable': false
          },
          'label':
              'annualSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant'
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
  surfaceWidget: 'MinimalPaywallSurface',
);

final minimalPaywallPlacementDefinition =
    () => _minimalPaywallPlacementDefinitionValue;

final class MinimalPaywallSurface extends StatefulWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const MinimalPaywallSurface({
    super.key,
    ValueChanged<String>? onContinue,
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
  /// Use [MinimalPaywallSurface] for the default placement; no name is needed.
  const MinimalPaywallSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ValueChanged<String>? onContinue,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored1 = onContinue,
        _restagePlacementName = restagePlacementId;

  final ValueChanged<String>? _restageStored1;
  ValueChanged<String>? get _restageArgument1 => _restageStored1;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final WidgetBuilder? loadingBuilder;

  final WidgetBuilder? fallbackBuilder;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  @override
  _MinimalPaywallSurfaceState createState() => _MinimalPaywallSurfaceState();
}

final class _MinimalPaywallSurfaceState extends State<MinimalPaywallSurface> {
  // ignore: unused_element
  /// Plan selection: the annual plan is the default; tapping Monthly flips it.
  bool annualSelected = true;

  // ignore: unused_element
  void selectAnnual() => setState(() => annualSelected = true);

  // ignore: unused_element
  void selectMonthly() => setState(() => annualSelected = false);

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
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) => switch (key.split('#').first) {
                  '_h0507fee626' => NativeBindingContract(
                      type: 'flutter.Color', nullable: false),
                  '_h47c626b423' =>
                    NativeBindingContract(type: '()->void', nullable: false),
                  '_h8ce94b61c2' =>
                    NativeBindingContract(type: '()->void', nullable: false),
                  '_hac39969bdc' =>
                    NativeBindingContract(type: '()->void', nullable: false),
                  '_he38a670278' => NativeBindingContract(
                      type: 'flutter.Color', nullable: false),
                  _ => throw StateError(key)
                },
            {}),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h0507fee626':
                    'annualSelected ? Theme.of(context).colorScheme.outlineVariant : Theme.of(context).colorScheme.primary',
                '_h47c626b423':
                    '() => widget.onContinue?.call(annualSelected ? \'annual\' : \'monthly\')',
                '_h8ce94b61c2': 'selectAnnual',
                '_hac39969bdc': 'selectMonthly',
                '_he38a670278':
                    'annualSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant',
              },
        child: RestagePaywall(
          id: 'minimal_paywall',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: minimalPaywallPlacementDefinition,
            name: widget._restagePlacementName,
            eventOwner: context,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            '_h0507fee626': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h0507fee626',
              "type": 'flutter.Color',
              "nullable": false
            },
            '_h47c626b423': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h47c626b423',
              "type": '()->void',
              "nullable": false
            },
            '_h8ce94b61c2': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h8ce94b61c2',
              "type": '()->void',
              "nullable": false
            },
            '_hac39969bdc': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hac39969bdc',
              "type": '()->void',
              "nullable": false
            },
            '_he38a670278': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_he38a670278',
              "type": 'flutter.Color',
              "nullable": false
            },
          },
          fallbackBuilder: widget.fallbackBuilder ?? ((_) => _restageBuilt),
          errorBuilder: widget.errorBuilder,
          onEvent: widget.onEvent,
          resolver: widget.resolver,
          loadingBuilder: widget.loadingBuilder,
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
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            elevation: 0),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(
                  'Go Pro',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Everything, unlocked.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                // Annual plan row (default selected). The border tracks selection.
                GestureDetector(
                  onTap: _restageRecording.native('_h8ce94b61c2', selectAnnual,
                      type: '()->void', nullable: false),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _restageRecording.native(
                            '_he38a670278',
                            annualSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                            type: 'flutter.Color',
                            nullable: false),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Annual',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          r'$59.99',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Monthly plan row.
                GestureDetector(
                  onTap: _restageRecording.native('_hac39969bdc', selectMonthly,
                      type: '()->void', nullable: false),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _restageRecording.native(
                            '_h0507fee626',
                            annualSelected
                                ? Theme.of(context).colorScheme.outlineVariant
                                : Theme.of(context).colorScheme.primary,
                            type: 'flutter.Color',
                            nullable: false),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Monthly',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          r'$6.99',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // Continue CTA — reports the selected plan.
                GestureDetector(
                  onTap: _restageRecording.native(
                      '_h47c626b423',
                      () => widget._restageArgument1
                          ?.call(annualSelected ? 'annual' : 'monthly'),
                      type: '()->void',
                      nullable: false),
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
