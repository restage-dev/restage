import 'dart:async';
import 'dart:convert';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:restage/restage.dart';
import 'package:restage_preview_host/restage_preview_host.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw_formats;

import 'generated/marketing_lumen_welcome.g.dart';
import 'marketing_lumen_bridge.dart';
import 'onboarding/flows/lumen_onboarding.dart';
import 'onboarding/screens/lumen_experience.dart';
import 'user_factories.g.dart';

void main() {
  // The embedding page owns the URL. Flow navigation stays inside this device.
  ui_web.urlStrategy = null;
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: const []);
  registerRestageWidgets();
  Restage.configure(
    apiKey: 'rs_pk_marketing_lumen',
    resolver: const AssetVariantResolver(),
  );
  runApp(const _MarketingLumenApp());
}

class _MarketingLumenApp extends StatefulWidget {
  const _MarketingLumenApp();

  @override
  State<_MarketingLumenApp> createState() => _MarketingLumenAppState();
}

class _MarketingLumenAppState extends State<_MarketingLumenApp> {
  late final MarketingLumenBridge _bridge;
  MarketingLumenState _state = const MarketingLumenState();

  @override
  void initState() {
    super.initState();
    _bridge = MarketingLumenBridge(onState: _receiveState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bridge.sendReady());
  }

  void _receiveState(MarketingLumenState state) {
    if (!mounted) return;
    setState(() => _state = state);
    if (!state.published && !state.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _state.requestId == state.requestId) {
          _bridge.sendApplied(state);
        }
      });
    }
  }

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
      darkTheme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      themeMode: _state.dark ? ThemeMode.dark : ThemeMode.light,
      home: ColoredBox(
        color: const Color(0xFF14171E),
        child: DeviceFrameHost(
          device: DeviceInfo.iPhone16ProMax,
          child: _LumenDevice(
            state: _state,
            onEvent: _bridge.sendEvent,
            onApplied: _bridge.sendApplied,
            onError: (error) => _bridge.sendError(
              error,
              requestId: _state.requestId,
            ),
          ),
        ),
      ),
    );
  }
}

class _LumenDevice extends StatefulWidget {
  const _LumenDevice({
    required this.state,
    required this.onEvent,
    required this.onApplied,
    required this.onError,
  });

  final MarketingLumenState state;
  final ValueChanged<String> onEvent;
  final ValueChanged<MarketingLumenState> onApplied;
  final ValueChanged<Object> onError;

  @override
  State<_LumenDevice> createState() => _LumenDeviceState();
}

class _LumenDeviceState extends State<_LumenDevice> {
  bool _flowStarted = false;
  String? _notice;

  @override
  void didUpdateWidget(_LumenDevice oldWidget) {
    super.didUpdateWidget(oldWidget);
    final state = widget.state;
    final oldState = oldWidget.state;
    final shouldReset = state.resetGeneration != oldState.resetGeneration ||
        state.published != oldState.published ||
        state.enabled != oldState.enabled;
    if (shouldReset) {
      _flowStarted = false;
      _notice = null;
    }
  }

  void _handleWelcomeEvent(String name) {
    widget.onEvent(name);
    if (name == 'next') setState(() => _flowStarted = true);
    if (name == 'sign_in') {
      setState(() {
        _notice = 'Sign in belongs to the app hosting this onboarding.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_flowStarted) {
      return _withNotice(
        MarketingLumenFlow(
          key: ValueKey(widget.state.resetGeneration),
          onEvent: widget.onEvent,
          onRestart: () => setState(() => _flowStarted = false),
          onHostNotice: (message) => setState(() => _notice = message),
        ),
      );
    }
    final delivered = widget.state.published || widget.state.enabled;
    final screen = delivered
        ? _DeliveredLumen(
            state: widget.state,
            onEvent: _handleWelcomeEvent,
            onApplied: widget.onApplied,
            onError: widget.onError,
          )
        : _NativeLumen(onEvent: _handleWelcomeEvent);
    return _withNotice(
      ClipRect(
        child: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 280),
          child: KeyedSubtree(key: ValueKey(delivered), child: screen),
        ),
      ),
    );
  }

  Widget _withNotice(Widget child) {
    final notice = _notice;
    if (notice == null) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: ColoredBox(
            color: const Color(0x990B0817),
            child: Center(
              child: AlertDialog(
                title: const Text('Lumen demo'),
                content: Text(notice),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _notice = null),
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MarketingLumenFlow extends StatefulWidget {
  const MarketingLumenFlow({
    required this.onEvent,
    required this.onRestart,
    required this.onHostNotice,
    super.key,
  });

  final ValueChanged<String> onEvent;
  final VoidCallback onRestart;
  final ValueChanged<String> onHostNotice;

  @override
  State<MarketingLumenFlow> createState() => _MarketingLumenFlowState();
}

class _MarketingLumenFlowState extends State<MarketingLumenFlow> {
  RestageFlowController<Map<String, Object?>>? _controller;
  FlowUnavailableError? _error;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    late final FlowSurfacePayload payload;
    try {
      final resolved =
          await Restage.defaultFlowResolver.resolve(lumenOnboardingFlowRef);
      if (!mounted) return;
      payload = FlowSurfacePayload(
        flowDocument: resolved.document,
        screenBlobs: resolved.screenBlobs,
      );
    } on FlowUnavailableError catch (error) {
      if (mounted) setState(() => _error = error);
      return;
    }
    late final RestageFlowController<Map<String, Object?>> controller;
    controller = buildPreviewFlowController(
      payload: payload,
      surface: Surface.onboarding,
      onEvent: (event) {
        if (!mounted || !identical(_controller, controller)) return;
        Restage.fireEvent(event);
        if (event is! FlowCustomEvent) return;
        switch (event.eventName) {
          case 'close':
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && identical(_controller, controller)) {
                widget.onRestart();
              }
            });
          case 'sign_in':
            widget.onHostNotice(
              'Sign in belongs to the app hosting this onboarding.',
            );
          case 'terms':
            widget.onHostNotice(
              'Terms would open the app’s own policy screen.',
            );
        }
      },
      onComplete: (result) {
        if (mounted && identical(_controller, controller)) {
          setState(() => _completed = result['completed'] == true);
        }
      },
      onUnavailable: (error) {
        if (mounted && identical(_controller, controller)) {
          setState(() => _error = error);
        }
      },
    );
    _controller = controller;
    await controller.load();
    if (!mounted || !identical(_controller, controller)) return;
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !identical(_controller, controller)) return;
    controller.handleEvent('next', null);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_completed) {
      return _LumenCompletion(onRestart: widget.onRestart);
    }
    final error = _error;
    if (error != null) {
      return _LumenFlowError(
        message: error.message,
        onRetry: () {
          _controller?.dispose();
          _controller = null;
          setState(() => _error = null);
          unawaited(_start());
        },
      );
    }
    final controller = _controller;
    if (controller == null) return const SizedBox.expand();
    return PreviewFlowView<Map<String, Object?>>(
      controller: controller,
      brightness: Theme.of(context).brightness,
      loadingBuilder: (_) => const SizedBox.expand(),
      onScreenEvent: (name, arguments) {
        widget.onEvent(name);
        if (name == 'back' &&
            controller.currentScreenId == lumenExperienceScreenRef.id) {
          widget.onRestart();
          return true;
        }
        return false;
      },
    );
  }
}

class _LumenCompletion extends StatelessWidget {
  const _LumenCompletion({required this.onRestart});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0B0817) : const Color(0xFFEFEAF9),
      body: Center(
        child: Semantics(
          container: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.self_improvement,
                size: 64,
                color: dark ? const Color(0xFFC39BFF) : const Color(0xFF6A55C4),
              ),
              const SizedBox(height: 24),
              Text(
                'Your quiet starts here.',
                style: TextStyle(
                  color:
                      dark ? const Color(0xFFF4F1FF) : const Color(0xFF221E33),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: onRestart, child: const Text('Start over')),
            ],
          ),
        ),
      ),
    );
  }
}

class _LumenFlowError extends StatelessWidget {
  const _LumenFlowError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}

class _NativeLumen extends StatelessWidget {
  const _NativeLumen({required this.onEvent});

  final ValueChanged<String> onEvent;

  @override
  Widget build(BuildContext context) {
    return MarketingLumenWelcomeScreen(
      onNext: () => onEvent('next'),
      onSignIn: () => onEvent('sign_in'),
    );
  }
}

class _DeliveredLumen extends StatefulWidget {
  const _DeliveredLumen({
    required this.state,
    required this.onEvent,
    required this.onApplied,
    required this.onError,
  });

  final MarketingLumenState state;
  final ValueChanged<String> onEvent;
  final ValueChanged<MarketingLumenState> onApplied;
  final ValueChanged<Object> onError;

  @override
  State<_DeliveredLumen> createState() => _DeliveredLumenState();
}

class _DeliveredLumenState extends State<_DeliveredLumen> {
  late final Future<({Uint8List original, Uint8List published})> _blobs =
      _loadBlobs();
  ({int requestId, bool dark, bool published, bool enabled})? _reportedState;
  int? _reportedErrorRequestId;

  Future<({Uint8List original, Uint8List published})> _loadBlobs() async {
    final data = await rootBundle.load(
      'assets/restage/bundles/lib/onboarding/screens/lumen_welcome.rsbundle',
    );
    final bundle = RestageBundleCodec.decode(Uint8List.sublistView(data));
    final textEntry = bundle.entries.singleWhere(
      (entry) => entry.role == RestageBundleEntryRole.rfwText,
    );
    final source = utf8.decode(textEntry.bytes);
    const original = 'Text(text: "Begin",';
    const replacement = 'Text(text: "Begin your practice",';
    if (original.allMatches(source).length != 1) {
      throw const FormatException('The Lumen CTA source shape has changed.');
    }
    return (
      original: rfw_formats.encodeLibraryBlob(
        rfw_formats.parseLibraryFile(source),
      ),
      published: rfw_formats.encodeLibraryBlob(
        rfw_formats
            .parseLibraryFile(source.replaceFirst(original, replacement)),
      ),
    );
  }

  void _reportApplied() {
    final state = (
      requestId: widget.state.requestId,
      dark: widget.state.dark,
      published: widget.state.published,
      enabled: widget.state.enabled,
    );
    if (_reportedState == state) return;
    _reportedState = state;
    widget.onApplied(widget.state);
  }

  void _reportError(Object error) {
    final requestId = widget.state.requestId;
    if (_reportedErrorRequestId == requestId) return;
    _reportedErrorRequestId = requestId;
    widget.onError(error);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({Uint8List original, Uint8List published})>(
      future: _blobs,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _reportError(snapshot.error!);
          });
          return const SizedBox.shrink();
        }
        final blobs = snapshot.data;
        if (blobs == null) return const SizedBox.shrink();
        return RawRfwRenderSurface(
          epoch: widget.state.requestId,
          blob: widget.state.published ? blobs.published : blobs.original,
          data: const {},
          environment: RenderEnv(
            theme: const {},
            brightness: widget.state.dark ? 'dark' : 'light',
            locale: 'en_US',
            textScale: 1,
            zoom: 1,
            frame: MediaQuery.sizeOf(context),
          ),
          registrations: const [],
          entryWidgetName: 'OnboardingScreen',
          onRemoteEvent: (name, arguments) => widget.onEvent(name),
          onRenderEvent: (event) {
            if (event is Settled) {
              _reportApplied();
            } else if (event is RenderError) {
              _reportError(event.message);
            }
          },
        );
      },
    );
  }
}
