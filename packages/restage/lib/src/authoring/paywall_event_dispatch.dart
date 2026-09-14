import 'package:flutter/widgets.dart';

import 'event_dispatch_admission.dart';
import 'authoring_refusal_diagnostic.dart';

typedef RestagePaywallDispatchHandler = void Function(
  String name,
  Map<String, Object?> args,
);

final class RestagePaywallEventTargetScope extends InheritedWidget {
  const RestagePaywallEventTargetScope({
    super.key,
    required this.owner,
    required this.content,
    required this.isCurrent,
    required super.child,
  });

  final Object owner;
  final Object content;
  final bool Function() isCurrent;

  static RestagePaywallEventTargetScope? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<RestagePaywallEventTargetScope>();

  @override
  bool updateShouldNotify(RestagePaywallEventTargetScope oldWidget) =>
      !identical(owner, oldWidget.owner) ||
      !identical(content, oldWidget.content);
}

final class RestagePaywallEventDispatchRegistration {
  RestagePaywallEventDispatchRegistration({
    required RestagePaywallDispatchHandler handler,
  }) : _handler = handler {
    RestagePaywallEventDispatchAuthority._register(this);
  }

  RestagePaywallDispatchHandler _handler;
  RestagePaywallEventTargetScope? _target;
  Object _revision = Object();
  bool _mounted = true;

  void updateHandler(RestagePaywallDispatchHandler handler) {
    if (identical(_handler, handler)) return;
    _handler = handler;
    _revision = Object();
  }

  void updateTarget(RestagePaywallEventTargetScope? target) {
    final previous = _target;
    _target = target;
    if (identical(previous?.owner, target?.owner) &&
        identical(previous?.content, target?.content)) {
      return;
    }
    _revision = Object();
  }

  RestagePaywallDispatchHandler? capture({
    void Function(AuthoringRefusalKind refusal)? onRefused,
  }) {
    if (!_mounted) return null;
    final revision = _revision;
    final target = _target;
    final owner = target?.owner ?? this;
    final content = target?.content ?? this;
    final handler = _handler;
    final lease = RestageTargetEventDispatchLease(
      isCurrent: () {
        if (!_mounted ||
            !RestagePaywallEventDispatchAuthority._contains(this) ||
            !identical(revision, _revision) ||
            !identical(handler, _handler)) {
          return false;
        }
        final liveTarget = _target;
        return identical(owner, liveTarget?.owner ?? this) &&
            identical(content, liveTarget?.content ?? this) &&
            _isTargetCurrent(liveTarget);
      },
    );
    return (name, args) {
      if (!lease.invoke(() => handler(name, args))) {
        onRefused?.call(AuthoringRefusalKind.callbackRefused);
      }
    };
  }

  void dispose() {
    if (!_mounted) return;
    _mounted = false;
    _revision = Object();
    RestagePaywallEventDispatchAuthority._unregister(this);
  }

  static bool _isTargetCurrent(RestagePaywallEventTargetScope? target) {
    if (target == null) return true;
    try {
      return target.isCurrent();
    } on Object {
      return false;
    }
  }
}

final class RestagePaywallEventDispatchAuthority {
  static final List<RestagePaywallEventDispatchRegistration> _registrations =
      <RestagePaywallEventDispatchRegistration>[];
  static final List<RestagePaywallEventDispatchRegistration> _buildScopes =
      <RestagePaywallEventDispatchRegistration>[];

  static RestagePaywallDispatchHandler? capture({
    void Function(AuthoringRefusalKind refusal)? onRefused,
  }) {
    if (_buildScopes case [..., final registration]) {
      return registration.capture(onRefused: onRefused) ??
          _refusingHandler(onRefused, AuthoringRefusalKind.callbackRefused);
    }
    if (_registrations.length == 1) {
      return _registrations.single.capture(onRefused: onRefused) ??
          _refusingHandler(onRefused, AuthoringRefusalKind.callbackRefused);
    }
    return _registrations.isEmpty
        ? null
        : _refusingHandler(
            onRefused,
            AuthoringRefusalKind.ambiguousDispatcher,
          );
  }

  static void _refused(String _, Map<String, Object?> __) {}

  static RestagePaywallDispatchHandler _refusingHandler(
    void Function(AuthoringRefusalKind refusal)? onRefused,
    AuthoringRefusalKind refusal,
  ) {
    if (onRefused == null) return _refused;
    return (_, __) => onRefused(refusal);
  }

  static void runBuild(
    RestagePaywallEventDispatchRegistration registration,
    void Function() body,
  ) {
    if (!_contains(registration)) {
      body();
      return;
    }
    _buildScopes.add(registration);
    try {
      body();
    } finally {
      final index = _buildScopes.lastIndexWhere(
        (candidate) => identical(candidate, registration),
      );
      if (index >= 0) _buildScopes.removeAt(index);
    }
  }

  static void _register(RestagePaywallEventDispatchRegistration registration) {
    _registrations.add(registration);
  }

  static void _unregister(
    RestagePaywallEventDispatchRegistration registration,
  ) {
    _registrations.removeWhere(
      (candidate) => identical(candidate, registration),
    );
    _buildScopes.removeWhere(
      (candidate) => identical(candidate, registration),
    );
  }

  static bool _contains(
    RestagePaywallEventDispatchRegistration registration,
  ) =>
      _registrations.any(
        (candidate) => identical(candidate, registration),
      );
}
