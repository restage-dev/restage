part of '../sentinel_protection.dart';

// ignore_for_file: type=lint, unnecessary_cast

final _sentinelProtectionPaywallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'sentinel_protection',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'sentinel_protection',
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
        '_hbb09c834d3': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': true},
          'label': 'widget.onClose'
        },
        '_hbc7931e8b3': <String, Object?>{
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
                  'bc7931e8b3c43390dea3d1917bad5238f6d9b243f820489eb40a77459cfd5887'
            }
          }
        },
        '_hce0a6b3f04': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': '(dart:core#String)->void?',
            'nullable': true
          },
          'label': 'widget.onContinue'
        },
        '_hd341a8328d': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': true},
          'label': 'widget.onSubscriptionInfo'
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
        'Expanded': buildExpanded,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'Positioned': buildPositioned,
        'Row': buildRow,
        'SafeArea': buildSafeArea,
        'SizedBox': buildSizedBox,
        'Spacer': buildSpacer,
        'Stack': buildStack,
        'Text': buildText,
      },
      material: {
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xf636: IconData(0xf636, fontFamily: 'MaterialIcons'),
        0xf016b: IconData(0xf016b, fontFamily: 'MaterialIcons'),
      },
    }, mirrored: {
      'MaterialIcons': {
        0xf63a: IconData(0xf63a,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
      },
    }),
  ),
  surfaceWidget: 'SentinelProtectionPaywallSurface',
);

final sentinelProtectionPaywallPlacementDefinition =
    () => _sentinelProtectionPaywallPlacementDefinitionValue;

final _restageSentinelProtectionPaywallSurface_hbc7931e8b3Contract =
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
        "bc7931e8b3c43390dea3d1917bad5238f6d9b243f820489eb40a77459cfd5887"
  }
});
final NativeCallAdapter
    _restageSentinelProtectionPaywallSurface_hbc7931e8b3Native =
    NativeCallAdapter(
        _restageSentinelProtectionPaywallSurface_hbc7931e8b3Contract,
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

final class SentinelProtectionPaywallSurface extends StatefulWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const SentinelProtectionPaywallSurface({
    super.key,
    ValueChanged<String>? onContinue,
    VoidCallback? onClose,
    VoidCallback? onSubscriptionInfo,
    String? placement,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored1 = onContinue,
        _restageStored2 = onClose,
        _restageStored3 = onSubscriptionInfo,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [SentinelProtectionPaywallSurface] for the default placement; no name is needed.
  const SentinelProtectionPaywallSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ValueChanged<String>? onContinue,
    VoidCallback? onClose,
    VoidCallback? onSubscriptionInfo,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored1 = onContinue,
        _restageStored2 = onClose,
        _restageStored3 = onSubscriptionInfo,
        _restagePlacementName = restagePlacementId;

  final ValueChanged<String>? _restageStored1;
  ValueChanged<String>? get _restageArgument1 => _restageStored1;

  final VoidCallback? _restageStored2;
  VoidCallback? get _restageArgument2 => _restageStored2;

  final VoidCallback? _restageStored3;
  VoidCallback? get _restageArgument3 => _restageStored3;
  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final WidgetBuilder? loadingBuilder;

  final WidgetBuilder? fallbackBuilder;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  @override
  _SentinelProtectionPaywallSurfaceState createState() =>
      _SentinelProtectionPaywallSurfaceState();
}

final class _SentinelProtectionPaywallSurfaceState
    extends State<SentinelProtectionPaywallSurface> {
  // ignore: unused_element
  /// Plan selection: the 1-year plan is the default; tapping the 1-month card
  /// flips it.
  bool yearSelected = true;

  // ignore: unused_element
  void selectYear() => setState(() => yearSelected = true);

  // ignore: unused_element
  void selectMonth() => setState(() => yearSelected = false);

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
            'Expanded': buildExpanded,
            'GestureDetector': buildGestureDetector,
            'Padding': buildPadding,
            'Positioned': buildPositioned,
            'Row': buildRow,
            'SafeArea': buildSafeArea,
            'SizedBox': buildSizedBox,
            'Spacer': buildSpacer,
            'Stack': buildStack,
            'Text': buildText,
          },
          material: {
            'Icon': buildIcon,
            'Scaffold': buildScaffold,
          },
        ),
        icons: RestageIconTable.fromFamilies(families: {
          'MaterialIcons': {
            0xf636: IconData(0xf636, fontFamily: 'MaterialIcons'),
            0xf016b: IconData(0xf016b, fontFamily: 'MaterialIcons'),
          },
        }, mirrored: {
          'MaterialIcons': {
            0xf63a: IconData(0xf63a,
                fontFamily: 'MaterialIcons', matchTextDirection: true),
          },
        }),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) =>
                switch (key.split('#').first) { _ => throw StateError(key) },
            {
              '_hbb09c834d3': NativeBinding(
                  contract:
                      NativeBindingContract(type: '()->void', nullable: true),
                  value: widget._restageArgument2),
              '_hbc7931e8b3': NativeBinding(
                  contract:
                      _restageSentinelProtectionPaywallSurface_hbc7931e8b3Contract,
                  value:
                      _restageSentinelProtectionPaywallSurface_hbc7931e8b3Native),
              '_hce0a6b3f04': NativeBinding(
                  contract: NativeBindingContract(
                      type: '(dart:core#String)->void?', nullable: true),
                  value: widget._restageArgument1),
              '_hd341a8328d': NativeBinding(
                  contract:
                      NativeBindingContract(type: '()->void', nullable: true),
                  value: widget._restageArgument3),
            }),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_hbb09c834d3': 'widget.onClose',
                '_hbc7931e8b3':
                    '() => _restageInput0\n                    ?.call(_restageInput1)',
                '_hce0a6b3f04': 'widget.onContinue',
                '_hd341a8328d': 'widget.onSubscriptionInfo',
              },
        child: RestagePaywall(
          id: 'sentinel_protection',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: sentinelProtectionPaywallPlacementDefinition,
            name: widget._restagePlacementName,
            eventOwner: context,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            '_hbb09c834d3': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hbb09c834d3',
              "type": '()->void',
              "nullable": true
            },
            '_hbc7931e8b3': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hbc7931e8b3',
              "type": 'installed.call',
              "nullable": false
            },
            '_hce0a6b3f04': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hce0a6b3f04',
              "type": '(dart:core#String)->void?',
              "nullable": true
            },
            '_hd341a8328d': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hd341a8328d',
              "type": '()->void',
              "nullable": true
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
        backgroundColor: const Color(0xFFF4F5F7),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header.
                // Back affordance, top-left (start-aligned Row).
                Row(
                  children: [
                    GestureDetector(
                      onTap: widget._restageArgument2,
                      child: const Icon(
                        Icons.chevron_left_rounded,
                        color: Color(0xFF0EA5A4),
                        size: 30,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Select your protection plan',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF14142B),
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'No commitment. You can cancel anytime in your Apple account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF6B6B76),
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                // Slack above the hero — pushes it into the upper-middle.
                const Spacer(),
                // Brand badge + discount mark hero, sized for central presence.
                SizedBox(
                  height: 178,
                  child: Stack(
                    children: [
                      Center(
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD6F5F2),
                            borderRadius: BorderRadius.circular(75),
                          ),
                          child: Center(
                            child: Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0EA5A4),
                                borderRadius: BorderRadius.circular(46),
                              ),
                              child: const Icon(
                                Icons.shield_rounded,
                                color: Colors.white,
                                size: 50,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 70,
                        top: 16,
                        child: Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5A4D),
                            borderRadius: BorderRadius.circular(31),
                          ),
                          child: const Center(
                            child: Text(
                              '%',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Slack between the hero and the cards.
                const Spacer(),
                // 1-year plan (default selected). A "Save 50%" badge sits at the
                // top-right; the teal frame + filled radio track the selection.
                GestureDetector(
                  onTap: selectYear,
                  child: Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: yearSelected
                                ? const Color(0xFF0EA5A4)
                                : const Color(0xFFE2E3E8),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            // Radio indicator.
                            yearSelected
                                ? Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0EA5A4),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  )
                                : Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(
                                        color: const Color(0xFFC2C3CC),
                                        width: 2,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '1-year plan',
                                    style: TextStyle(
                                      color: Color(0xFF14142B),
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        r'$99.99',
                                        style: TextStyle(
                                          color: Color(0xFF9A9AA3),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        r'$49.99',
                                        style: TextStyle(
                                          color: Color(0xFF14142B),
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Text(
                              r'$4.17/month',
                              style: TextStyle(
                                color: Color(0xFF0EA5A4),
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0EA5A4),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Text(
                            'Save 50%',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 1-month plan (unselected default). The standalone monthly price
                // binds to the live monthly slot.
                GestureDetector(
                  onTap: selectMonth,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: yearSelected
                            ? const Color(0xFFE2E3E8)
                            : const Color(0xFF0EA5A4),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        yearSelected
                            ? Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: const Color(0xFFC2C3CC),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              )
                            : Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0EA5A4),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            '1-month plan',
                            style: TextStyle(
                              color: Color(0xFF14142B),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          r'$12.99/month',
                          style: const TextStyle(
                            color: Color(0xFF6B6B76),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Slack between the cards and the bottom block.
                const Spacer(),
                const Text(
                  r'First year — $49.99. Auto-renews at $99.99/year.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF6B6B76),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                // Start subscription CTA — teal pill.
                GestureDetector(
                  onTap: () => widget._restageArgument1
                      ?.call(yearSelected ? 'annual' : 'monthly'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0EA5A4),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Start subscription',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: GestureDetector(
                    onTap: widget._restageArgument3,
                    child: const Text(
                      'Subscription and privacy info',
                      style: TextStyle(
                        color: Color(0xFF0EA5A4),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
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
