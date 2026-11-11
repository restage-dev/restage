part of '../fluent_pro.dart';

// ignore_for_file: type=lint, unnecessary_cast

final _fluentProPaywallPlacementDefinitionValue =
    RestagePaywall.generatedPlacementDefinition(
  id: 'fluent_pro',
  defaultSurfaceLocatorJson: <String, Object?>{
    'surfaceType': 'paywall',
    'slug': 'fluent_pro',
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
        'SafeArea': buildSafeArea,
        'SingleChildScrollView': buildSingleChildScrollView,
        'SizedBox': buildSizedBox,
        'Spacer': buildSpacer,
        'Stack': buildStack,
        'Text': buildText,
        'TextRich': buildTextRich,
      },
      material: {
        'Icon': buildIcon,
        'Scaffold': buildScaffold,
      },
    ),
    icons: RestageIconTable.fromFamilies(families: {
      'MaterialIcons': {
        0xe0b7: IconData(0xe0b7, fontFamily: 'MaterialIcons'),
        0xe163: IconData(0xe163, fontFamily: 'MaterialIcons'),
        0xf636: IconData(0xf636, fontFamily: 'MaterialIcons'),
      },
    }, mirrored: {
      'MaterialIcons': {
        0xe094: IconData(0xe094,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
        0xf572: IconData(0xf572,
            fontFamily: 'MaterialIcons', matchTextDirection: true),
      },
    }),
  ),
  surfaceWidget: 'FluentProPaywallSurface',
);

final fluentProPaywallPlacementDefinition =
    () => _fluentProPaywallPlacementDefinitionValue;

final class FluentProPaywallSurface extends StatefulWidget {
  /// Mounts this surface at its implicit placement by default.
  ///
  /// Use this constructor for ordinary mounts; no placement name is needed.
  const FluentProPaywallSurface({
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
  /// Use [FluentProPaywallSurface] for the default placement; no name is needed.
  const FluentProPaywallSurface.atPlacement(
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
  _FluentProPaywallSurfaceState createState() =>
      _FluentProPaywallSurfaceState();
}

final class _FluentProPaywallSurfaceState
    extends State<FluentProPaywallSurface> {
  // ignore: unused_element
  /// Plan selection: the framed "most popular" Personal plan is the default;
  /// tapping Family flips it.
  bool personalSelected = true;

  // ignore: unused_element
  void selectFamily() => setState(() => personalSelected = false);

  // ignore: unused_element
  void selectPersonal() => setState(() => personalSelected = true);

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
            'SingleChildScrollView': buildSingleChildScrollView,
            'SizedBox': buildSizedBox,
            'Spacer': buildSpacer,
            'Stack': buildStack,
            'Text': buildText,
            'TextRich': buildTextRich,
          },
          material: {
            'Icon': buildIcon,
            'Scaffold': buildScaffold,
          },
        ),
        icons: RestageIconTable.fromFamilies(families: {
          'MaterialIcons': {
            0xe0b7: IconData(0xe0b7, fontFamily: 'MaterialIcons'),
            0xe163: IconData(0xe163, fontFamily: 'MaterialIcons'),
            0xf636: IconData(0xf636, fontFamily: 'MaterialIcons'),
          },
        }, mirrored: {
          'MaterialIcons': {
            0xe094: IconData(0xe094,
                fontFamily: 'MaterialIcons', matchTextDirection: true),
            0xf572: IconData(0xf572,
                fontFamily: 'MaterialIcons', matchTextDirection: true),
          },
        }),
      ).addToInstalled();
      final restageContent = RestagePaywall(
        id: 'fluent_pro',
        placementBinding: RestagePaywall.generatedPlacementBinding(
          definition: fluentProPaywallPlacementDefinition,
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
      return _restageDesign(Scaffold(
        body: Container(
          // Dark indigo → violet canvas. Explicit Alignment(x, y) values keep the
          // gradient direction a concrete value in the delivered surface.
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(0, -1),
              end: Alignment(0, 1),
              colors: [
                Color(0xFF13183A),
                Color(0xFF241B5C),
                Color(0xFF3A2270),
              ],
              stops: [0, 0.5, 1],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Scrollable value content; the offer zone below is pinned.
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Top row: close affordance + the "PRO" badge.
                          Row(
                            children: [
                              // Dismissing the entry fires `skip`, which ends the
                              // generated flow. The Navigator.push conversion
                              // needs it.
                              GestureDetector(
                                onTap: _restageRecording
                                    .surfaceEvent(PaywallEvents.skip),
                                child: const Icon(
                                  Icons.arrow_back_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF16C79A),
                                      Color(0xFF35A0E8),
                                      Color(0xFF8B5CF6),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'PRO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    fontStyle: FontStyle.italic,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Glowing mascot hero + sparkle accents.
                          SizedBox(
                            height: 150,
                            child: Stack(
                              children: [
                                Center(
                                  child: Container(
                                    width: 94,
                                    height: 134,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        begin: Alignment(0, -1),
                                        end: Alignment(0, 1),
                                        colors: [
                                          Color(0xFF16C79A),
                                          Color(0xFF35C1E8),
                                          Color(0xFFC44BE6),
                                          Color(0xFFE7E9F5),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(42),
                                      border: Border.all(
                                        color: const Color(0x66FFFFFF),
                                        width: 2,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.auto_awesome,
                                        color: Colors.white,
                                        size: 36,
                                      ),
                                    ),
                                  ),
                                ),
                                const Positioned(
                                  left: 44,
                                  top: 28,
                                  child: Icon(
                                    Icons.auto_awesome,
                                    color: Color(0xFFEAF6FF),
                                    size: 18,
                                  ),
                                ),
                                const Positioned(
                                  right: 52,
                                  top: 44,
                                  child: Icon(
                                    Icons.auto_awesome,
                                    color: Color(0xFFEAF6FF),
                                    size: 14,
                                  ),
                                ),
                                const Positioned(
                                  right: 84,
                                  bottom: 34,
                                  child: Icon(
                                    Icons.circle,
                                    color: Color(0xFF7FC4FF),
                                    size: 8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          // Free-trial headline; the trial phrase is accented teal.
                          const Text.rich(
                            TextSpan(
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                                letterSpacing: -0.3,
                              ),
                              children: [
                                TextSpan(text: 'Get started with a '),
                                TextSpan(
                                  text: '7 day free trial',
                                  style: TextStyle(color: Color(0xFF16E0A8)),
                                ),
                                TextSpan(text: ' on Pro'),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Pinned offer zone — the two plan cards, the CTA, and the legal.
                  // Family plan (unselected default). Tapping it re-targets.
                  GestureDetector(
                    onTap: selectFamily,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF252050),
                        border: Border.all(
                          color: personalSelected
                              ? const Color(0x33FFFFFF)
                              : const Color(0xFF16C79A),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Family',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  r'12 mo • $119.99',
                                  style: TextStyle(
                                    color: Color(0xFFB4ADD6),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            r'$9.99 / MO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Selected check — appears when Family is the chosen plan
                          // (mirrors the Personal card's in-row check). Positive
                          // condition with swapped branches: the check shows when
                          // Personal is NOT selected.
                          personalSelected
                              ? const SizedBox(width: 26, height: 26)
                              : Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1CB0F6),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Personal plan — the framed "most popular" default. A bright
                  // gradient frame (composed as an outer gradient container around
                  // the card fill), a ribbon tab, and a selected check that appears
                  // when this plan is chosen.
                  GestureDetector(
                    onTap: selectPersonal,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF16C79A),
                            Color(0xFF1CB0F6),
                            Color(0xFFB45CFF),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2C2566),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // MOST POPULAR ribbon tab.
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF16C79A),
                                    Color(0xFF1CB0F6)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'MOST POPULAR',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Personal',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          r'12 mo • $95.99',
                                          style: TextStyle(
                                            color: Color(0xFFCFC9F0),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    r'$6.99',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Text(
                                    ' / MO',
                                    style: TextStyle(
                                      color: Color(0xFFCFC9F0),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  // Selected check — appears when Personal is the
                                  // chosen plan.
                                  personalSelected
                                      ? Container(
                                          width: 26,
                                          height: 26,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1CB0F6),
                                            borderRadius:
                                                BorderRadius.circular(13),
                                          ),
                                          child: const Icon(
                                            Icons.check_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        )
                                      : const SizedBox(width: 26, height: 26),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Cancel anytime in the App Store',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFC6CFE8),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // White "START MY FREE WEEK" pill — reports the selected plan.
                  GestureDetector(
                    onTap: _restageRecording.surfaceEvent(
                      FluentProPaywall.continueFlow,
                      {
                        'plan': personalSelected ? 'personal' : 'family',
                      },
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'START MY FREE WEEK',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF1A1340),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: GestureDetector(
                      // "View all plans" pushes the all-tiers "Choose a plan"
                      // screen. The build turns this Navigator.push into a flow
                      // step, and RestagePaywall hosts the flow.
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => _restageRecording
                              .route(const FluentProChoosePlanScreen()),
                        ),
                      ),
                      child: const Text(
                        'VIEW ALL PLANS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text.rich(
                    TextSpan(
                      style: TextStyle(
                        color: Color(0xFFB9C2DD),
                        fontSize: 11,
                        height: 1.4,
                      ),
                      children: [
                        TextSpan(
                          text: 'Your monthly or annual subscription ',
                        ),
                        TextSpan(
                          text: 'automatically renews',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(
                          text:
                              ' for the same term unless canceled at least 24 '
                              'hours prior to the end of the current term.',
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
    })();
  }
}
