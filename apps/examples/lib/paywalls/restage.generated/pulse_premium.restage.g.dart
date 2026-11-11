part of '../pulse_premium.dart';

// ignore_for_file: type=lint, unnecessary_cast

final _pulsePremiumPaywallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'pulse_premium',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'pulse_premium',
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
          'label': 'widget.onPrivacy'
        },
        '_h605e4d5108': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': '(dart:core#String,dart:core#String)->void?',
            'nullable': true
          },
          'label': 'widget.onContinue'
        },
        '_h6f877ef55c': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{
            'type': 'installed.call',
            'nullable': false,
            'call': <String, Object?>{
              'inputs': <Object?>[
                <String, Object?>{
                  'kind': 'native',
                  'nativeType': '(dart:core#String,dart:core#String)->void?',
                  'nullable': true
                },
                <String, Object?>{'kind': 'String'},
                <String, Object?>{'kind': 'String'}
              ],
              'captures': <String, Object?>{},
              'result': <String, Object?>{
                'kind': 'native',
                'nativeType': '()->void'
              },
              'implementation':
                  '6f877ef55ce77624acadcafe90e3633c19efed361bf777056dd0efb0b69baad1'
            }
          }
        },
        '_hbb09c834d3': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': true},
          'label': 'widget.onClose'
        },
        '_he2dd86c934': <String, Object?>{
          'kind': 'nativeBinding',
          'contract': <String, Object?>{'type': '()->void', 'nullable': true},
          'label': 'widget.onTerms'
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
        'IntrinsicHeight': buildIntrinsicHeight,
        'Padding': buildPadding,
        'Row': buildRow,
        'SafeArea': buildSafeArea,
        'SingleChildScrollView': buildSingleChildScrollView,
        'SizedBox': buildSizedBox,
        'Spacer': buildSpacer,
        'Text': buildText,
        'TextRich': buildTextRich,
      },
      material: {
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
        'TextButton': buildTextButton,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xefdb: IconData(0xefdb, fontFamily: 'MaterialIcons'),
        0xf580: IconData(0xf580, fontFamily: 'MaterialIcons'),
        0xf596: IconData(0xf596, fontFamily: 'MaterialIcons'),
        0xf5d1: IconData(0xf5d1, fontFamily: 'MaterialIcons'),
        0xf647: IconData(0xf647, fontFamily: 'MaterialIcons'),
        0xf6fb: IconData(0xf6fb, fontFamily: 'MaterialIcons'),
        0xf820: IconData(0xf820, fontFamily: 'MaterialIcons'),
        0xf889: IconData(0xf889, fontFamily: 'MaterialIcons'),
        0xf0023: IconData(0xf0023, fontFamily: 'MaterialIcons'),
        0xf0040: IconData(0xf0040, fontFamily: 'MaterialIcons'),
        0xf026e: IconData(0xf026e, fontFamily: 'MaterialIcons'),
        0xf027e: IconData(0xf027e, fontFamily: 'MaterialIcons'),
        0xf03c0: IconData(0xf03c0, fontFamily: 'MaterialIcons'),
      },
    }, mirrored: {
      'MaterialIcons': {
        0xf0254: IconData(0xf0254,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
      },
    }),
  ),
  surfaceWidget: 'PulsePremiumPaywallSurface',
);

final pulsePremiumPaywallPlacementDefinition =
    () => _pulsePremiumPaywallPlacementDefinitionValue;

final _restagePulsePremiumPaywallSurface_h6f877ef55cContract =
    NativeBindingContract.fromJson(<String, Object?>{
  "type": "installed.call",
  "nullable": false,
  "call": <String, Object?>{
    "inputs": <Object?>[
      <String, Object?>{
        "kind": "native",
        "nativeType": "(dart:core#String,dart:core#String)->void?",
        "nullable": true
      },
      <String, Object?>{"kind": "String"},
      <String, Object?>{"kind": "String"}
    ],
    "captures": <String, Object?>{},
    "result": <String, Object?>{"kind": "native", "nativeType": "()->void"},
    "implementation":
        "6f877ef55ce77624acadcafe90e3633c19efed361bf777056dd0efb0b69baad1"
  }
});
final NativeCallAdapter _restagePulsePremiumPaywallSurface_h6f877ef55cNative =
    NativeCallAdapter(_restagePulsePremiumPaywallSurface_h6f877ef55cContract,
        (_restageInputs, _restageCells) {
  T _restageAs<T>(Object? value) => value as T;
  final void Function(String, String)? _restageInput0 =
      _restageAs<void Function(String, String)?>((_restageInputs[0] == null
          ? null
          : (_restageInputs[0] as ValueNative).value));
  final String _restageInput1 = _restageAs<String>(_restageInputs[1]);
  final String _restageInput2 = _restageAs<String>(_restageInputs[2]);
  final void Function() _restageResult = () => _restageInput0?.call(
        _restageInput1,
        _restageInput2,
      );
  return NativeBinding<void Function()>(
      contract: NativeBindingContract(type: "()->void", nullable: false),
      value: _restageResult);
});

final class PulsePremiumPaywallSurface extends StatefulWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const PulsePremiumPaywallSurface({
    super.key,
    void Function(String tier, String term)? onContinue,
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
  /// Use [PulsePremiumPaywallSurface] for the default placement; no name is needed.
  const PulsePremiumPaywallSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    void Function(String tier, String term)? onContinue,
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

  final void Function(String tier, String term)? _restageStored1;
  void Function(String tier, String term)? get _restageArgument1 =>
      _restageStored1;

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
  _PulsePremiumPaywallSurfaceState createState() =>
      _PulsePremiumPaywallSurfaceState();
}

final class _PulsePremiumPaywallSurfaceState
    extends State<PulsePremiumPaywallSurface> {
  // ignore: unused_element
  /// Tier strip selection: 0 = Basic, 1 = Premium, 2 = Premium+.
  int selectedTier = 1;

  // ignore: unused_element
  /// Plan selection: annual when true, monthly when false. Monthly is the
  /// default so the promo flash shows.
  bool annualSelected = false;

  // ignore: unused_element
  void selectBasic() => setState(() => selectedTier = 0);

  // ignore: unused_element
  void selectPremium() => setState(() => selectedTier = 1);

  // ignore: unused_element
  void selectPremiumPlus() => setState(() => selectedTier = 2);

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
            'Center': buildCenter,
            'Column': buildColumn,
            'Container': buildContainer,
            'Expanded': buildExpanded,
            'GestureDetector': buildGestureDetector,
            'IntrinsicHeight': buildIntrinsicHeight,
            'Padding': buildPadding,
            'Row': buildRow,
            'SafeArea': buildSafeArea,
            'SingleChildScrollView': buildSingleChildScrollView,
            'SizedBox': buildSizedBox,
            'Spacer': buildSpacer,
            'Text': buildText,
            'TextRich': buildTextRich,
          },
          material: {
            'Icon': buildIcon,
            'Scaffold': buildScaffold,
            'TextButton': buildTextButton,
          },
        ),
        icons: RestageIconTable.fromFamilies(families: {
          'MaterialIcons': {
            0xefdb: IconData(0xefdb, fontFamily: 'MaterialIcons'),
            0xf580: IconData(0xf580, fontFamily: 'MaterialIcons'),
            0xf596: IconData(0xf596, fontFamily: 'MaterialIcons'),
            0xf5d1: IconData(0xf5d1, fontFamily: 'MaterialIcons'),
            0xf647: IconData(0xf647, fontFamily: 'MaterialIcons'),
            0xf6fb: IconData(0xf6fb, fontFamily: 'MaterialIcons'),
            0xf820: IconData(0xf820, fontFamily: 'MaterialIcons'),
            0xf889: IconData(0xf889, fontFamily: 'MaterialIcons'),
            0xf0023: IconData(0xf0023, fontFamily: 'MaterialIcons'),
            0xf0040: IconData(0xf0040, fontFamily: 'MaterialIcons'),
            0xf026e: IconData(0xf026e, fontFamily: 'MaterialIcons'),
            0xf027e: IconData(0xf027e, fontFamily: 'MaterialIcons'),
            0xf03c0: IconData(0xf03c0, fontFamily: 'MaterialIcons'),
          },
        }, mirrored: {
          'MaterialIcons': {
            0xf0254: IconData(0xf0254,
                fontFamily: 'MaterialIcons', matchTextDirection: true),
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
                  value: widget._restageArgument4),
              '_h605e4d5108': NativeBinding(
                  contract: NativeBindingContract(
                      type: '(dart:core#String,dart:core#String)->void?',
                      nullable: true),
                  value: widget._restageArgument1),
              '_h6f877ef55c': NativeBinding(
                  contract:
                      _restagePulsePremiumPaywallSurface_h6f877ef55cContract,
                  value: _restagePulsePremiumPaywallSurface_h6f877ef55cNative),
              '_hbb09c834d3': NativeBinding(
                  contract:
                      NativeBindingContract(type: '()->void', nullable: true),
                  value: widget._restageArgument2),
              '_he2dd86c934': NativeBinding(
                  contract:
                      NativeBindingContract(type: '()->void', nullable: true),
                  value: widget._restageArgument3),
            }),
        labels: const bool.fromEnvironment('dart.vm.product')
            ? const <String, String>{}
            : const <String, String>{
                '_h22ad072923': 'widget.onPrivacy',
                '_h605e4d5108': 'widget.onContinue',
                '_h6f877ef55c':
                    '() => _restageInput0?.call(\n                  _restageInput1,\n                  _restageInput2,\n                )',
                '_hbb09c834d3': 'widget.onClose',
                '_he2dd86c934': 'widget.onTerms',
              },
        child: RestagePaywall(
          id: 'pulse_premium',
          placementBinding: RestagePaywall.generatedPlacementBinding(
            definition: pulsePremiumPaywallPlacementDefinition,
            name: widget._restagePlacementName,
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
            '_h605e4d5108': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h605e4d5108',
              "type": '(dart:core#String,dart:core#String)->void?',
              "nullable": true
            },
            '_h6f877ef55c': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_h6f877ef55c',
              "type": 'installed.call',
              "nullable": false
            },
            '_hbb09c834d3': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_hbb09c834d3',
              "type": '()->void',
              "nullable": true
            },
            '_he2dd86c934': <String, Object?>{
              "kind": "nativeBinding",
              "key": '_he2dd86c934',
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
        backgroundColor: const Color(0xFF0B0B12),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Scrollable value content; the offer zone below is pinned.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Close affordance, top-left (start-aligned Row).
                        Row(
                          children: [
                            GestureDetector(
                              onTap: widget._restageArgument2,
                              child: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFFE6E6F0),
                                size: 26,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Brand wordmark at the top.
                        const Center(
                          child: Text(
                            'Pulse',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Upgrade to Premium',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Tri-state segmented tier selector — Basic | Premium |
                        // Premium+. Each segment's fill + label color switch on
                        // `selectedTier == n`.
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF17171F),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: selectBasic,
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      color: selectedTier == 0
                                          ? const Color(0xFF7B61FF)
                                          : const Color(0x00000000),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Text(
                                      'Basic',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: selectedTier == 0
                                            ? const Color(0xFFFFFFFF)
                                            : const Color(0xFF9AA0AB),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: selectPremium,
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      color: selectedTier == 1
                                          ? const Color(0xFF7B61FF)
                                          : const Color(0x00000000),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Text(
                                      'Premium',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: selectedTier == 1
                                            ? const Color(0xFFFFFFFF)
                                            : const Color(0xFF9AA0AB),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: selectPremiumPlus,
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      color: selectedTier == 2
                                          ? const Color(0xFF7B61FF)
                                          : const Color(0x00000000),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Text(
                                      'Premium+',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: selectedTier == 2
                                            ? const Color(0xFFFFFFFF)
                                            : const Color(0xFF9AA0AB),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        // The full feature list — icon-tile + bold-title + grey
                        // subtitle rows, inlined flat. The long list scrolls; the
                        // offer pins.
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E28),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(
                                  Icons.verified_rounded,
                                  color: Color(0xFF7B61FF),
                                  size: 23,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Verified badge',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Build trust and protect your profile from '
                                      'impersonation.',
                                      style: TextStyle(
                                        color: Color(0xFF9AA0AB),
                                        fontSize: 13,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E28),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(
                                  Icons.auto_awesome_rounded,
                                  color: Color(0xFF7B61FF),
                                  size: 23,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'AI-assisted replies',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Draft faster with higher assistant usage '
                                      'limits.',
                                      style: TextStyle(
                                        color: Color(0xFF9AA0AB),
                                        fontSize: 13,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E28),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(
                                  Icons.trending_up_rounded,
                                  color: Color(0xFF7B61FF),
                                  size: 23,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Boosted reach',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Get your posts seen by more people across '
                                      'the network.',
                                      style: TextStyle(
                                        color: Color(0xFF9AA0AB),
                                        fontSize: 13,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E28),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(
                                  Icons.do_not_disturb_on_outlined,
                                  color: Color(0xFF7B61FF),
                                  size: 23,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Fewer ads',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'See about half the ads across your '
                                      'timelines.',
                                      style: TextStyle(
                                        color: Color(0xFF9AA0AB),
                                        fontSize: 13,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E28),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: const Icon(
                                  Icons.notes_rounded,
                                  color: Color(0xFF7B61FF),
                                  size: 23,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Longer posts',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Write longer posts with more room to say '
                                      'it.',
                                      style: TextStyle(
                                        color: Color(0xFF9AA0AB),
                                        fontSize: 13,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Mid-tier features — hidden for the entry tier (selected
                        // index 0), shown for the upper two tiers.
                        selectedTier == 0
                            ? const SizedBox()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E1E28),
                                            borderRadius:
                                                BorderRadius.circular(11),
                                          ),
                                          child: const Icon(
                                            Icons.edit_rounded,
                                            color: Color(0xFF7B61FF),
                                            size: 23,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Edit window',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'Fix typos for up to an hour after posting.',
                                                style: TextStyle(
                                                  color: Color(0xFF9AA0AB),
                                                  fontSize: 13,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E1E28),
                                            borderRadius:
                                                BorderRadius.circular(11),
                                          ),
                                          child: const Icon(
                                            Icons.videocam_rounded,
                                            color: Color(0xFF7B61FF),
                                            size: 23,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'HD video',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'Upload longer, higher-quality videos.',
                                                style: TextStyle(
                                                  color: Color(0xFF9AA0AB),
                                                  fontSize: 13,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E1E28),
                                            borderRadius:
                                                BorderRadius.circular(11),
                                          ),
                                          child: const Icon(
                                            Icons.lock_rounded,
                                            color: Color(0xFF7B61FF),
                                            size: 23,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Encrypted DMs',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'Keep your direct messages private and '
                                                'secure.',
                                                style: TextStyle(
                                                  color: Color(0xFF9AA0AB),
                                                  fontSize: 13,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E1E28),
                                            borderRadius:
                                                BorderRadius.circular(11),
                                          ),
                                          child: const Icon(
                                            Icons.article_rounded,
                                            color: Color(0xFF7B61FF),
                                            size: 23,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Long-form publishing',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'Publish formatted, long-form articles.',
                                                style: TextStyle(
                                                  color: Color(0xFF9AA0AB),
                                                  fontSize: 13,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                        // Top-tier-only features — shown only for the top tier
                        // (selected index 2).
                        selectedTier == 2
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E1E28),
                                            borderRadius:
                                                BorderRadius.circular(11),
                                          ),
                                          child: const Icon(
                                            Icons.workspace_premium_rounded,
                                            color: Color(0xFF7B61FF),
                                            size: 23,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Creator subscriptions',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'Earn recurring revenue from your '
                                                'subscribers.',
                                                style: TextStyle(
                                                  color: Color(0xFF9AA0AB),
                                                  fontSize: 13,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E1E28),
                                            borderRadius:
                                                BorderRadius.circular(11),
                                          ),
                                          child: const Icon(
                                            Icons.paid_rounded,
                                            color: Color(0xFF7B61FF),
                                            size: 23,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Revenue share',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'Share in the ad revenue from replies to '
                                                'your posts.',
                                                style: TextStyle(
                                                  color: Color(0xFF9AA0AB),
                                                  fontSize: 13,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E1E28),
                                            borderRadius:
                                                BorderRadius.circular(11),
                                          ),
                                          child: const Icon(
                                            Icons.insights_rounded,
                                            color: Color(0xFF7B61FF),
                                            size: 23,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Advanced analytics',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'See deeper insight into how your content '
                                                'performs.',
                                                style: TextStyle(
                                                  color: Color(0xFF9AA0AB),
                                                  fontSize: 13,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E1E28),
                                            borderRadius:
                                                BorderRadius.circular(11),
                                          ),
                                          child: const Icon(
                                            Icons.bookmark_rounded,
                                            color: Color(0xFF7B61FF),
                                            size: 23,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Bookmark folders',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'Organize your saved posts into custom '
                                                'folders.',
                                                style: TextStyle(
                                                  color: Color(0xFF9AA0AB),
                                                  fontSize: 13,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Pinned offer zone — the side-by-side plan cards, the CTA, and the
                // legal stay on screen while the value content above scrolls.
                // Monthly | Annual two-column cards (IntrinsicHeight equalises the
                // two card heights); the selected card gets the violet border and
                // tapping it re-targets the CTA.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: selectMonthly,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF17171F),
                              border: Border.all(
                                color: annualSelected
                                    ? const Color(0xFF2A2A33)
                                    : const Color(0xFF7B61FF),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Monthly',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '50% off',
                                  style: TextStyle(
                                    color: Color(0xFF7B61FF),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Text(
                                  'for 2 months',
                                  style: TextStyle(
                                    color: Color(0xFF9AA0AB),
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Text(
                                      'Then ',
                                      style: TextStyle(
                                        color: Color(0xFF9AA0AB),
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      selectedTier == 0
                                          ? r'$4.99'
                                          : selectedTier == 1
                                              ? r'$7.99'
                                              : r'$10.99',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const Text(
                                      '/mo',
                                      style: TextStyle(
                                        color: Color(0xFF9AA0AB),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: selectAnnual,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF17171F),
                              border: Border.all(
                                color: annualSelected
                                    ? const Color(0xFF7B61FF)
                                    : const Color(0xFF2A2A33),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Annual',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Best value',
                                  style: TextStyle(
                                    color: Color(0xFF9AA0AB),
                                    fontSize: 13,
                                  ),
                                ),
                                const Spacer(),
                                Row(
                                  children: [
                                    Text(
                                      selectedTier == 0
                                          ? r'$39.99'
                                          : selectedTier == 1
                                              ? r'$69.99'
                                              : r'$99.99',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const Text(
                                      '/yr',
                                      style: TextStyle(
                                        color: Color(0xFF9AA0AB),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Continue CTA — violet pill.
                GestureDetector(
                  onTap: () => widget._restageArgument1?.call(
                    selectedTier == 0
                        ? 'basic'
                        : selectedTier == 1
                            ? 'premium'
                            : 'premium_plus',
                    annualSelected ? 'annual' : 'monthly',
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B61FF),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Text(
                      'Subscribe & pay',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Dense legal fine print as one flowing italic rich-text paragraph
                // inside a bordered box; the link word is styled inline (the
                // working tap is the row below).
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF2A2A33)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        color: Color(0xFF6B6B78),
                        fontSize: 11,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                      ),
                      children: const [
                        TextSpan(text: 'By subscribing, you agree to our '),
                        TextSpan(
                          text: 'Terms of Service',
                          style: TextStyle(
                            color: Color(0xFF7B61FF),
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        TextSpan(
                          text: '. Subscriptions auto-renew until canceled. '
                              'Cancel anytime.',
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: widget._restageArgument3,
                      child: const Text(
                        'Terms',
                        style:
                            TextStyle(color: Color(0xFF7B61FF), fontSize: 11),
                      ),
                    ),
                    const Text(
                      '·',
                      style: TextStyle(color: Color(0xFF6B6B78)),
                    ),
                    TextButton(
                      onPressed: widget._restageArgument4,
                      child: const Text(
                        'Privacy',
                        style:
                            TextStyle(color: Color(0xFF7B61FF), fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ));
    })();
  }
}
