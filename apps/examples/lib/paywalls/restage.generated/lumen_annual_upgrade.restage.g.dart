part of '../lumen_annual_upgrade.dart';

// ignore_for_file: type=lint, unnecessary_cast

final _lumenAnnualUpgradePaywallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'lumen_annual_upgrade',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'lumen_annual_upgrade',
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
        '_h038e4733db': <String, Object?>{
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
                }
              ],
              'captures': <String, Object?>{},
              'result': <String, Object?>{
                'kind': 'native',
                'nativeType': '()->void'
              },
              'implementation':
                  '038e4733dbd9e6e03110a9b2d85ebe413d5eb6ac18e4ba2975cfb5572ae1309e'
            }
          }
        },
        '_h22ad072923': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': true},
          'label': 'onPrivacy'
        },
        '_hbb09c834d3': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': true},
          'label': 'onClose'
        },
        '_hce0a6b3f04': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': '(dart:core#String)->void?',
            'nullable': true
          },
          'label': 'onContinue'
        },
        '_he2dd86c934': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': true},
          'label': 'onTerms'
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
        'FittedBox': buildFittedBox,
        'Flexible': buildFlexible,
        'GestureDetector': buildGestureDetector,
        'Padding': buildPadding,
        'Positioned': buildPositioned,
        'Row': buildRow,
        'SingleChildScrollView': buildSingleChildScrollView,
        'SizedBox': buildSizedBox,
        'Stack': buildStack,
        'Text': buildText,
      },
      material: {
        'Divider': buildDivider,
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xe15a: IconData(0xe15a, fontFamily: 'MaterialIcons'),
        0xf4bc: IconData(0xf4bc, fontFamily: 'MaterialIcons'),
      },
    }),
  ),
  surfaceWidget: 'LumenAnnualUpgradePaywallSurface',
);

final lumenAnnualUpgradePaywallPlacementDefinition =
    () => _lumenAnnualUpgradePaywallPlacementDefinitionValue;

final _restageLumenAnnualUpgradePaywallSurface_h038e4733dbContract =
    NativeBindingContract.fromJson(<String, Object?>{
  "type": "installed.call",
  "nullable": false,
  "call": <String, Object?>{
    "inputs": <Object?>[
      <String, Object?>{
        "kind": "native",
        "nativeType": "(dart:core#String)->void?",
        "nullable": true
      }
    ],
    "captures": <String, Object?>{},
    "result": <String, Object?>{"kind": "native", "nativeType": "()->void"},
    "implementation":
        "038e4733dbd9e6e03110a9b2d85ebe413d5eb6ac18e4ba2975cfb5572ae1309e"
  }
});
final NativeCallAdapter
    _restageLumenAnnualUpgradePaywallSurface_h038e4733dbNative =
    NativeCallAdapter(
        _restageLumenAnnualUpgradePaywallSurface_h038e4733dbContract,
        (_restageInputs, _restageCells) {
  T _restageAs<T>(Object? value) => value as T;
  final ValueChanged<String>? _restageInput0 =
      _restageAs<ValueChanged<String>?>((_restageInputs[0] == null
          ? null
          : (_restageInputs[0] as ValueNative).value));
  final void Function() _restageResult = () => _restageInput0?.call('yearly');
  return NativeBinding<void Function()>(
      contract: NativeBindingContract(type: "()->void", nullable: false),
      value: _restageResult);
});

final class LumenAnnualUpgradePaywallSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const LumenAnnualUpgradePaywallSurface({
    super.key,
    ValueChanged<String>? onContinue,
    VoidCallback? onClose,
    VoidCallback? onTerms,
    VoidCallback? onPrivacy,
    String? placement,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored1 = onContinue,
        _restageStored2 = onClose,
        _restageStored3 = onTerms,
        _restageStored4 = onPrivacy,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [LumenAnnualUpgradePaywallSurface] for the default placement; no name is needed.
  const LumenAnnualUpgradePaywallSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ValueChanged<String>? onContinue,
    VoidCallback? onClose,
    VoidCallback? onTerms,
    VoidCallback? onPrivacy,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored1 = onContinue,
        _restageStored2 = onClose,
        _restageStored3 = onTerms,
        _restageStored4 = onPrivacy,
        _restagePlacementName = restagePlacementId;

  final ValueChanged<String>? _restageStored1;
  ValueChanged<String>? get _restageArgument1 => _restageStored1;

  final VoidCallback? _restageStored2;
  VoidCallback? get _restageArgument2 => _restageStored2;

  final VoidCallback? _restageStored3;
  VoidCallback? get _restageArgument3 => _restageStored3;

  final VoidCallback? _restageStored4;
  VoidCallback? get _restageArgument4 => _restageStored4;
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
            'Expanded': buildExpanded,
            'FittedBox': buildFittedBox,
            'Flexible': buildFlexible,
            'GestureDetector': buildGestureDetector,
            'Padding': buildPadding,
            'Positioned': buildPositioned,
            'Row': buildRow,
            'SingleChildScrollView': buildSingleChildScrollView,
            'SizedBox': buildSizedBox,
            'Stack': buildStack,
            'Text': buildText,
          },
          material: {
            'Divider': buildDivider,
            'Icon': buildIcon,
            'Scaffold': buildScaffold,
          },
        ),
        icons: RestageIconTable.fromFamilies(families: {
          'MaterialIcons': {
            0xe15a: IconData(0xe15a, fontFamily: 'MaterialIcons'),
            0xf4bc: IconData(0xf4bc, fontFamily: 'MaterialIcons'),
          },
        }),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) =>
                switch (key.split('#').first) { _ => throw StateError(key) },
            {
              '_h038e4733db': NativeBinding(
                  contract:
                      _restageLumenAnnualUpgradePaywallSurface_h038e4733dbContract,
                  value:
                      _restageLumenAnnualUpgradePaywallSurface_h038e4733dbNative),
              '_h22ad072923': NativeBinding(
                  contract:
                      NativeBindingContract(type: '()->void', nullable: true),
                  value: _restageArgument4),
              '_hbb09c834d3': NativeBinding(
                  contract:
                      NativeBindingContract(type: '()->void', nullable: true),
                  value: _restageArgument2),
              '_hce0a6b3f04': NativeBinding(
                  contract: NativeBindingContract(
                      type: '(dart:core#String)->void?', nullable: true),
                  value: _restageArgument1),
              '_he2dd86c934': NativeBinding(
                  contract:
                      NativeBindingContract(type: '()->void', nullable: true),
                  value: _restageArgument3),
            }),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h038e4733db': '() => _restageInput0?.call(\'yearly\')',
                '_h22ad072923': 'onPrivacy',
                '_hbb09c834d3': 'onClose',
                '_hce0a6b3f04': 'onContinue',
                '_he2dd86c934': 'onTerms',
              },
        child: RestagePaywall(
          id: 'lumen_annual_upgrade',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: lumenAnnualUpgradePaywallPlacementDefinition,
            name: _restagePlacementName,
            eventOwner: context,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            '_h038e4733db': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h038e4733db',
              "type": 'installed.call',
              "nullable": false
            },
            '_h22ad072923': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h22ad072923',
              "type": '()->void',
              "nullable": true
            },
            '_hbb09c834d3': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hbb09c834d3',
              "type": '()->void',
              "nullable": true
            },
            '_hce0a6b3f04': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hce0a6b3f04',
              "type": '(dart:core#String)->void?',
              "nullable": true
            },
            '_he2dd86c934': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_he2dd86c934',
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
      final dark = Theme.of(context).brightness == Brightness.dark;
      return _restageDesign(Scaffold(
        body: Container(
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF120E22) : const Color(0xFFFFFDFB),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The sunrise band: a share of the screen rather than a fixed
              // height, so a small phone keeps room for the price and the CTA.
              Flexible(
                flex: 46,
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: 220,
                    maxHeight: 420,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: const Alignment(-0.34, -0.94),
                      end: const Alignment(0.34, 0.94),
                      colors: dark
                          ? const [
                              Color(0xFF2A1B4D),
                              Color(0xFF5B2C6F),
                              Color(0xFFC4573A),
                            ]
                          : const [
                              Color(0xFFEFE7FF),
                              Color(0xFFF8D7E3),
                              Color(0xFFFFC9A9),
                            ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: -60,
                        bottom: -140,
                        child: Container(
                          width: 360,
                          height: 360,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [Color(0x8CFFFFFF), Color(0x00FFFFFF)],
                              stops: [0.0, 0.68],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 26,
                        top: 150,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              center: Alignment(-0.2, -0.3),
                              colors: [
                                Color(0xFFFFF1E0),
                                Color(0xFFFFB59A),
                                Color(0x00FFB59A),
                              ],
                              stops: [0.0, 0.55, 0.72],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x80FFB59A),
                                blurRadius: 80,
                                offset: Offset(0, 30),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 24,
                        top: 72,
                        child: Row(
                          children: [
                            Icon(
                              Icons.wb_sunny_outlined,
                              size: 28,
                              color: dark
                                  ? const Color(0xFFF7F3FF)
                                  : const Color(0xFF2A2833),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'LUMEN PLUS',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                                color: dark
                                    ? const Color(0xFFF7F3FF)
                                    : const Color(0xFF2A2833),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 40,
                        child: Text(
                          'A whole year\nof calm.',
                          style: TextStyle(
                            fontSize: 40,
                            height: 1.02,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.4,
                            color: dark
                                ? const Color(0xFFF7F3FF)
                                : const Color(0xFF2A2833),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 54,
                // A tablet gets a centered column rather than a stretched card.
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Switch to yearly and pay \$59.99 for your first year. '
                                    'Every session, sleep story and focus mix included.',
                                    style: TextStyle(
                                      fontSize: 16,
                                      height: 1.45,
                                      color: dark
                                          ? const Color(0xFFB4AACB)
                                          : const Color(0xFF7A7290),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 20,
                                        color: dark
                                            ? const Color(0xFFFFB59A)
                                            : const Color(0xFF6A55C4),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Save 44% against monthly',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: -0.1,
                                            color: dark
                                                ? const Color(0xFFF7F3FF)
                                                : const Color(0xFF2A2833),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 20,
                                        color: dark
                                            ? const Color(0xFFFFB59A)
                                            : const Color(0xFF6A55C4),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Offline downloads for every session',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: -0.1,
                                            color: dark
                                                ? const Color(0xFFF7F3FF)
                                                : const Color(0xFF2A2833),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 20,
                                        color: dark
                                            ? const Color(0xFFFFB59A)
                                            : const Color(0xFF6A55C4),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'New sleep stories every week',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: -0.1,
                                            color: dark
                                                ? const Color(0xFFF7F3FF)
                                                : const Color(0xFF2A2833),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 18,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              color: dark
                                  ? const Color(0x0FFFFFFF)
                                  : const Color(0xFFFFFFFF),
                              border: Border.all(
                                color: dark
                                    ? const Color(0x1AFFFFFF)
                                    : const Color(0xFFEFE9F6),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'YEARLY',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.6,
                                        color: dark
                                            ? const Color(0xFFFFB59A)
                                            : const Color(0xFFC4573A),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        color: dark
                                            ? const Color(0xFFFFB59A)
                                            : const Color(0xFFC4573A),
                                      ),
                                      child: const Text(
                                        'SAVE 44%',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.4,
                                          color: Color(0xFFFFFFFF),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Scales down rather than overflowing when a
                                // longer localised price widens the row.
                                Row(
                                  children: [
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              r'$59.99',
                                              style: TextStyle(
                                                fontSize: 42,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: -1.6,
                                                color: dark
                                                    ? const Color(0xFFF7F3FF)
                                                    : const Color(0xFF2A2833),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Sits on the price's baseline, which the
                                            // catalog Row cannot align to directly.
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 7),
                                              child: Text(
                                                'first year',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: dark
                                                      ? const Color(0xFFB4AACB)
                                                      : const Color(0xFF7A7290),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 7),
                                              child: Text(
                                                r'$107.88',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  decoration: TextDecoration
                                                      .lineThrough,
                                                  color: dark
                                                      ? const Color(0xFFB4AACB)
                                                      : const Color(0xFF7A7290),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Divider(
                                  height: 16,
                                  thickness: 1,
                                  color: dark
                                      ? const Color(0x1AFFFFFF)
                                      : const Color(0xFFEFE9F6),
                                ),
                                Text(
                                  r'$5 a month, billed once. '
                                  r'Renews at $69.99 / year.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: dark
                                        ? const Color(0xFFB4AACB)
                                        : const Color(0xFF7A7290),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => _restageArgument1?.call('yearly'),
                            child: Container(
                              height: 58,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                // Dark is a flat coral; light is the violet ramp.
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: dark
                                      ? const [
                                          Color(0xFFFFB59A),
                                          Color(0xFFFFB59A),
                                        ]
                                      : const [
                                          Color(0xFF6A55C4),
                                          Color(0xFF9A7BE8),
                                        ],
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Go yearly',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: dark
                                        ? const Color(0xFF2A1B4D)
                                        : const Color(0xFFFFFFFF),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: GestureDetector(
                                  onTap: _restageArgument2,
                                  child: Text(
                                    'Keep monthly',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: dark
                                          ? const Color(0xFF7E759B)
                                          : const Color(0xFF9A93AE),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 18),
                              Flexible(
                                child: GestureDetector(
                                  onTap: _restageArgument3,
                                  child: Text(
                                    'Terms',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: dark
                                          ? const Color(0xFF7E759B)
                                          : const Color(0xFF9A93AE),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 18),
                              Flexible(
                                child: GestureDetector(
                                  onTap: _restageArgument4,
                                  child: Text(
                                    'Privacy',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: dark
                                          ? const Color(0xFF7E759B)
                                          : const Color(0xFF9A93AE),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
    })();
  }
}
