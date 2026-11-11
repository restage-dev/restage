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
        '_hce0a6b3f04': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': '(dart:core#String)->void?',
            'nullable': true
          },
          'label': 'widget.onContinue'
        },
        '_hcf6fc3204a': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'installed.call',
            'nullable': false,
            'call': <String, Object?>{
              'inputs': <Object?>[
                <String, Object?>{
                  'kind': 'native',
                  'nativeType': '(dart:core#String)->void?',
                  'nullable': true
                },
                <String, Object?>{'kind': 'String'}
              ],
              'captures': <String, Object?>{},
              'result': <String, Object?>{
                'kind': 'native',
                'nativeType': '()->void'
              },
              'implementation':
                  'cf6fc3204ae05a61a836dc1199a6b8bbbf03438e02235bdfc0051db5d3c3c5ff'
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

final _restageMinimalPaywallSurface_hcf6fc3204aContract =
    NativeBindingContract.fromJson(<String, Object?>{
  "type": "installed.call",
  "nullable": false,
  "call": <String, Object?>{
    "inputs": <Object?>[
      <String, Object?>{
        "kind": "native",
        "nativeType": "(dart:core#String)->void?",
        "nullable": true
      },
      <String, Object?>{"kind": "String"}
    ],
    "captures": <String, Object?>{},
    "result": <String, Object?>{"kind": "native", "nativeType": "()->void"},
    "implementation":
        "cf6fc3204ae05a61a836dc1199a6b8bbbf03438e02235bdfc0051db5d3c3c5ff"
  }
});
final NativeCallAdapter _restageMinimalPaywallSurface_hcf6fc3204aNative =
    NativeCallAdapter(_restageMinimalPaywallSurface_hcf6fc3204aContract,
        (_restageInputs, _restageCells) {
  T _restageAs<T>(Object? value) => value as T;
  final ValueChanged<String>? _restageInput0 =
      _restageAs<ValueChanged<String>?>((_restageInputs[0] == null
          ? null
          : (_restageInputs[0] as ValueNative).value));
  final String _restageInput1 = _restageAs<String>(_restageInputs[1]);
  final void Function() _restageResult =
      () => _restageInput0?.call(_restageInput1);
  return NativeBinding<void Function()>(
      contract: NativeBindingContract(type: "()->void", nullable: false),
      value: _restageResult);
});

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
            (key) =>
                switch (key.split('#').first) { _ => throw StateError(key) },
            {
              '_hce0a6b3f04': NativeBinding(
                  contract: NativeBindingContract(
                      type: '(dart:core#String)->void?', nullable: true),
                  value: widget._restageArgument1),
              '_hcf6fc3204a': NativeBinding(
                  contract: _restageMinimalPaywallSurface_hcf6fc3204aContract,
                  value: _restageMinimalPaywallSurface_hcf6fc3204aNative),
            }),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_hce0a6b3f04': 'widget.onContinue',
                '_hcf6fc3204a':
                    '() => _restageInput0\n                    ?.call(_restageInput1)',
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
            '_hce0a6b3f04': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hce0a6b3f04',
              "type": '(dart:core#String)->void?',
              "nullable": true
            },
            '_hcf6fc3204a': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hcf6fc3204a',
              "type": 'installed.call',
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
                  onTap: selectAnnual,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: annualSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
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
                  onTap: selectMonthly,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: annualSelected
                            ? Theme.of(context).colorScheme.outlineVariant
                            : Theme.of(context).colorScheme.primary,
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
                  onTap: () => widget._restageArgument1
                      ?.call(annualSelected ? 'annual' : 'monthly'),
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
