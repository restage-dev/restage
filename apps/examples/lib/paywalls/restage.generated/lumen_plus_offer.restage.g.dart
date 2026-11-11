part of '../lumen_plus_offer.dart';

// ignore_for_file: type=lint, unnecessary_cast

final _lumenPlusOfferPaywallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'lumen_plus_offer',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'lumen_plus_offer',
    'family': <String, Object?>{'kind': 'general'}
  },
  hostContractJson: <String, Object?>{
    'schemaVersion': 1,
    'hosting': <String, Object?>{
      'contentKind': 'flow',
      'presentation': 'inline'
    },
    'providedContext': <String, Object?>{
      'schemaVersion': 1,
      'inputs': <String, Object?>{}
    },
    'handledEvents': <String, Object?>{
      'schemaVersion': 1,
      'events': <Object?>[]
    },
    'flowBoundary': <String, Object?>{
      'schemaVersion': 1,
      'deliveryMode': 'typed',
      'hostSeedableState': <String, Object?>{},
      'actions': <String, Object?>{},
      'signals': <Object?>[],
      'outbound': <String, Object?>{
        'actionArgs': <String, Object?>{},
        'terminalResult': <String, Object?>{},
        'lifecycle': <String, Object?>{},
        'surveyAnswers': <String, Object?>{},
        'subFlowResult': <String, Object?>{},
        'customEvents': <String, Object?>{}
      }
    }
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
        0xe15a: IconData(0xe15a, fontFamily: 'MaterialIcons'),
        0xef9f: IconData(0xef9f, fontFamily: 'MaterialIcons'),
        0xf647: IconData(0xf647, fontFamily: 'MaterialIcons'),
      },
    }, mirrored: {
      'MaterialIcons': {
        0xe094: IconData(0xe094,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
      },
    }),
  ),
  surfaceWidget: 'LumenPlusOfferPaywallSurface',
);

final lumenPlusOfferPaywallPlacementDefinition =
    () => _lumenPlusOfferPaywallPlacementDefinitionValue;

final class LumenPlusOfferPaywallSurface extends StatefulWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const LumenPlusOfferPaywallSurface({
    super.key,
    String? placement,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  }) : _restagePlacementName = placement;

  /// Overrides the implicit placement with an explicit name.
  ///
  /// Use [LumenPlusOfferPaywallSurface] for the default placement; no name is needed.
  const LumenPlusOfferPaywallSurface.atPlacement(
    String restagePlacementId, {
    super.key,
    this.onEvent,
    this.resolver,
    this.loadingBuilder,
    this.fallbackBuilder,
    this.errorBuilder,
  }) : _restagePlacementName = restagePlacementId;

  final String? _restagePlacementName;

  final ValueChanged<RestageEvent>? onEvent;

  final VariantResolver? resolver;

  final WidgetBuilder? loadingBuilder;

  final WidgetBuilder? fallbackBuilder;

  final Widget Function(BuildContext, RestagePaywallError)? errorBuilder;

  @override
  _LumenPlusOfferPaywallSurfaceState createState() =>
      _LumenPlusOfferPaywallSurfaceState();
}

final class _LumenPlusOfferPaywallSurfaceState
    extends State<LumenPlusOfferPaywallSurface> {
  // ignore: unused_element
  /// The annual term is the default; tapping the monthly card flips it.
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
            'Center': buildCenter,
            'Column': buildColumn,
            'Container': buildContainer,
            'Expanded': buildExpanded,
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
            0xe15a: IconData(0xe15a, fontFamily: 'MaterialIcons'),
            0xef9f: IconData(0xef9f, fontFamily: 'MaterialIcons'),
            0xf647: IconData(0xf647, fontFamily: 'MaterialIcons'),
          },
        }, mirrored: {
          'MaterialIcons': {
            0xe094: IconData(0xe094,
                fontFamily: 'MaterialIcons', matchTextDirection: true),
          },
        }),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'lumen_plus_offer',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: lumenPlusOfferPaywallPlacementDefinition,
          name: widget._restagePlacementName,
          eventOwner: context,
        ),
        fallbackBuilder: widget.fallbackBuilder ?? ((_) => _restageBuilt),
        errorBuilder: widget.errorBuilder,
        onEvent: widget.onEvent,
        resolver: widget.resolver,
        loadingBuilder: widget.loadingBuilder,
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
            // The aurora ground: a vertical wash, then two soft glows.
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
                            Color(0xFF0F0B1F),
                            Color(0xFF14102A),
                            Color(0xFF0B0817),
                          ]
                        : const [
                            Color(0xFFFBFAFF),
                            Color(0xFFF4F1FC),
                            Color(0xFFEFEAF9),
                          ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              left: -90,
              top: -40,
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: dark
                        ? const [Color(0xBF8B7CF6), Color(0x008B7CF6)]
                        : const [Color(0x738B7CF6), Color(0x008B7CF6)],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -120,
              top: 120,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: dark
                        ? const [Color(0x8C5EDBD1), Color(0x005EDBD1)]
                        : const [Color(0x735EDBD1), Color(0x005EDBD1)],
                    stops: const [0.0, 0.7],
                  ),
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
                            Row(
                              children: [
                                Icon(
                                  Icons.dark_mode_outlined,
                                  size: 28,
                                  color: dark
                                      ? const Color(0xFFC39BFF)
                                      : const Color(0xFF6A55C4),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'LUMEN PLUS',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 2,
                                    color: dark
                                        ? const Color(0xFFC39BFF)
                                        : const Color(0xFF6A55C4),
                                  ),
                                ),
                              ],
                            ),
                            GestureDetector(
                              onTap: _restageRecording
                                  .surfaceEvent(PaywallEvents.skip),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: dark
                                      ? const Color(0x1AFFFFFF)
                                      : const Color(0x1A7C6CD6),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: dark
                                        ? const Color(0xFFB6AFD6)
                                        : const Color(0xFF6F6889),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 40),
                                Text(
                                  'Sleep deeper\ntonight.',
                                  style: TextStyle(
                                    fontSize: 44,
                                    height: 1.02,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1.6,
                                    color: dark
                                        ? const Color(0xFFF4F1FF)
                                        : const Color(0xFF221E33),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Guided meditations, sleep stories and focus music, '
                                  'unlocked in one calm place.',
                                  style: TextStyle(
                                    fontSize: 17,
                                    height: 1.45,
                                    color: dark
                                        ? const Color(0xFFB6AFD6)
                                        : const Color(0xFF6F6889),
                                  ),
                                ),
                                const SizedBox(height: 32),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 20,
                                      color: dark
                                          ? const Color(0xFFC39BFF)
                                          : const Color(0xFF6A55C4),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        '300+ guided meditations',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: -0.1,
                                          color: dark
                                              ? const Color(0xFFF4F1FF)
                                              : const Color(0xFF221E33),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 20,
                                      color: dark
                                          ? const Color(0xFFC39BFF)
                                          : const Color(0xFF6A55C4),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Sleep stories and soundscapes',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: -0.1,
                                          color: dark
                                              ? const Color(0xFFF4F1FF)
                                              : const Color(0xFF221E33),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 20,
                                      color: dark
                                          ? const Color(0xFFC39BFF)
                                          : const Color(0xFF6A55C4),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Focus sessions for deep work',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: -0.1,
                                          color: dark
                                              ? const Color(0xFFF4F1FF)
                                              : const Color(0xFF221E33),
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
                        // Annual — glass, framed while selected, carrying the badge.
                        GestureDetector(
                          onTap: selectAnnual,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: annualSelected
                                  ? (dark
                                      ? const Color(0x388B7CF6)
                                      : const Color(0x1F7C6CD6))
                                  : (dark
                                      ? const Color(0x14FFFFFF)
                                      : const Color(0x99FFFFFF)),
                              border: Border.all(
                                width: 1.5,
                                color: annualSelected
                                    ? (dark
                                        ? const Color(0xFFA899FF)
                                        : const Color(0xFF7C6CD6))
                                    : (dark
                                        ? const Color(0x24FFFFFF)
                                        : const Color(0x2E7C6CD6)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Annual',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: dark
                                              ? const Color(0xFFF4F1FF)
                                              : const Color(0xFF221E33),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        r'14 days free, then $69.99 / year',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: dark
                                              ? const Color(0xFFB6AFD6)
                                              : const Color(0xFF6F6889),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      colors: dark
                                          ? const [
                                              Color(0xFF8B7CF6),
                                              Color(0xFFC39BFF),
                                            ]
                                          : const [
                                              Color(0xFF6A55C4),
                                              Color(0xFF8B7CF6),
                                            ],
                                    ),
                                  ),
                                  child: Text(
                                    'SAVE 35%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                      color: dark
                                          ? const Color(0xFF14102A)
                                          : const Color(0xFFFFFFFF),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Monthly — the same glass, plain while the annual is chosen.
                        GestureDetector(
                          onTap: selectMonthly,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: annualSelected
                                  ? (dark
                                      ? const Color(0x14FFFFFF)
                                      : const Color(0x99FFFFFF))
                                  : (dark
                                      ? const Color(0x388B7CF6)
                                      : const Color(0x1F7C6CD6)),
                              border: Border.all(
                                width: 1.5,
                                color: annualSelected
                                    ? (dark
                                        ? const Color(0x24FFFFFF)
                                        : const Color(0x2E7C6CD6))
                                    : (dark
                                        ? const Color(0xFFA899FF)
                                        : const Color(0xFF7C6CD6)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Monthly',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: dark
                                              ? const Color(0xFFF4F1FF)
                                              : const Color(0xFF221E33),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        r'$8.99 / month',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: dark
                                              ? const Color(0xFFB6AFD6)
                                              : const Color(0xFF6F6889),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => _restageRecording
                                  .route(const LumenPlusCheckoutScreen()),
                            ),
                          ),
                          child: Container(
                            height: 58,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: dark
                                    ? const [
                                        Color(0xFF8B7CF6),
                                        Color(0xFFC39BFF)
                                      ]
                                    : const [
                                        Color(0xFF6A55C4),
                                        Color(0xFF8B7CF6)
                                      ],
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x597C6CD6),
                                  blurRadius: 30,
                                  offset: Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: dark
                                      ? const Color(0xFF14102A)
                                      : const Color(0xFFFFFFFF),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: _restageRecording.surfaceEvent(
                                  LumenPlusOfferPaywall.restorePurchases),
                              child: const Text(
                                'Restore',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF8E86B3),
                                ),
                              ),
                            ),
                            const SizedBox(width: 18),
                            GestureDetector(
                              onTap: _restageRecording
                                  .surfaceEvent(LumenPlusOfferPaywall.terms),
                              child: const Text(
                                'Terms',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF8E86B3),
                                ),
                              ),
                            ),
                            const SizedBox(width: 18),
                            GestureDetector(
                              onTap: _restageRecording
                                  .surfaceEvent(LumenPlusOfferPaywall.privacy),
                              child: const Text(
                                'Privacy',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF8E86B3),
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
