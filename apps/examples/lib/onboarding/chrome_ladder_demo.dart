import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/first_run.dart';

/// A rung of the chrome customization ladder, selectable in [ChromeLadderDemo].
enum ChromeRung {
  /// The built-in chrome, with no customization parameters.
  defaultChrome,

  /// The *Theme* rung — restyle the built-in affordances via [FlowChromeTheme].
  theme,

  /// The *Slots* rung — supply the affordance widget; the SDK positions it.
  slots,

  /// The *Layout* rung — own the chrome layout around the screen or flow.
  layout,
}

/// The themed back icon, color, and size used by the *Theme* rung — distinct
/// from the platform default so the change is visible (and assertable).
const IconData kChromeLadderThemeIcon = Icons.west;
const Color kChromeLadderThemeColor = Color(0xFF6FD6C6);
const double kChromeLadderThemeSize = 34;

/// A runnable tour of the chrome customization ladder over a single flow.
///
/// The same short onboarding flow is hosted by [RestageOnboarding] while a
/// control switches the active [ChromeRung], so the back affordance visibly
/// changes — its icon/color/size (Theme), the whole widget (Slots), or its
/// position (Layout) — and a toggle flips the chrome between persistent (framing
/// the flow) and per-screen. Advance the flow once (so there is history) to see
/// the back affordance, then switch rungs.
class ChromeLadderDemo extends StatefulWidget {
  /// Creates the chrome-ladder demo starting on [initialRung].
  const ChromeLadderDemo({
    super.key,
    this.initialRung = ChromeRung.theme,
    this.initialPersistent = true,
  });

  /// The rung shown first.
  final ChromeRung initialRung;

  /// Whether the built-in chrome starts persistent (vs per-screen).
  final bool initialPersistent;

  @override
  State<ChromeLadderDemo> createState() => _ChromeLadderDemoState();
}

class _ChromeLadderDemoState extends State<ChromeLadderDemo> {
  late ChromeRung _rung = widget.initialRung;
  late bool _persistent = widget.initialPersistent;

  // Built once: switching rungs must re-render the chrome without restarting
  // the flow (RestageOnboarding restarts only when flow/resolver/actions
  // change), so the flow position is preserved as you tour the rungs.
  late final FirstRunActions _actions = FirstRunActions(
    requestNotifications: (args, context) async =>
        const NotificationDecision(granted: true),
  );

  static const _themeData = FlowChromeTheme(
    backIcon: kChromeLadderThemeIcon,
    color: kChromeLadderThemeColor,
    size: kChromeLadderThemeSize,
  );

  // Slots rung: the SDK positions this widget at the back slot (shown when
  // `canBack`); the host owns the widget. A labelled control owns its own
  // Semantics (the rung's a11y contract — the built-in chrome's clean label
  // is the host's responsibility once the host supplies the widget).
  Widget _slotsBackButton(BuildContext context, VoidCallback onAction) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TextButton.icon(
        key: const Key('chrome-ladder-slots-back'),
        onPressed: onAction,
        icon: const Icon(Icons.chevron_left, size: 18),
        label: const Text('Back'),
        style: TextButton.styleFrom(
          foregroundColor: kChromeLadderThemeColor,
          backgroundColor: const Color(0x226FD6C6),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }

  // Layout rung: the host owns the whole chrome layout. Here the back affordance
  // is composed over the screen at the top-*right* (a custom position the
  // built-in chrome never uses), demonstrating "put affordances anywhere". The
  // control reads availability from [FlowChromeState] and owns its Semantics.
  Widget _layoutChrome(
    BuildContext context,
    FlowChromeState state,
    Widget screen,
  ) {
    return Stack(
      children: [
        Positioned.fill(child: screen),
        if (state.canBack)
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Semantics(
                  button: true,
                  label: 'Back',
                  child: GestureDetector(
                    key: const Key('chrome-ladder-layout-back'),
                    behavior: HitTestBehavior.opaque,
                    onTap: state.onBack,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: ExcludeSemantics(
                        child: Icon(
                          Icons.arrow_back,
                          color: Color(0xFFF5F7FB),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _onboarding()),
        _controlBar(),
      ],
    );
  }

  Widget _onboarding() {
    final layoutRung = _rung == ChromeRung.layout;
    return RestageOnboarding<FirstRunResult>(
      flow: FirstRunFlowDescriptor.ref,
      actions: _actions,
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => ColoredBox(
          color: const Color(0xFF0E1B33),
          child: Center(child: Text(error.message)),
        ),
      ),
      persistentChrome: _persistent,
      chromeTheme: _rung == ChromeRung.theme ? _themeData : null,
      backBuilder: _rung == ChromeRung.slots ? _slotsBackButton : null,
      chromeBuilder: layoutRung && !_persistent ? _layoutChrome : null,
      persistentChromeBuilder: layoutRung && _persistent ? _layoutChrome : null,
    );
  }

  // The demo's own controls — a rung selector + the persistentChrome toggle —
  // so the chrome change is observable live. These live outside the flow; the
  // flow position is preserved as the rung switches (the actions registry is
  // built once, so RestageOnboarding does not restart). The bar reads from the
  // theme so it stays legible in both light and dark mode.
  Widget _controlBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The demo's own close-to-gallery control. The flow chrome above is
              // the *subject* of this reference (it switches per rung, and at the
              // Default rung / flow root there is no back affordance at all), so
              // the escape lives in the demo's own control bar — always present
              // and never clashing with whichever rung's chrome is on stage.
              Row(
                children: [
                  Text(
                    'Chrome customization ladder',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    key: const Key('chrome-ladder-close'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Close'),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<ChromeRung>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: ChromeRung.defaultChrome,
                            label: Text('Default'),
                          ),
                          ButtonSegment(
                            value: ChromeRung.theme,
                            label: Text('Theme'),
                          ),
                          ButtonSegment(
                            value: ChromeRung.slots,
                            label: Text('Slots'),
                          ),
                          ButtonSegment(
                            value: ChromeRung.layout,
                            label: Text('Layout'),
                          ),
                        ],
                        selected: {_rung},
                        onSelectionChanged: (selection) =>
                            setState(() => _rung = selection.first),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Persistent',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Switch(
                        value: _persistent,
                        onChanged: (value) =>
                            setState(() => _persistent = value),
                      ),
                    ],
                  ),
                ],
              ),
              // Persistent chrome only differs from per-screen *during* a
              // transition, so toggling at rest is a no-op. Tell the user how to
              // observe it rather than leaving the switch reading as inert.
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                child: Text(
                  'Persistent: toggle, then tap Back or advance a screen — '
                  'the back affordance holds its place when on, and rides the '
                  'transition with the screen when off.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
