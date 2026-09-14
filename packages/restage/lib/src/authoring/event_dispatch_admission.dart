import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

/// Runs a target's event only while that target is still the current one.
final class RestageTargetEventDispatchLease {
  const RestageTargetEventDispatchLease({required bool Function() isCurrent})
      : _isCurrent = isCurrent;

  final bool Function() _isCurrent;

  bool invoke(void Function() body) {
    try {
      if (!_isCurrent()) return false;
    } on Object {
      return false;
    }
    body();
    return true;
  }
}

final class RestageFlowEventDispatchBinding {
  const RestageFlowEventDispatchBinding({
    required this.controller,
    required this.registration,
  });

  final Object controller;
  final Object registration;
}

final class RestageFlowEventDispatchScope extends InheritedWidget {
  const RestageFlowEventDispatchScope({
    super.key,
    required Object controller,
    required Object registration,
    required super.child,
  })  : _controller = controller,
        _registration = registration;

  final Object _controller;
  final Object _registration;

  static RestageFlowEventDispatchBinding? maybeOf(
    BuildContext context,
  ) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<RestageFlowEventDispatchScope>();
    if (scope == null) return null;
    return RestageFlowEventDispatchBinding(
      controller: scope._controller,
      registration: scope._registration,
    );
  }

  @override
  bool updateShouldNotify(RestageFlowEventDispatchScope oldWidget) =>
      !identical(_controller, oldWidget._controller) ||
      !identical(_registration, oldWidget._registration);
}

final class RestageFlowEventDispatchRegistry {
  static final Object _dispatchLeaseKey = Object();
  static final Object _dispatchRefusalKey = Object();
  static final Map<Object,
          Map<Object, Map<Object, _RestageFlowEventDispatchRegistration>>>
      _owners = HashMap<
          Object,
          Map<Object,
              Map<Object, _RestageFlowEventDispatchRegistration>>>.identity();
  static final Map<Object, _RestageFlowContentState> _contentStates =
      HashMap<Object, _RestageFlowContentState>.identity();
  static final Map<Object, Map<Object, _RestageFlowEventHandlerAssociation>>
      _handlerAssociations = HashMap<Object,
          Map<Object, _RestageFlowEventHandlerAssociation>>.identity();
  static final Expando<bool> _registeredOwners = Expando<bool>();
  static final Expando<bool> _registeredControllers = Expando<bool>();

  static void register({
    required Object controller,
    required Object owner,
    required Object registration,
    Object? contentToken,
    bool Function()? isCurrent,
    void Function(String, Object?)? associatedHandler,
  }) {
    _registeredOwners[owner] = true;
    _registeredControllers[controller] = true;
    final controllers = _owners.putIfAbsent(
      owner,
      () => HashMap<Object,
          Map<Object, _RestageFlowEventDispatchRegistration>>.identity(),
    );
    final callbacks = controllers.putIfAbsent(
      controller,
      () => HashMap<Object, _RestageFlowEventDispatchRegistration>.identity(),
    );
    callbacks[registration] = _RestageFlowEventDispatchRegistration(
      contentToken: contentToken,
      isCurrent: isCurrent,
      associatedHandler: associatedHandler,
    );
    _refreshCurrentContent(controller);
  }

  static void unregister({
    required Object controller,
    required Object owner,
    required Object registration,
  }) {
    final controllers = _owners[owner];
    if (controllers == null) return;
    final callbacks = controllers[controller];
    if (callbacks == null) return;
    if (callbacks.remove(registration) == null) return;
    if (callbacks.isEmpty) {
      controllers.remove(controller);
      if (controllers.isEmpty) _owners.remove(owner);
    }
    _refreshCurrentContent(controller);
  }

  static bool hasRegistration({
    required Object controller,
    required Object owner,
  }) =>
      _owners[owner]?[controller]?.isNotEmpty ?? false;

  static void registerHandlerAssociation({
    required Object controller,
    required Object owner,
    required Object association,
    required void Function(String, Object?) handler,
    required bool Function() isCurrent,
  }) {
    _registeredOwners[owner] = true;
    final associations = _handlerAssociations.putIfAbsent(
      owner,
      () => HashMap<Object, _RestageFlowEventHandlerAssociation>.identity(),
    );
    associations[association] = _RestageFlowEventHandlerAssociation(
      controller: controller,
      handler: handler,
      isCurrent: isCurrent,
    );
  }

  static void unregisterHandlerAssociation({
    required Object owner,
    required Object association,
  }) {
    final associations = _handlerAssociations[owner];
    if (associations == null || associations.remove(association) == null) {
      return;
    }
    if (associations.isEmpty) _handlerAssociations.remove(owner);
  }

  static void Function(String, Object?)? bindDispatcherHandler({
    required Object owner,
    required RestageFlowEventDispatchBinding? binding,
    required void Function(String, Object?) handler,
    required void Function(void Function()) invokeWithOwner,
    required bool Function() dispatcherIsActive,
    required bool Function() handlerIsCurrent,
  }) {
    final admission = _acquireAdmission(
      owner: owner,
      binding: binding,
      handler: handler,
    );
    if (admission == null) {
      if (binding != null || !_remainedUnregistered(owner)) {
        return null;
      }
    }
    final lease = _RestageFlowEventDispatchLease(
      owner: owner,
      binding: binding,
      handler: handler,
      admission: admission,
      dispatcherIsActive: dispatcherIsActive,
      handlerIsCurrent: handlerIsCurrent,
    );
    final targetLease = RestageTargetEventDispatchLease(
      isCurrent: () {
        if (!_isDispatchLeaseCurrent(lease)) return false;
        final liveAdmission = _acquireAdmission(
          owner: owner,
          binding: binding,
          handler: handler,
        );
        if (admission == null) return _remainedUnregistered(owner);
        return _sameAdmission(admission, liveAdmission);
      },
    );

    return (eventId, value) {
      if (!targetLease.invoke(() {
        runZoned<void>(
          () => invokeWithOwner(() => handler(eventId, value)),
          zoneValues: <Object, Object?>{_dispatchLeaseKey: lease},
        );
      })) {
        _refuseControllerEvent();
      }
    };
  }

  static void runControllerEvent({
    required Object controller,
    required void Function() body,
  }) {
    final lease = Zone.current[_dispatchLeaseKey];
    if (lease is! _RestageFlowEventDispatchLease) {
      body();
      return;
    }
    if (!_isDispatchLeaseCurrent(lease)) {
      _refuseControllerEvent();
      return;
    }
    final liveAdmission = _acquireAdmission(
      owner: lease.owner,
      binding: lease.binding,
      handler: lease.handler,
    );
    final capturedAdmission = lease.admission;
    if (capturedAdmission != null) {
      if (!identical(capturedAdmission.controller, controller) ||
          !_sameAdmission(capturedAdmission, liveAdmission)) {
        _refuseControllerEvent();
        return;
      }
    } else if (_registeredControllers[controller] == true) {
      if (liveAdmission == null ||
          !identical(liveAdmission.controller, controller)) {
        _refuseControllerEvent();
        return;
      }
    } else {
      if (liveAdmission != null) {
        _refuseControllerEvent();
        return;
      }
      body();
      return;
    }
    body();
  }

  static T runWithControllerEventRefusal<T>({
    required T Function() body,
    required void Function() onRefused,
  }) =>
      runZoned<T>(
        body,
        zoneValues: <Object, Object?>{_dispatchRefusalKey: onRefused},
      );

  static void _refuseControllerEvent() {
    final onRefused = Zone.current[_dispatchRefusalKey];
    if (onRefused is void Function()) onRefused();
  }

  static _RestageFlowRenderEventAdmission? _acquireAdmission({
    required Object owner,
    required RestageFlowEventDispatchBinding? binding,
    required void Function(String, Object?) handler,
  }) {
    if (binding != null) {
      return _acquireBindingAdmission(
        owner: owner,
        binding: binding,
        handler: handler,
      );
    }

    final ownerControllers = _owners[owner];
    late final Object controller;
    late final List<_RestageFlowEventHandlerAssociationEvidence>
        handlerAssociations;

    if (ownerControllers != null && ownerControllers.isNotEmpty) {
      final currentControllers = <Object>[
        for (final entry in ownerControllers.entries)
          if (_hasCurrentRegistration(entry.value)) entry.key,
      ];
      if (currentControllers.length != 1) return null;
      controller = currentControllers.single;
      final current = _currentContent(controller);
      if (current == null) return null;
      handlerAssociations = _ownerHandlerAssociations(
        owner: owner,
        controller: controller,
        handler: handler,
        contentToken: current.contentToken,
      );
      if (handlerAssociations.isEmpty) return null;
    } else {
      if (!_remainedUnregistered(owner)) return null;
      final matches = <({
        Object controller,
        Object sourceOwner,
        Object registration,
      })>[];
      final associatedControllers = HashSet<Object>.identity();
      for (final ownerEntry in _owners.entries) {
        final controllers = ownerEntry.value;
        for (final entry in controllers.entries) {
          for (final registrationEntry in entry.value.entries) {
            final registration = registrationEntry.value;
            if (registration.associatedHandler == handler &&
                registration.contentToken != null &&
                _isCurrent(registration)) {
              associatedControllers.add(entry.key);
              matches.add((
                controller: entry.key,
                sourceOwner: ownerEntry.key,
                registration: registrationEntry.key,
              ));
            }
          }
        }
      }
      if (associatedControllers.length != 1) return null;
      controller = associatedControllers.single;
      final current = _currentContent(controller);
      if (current == null) return null;
      handlerAssociations = <_RestageFlowEventHandlerAssociationEvidence>[
        for (final match in matches)
          if (identical(match.controller, controller) &&
              current.registrations.any(
                (registration) => identical(registration, match.registration),
              ))
            _RestageFlowEventHandlerAssociationEvidence(
              owner: owner,
              sourceOwner: match.sourceOwner,
              identity: match.registration,
              handler: handler,
              kind: _RestageFlowEventHandlerAssociationKind.crossOwner,
            ),
      ];
      if (handlerAssociations.isEmpty) return null;
    }

    final current = _currentContent(controller);
    if (current == null) return null;
    return _RestageFlowRenderEventAdmission(
      controller: controller,
      contentToken: current.contentToken,
      contentRevision: current.contentRevision,
      registrations: current.registrations,
      callbacks: current.callbacks,
      exactRegistration: null,
      exactOwner: null,
      handlerAssociations: handlerAssociations,
    );
  }

  static _RestageFlowRenderEventAdmission? _acquireBindingAdmission({
    required Object owner,
    required RestageFlowEventDispatchBinding binding,
    required void Function(String, Object?) handler,
  }) {
    final exactMatch = _uniqueExactRegistration(binding);
    if (exactMatch == null) return null;
    final exact = exactMatch.registration;
    if (!_isCurrent(exact) || exact.contentToken == null) return null;

    final exactOwner = exactMatch.owner;
    final ownsRegistration = identical(owner, exactOwner);
    if (!ownsRegistration && !_remainedUnregistered(owner)) return null;

    final current = _currentContent(binding.controller);
    if (current == null || current.contentToken != exact.contentToken) {
      return null;
    }
    List<_RestageFlowEventHandlerAssociationEvidence> handlerAssociations;
    if (ownsRegistration) {
      handlerAssociations = <_RestageFlowEventHandlerAssociationEvidence>[
        if (exact.associatedHandler == handler)
          _RestageFlowEventHandlerAssociationEvidence(
            owner: owner,
            sourceOwner: exactOwner,
            identity: binding.registration,
            handler: handler,
            kind: _RestageFlowEventHandlerAssociationKind.registration,
          ),
        ..._explicitHandlerAssociations(
          owner: owner,
          controller: binding.controller,
          handler: handler,
        ),
      ];
    } else {
      if (exact.associatedHandler != handler) return null;
      handlerAssociations = <_RestageFlowEventHandlerAssociationEvidence>[
        _RestageFlowEventHandlerAssociationEvidence(
          owner: owner,
          sourceOwner: exactOwner,
          identity: binding.registration,
          handler: handler,
          kind: _RestageFlowEventHandlerAssociationKind.crossOwner,
        ),
      ];
    }
    if (handlerAssociations.isEmpty) return null;
    return _RestageFlowRenderEventAdmission(
      controller: binding.controller,
      contentToken: current.contentToken,
      contentRevision: current.contentRevision,
      registrations: <Object>[binding.registration],
      callbacks: current.callbacks,
      exactRegistration: binding.registration,
      exactOwner: exactOwner,
      handlerAssociations: handlerAssociations,
    );
  }

  static List<_RestageFlowEventHandlerAssociationEvidence>
      _ownerHandlerAssociations({
    required Object owner,
    required Object controller,
    required void Function(String, Object?) handler,
    required Object contentToken,
  }) {
    return <_RestageFlowEventHandlerAssociationEvidence>[
      for (final entry in _owners[owner]?[controller]?.entries ??
          <MapEntry<Object, _RestageFlowEventDispatchRegistration>>[])
        if (entry.value.associatedHandler == handler &&
            entry.value.contentToken == contentToken &&
            _isCurrent(entry.value))
          _RestageFlowEventHandlerAssociationEvidence(
            owner: owner,
            sourceOwner: owner,
            identity: entry.key,
            handler: handler,
            kind: _RestageFlowEventHandlerAssociationKind.registration,
          ),
      ..._explicitHandlerAssociations(
        owner: owner,
        controller: controller,
        handler: handler,
      ),
    ];
  }

  static List<_RestageFlowEventHandlerAssociationEvidence>
      _explicitHandlerAssociations({
    required Object owner,
    required Object controller,
    required void Function(String, Object?) handler,
  }) {
    return <_RestageFlowEventHandlerAssociationEvidence>[
      for (final entry in _handlerAssociations[owner]?.entries ??
          <MapEntry<Object, _RestageFlowEventHandlerAssociation>>[])
        if (identical(entry.value.controller, controller) &&
            entry.value.handler == handler &&
            _isHandlerAssociationCurrent(entry.value))
          _RestageFlowEventHandlerAssociationEvidence(
            owner: owner,
            sourceOwner: owner,
            identity: entry.key,
            handler: handler,
            kind: _RestageFlowEventHandlerAssociationKind.explicit,
          ),
    ];
  }

  static _RestageFlowExactRegistration? _uniqueExactRegistration(
    RestageFlowEventDispatchBinding binding,
  ) {
    _RestageFlowExactRegistration? match;
    for (final ownerEntry in _owners.entries) {
      final registration =
          ownerEntry.value[binding.controller]?[binding.registration];
      if (registration == null) continue;
      if (match != null) return null;
      match = _RestageFlowExactRegistration(
        owner: ownerEntry.key,
        registration: registration,
      );
    }
    return match;
  }

  static _RestageFlowCurrentContent? _currentContent(Object controller) {
    Object? contentToken;
    final registrations = <Object>[];
    final callbacks = <bool Function()>[];
    for (final controllers in _owners.values) {
      final registered = controllers[controller];
      if (registered == null) continue;
      for (final entry in registered.entries) {
        final registration = entry.value;
        if (!_isCurrent(registration) || registration.contentToken == null) {
          continue;
        }
        if (contentToken != null && contentToken != registration.contentToken) {
          _contentStates.remove(controller);
          return null;
        }
        contentToken = registration.contentToken;
        registrations.add(entry.key);
      }
    }
    if (contentToken == null || registrations.isEmpty) {
      _contentStates.remove(controller);
      return null;
    }
    final previous = _contentStates[controller];
    final state = previous != null && previous.contentToken == contentToken
        ? previous
        : _RestageFlowContentState(
            contentToken: contentToken,
            contentRevision: Object(),
          );
    _contentStates[controller] = state;
    return _RestageFlowCurrentContent(
      contentToken: contentToken,
      contentRevision: state.contentRevision,
      registrations: registrations,
      callbacks: callbacks,
    );
  }

  static void _refreshCurrentContent(Object controller) {
    _currentContent(controller);
  }

  static bool _hasCurrentRegistration(
    Map<Object, _RestageFlowEventDispatchRegistration> registrations,
  ) =>
      registrations.values.any(
        (registration) =>
            registration.contentToken != null && _isCurrent(registration),
      );

  static bool _sameAdmission(
    _RestageFlowRenderEventAdmission expected,
    _RestageFlowRenderEventAdmission? actual,
  ) {
    if (actual == null ||
        !identical(expected.controller, actual.controller) ||
        expected.contentToken != actual.contentToken ||
        !identical(expected.contentRevision, actual.contentRevision) ||
        !identical(expected.exactRegistration, actual.exactRegistration) ||
        !identical(expected.exactOwner, actual.exactOwner) ||
        expected.registrations.length != actual.registrations.length ||
        expected.handlerAssociations.length !=
            actual.handlerAssociations.length) {
      return false;
    }
    for (final registration in expected.registrations) {
      if (!actual.registrations.any(
        (candidate) => identical(candidate, registration),
      )) {
        return false;
      }
    }
    for (final association in expected.handlerAssociations) {
      if (!actual.handlerAssociations.any(association.matches)) return false;
    }
    return true;
  }

  static bool _isCurrent(
    _RestageFlowEventDispatchRegistration registration,
  ) {
    try {
      return registration.isCurrent?.call() ?? false;
    } on Object {
      return false;
    }
  }

  static bool _isHandlerAssociationCurrent(
    _RestageFlowEventHandlerAssociation association,
  ) {
    try {
      return association.isCurrent();
    } on Object {
      return false;
    }
  }

  static bool _isDispatchLeaseCurrent(
    _RestageFlowEventDispatchLease lease,
  ) {
    try {
      return lease.dispatcherIsActive() && lease.handlerIsCurrent();
    } on Object {
      return false;
    }
  }

  static bool _remainedUnregistered(Object owner) =>
      _registeredOwners[owner] != true &&
      !(_owners[owner]?.isNotEmpty ?? false);
}

final class _RestageFlowEventDispatchLease {
  const _RestageFlowEventDispatchLease({
    required this.owner,
    required this.binding,
    required this.handler,
    required this.admission,
    required this.dispatcherIsActive,
    required this.handlerIsCurrent,
  });

  final Object owner;
  final RestageFlowEventDispatchBinding? binding;
  final void Function(String, Object?) handler;
  final _RestageFlowRenderEventAdmission? admission;
  final bool Function() dispatcherIsActive;
  final bool Function() handlerIsCurrent;
}

final class _RestageFlowEventDispatchRegistration {
  const _RestageFlowEventDispatchRegistration({
    required this.contentToken,
    required this.isCurrent,
    required this.associatedHandler,
  });

  final Object? contentToken;
  final bool Function()? isCurrent;
  final void Function(String, Object?)? associatedHandler;
}

final class _RestageFlowEventHandlerAssociation {
  const _RestageFlowEventHandlerAssociation({
    required this.controller,
    required this.handler,
    required this.isCurrent,
  });

  final Object controller;
  final void Function(String, Object?) handler;
  final bool Function() isCurrent;
}

final class _RestageFlowCurrentContent {
  const _RestageFlowCurrentContent({
    required this.contentToken,
    required this.contentRevision,
    required this.registrations,
    required this.callbacks,
  });

  final Object contentToken;
  final Object contentRevision;
  final List<Object> registrations;
  final List<bool Function()> callbacks;
}

final class _RestageFlowRenderEventAdmission {
  const _RestageFlowRenderEventAdmission({
    required this.controller,
    required this.contentToken,
    required this.contentRevision,
    required this.registrations,
    required this.callbacks,
    required this.exactRegistration,
    required this.exactOwner,
    required this.handlerAssociations,
  });

  final Object controller;
  final Object contentToken;
  final Object contentRevision;
  final List<Object> registrations;
  final List<bool Function()> callbacks;
  final Object? exactRegistration;
  final Object? exactOwner;
  final List<_RestageFlowEventHandlerAssociationEvidence> handlerAssociations;
}

enum _RestageFlowEventHandlerAssociationKind {
  registration,
  crossOwner,
  explicit,
}

final class _RestageFlowEventHandlerAssociationEvidence {
  const _RestageFlowEventHandlerAssociationEvidence({
    required this.owner,
    required this.sourceOwner,
    required this.identity,
    required this.handler,
    required this.kind,
  });

  final Object owner;
  final Object sourceOwner;
  final Object identity;
  final void Function(String, Object?) handler;
  final _RestageFlowEventHandlerAssociationKind kind;

  bool matches(_RestageFlowEventHandlerAssociationEvidence other) =>
      identical(owner, other.owner) &&
      identical(sourceOwner, other.sourceOwner) &&
      identical(identity, other.identity) &&
      handler == other.handler &&
      kind == other.kind;
}

final class _RestageFlowExactRegistration {
  const _RestageFlowExactRegistration({
    required this.owner,
    required this.registration,
  });

  final Object owner;
  final _RestageFlowEventDispatchRegistration registration;
}

final class _RestageFlowContentState {
  const _RestageFlowContentState({
    required this.contentToken,
    required this.contentRevision,
  });

  final Object contentToken;
  final Object contentRevision;
}
