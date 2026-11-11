part of '../lumen_holiday_promo.dart';

// ignore_for_file: type=lint, unnecessary_cast

final _lumenHolidayPromoPaywallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'lumen_holiday_promo',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'lumen_holiday_promo',
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
        '_h22ad072923': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': true},
          'label': 'onPrivacy'
        },
        '_h4cc80048b6': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': true},
          'label': 'onRestore'
        },
        '_h5530a497c9': <String, Object?>{
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
                  '5530a497c955ba690be10b1b056df2593fef2d693335bc309ede305ba543235c'
            }
          }
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
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xe037: IconData(0xe037, fontFamily: 'MaterialIcons'),
        0xe15a: IconData(0xe15a, fontFamily: 'MaterialIcons'),
      },
    }),
  ),
  surfaceWidget: 'LumenHolidayPromoPaywallSurface',
);

final lumenHolidayPromoPaywallPlacementDefinition =
    () => _lumenHolidayPromoPaywallPlacementDefinitionValue;

final _restageLumenHolidayPromoPaywallSurface_h5530a497c9Contract =
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
        "5530a497c955ba690be10b1b056df2593fef2d693335bc309ede305ba543235c"
  }
});
final NativeCallAdapter
    _restageLumenHolidayPromoPaywallSurface_h5530a497c9Native =
    NativeCallAdapter(
        _restageLumenHolidayPromoPaywallSurface_h5530a497c9Contract,
        (_restageInputs, _restageCells) {
  T _restageAs<T>(Object? value) => value as T;
  final ValueChanged<String>? _restageInput0 =
      _restageAs<ValueChanged<String>?>((_restageInputs[0] == null
          ? null
          : (_restageInputs[0] as ValueNative).value));
  final void Function() _restageResult =
      () => _restageInput0?.call('winter_yearly');
  return NativeBinding<void Function()>(
      contract: NativeBindingContract(type: "()->void", nullable: false),
      value: _restageResult);
});

final class LumenHolidayPromoPaywallSurface extends StatelessWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const LumenHolidayPromoPaywallSurface({
    super.key,
    ValueChanged<String>? onContinue,
    VoidCallback? onRestore,
    VoidCallback? onTerms,
    VoidCallback? onPrivacy,
    String? placement,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored1 = onContinue,
        _restageStored2 = onRestore,
        _restageStored3 = onTerms,
        _restageStored4 = onPrivacy,
        _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [LumenHolidayPromoPaywallSurface] for the default placement; no name is needed.
  const LumenHolidayPromoPaywallSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    ValueChanged<String>? onContinue,
    VoidCallback? onRestore,
    VoidCallback? onTerms,
    VoidCallback? onPrivacy,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  })  : _restageStored1 = onContinue,
        _restageStored2 = onRestore,
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
            'Icon': buildIcon,
            'Scaffold': buildScaffold,
          },
        ),
        icons: RestageIconTable.fromFamilies(families: {
          'MaterialIcons': {
            0xe037: IconData(0xe037, fontFamily: 'MaterialIcons'),
            0xe15a: IconData(0xe15a, fontFamily: 'MaterialIcons'),
          },
        }),
      ).addToInstalled();
      final restageContent = RestageNativeValues(
        bindings: _restageRecording.bindings(
            (key) =>
                switch (key.split('#').first) { _ => throw StateError(key) },
            {
              '_h22ad072923': NativeBinding(
                  contract:
                      NativeBindingContract(type: '()->void', nullable: true),
                  value: _restageArgument4),
              '_h4cc80048b6': NativeBinding(
                  contract:
                      NativeBindingContract(type: '()->void', nullable: true),
                  value: _restageArgument2),
              '_h5530a497c9': NativeBinding(
                  contract:
                      _restageLumenHolidayPromoPaywallSurface_h5530a497c9Contract,
                  value:
                      _restageLumenHolidayPromoPaywallSurface_h5530a497c9Native),
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
                '_h22ad072923': 'onPrivacy',
                '_h4cc80048b6': 'onRestore',
                '_h5530a497c9': '() => _restageInput0?.call(\'winter_yearly\')',
                '_hce0a6b3f04': 'onContinue',
                '_he2dd86c934': 'onTerms',
              },
        child: RestagePaywall(
          id: 'lumen_holiday_promo',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: lumenHolidayPromoPaywallPlacementDefinition,
            name: _restagePlacementName,
            eventOwner: context,
          ),
          context: <String, Object?>{
            ..._restageRecording.values,
            '_h22ad072923': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h22ad072923',
              "type": '()->void',
              "nullable": true
            },
            '_h4cc80048b6': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h4cc80048b6',
              "type": '()->void',
              "nullable": true
            },
            '_h5530a497c9': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h5530a497c9',
              "type": 'installed.call',
              "nullable": false
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
        body: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: dark
                        ? const [
                            Color(0xFF06111F),
                            Color(0xFF0B1B33),
                            Color(0xFF071426),
                          ]
                        : const [
                            Color(0xFFF3F8FF),
                            Color(0xFFE8F1FB),
                            Color(0xFFEEF3FA),
                          ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            // The aurora: a teal-to-violet sweep whose open ends fall offscreen.
            Positioned(
              left: -80,
              top: -160,
              child: Container(
                width: 560,
                height: 560,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    center: const Alignment(0.2, -0.4),
                    startAngle: 1.9199,
                    endAngle: 5.4105,
                    colors: dark
                        ? const [
                            Color(0x005EDBD1),
                            Color(0x8C5EDBD1),
                            Color(0x8C8B7CF6),
                            Color(0x005EDBD1),
                          ]
                        : const [
                            Color(0x005EDBD1),
                            Color(0x735EDBD1),
                            Color(0x668B7CF6),
                            Color(0x005EDBD1),
                          ],
                    stops: const [0.0, 0.3, 0.6, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 40,
              top: 110,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
                ),
              ),
            ),
            Positioned(
              left: 120,
              top: 60,
              child: Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
                ),
              ),
            ),
            Positioned(
              left: 210,
              top: 150,
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
                ),
              ),
            ),
            Positioned(
              left: 300,
              top: 80,
              child: Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
                ),
              ),
            ),
            Positioned(
              left: 350,
              top: 200,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
                ),
              ),
            ),
            Positioned(
              left: 70,
              top: 230,
              child: Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
                ),
              ),
            ),
            Positioned(
              left: 250,
              top: 250,
              child: Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
                ),
              ),
            ),
            Positioned(
              left: 330,
              top: 300,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
                ),
              ),
            ),
            Positioned(
              left: 150,
              top: 320,
              child: Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 72, 24, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.ac_unit,
                                      size: 28,
                                      color: dark
                                          ? const Color(0xFF8FF0E8)
                                          : const Color(0xFF0E7C74),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'WINTER OFFER',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 2,
                                        color: dark
                                            ? const Color(0xFF8FF0E8)
                                            : const Color(0xFF0E7C74),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: dark
                                    ? const Color(0x295EDBD1)
                                    : const Color(0x405EDBD1),
                              ),
                              child: Text(
                                'ENDS JAN 2',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                  color: dark
                                      ? const Color(0xFF8FF0E8)
                                      : const Color(0xFF0E7C74),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // The airy top is a share of what is left rather than a
                        // fixed drop, so the headline is on the first screen of a
                        // small phone and the design keeps its height on a tall
                        // one.
                        const Flexible(child: SizedBox(height: 150)),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'A quieter\nwinter.',
                                  style: TextStyle(
                                    fontSize: 46,
                                    height: 1.0,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1.8,
                                    color: dark
                                        ? const Color(0xFFEEF6FF)
                                        : const Color(0xFF152238),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    // Capped rather than fixed, so a narrow
                                    // phone can shrink it.
                                    Flexible(
                                      child: Container(
                                        constraints: const BoxConstraints(
                                          maxWidth: 330,
                                        ),
                                        child: Text(
                                          "The full library for the darkest weeks, at the "
                                          "year's lowest price.",
                                          style: TextStyle(
                                            fontSize: 17,
                                            height: 1.45,
                                            color: dark
                                                ? const Color(0xFF9FB3CC)
                                                : const Color(0xFF5E6F8A),
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
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            color: dark
                                ? const Color(0x0FFFFFFF)
                                : const Color(0xB3FFFFFF),
                            border: Border.all(
                              color: dark
                                  ? const Color(0x24FFFFFF)
                                  : const Color(0x1A152238),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  // Scales down rather than overflowing when a
                                  // longer localised price widens the row.
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            r'$49.99',
                                            style: TextStyle(
                                              fontSize: 42,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -1.6,
                                              color: dark
                                                  ? const Color(0xFFEEF6FF)
                                                  : const Color(0xFF152238),
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
                                                    ? const Color(0xFF9FB3CC)
                                                    : const Color(0xFF5E6F8A),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Flexible(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 7),
                                      child: Text(
                                        r'$69.99',
                                        style: TextStyle(
                                          fontSize: 14,
                                          decoration:
                                              TextDecoration.lineThrough,
                                          color: dark
                                              ? const Color(0xFF9FB3CC)
                                              : const Color(0xFF5E6F8A),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Container(
                                height: 1,
                                decoration: BoxDecoration(
                                  color: dark
                                      ? const Color(0x24FFFFFF)
                                      : const Color(0x1A152238),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    size: 20,
                                    color: dark
                                        ? const Color(0xFF8FF0E8)
                                        : const Color(0xFF0E7C74),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Everything in Lumen Plus',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: -0.1,
                                        color: dark
                                            ? const Color(0xFFEEF6FF)
                                            : const Color(0xFF152238),
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
                                        ? const Color(0xFF8FF0E8)
                                        : const Color(0xFF0E7C74),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      r'Renews at $69.99 / year',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: -0.1,
                                        color: dark
                                            ? const Color(0xFFEEF6FF)
                                            : const Color(0xFF152238),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () => _restageArgument1?.call('winter_yearly'),
                          child: Container(
                            height: 58,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: dark
                                    ? const [
                                        Color(0xFF5EDBD1),
                                        Color(0xFF8B7CF6)
                                      ]
                                    : const [
                                        Color(0xFF2FB8AD),
                                        Color(0xFF6A55C4)
                                      ],
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x475EDBD1),
                                  blurRadius: 34,
                                  offset: Offset(0, 14),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                'Claim the winter price',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: dark
                                      ? const Color(0xFF061224)
                                      : const Color(0xFFFFFFFF),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: GestureDetector(
                                onTap: _restageArgument2,
                                child: Text(
                                  'Restore',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: dark
                                        ? const Color(0xFF6F83A0)
                                        : const Color(0xFF8895AA),
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
                                        ? const Color(0xFF6F83A0)
                                        : const Color(0xFF8895AA),
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
                                        ? const Color(0xFF6F83A0)
                                        : const Color(0xFF8895AA),
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
      ));
    })();
  }
}
