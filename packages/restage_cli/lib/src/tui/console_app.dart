import 'dart:async';

import 'package:nocterm/nocterm.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/tui/console_controller.dart';
import 'package:restage_cli/src/tui/console_models.dart';

class RestageConsoleApp extends StatefulComponent {
  const RestageConsoleApp({required this.controller, super.key});

  final ConsoleController controller;

  @override
  State<RestageConsoleApp> createState() => _RestageConsoleAppState();
}

class _RestageConsoleAppState extends State<RestageConsoleApp> {
  static const _commandNames = [
    'status',
    'kill',
    'rollback',
    'freeze',
    'unfreeze',
    'publish',
  ];
  static const _minNavWidth = 18;
  static const _minSurfaceWidth = 22;
  static const _minDetailWidth = 24;
  static const _dividerWidth = 3;

  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  _PromptKind? _prompt;
  _PendingConfirmOperation? _pendingConfirm;
  bool _previewInFlight = false;
  int _previewGeneration = 0;
  _ConsoleView _activeView = _ConsoleView.overview;
  _SurfaceFilter _surfaceFilter = _SurfaceFilter.all;
  _SurfaceFocus _surfaceFocus = _SurfaceFocus.rows;
  _DetailAction _detailAction = _DetailAction.publish;
  bool _leftEnvironmentFocused = false;
  int _leftEnvironmentFocusIndex = 0;
  _PanelDivider? _activeDivider;
  int _navWidth = 17;
  int _surfaceWidth = 20;
  int? _lastDragX;
  bool _searchFocused = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _promptController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await component.controller.load();
    if (!mounted) return;
    setState(() {
      _leftEnvironmentFocusIndex = component.controller.state.environmentIndex;
    });
  }

  bool _handleVerticalNavigation(int delta) {
    final focusedPanel = component.controller.state.focusedPanel;
    if (_isLeftPanel(focusedPanel)) {
      _moveLeftNavigation(delta);
      return true;
    }
    if (focusedPanel == ConsolePanel.surfaces) {
      _handleSurfaceVerticalNavigation(delta);
      return true;
    }
    if (_isDetailPanel(focusedPanel)) {
      _moveDetailAction(delta);
      return true;
    }

    if (delta < 0) {
      _openSearch();
    }
    return true;
  }

  void _handleSurfaceVerticalNavigation(int delta) {
    if (!_surfaceMiddleVisible) {
      if (delta < 0) _openSearch();
      return;
    }
    if (_surfaceFocus == _SurfaceFocus.filters) {
      final nextFilter = _verticalSurfaceFilterTarget(delta);
      if (nextFilter != null) {
        unawaited(_selectSurfaceFilter(nextFilter));
        return;
      }
      if (delta > 0) {
        if (_visibleSurfaces(component.controller.state).isNotEmpty) {
          setState(() {
            _surfaceFocus = _SurfaceFocus.rows;
          });
        }
      } else {
        _openSearch();
      }
      return;
    }

    final visibleSurfaces = _visibleSurfaces(component.controller.state);
    if (visibleSurfaces.isEmpty) {
      setState(() {
        _surfaceFocus = _SurfaceFocus.filters;
      });
      return;
    }
    final selectedIndex = _selectedVisibleSurfaceIndex(visibleSurfaces);
    if (delta < 0 && selectedIndex <= 0) {
      setState(() {
        _surfaceFocus = _SurfaceFocus.filters;
      });
      return;
    }

    unawaited(_moveVisibleSurface(delta));
  }

  void _moveLeftNavigation(int delta) {
    final state = component.controller.state;
    if (_leftEnvironmentFocused) {
      final lastEnvironment = state.environments.length - 1;
      if (delta < 0 && _leftEnvironmentFocusIndex <= 0) {
        setState(() {
          _leftEnvironmentFocused = false;
          _activeView = _ConsoleView.auditTrail;
        });
        return;
      }
      if (state.environments.isEmpty) return;
      setState(() {
        _leftEnvironmentFocusIndex = (_leftEnvironmentFocusIndex + delta).clamp(
          0,
          lastEnvironment,
        );
      });
      return;
    }

    final values = _ConsoleView.values;
    final current = values.indexOf(_activeView);
    if (delta < 0 && current == 0) {
      _openSearch();
      return;
    }
    if (delta > 0 && current == values.length - 1) {
      if (state.environments.isNotEmpty) {
        setState(() {
          _leftEnvironmentFocused = true;
          _leftEnvironmentFocusIndex = 0;
        });
      }
      return;
    }
    final next = (current + delta).clamp(0, values.length - 1).toInt();
    setState(() {
      _activeView = values[next];
    });
  }

  _SurfaceFilter? _verticalSurfaceFilterTarget(int delta) {
    if (delta > 0) {
      return switch (_surfaceFilter) {
        _SurfaceFilter.all => _SurfaceFilter.message,
        _SurfaceFilter.paywall => _SurfaceFilter.survey,
        _SurfaceFilter.onboarding => _SurfaceFilter.survey,
        _SurfaceFilter.message || _SurfaceFilter.survey => null,
      };
    }
    if (delta < 0) {
      return switch (_surfaceFilter) {
        _SurfaceFilter.message => _SurfaceFilter.all,
        _SurfaceFilter.survey => _SurfaceFilter.paywall,
        _SurfaceFilter.all ||
        _SurfaceFilter.paywall ||
        _SurfaceFilter.onboarding => null,
      };
    }
    return null;
  }

  Future<void> _moveVisibleSurface(int delta) async {
    final state = component.controller.state;
    final visibleSurfaces = _visibleSurfaces(state);
    if (visibleSurfaces.isEmpty) return;
    final selectedIndex = _selectedVisibleSurfaceIndex(visibleSurfaces);
    final nextIndex = selectedIndex < 0
        ? 0
        : (selectedIndex + delta).clamp(0, visibleSurfaces.length - 1).toInt();
    await _selectSurface(state.surfaces.indexOf(visibleSurfaces[nextIndex]));
  }

  int _selectedVisibleSurfaceIndex(List<ConsoleSurface> visibleSurfaces) {
    final selectedSurface = component.controller.state.selectedSurface;
    if (selectedSurface == null) return -1;
    return visibleSurfaces.indexOf(selectedSurface);
  }

  void _handleHorizontalNavigation(int delta) {
    if (component.controller.state.focusedPanel == ConsolePanel.surfaces &&
        _surfaceMiddleVisible &&
        _surfaceFocus == _SurfaceFocus.filters) {
      unawaited(_moveSurfaceFilter(delta));
      return;
    }

    _focusAdjacentVisualPanel(reverse: delta < 0);
  }

  Future<void> _moveSurfaceFilter(int delta) async {
    final values = _SurfaceFilter.values;
    final next =
        (values.indexOf(_surfaceFilter) + delta + values.length) %
        values.length;
    await _selectSurfaceFilter(values[next]);
  }

  void _focusAdjacentVisualPanel({required bool reverse}) {
    final next = _adjacentVisualPanel(reverse: reverse);
    setState(() {
      component.controller.focusPanel(next);
      if (next == ConsolePanel.surfaces && _surfaceMiddleVisible) {
        _surfaceFocus = _SurfaceFocus.rows;
      }
    });
  }

  void _focusPanel(ConsolePanel panel) {
    setState(() {
      _searchFocused = false;
      component.controller.focusPanel(panel);
      if (panel == ConsolePanel.surfaces && _surfaceMiddleVisible) {
        _surfaceFocus = _SurfaceFocus.rows;
      }
    });
  }

  ConsolePanel _adjacentVisualPanel({required bool reverse}) {
    final focusedPanel = component.controller.state.focusedPanel;
    if (_isLeftPanel(focusedPanel)) {
      return reverse ? ConsolePanel.detail : ConsolePanel.surfaces;
    }
    if (focusedPanel == ConsolePanel.surfaces) {
      return reverse ? ConsolePanel.projects : ConsolePanel.detail;
    }
    return reverse ? ConsolePanel.surfaces : ConsolePanel.projects;
  }

  bool _isLeftPanel(ConsolePanel panel) =>
      panel == ConsolePanel.projects || panel == ConsolePanel.apps;

  bool _isDetailPanel(ConsolePanel panel) =>
      panel == ConsolePanel.detail || panel == ConsolePanel.actions;

  bool _handleKeyEvent(KeyboardEvent event) {
    if (_previewInFlight) {
      if (event.logicalKey == LogicalKey.escape) {
        setState(() {
          _previewInFlight = false;
          _previewGeneration++;
        });
      }
      return true;
    }

    if (_prompt != null) {
      if (event.logicalKey == LogicalKey.escape) {
        setState(() {
          _prompt = null;
          _pendingConfirm = null;
          _promptController.clear();
        });
        return true;
      }
      return false;
    }

    if (_searchFocused) {
      if (event.logicalKey == LogicalKey.escape) {
        _closeSearch();
        return true;
      }
      if (event.logicalKey == LogicalKey.arrowDown) {
        _closeSearch();
        return true;
      }
      return false;
    }

    switch (event.logicalKey) {
      case LogicalKey.slash:
        _openSearch();
        return true;
      case LogicalKey.tab:
        _focusAdjacentVisualPanel(reverse: event.modifiers.shift);
        return true;
      case LogicalKey.arrowUp:
        return _handleVerticalNavigation(-1);
      case LogicalKey.arrowDown:
        return _handleVerticalNavigation(1);
      case LogicalKey.arrowLeft:
        _handleHorizontalNavigation(-1);
        return true;
      case LogicalKey.arrowRight:
        _handleHorizontalNavigation(1);
        return true;
      case LogicalKey.enter:
      case LogicalKey.space:
        if (_canCommitLeftEnvironment()) {
          unawaited(_selectEnvironment(_leftEnvironmentFocusIndex));
          return true;
        }
        if (_canCommitDetailAction()) {
          unawaited(_triggerDetailAction(_detailAction));
          return true;
        }
        if (_canCommitSurfaceFilter()) {
          unawaited(_commitSurfaceFilter());
          return true;
        }
        return false;
      case LogicalKey.keyQ:
        component.controller.quit();
        shutdownApp();
        return true;
      case LogicalKey.keyK:
        _detailAction = _DetailAction.kill;
        _openPrompt(_PromptKind.kill);
        return true;
      case LogicalKey.keyR:
        _detailAction = _DetailAction.rollback;
        _openPrompt(_PromptKind.rollback);
        return true;
      case LogicalKey.keyF:
        _detailAction = _DetailAction.freeze;
        _openPrompt(_PromptKind.freeze);
        return true;
      case LogicalKey.keyU:
        _detailAction = _DetailAction.unfreeze;
        _openPrompt(_PromptKind.unfreeze);
        return true;
      case LogicalKey.keyP:
        _detailAction = _DetailAction.publish;
        unawaited(_publishSelected());
        return true;
      default:
        return false;
    }
  }

  void _openSearch() {
    setState(() {
      _searchFocused = true;
    });
  }

  void _closeSearch({bool clear = false}) {
    setState(() {
      _searchFocused = false;
      if (clear) _searchController.clear();
    });
  }

  void _updateSearch(String _) {
    setState(() {});
  }

  Future<void> _submitSearch(String raw) async {
    final command = _matchedCommand(raw);
    if (command == null) {
      _closeSearch();
      return;
    }

    _closeSearch(clear: true);
    switch (command) {
      case 'status':
        await component.controller.refreshStatus();
        if (!mounted) return;
        setState(() {});
      case 'kill':
        _detailAction = _DetailAction.kill;
        _openPrompt(_PromptKind.kill);
      case 'rollback':
        _detailAction = _DetailAction.rollback;
        _openPrompt(_PromptKind.rollback);
      case 'freeze':
        _detailAction = _DetailAction.freeze;
        _openPrompt(_PromptKind.freeze);
      case 'unfreeze':
        _detailAction = _DetailAction.unfreeze;
        _openPrompt(_PromptKind.unfreeze);
      case 'publish':
        _detailAction = _DetailAction.publish;
        await _publishSelected();
    }
  }

  String? _matchedCommand(String raw) {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) return null;
    for (final command in _commandNames) {
      if (command == query || command.startsWith(query)) return command;
    }
    return null;
  }

  void _openPrompt(_PromptKind kind) {
    setState(() {
      _prompt = kind;
      _promptController.clear();
    });
  }

  Future<void> _submitPrompt(String raw) async {
    final prompt = _prompt;
    if (prompt == null) return;
    final input = raw.trim();
    if (input.isEmpty) return;

    setState(() {
      _prompt = null;
      _promptController.clear();
    });

    switch (prompt) {
      case _PromptKind.kill:
        if (_needsLiveConfirmation) {
          final target = _confirmTarget();
          if (target == null) {
            _reportNothingSelected();
            return;
          }
          _openOperationConfirmation(
            _PendingKill(reason: input, target: target),
          );
          return;
        }
        await component.controller.killSelected(reason: input, frozen: false);
      case _PromptKind.freeze:
        await component.controller.freezeSelected(reason: input);
      case _PromptKind.unfreeze:
        await component.controller.unfreezeSelected(reason: input);
      case _PromptKind.rollback:
        await _submitRollback(input);
      case _PromptKind.operationConfirm:
        await _submitOperationConfirmation(input);
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _submitRollback(String input) async {
    if (_previewInFlight) return;

    final parts = input.split(RegExp(r'\s+'));
    final version = parts.isEmpty ? null : int.tryParse(parts.first);
    final reason = parts.length <= 1 ? '' : parts.skip(1).join(' ').trim();
    if (version == null || reason.isEmpty) {
      setState(() {
        _prompt = _PromptKind.rollback;
        _promptController.text = input;
      });
      return;
    }
    // Rollback is always preview-then-confirm: the read-only preview's
    // cohort-impact note is the only signal for how the re-point lands
    // across the installed cohort, so it is shown before the mutation in
    // every environment (the live plane additionally keeps its guardrail
    // semantics on the executor side). The preflight classification never
    // blocks a rollback server-side, but a FAILED preview does abort this
    // console flow (fail-visible; the raw CLI can still roll back without
    // a preview).
    //
    // The target is read BEFORE the await so a selection that moves during
    // the preview is detected. A null target (nothing selected) needs no
    // message of its own: previewRollback's guard reports it and returns
    // null, landing in the note == null arm below.
    final target = _confirmTarget();
    late final String? note;
    final previewGeneration = ++_previewGeneration;
    setState(() {
      _previewInFlight = true;
    });
    try {
      note = await component.controller.previewRollback(toVersion: version);
    } finally {
      if (mounted && previewGeneration == _previewGeneration) {
        setState(() {
          _previewInFlight = false;
        });
      }
    }
    if (!mounted || previewGeneration != _previewGeneration) return;
    if (note == null) {
      // Preview failed or refused; the operation message carries the cause.
      return;
    }
    // The preview awaited — abort if the selection moved meanwhile, so the
    // note can never be presented against a different surface. (A null
    // target cannot reach here — the preview's own guard already returned —
    // but the check also promotes the type.)
    if (target == null || _confirmTarget() != target) {
      component.controller.reportOperationMessage(
        'Selection changed during the preview — nothing was rolled back.',
      );
      if (mounted) setState(() {});
      return;
    }
    _openOperationConfirmation(
      _PendingRollback(
        reason: reason,
        toVersion: version,
        target: target,
        impactNote: note.isEmpty ? null : note,
      ),
    );
  }

  /// The exact surface and environment target a parked confirm is pinned to,
  /// or null when nothing is selected.
  _ConfirmTarget? _confirmTarget() {
    final state = component.controller.state;
    final surface = state.selectedSurface;
    final context = state.context;
    if (surface == null || context == null) return null;
    return _ConfirmTarget(
      surfaceType: surface.surfaceType,
      surfaceSlug: surface.slug,
      appId: context.appId,
      environmentTargetId: context.environmentTargetId,
      namedEnvironmentId: context.namedEnvironmentId,
      environment: context.environment,
      runtimePlane: context.runtimePlane,
    );
  }

  Future<void> _submitOperationConfirmation(String input) async {
    final pending = _pendingConfirm;
    if (pending == null) return;
    if (input.toLowerCase() != 'confirm') {
      setState(() {
        _prompt = _PromptKind.operationConfirm;
        _promptController.text = input;
      });
      return;
    }
    _pendingConfirm = null;
    // The operation executes against the CURRENT selection, so a confirm is
    // only honored while the selection still matches the target it was
    // opened (and previewed) for — otherwise it could mutate a different
    // surface or environment than the one the operator saw.
    if (_confirmTarget() != pending.target) {
      component.controller.reportOperationMessage(
        'Selection changed since the confirmation opened — nothing was '
        'changed. Re-run the operation on the selected surface.',
      );
      return;
    }
    switch (pending) {
      case _PendingKill():
        await component.controller.killSelected(
          reason: pending.reason,
          frozen: false,
          confirmedProduction: true,
        );
      case _PendingRollback(:final toVersion):
        // "The operator typed confirm" — the executor scopes the flag to
        // the live plane itself, so both arms pass it unconditionally.
        await component.controller.rollbackSelected(
          reason: pending.reason,
          toVersion: toVersion,
          freeze: false,
          confirmedProduction: true,
        );
    }
  }

  bool get _needsLiveConfirmation =>
      component.controller.state.context?.runtimePlane == RuntimePlane.live;

  /// Surface a visible refusal when a live-plane kill was submitted with no
  /// usable selection (e.g. a background refresh emptied the surface list
  /// while the prompt was open). The prompt input is already consumed at
  /// this point, so dropping it silently would leave the operator unable to
  /// tell whether the operation ran. Uses the controller's guard wording so
  /// the refusal reads the same on every path. The setState is load-bearing:
  /// this path early-returns before _submitPrompt's trailing repaint.
  void _reportNothingSelected() {
    component.controller.reportOperationMessage('No surface selected.');
    if (mounted) setState(() {});
  }

  void _openOperationConfirmation(_PendingConfirmOperation pending) {
    setState(() {
      _pendingConfirm = pending;
      _prompt = _PromptKind.operationConfirm;
      _promptController.clear();
    });
  }

  Future<void> _publishSelected() async {
    await component.controller.publishSelected();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _selectSurface(int index) async {
    setState(() {
      component.controller.focusPanel(ConsolePanel.surfaces);
      _surfaceFocus = _SurfaceFocus.rows;
    });
    await component.controller.selectSurface(index);
    if (!mounted) return;
    setState(() {});
  }

  void _selectView(_ConsoleView view) {
    setState(() {
      _activeView = view;
      _leftEnvironmentFocused = false;
      component.controller.focusPanel(ConsolePanel.projects);
    });
  }

  bool _canCommitLeftEnvironment() =>
      _isLeftPanel(component.controller.state.focusedPanel) &&
      _leftEnvironmentFocused;

  bool _canCommitDetailAction() =>
      _activeView == _ConsoleView.surfaces &&
      _isDetailPanel(component.controller.state.focusedPanel);

  void _moveDetailAction(int delta) {
    if (_activeView != _ConsoleView.surfaces) return;
    final values = _DetailAction.values;
    final current = values.indexOf(_detailAction);
    final next = (current + delta).clamp(0, values.length - 1).toInt();
    setState(() {
      _detailAction = values[next];
    });
  }

  Future<void> _selectDetailAction(
    _DetailAction action, {
    required bool launch,
  }) async {
    setState(() {
      _detailAction = action;
      component.controller.focusPanel(ConsolePanel.detail);
    });
    if (launch) await _triggerDetailAction(action);
  }

  Future<void> _triggerDetailAction(_DetailAction action) async {
    switch (action) {
      case _DetailAction.publish:
        await _publishSelected();
      case _DetailAction.freeze:
        _openPrompt(_PromptKind.freeze);
      case _DetailAction.unfreeze:
        _openPrompt(_PromptKind.unfreeze);
      case _DetailAction.rollback:
        _openPrompt(_PromptKind.rollback);
      case _DetailAction.kill:
        _openPrompt(_PromptKind.kill);
    }
  }

  Future<void> _selectEnvironment(int index) async {
    setState(() {
      _leftEnvironmentFocused = true;
      _leftEnvironmentFocusIndex = index;
      component.controller.focusPanel(ConsolePanel.projects);
    });
    await component.controller.selectEnvironment(index);
    if (!mounted) return;
    setState(() {
      _leftEnvironmentFocusIndex = component.controller.state.environmentIndex;
    });
  }

  bool _canCommitSurfaceFilter() =>
      component.controller.state.focusedPanel == ConsolePanel.surfaces &&
      _surfaceMiddleVisible &&
      _surfaceFocus == _SurfaceFocus.filters;

  Future<void> _commitSurfaceFilter() async {
    await _ensureSelectedSurfaceVisible();
    if (!mounted) return;
    if (_visibleSurfaces(component.controller.state).isEmpty) return;
    setState(() {
      _surfaceFocus = _SurfaceFocus.rows;
    });
  }

  Future<void> _selectSurfaceFilter(
    _SurfaceFilter filter, {
    bool commitRows = false,
  }) async {
    setState(() {
      _surfaceFilter = filter;
      _surfaceFocus = _SurfaceFocus.filters;
      component.controller.focusPanel(ConsolePanel.surfaces);
    });
    await _ensureSelectedSurfaceVisible();
    if (!mounted) return;
    setState(() {
      if (commitRows &&
          _visibleSurfaces(component.controller.state).isNotEmpty) {
        _surfaceFocus = _SurfaceFocus.rows;
      }
    });
  }

  Future<void> _ensureSelectedSurfaceVisible() async {
    final state = component.controller.state;
    final visibleSurfaces = _visibleSurfaces(state);
    if (visibleSurfaces.isEmpty) return;
    final selectedSurface = state.selectedSurface;
    if (selectedSurface != null && visibleSurfaces.contains(selectedSurface)) {
      return;
    }
    await component.controller.selectSurface(
      state.surfaces.indexOf(visibleSurfaces.first),
    );
  }

  void _startPanelResize(_PanelDivider divider, int x) {
    setState(() {
      _activeDivider = divider;
      _lastDragX = x;
    });
  }

  void _handlePanelResizeMouse(MouseEvent event) {
    final activeDivider = _activeDivider;
    if (activeDivider == null) return;
    if (!event.pressed && !event.isPrimaryButtonDown) {
      setState(() {
        _activeDivider = null;
        _lastDragX = null;
      });
      return;
    }

    final lastDragX = _lastDragX ?? event.x;
    final delta = event.x - lastDragX;
    if (delta == 0) return;
    setState(() {
      switch (activeDivider) {
        case _PanelDivider.navSurface:
          _navWidth = (_navWidth + delta).clamp(_minNavWidth, 40).toInt();
        case _PanelDivider.surfaceDetail:
          _surfaceWidth = (_surfaceWidth + delta)
              .clamp(_minSurfaceWidth, 64)
              .toInt();
      }
      _lastDragX = event.x;
    });
  }

  @override
  Component build(BuildContext context) {
    final state = component.controller.state;
    return Focusable(
      focused: true,
      onKeyEvent: _handleKeyEvent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        decoration: const BoxDecoration(color: _ConsoleTheme.ground),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 1),
            Text(
              'restage        ${_contextLabel(state)}',
              style: const TextStyle(
                color: _ConsoleTheme.brand,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 1),
            _searchBand(state),
            const SizedBox(height: 1),
            Expanded(child: _body(state)),
            if (_previewInFlight) ...[
              _previewIndicator(),
              const SizedBox(height: 1),
            ] else if (_prompt != null) ...[
              _promptBox(_prompt!),
              const SizedBox(height: 1),
            ],
            // The single operation-message slot. It renders in every view
            // and selection state, so a refused or failed operation is never
            // silently dropped (the surface detail panel is only on screen
            // in the surfaces view, and can early-return before its body).
            if (state.operationMessage != null)
              Text(
                state.operationMessage!,
                maxLines: 1,
                style: const TextStyle(color: _ConsoleTheme.warning),
              ),
            const Text(
              '/ search | tab panels | arrows move | enter/space select | drag resize | q quit',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(color: _ConsoleTheme.muted),
            ),
          ],
        ),
      ),
    );
  }

  Component _body(ConsoleState state) {
    if (state.loading) {
      return const Center(
        child: Text(
          'Loading console...',
          style: TextStyle(color: _ConsoleTheme.muted),
        ),
      );
    }
    final error = state.error;
    if (error != null) {
      return Center(
        child: Text(error, style: const TextStyle(color: _ConsoleTheme.brand)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = _resolvedPanelWidths(constraints.maxWidth.floor());
        return MouseRegion(
          onHover: _handlePanelResizeMouse,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: widths.nav.toDouble(),
                child: _panelBox(
                  panel: ConsolePanel.projects,
                  title: 'Dashboard',
                  focused:
                      state.focusedPanel == ConsolePanel.projects ||
                      state.focusedPanel == ConsolePanel.apps,
                  child: _leftNav(state),
                ),
              ),
              _resizeDivider(_PanelDivider.navSurface),
              SizedBox(
                width: widths.surface.toDouble(),
                child: _panelBox(
                  panel: ConsolePanel.surfaces,
                  title: _middlePanelTitle,
                  focused: state.focusedPanel == ConsolePanel.surfaces,
                  child: _middlePanel(state, width: widths.surface),
                ),
              ),
              _resizeDivider(_PanelDivider.surfaceDetail),
              Expanded(
                child: _panelBox(
                  panel: ConsolePanel.detail,
                  title: _detailPanelTitle(state),
                  focused:
                      state.focusedPanel == ConsolePanel.detail ||
                      state.focusedPanel == ConsolePanel.actions,
                  child: _detailPanel(state),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  _PanelWidths _resolvedPanelWidths(int availableWidth) {
    final maxFixed = (availableWidth - _minDetailWidth - _dividerWidth * 2)
        .clamp(_minNavWidth + _minSurfaceWidth, 104);
    var nav = _navWidth.clamp(_minNavWidth, 40).toInt();
    var surface = _surfaceWidth.clamp(_minSurfaceWidth, 64).toInt();

    if (nav + surface > maxFixed) {
      final surfaceReduction = (surface - _minSurfaceWidth).clamp(
        0,
        nav + surface - maxFixed,
      );
      surface -= surfaceReduction.toInt();
    }
    if (nav + surface > maxFixed) {
      nav -= (nav + surface - maxFixed).toInt();
    }

    return _PanelWidths(nav: nav, surface: surface);
  }

  Component _resizeDivider(_PanelDivider divider) {
    final active = _activeDivider == divider;
    return MouseRegion(
      onHover: (event) {
        if (event.pressed || event.isPrimaryButtonDown) {
          _startPanelResize(divider, event.x);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) =>
            _startPanelResize(divider, details.globalPosition.dx.toInt()),
        child: SizedBox(
          width: _dividerWidth.toDouble(),
          child: Center(
            child: Text(
              '|',
              style: TextStyle(
                color: active ? _ConsoleTheme.focus : _ConsoleTheme.border,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _contextLabel(ConsoleState state) {
    final context = state.context;
    if (context == null) return '- / - / -';
    return '${context.project} / ${context.app} / '
        '${context.environmentLabel}';
  }

  String get _middlePanelTitle {
    if (_searchQuery.isNotEmpty) return 'Search';
    return _activeView.label;
  }

  bool get _surfaceMiddleVisible =>
      _searchQuery.isNotEmpty || _activeView == _ConsoleView.surfaces;

  Component _middlePanel(ConsoleState state, {required int width}) {
    if (_surfaceMiddleVisible) return _surfaceList(state, width: width);
    return switch (_activeView) {
      _ConsoleView.overview => _overviewPanel(state),
      _ConsoleView.auditTrail => _auditTrailPanel(state),
      _ConsoleView.surfaces => _surfaceList(state, width: width),
    };
  }

  String _detailPanelTitle(ConsoleState state) {
    return switch (_activeView) {
      _ConsoleView.overview => 'Overview detail',
      _ConsoleView.auditTrail => 'Audit detail',
      _ConsoleView.surfaces =>
        'Detail: ${state.selectedSurface?.slug ?? '-'} Actions',
    };
  }

  Component _overviewPanel(ConsoleState state) {
    final paywallCount = state.surfaces
        .where((surface) => surface.surfaceType == 'paywall')
        .length;
    final onboardingCount = state.surfaces
        .where((surface) => surface.surfaceType == 'onboarding')
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Project snapshot',
          style: TextStyle(
            color: _ConsoleTheme.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Surfaces ${state.surfaces.length}',
          maxLines: 1,
          style: const TextStyle(color: _ConsoleTheme.text),
        ),
        Text(
          'Paywalls $paywallCount',
          maxLines: 1,
          style: const TextStyle(color: _ConsoleTheme.text),
        ),
        Text(
          'Onboarding $onboardingCount',
          maxLines: 1,
          style: const TextStyle(color: _ConsoleTheme.text),
        ),
        const SizedBox(height: 1),
        const Text(
          'Use / to search surfaces or commands',
          maxLines: 1,
          style: TextStyle(color: _ConsoleTheme.muted),
        ),
      ],
    );
  }

  Component _auditTrailPanel(ConsoleState state) {
    final activity = state.activity;
    final auditLog = state.auditLog;
    final verdict = state.auditVerdict;
    final auditError = state.auditError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Server audit',
          maxLines: 1,
          style: TextStyle(
            color: _ConsoleTheme.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (verdict != null)
          Text(
            'Verdict ${verdict.status}',
            maxLines: 1,
            style: TextStyle(
              color: verdict.status == 'verified'
                  ? _ConsoleTheme.focus
                  : _ConsoleTheme.warning,
            ),
          ),
        if (auditError != null)
          Text(
            auditError,
            maxLines: 1,
            style: const TextStyle(color: _ConsoleTheme.warning),
          )
        else if (auditLog.isEmpty)
          const Text(
            'No server audit rows',
            maxLines: 1,
            style: TextStyle(color: _ConsoleTheme.muted),
          )
        else
          for (final entry in auditLog.take(4)) ...[
            Text(
              _auditEntryLabel(entry),
              maxLines: 1,
              style: TextStyle(
                color: entry.chainVerified
                    ? _ConsoleTheme.focus
                    : _ConsoleTheme.warning,
              ),
            ),
            if (entry.actorEmail != null)
              Text(
                entry.actorEmail!,
                maxLines: 1,
                style: const TextStyle(color: _ConsoleTheme.muted),
              ),
          ],
        const SizedBox(height: 1),
        Text(
          'Session activity',
          maxLines: 1,
          style: TextStyle(
            color: _ConsoleTheme.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (activity.isEmpty)
          const Text(
            'No local operations yet',
            maxLines: 1,
            style: TextStyle(color: _ConsoleTheme.muted),
          )
        else
          for (final entry in activity.take(5))
            Text(
              _activityLabel(entry),
              maxLines: 1,
              style: TextStyle(
                color: entry.exitCode == 0
                    ? _ConsoleTheme.focus
                    : _ConsoleTheme.warning,
              ),
            ),
      ],
    );
  }

  String _activityLabel(ConsoleActivityEntry entry) {
    return '${entry.operation} ${entry.surfaceSlug} '
        'exit ${entry.exitCode}  ${entry.message}';
  }

  String _auditEntryLabel(SurfaceAuditLogEntry entry) {
    final surface =
        entry.context['surfaceSlug'] ??
        entry.targetId ??
        entry.targetType ??
        '-';
    final chain = entry.chainState == 'pendingChain'
        ? 'pending'
        : entry.chainVerified
        ? 'verified'
        : 'unverified';
    return '${entry.action} $surface $chain';
  }

  Component _searchBand(ConsoleState state) {
    return SizedBox(
      width: 64,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openSearch,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: _ConsoleTheme.recessed,
            border: BoxBorder.all(
              color: _searchFocused
                  ? _ConsoleTheme.focus
                  : _ConsoleTheme.border,
            ),
          ),
          child: _searchFocused
              ? TextField(
                  controller: _searchController,
                  focused: true,
                  placeholder: 'search surfaces, commands',
                  onChanged: _updateSearch,
                  onSubmitted: (value) => unawaited(_submitSearch(value)),
                )
              : Text(
                  _searchLabel(state),
                  maxLines: 1,
                  style: const TextStyle(color: _ConsoleTheme.muted),
                ),
        ),
      ),
    );
  }

  String _searchLabel(ConsoleState state) {
    final query = _searchQuery;
    if (query.isEmpty) return '/ search surfaces, commands';
    final count = _searchResults(state).length;
    return '/ $query  ($count result${count == 1 ? '' : 's'})';
  }

  Component _leftNav(ConsoleState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _navRow(
          selected: _activeView == _ConsoleView.overview,
          label: _ConsoleView.overview.label,
          onTap: () => _selectView(_ConsoleView.overview),
        ),
        _navRow(
          selected: _activeView == _ConsoleView.surfaces,
          label: _ConsoleView.surfaces.label,
          onTap: () => _selectView(_ConsoleView.surfaces),
        ),
        _navRow(
          selected: _activeView == _ConsoleView.auditTrail,
          label: _ConsoleView.auditTrail.label,
          onTap: () => _selectView(_ConsoleView.auditTrail),
        ),
        const Text('CONTEXT', style: TextStyle(color: _ConsoleTheme.muted)),
        Text(
          'Proj ${state.projects.length}  Apps ${state.apps.length}',
          maxLines: 1,
          style: const TextStyle(color: _ConsoleTheme.text),
        ),
        Text(
          'ENVIRONMENTS ${state.environments.length}',
          maxLines: 1,
          style: const TextStyle(color: _ConsoleTheme.muted),
        ),
        for (var index = 0; index < state.environments.length; index++)
          _environmentRow(state, index),
      ],
    );
  }

  Component _environmentRow(ConsoleState state, int index) {
    final environment = state.environments[index];
    final selected = index == state.environmentIndex;
    final focused =
        _leftEnvironmentFocused &&
        index == _leftEnvironmentFocusIndex &&
        _isLeftPanel(state.focusedPanel);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_selectEnvironment(index)),
      child: SizedBox(
        width: 17,
        child: Text(
          '${selected ? '>' : ' '} ${environment.label}',
          maxLines: 1,
          style: TextStyle(
            color: focused
                ? _ConsoleTheme.focus
                : selected
                ? _ConsoleTheme.brand
                : _ConsoleTheme.text,
            backgroundColor: selected ? _ConsoleTheme.brandScrim : null,
            fontWeight: selected || focused ? FontWeight.bold : null,
          ),
        ),
      ),
    );
  }

  Component _navRow({
    required bool selected,
    required String label,
    required void Function() onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 17,
        child: Text(
          '${selected ? '>' : ' '} $label',
          maxLines: 1,
          style: TextStyle(
            color: selected ? _ConsoleTheme.brand : _ConsoleTheme.text,
            backgroundColor: selected ? _ConsoleTheme.brandScrim : null,
            fontWeight: selected ? FontWeight.bold : null,
          ),
        ),
      ),
    );
  }

  Component _surfaceList(ConsoleState state, {required int width}) {
    final visibleSurfaces = _visibleSurfaces(state);
    final searchResults = _searchResults(state);
    final showWideRows = width >= 29;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _filterChip(_SurfaceFilter.all),
            const SizedBox(width: 1),
            _filterChip(_SurfaceFilter.paywall),
            const SizedBox(width: 1),
            _filterChip(_SurfaceFilter.onboarding),
          ],
        ),
        Row(
          children: [
            _filterChip(_SurfaceFilter.message),
            const SizedBox(width: 1),
            _filterChip(_SurfaceFilter.survey),
          ],
        ),
        const SizedBox(height: 1),
        if (_searchQuery.isNotEmpty) ...[
          const Text(
            'Search results',
            style: TextStyle(
              color: _ConsoleTheme.text,
              fontWeight: FontWeight.bold,
            ),
          ),
          for (final result in searchResults.take(3))
            Text(
              result,
              maxLines: 1,
              style: const TextStyle(color: _ConsoleTheme.focus),
            ),
          const SizedBox(height: 1),
        ],
        if (visibleSurfaces.isEmpty)
          const Text(
            'No surfaces',
            maxLines: 1,
            style: TextStyle(color: _ConsoleTheme.muted),
          )
        else if (showWideRows)
          const Text(
            'surface     delivery   v',
            maxLines: 1,
            style: TextStyle(color: _ConsoleTheme.muted),
          ),
        for (final surface in visibleSurfaces)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                unawaited(_selectSurface(state.surfaces.indexOf(surface))),
            child: SizedBox(
              width: width - 2,
              child: Text(
                _surfaceRowLabel(
                  state: state,
                  surface: surface,
                  wide: showWideRows,
                ),
                maxLines: 1,
                style: TextStyle(
                  color: state.surfaces.indexOf(surface) == state.surfaceIndex
                      ? _ConsoleTheme.brand
                      : _ConsoleTheme.text,
                  backgroundColor:
                      state.surfaces.indexOf(surface) == state.surfaceIndex
                      ? _ConsoleTheme.brandScrim
                      : null,
                  fontWeight:
                      state.surfaces.indexOf(surface) == state.surfaceIndex
                      ? FontWeight.bold
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Component _filterChip(_SurfaceFilter filter) {
    final selected = _surfaceFilter == filter;
    final focused =
        selected &&
        _surfaceFocus == _SurfaceFocus.filters &&
        component.controller.state.focusedPanel == ConsolePanel.surfaces;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_selectSurfaceFilter(filter, commitRows: true)),
      child: Text(
        '[${filter.shortLabel}]',
        maxLines: 1,
        style: TextStyle(
          color: focused
              ? _ConsoleTheme.focus
              : selected
              ? _ConsoleTheme.brand
              : _ConsoleTheme.text,
          backgroundColor: selected ? _ConsoleTheme.brandScrim : null,
          fontWeight: selected || focused ? FontWeight.bold : null,
        ),
      ),
    );
  }

  List<ConsoleSurface> _visibleSurfaces(ConsoleState state) {
    final filtered = _filteredSurfaces(state);
    final query = _searchQuery;
    if (query.isEmpty) return filtered;

    final matches = filtered
        .where((surface) => _surfaceMatches(surface, query))
        .toList();
    if (matches.isNotEmpty) return matches;
    if (_matchedCommand(query) != null) return filtered;
    return const [];
  }

  List<ConsoleSurface> _filteredSurfaces(ConsoleState state) {
    return switch (_surfaceFilter) {
      _SurfaceFilter.all => state.surfaces,
      _SurfaceFilter.paywall =>
        state.surfaces
            .where((surface) => surface.surfaceType == 'paywall')
            .toList(),
      _SurfaceFilter.onboarding =>
        state.surfaces
            .where((surface) => surface.surfaceType == 'onboarding')
            .toList(),
      _SurfaceFilter.message =>
        state.surfaces
            .where((surface) => surface.surfaceType == 'message')
            .toList(),
      _SurfaceFilter.survey =>
        state.surfaces
            .where((surface) => surface.surfaceType == 'survey')
            .toList(),
    };
  }

  List<String> _searchResults(ConsoleState state) {
    final query = _searchQuery;
    if (query.isEmpty) return const [];

    return [
      for (final surface in _filteredSurfaces(state))
        if (_surfaceMatches(surface, query))
          '${surface.slug}  ${surface.surfaceType}',
      for (final command in _commandNames)
        if (command.contains(query)) 'command  $command',
    ];
  }

  bool _surfaceMatches(ConsoleSurface surface, String query) {
    return surface.slug.toLowerCase().contains(query) ||
        surface.name.toLowerCase().contains(query) ||
        surface.surfaceType.toLowerCase().contains(query);
  }

  String get _searchQuery => _searchController.text.trim().toLowerCase();

  Component _detailPanel(ConsoleState state) {
    return switch (_activeView) {
      _ConsoleView.overview => _overviewDetailPanel(state),
      _ConsoleView.surfaces => _surfaceDetailPanel(state),
      _ConsoleView.auditTrail => _auditDetailPanel(state),
    };
  }

  Component _overviewDetailPanel(ConsoleState state) {
    final paywallCount = state.surfaces
        .where((surface) => surface.surfaceType == 'paywall')
        .length;
    final onboardingCount = state.surfaces
        .where((surface) => surface.surfaceType == 'onboarding')
        .length;
    final context = state.context;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Project snapshot',
          maxLines: 1,
          style: TextStyle(
            color: _ConsoleTheme.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Active surfaces ${state.surfaces.length}',
          maxLines: 1,
          style: const TextStyle(color: _ConsoleTheme.focus),
        ),
        Text(
          'Paywalls $paywallCount / onboarding $onboardingCount',
          maxLines: 1,
          style: const TextStyle(color: _ConsoleTheme.text),
        ),
        const Text(
          '30-day views -',
          maxLines: 1,
          style: TextStyle(color: _ConsoleTheme.muted),
        ),
        const Text(
          'Conversion rate -',
          maxLines: 1,
          style: TextStyle(color: _ConsoleTheme.muted),
        ),
        const Text(
          r'MAR consumed $0 / $10k',
          maxLines: 1,
          style: TextStyle(color: _ConsoleTheme.text),
        ),
        const Text(
          'Free tier',
          maxLines: 1,
          style: TextStyle(color: _ConsoleTheme.muted),
        ),
        if (context != null)
          Text(
            'Env ${context.environmentLabel}',
            maxLines: 1,
            style: const TextStyle(color: _ConsoleTheme.accentBlue),
          ),
      ],
    );
  }

  Component _auditDetailPanel(ConsoleState state) {
    final latestOperation = state.activity.isEmpty
        ? null
        : state.activity.first;
    final latestAudit = state.auditLog.isEmpty ? null : state.auditLog.first;
    final verdict = state.auditVerdict;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Chain verdict',
          maxLines: 1,
          style: TextStyle(
            color: _ConsoleTheme.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (verdict == null) ...[
          const Text(
            'No verdict loaded',
            maxLines: 1,
            style: TextStyle(color: _ConsoleTheme.muted),
          ),
        ] else ...[
          Text(
            'status ${verdict.status}',
            maxLines: 1,
            style: TextStyle(
              color: verdict.status == 'verified'
                  ? _ConsoleTheme.focus
                  : _ConsoleTheme.warning,
            ),
          ),
          if (verdict.verifiedThroughEntryId != null)
            Text(
              'verified through entry ${verdict.verifiedThroughEntryId}',
              maxLines: 1,
              style: const TextStyle(color: _ConsoleTheme.text),
            ),
          if (verdict.failedEntryId != null)
            Text(
              'failed entry ${verdict.failedEntryId}',
              maxLines: 1,
              style: const TextStyle(color: _ConsoleTheme.warning),
            ),
          if (verdict.failedCheck != null)
            Text(
              'failed check ${verdict.failedCheck}',
              maxLines: 1,
              style: const TextStyle(color: _ConsoleTheme.warning),
            ),
        ],
        const SizedBox(height: 1),
        const Text(
          'Latest server event',
          maxLines: 1,
          style: TextStyle(
            color: _ConsoleTheme.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (latestAudit == null)
          const Text(
            'No server audit rows',
            maxLines: 1,
            style: TextStyle(color: _ConsoleTheme.muted),
          )
        else ...[
          Text(
            _auditEntryLabel(latestAudit),
            maxLines: 1,
            style: TextStyle(
              color: latestAudit.chainVerified
                  ? _ConsoleTheme.focus
                  : _ConsoleTheme.warning,
            ),
          ),
          if (latestAudit.actorEmail != null)
            Text(
              latestAudit.actorEmail!,
              maxLines: 1,
              style: const TextStyle(color: _ConsoleTheme.text),
            ),
          if (latestAudit.reason != null)
            Text(
              'reason ${latestAudit.reason}',
              maxLines: 1,
              style: const TextStyle(color: _ConsoleTheme.muted),
            ),
        ],
        const SizedBox(height: 1),
        const Text(
          'Latest operation',
          maxLines: 1,
          style: TextStyle(
            color: _ConsoleTheme.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (latestOperation == null)
          const Text(
            'No local operations yet',
            maxLines: 1,
            style: TextStyle(color: _ConsoleTheme.muted),
          )
        else ...[
          Text(
            '${latestOperation.operation} ${latestOperation.surfaceSlug}',
            maxLines: 1,
            style: const TextStyle(color: _ConsoleTheme.focus),
          ),
          Text(
            'Result exit ${latestOperation.exitCode}',
            maxLines: 1,
            style: TextStyle(
              color: latestOperation.exitCode == 0
                  ? _ConsoleTheme.focus
                  : _ConsoleTheme.warning,
            ),
          ),
          Text(
            latestOperation.message,
            maxLines: 1,
            style: const TextStyle(color: _ConsoleTheme.text),
          ),
        ],
      ],
    );
  }

  Component _surfaceDetailPanel(ConsoleState state) {
    final surface = state.selectedSurface;
    if (surface == null) return const Text('No surface selected');
    final status = state.status;
    final liveVersion = status?.liveVersion;
    final lockedText = status?.locked == true ? 'locked' : 'unlocked';
    final liveText = liveVersion == null ? '-' : 'v$liveVersion';
    final latestHash = status?.versions.isNotEmpty == true
        ? status!.versions.first.contentHash
        : null;
    // The active version's flow delivery mode ('typed'/'general'), when the
    // server supplies one — general means the flow structure itself can be
    // recomposed over the air.
    final activeMode = status?.versions
        .where((v) => v.isActive)
        .firstOrNull
        ?.deliveryMode;
    final shapeText =
        '${status?.deliveryShape ?? '-'}'
        '${activeMode != null ? ' ($activeMode)' : ''}';
    final deliveryText = status?.supportsRollback == false
        ? 'delivery $shapeText version-pinned'
        : latestHash == null
        ? 'delivery $shapeText / $lockedText'
        : '$latestHash delivery $shapeText / $lockedText';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Snapshot Active surfaces',
          maxLines: 1,
          style: TextStyle(
            color: _ConsoleTheme.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Live version $liveText',
          maxLines: 1,
          style: const TextStyle(color: _ConsoleTheme.accentBlue),
        ),
        Text(
          deliveryText,
          maxLines: 1,
          style: TextStyle(
            color: status?.locked == true
                ? _ConsoleTheme.warning
                : _ConsoleTheme.focus,
          ),
        ),
        ..._rollbackSupportLines(status),
        ..._versionHistoryLines(status),
        Text(
          _commandPreview(state, _detailAction),
          maxLines: 1,
          style: TextStyle(
            color: _ConsoleTheme.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        for (final action in _DetailAction.values) _actionChip(action),
        const Text(
          'Status-backed history',
          style: TextStyle(
            color: _ConsoleTheme.text,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  List<Component> _rollbackSupportLines(SurfaceStatusResult? status) {
    if (status == null) return const [];
    if (status.supportsRollback) return const [];
    return const [
      Text(
        'Rollback unsupported',
        maxLines: 1,
        style: TextStyle(color: _ConsoleTheme.muted),
      ),
    ];
  }

  List<Component> _versionHistoryLines(SurfaceStatusResult? status) {
    if (status == null || status.versions.isEmpty) return const [];
    final latest = status.versions.first;
    return [
      Text(
        'Version history ${_versionHistoryLabel(latest)}',
        maxLines: 1,
        style: TextStyle(
          color: latest.isActive
              ? _ConsoleTheme.accentBlue
              : _ConsoleTheme.muted,
        ),
      ),
    ];
  }

  String _versionHistoryLabel(SurfaceVersionResult version) {
    final active = version.isActive ? ' active' : '';
    final mode = version.deliveryMode != null
        ? '  ${version.deliveryMode}'
        : '';
    return 'v${version.version}$active  ${version.contentHash}$mode';
  }

  String _commandPreview(ConsoleState state, _DetailAction action) {
    final surface = state.selectedSurface;
    final context = state.context;
    if (surface == null || context == null) {
      return 'surface ${action.commandName} -';
    }
    return 'surface ${action.commandName} ${surface.slug} '
        '--type ${surface.surfaceType} '
        '--project ${context.project} '
        '--app ${context.app} '
        '--env ${context.environment} '
        '--plane ${context.runtimePlane.wireName}';
  }

  Component _actionChip(_DetailAction action) {
    final selected = _detailAction == action;
    final focused =
        selected && _isDetailPanel(component.controller.state.focusedPanel);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_selectDetailAction(action, launch: true)),
      child: Text(
        '${selected ? '>' : ' '} ${action.keyLabel} ${action.label}',
        maxLines: 1,
        style: TextStyle(
          color: focused
              ? _ConsoleTheme.focus
              : selected
              ? _ConsoleTheme.brand
              : _ConsoleTheme.text,
          backgroundColor: selected ? _ConsoleTheme.brandScrim : null,
          fontWeight: selected || focused ? FontWeight.bold : null,
        ),
      ),
    );
  }

  Component _panelBox({
    required ConsolePanel panel,
    required String title,
    required bool focused,
    required Component child,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _focusPanel(panel),
      child: Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: focused ? _ConsoleTheme.panel : _ConsoleTheme.recessed,
          border: BoxBorder.all(
            color: focused ? _ConsoleTheme.focus : _ConsoleTheme.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                color: focused ? _ConsoleTheme.focus : _ConsoleTheme.text,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  String _surfaceRowLabel({
    required ConsoleState state,
    required ConsoleSurface surface,
    required bool wide,
  }) {
    final index = state.surfaces.indexOf(surface);
    final selected = index == state.surfaceIndex;
    final marker = selected ? '> ' : '  ';
    if (!wide) {
      return '$marker${surface.slug}  ${surface.surfaceType}';
    }

    final selectedStatus = selected ? state.status : null;
    final delivery = selectedStatus?.deliveryShape ?? '-';
    final version = selectedStatus?.liveVersion == null
        ? '-'
        : 'v${selectedStatus!.liveVersion}';
    return '$marker'
        '${surface.slug.padRight(8)} '
        '${surface.surfaceType.padRight(10)} '
        '${delivery.padRight(8)} '
        '$version';
  }

  Component _promptBox(_PromptKind prompt) {
    final impactNote = switch (_pendingConfirm) {
      _PendingRollback(:final impactNote) => impactNote,
      _ => null,
    };
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: _ConsoleTheme.recessed,
        border: BoxBorder.all(color: _ConsoleTheme.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (prompt == _PromptKind.operationConfirm && impactNote != null)
            Text(
              impactNote,
              style: const TextStyle(color: _ConsoleTheme.accentBlue),
            ),
          Text(
            prompt.label,
            maxLines: 1,
            style: const TextStyle(color: _ConsoleTheme.warning),
          ),
          TextField(
            controller: _promptController,
            focused: true,
            placeholder: prompt.placeholder,
            onSubmitted: (value) => unawaited(_submitPrompt(value)),
          ),
        ],
      ),
    );
  }

  Component _previewIndicator() {
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: _ConsoleTheme.recessed,
        border: BoxBorder.all(color: _ConsoleTheme.warning),
      ),
      child: const Text(
        'Previewing rollback…',
        maxLines: 1,
        style: TextStyle(color: _ConsoleTheme.warning),
      ),
    );
  }
}

abstract class _ConsoleTheme {
  static const ground = Color.fromRGB(16, 15, 14);
  static const recessed = Color.fromRGB(32, 31, 28);
  static const panel = Color.fromRGB(42, 41, 38);
  static const border = Color.fromRGB(86, 82, 77);
  static const text = Color.fromRGB(244, 243, 240);
  static const muted = Color.fromRGB(150, 146, 139);
  static const brand = Color.fromRGB(255, 126, 107);
  static const brandScrim = Color.fromRGB(72, 43, 38);
  static const focus = Color.fromRGB(52, 211, 153);
  static const accentBlue = Color.fromRGB(96, 165, 250);
  static const warning = Color.fromRGB(245, 158, 11);
}

enum _ConsoleView {
  overview('Overview'),
  surfaces('Surfaces'),
  auditTrail('Audit trail');

  const _ConsoleView(this.label);

  final String label;
}

enum _SurfaceFilter {
  all,
  paywall,
  onboarding,
  message,
  survey;

  String get shortLabel {
    return switch (this) {
      _SurfaceFilter.all => 'all',
      _SurfaceFilter.paywall => 'pay',
      _SurfaceFilter.onboarding => 'onbd',
      _SurfaceFilter.message => 'msg',
      _SurfaceFilter.survey => 'surv',
    };
  }
}

enum _SurfaceFocus { filters, rows }

enum _DetailAction {
  publish('p', 'publish', 'publish'),
  freeze('f', 'freeze', 'freeze'),
  unfreeze('u', 'unfreeze', 'unfreeze'),
  rollback('r', 'rollback', 'rollback'),
  kill('k', 'kill', 'kill');

  const _DetailAction(this.keyLabel, this.label, this.commandName);

  final String keyLabel;
  final String label;
  final String commandName;
}

enum _PanelDivider { navSurface, surfaceDetail }

class _PanelWidths {
  const _PanelWidths({required this.nav, required this.surface});

  final int nav;
  final int surface;
}

enum _PromptKind {
  kill('Reason for kill', 'cleanup window'),
  rollback('Rollback target and reason', '2 bad release'),
  freeze('Reason for freeze', 'pause publishes'),
  unfreeze('Reason for unfreeze', 'resume publishes'),
  operationConfirm('Type confirm to proceed', 'confirm');

  const _PromptKind(this.label, this.placeholder);

  final String label;
  final String placeholder;
}

/// A destructive operation parked behind the type-confirm prompt: kill on
/// the live plane, and rollback in every environment (its confirm carries the
/// preview's cohort-impact note). Pinned to the [target] it was opened for —
/// the confirm is refused if the selection moves before it is typed.
sealed class _PendingConfirmOperation {
  const _PendingConfirmOperation({required this.reason, required this.target});

  final String reason;
  final _ConfirmTarget target;
}

final class _PendingKill extends _PendingConfirmOperation {
  const _PendingKill({required super.reason, required super.target});
}

final class _PendingRollback extends _PendingConfirmOperation {
  const _PendingRollback({
    required super.reason,
    required this.toVersion,
    required super.target,
    required this.impactNote,
  });

  final int toVersion;
  final String? impactNote;
}

/// The full target identity a parked confirm is pinned to. Value-comparable so
/// same-slug plane switches are detectable by equality.
class _ConfirmTarget {
  const _ConfirmTarget({
    required this.surfaceType,
    required this.surfaceSlug,
    required this.appId,
    required this.environmentTargetId,
    required this.namedEnvironmentId,
    required this.environment,
    required this.runtimePlane,
  });

  final String surfaceType;
  final String surfaceSlug;
  final int appId;
  final int environmentTargetId;
  final int namedEnvironmentId;
  final String environment;
  final RuntimePlane runtimePlane;

  @override
  bool operator ==(Object other) =>
      other is _ConfirmTarget &&
      other.surfaceType == surfaceType &&
      other.surfaceSlug == surfaceSlug &&
      other.appId == appId &&
      other.environmentTargetId == environmentTargetId &&
      other.namedEnvironmentId == namedEnvironmentId &&
      other.environment == environment &&
      other.runtimePlane == runtimePlane;

  @override
  int get hashCode => Object.hash(
    surfaceType,
    surfaceSlug,
    appId,
    environmentTargetId,
    namedEnvironmentId,
    environment,
    runtimePlane,
  );
}
