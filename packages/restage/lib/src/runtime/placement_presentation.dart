import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

import 'placement_mount.dart';
import 'placement_registry.dart';
import 'placement_discovery.dart';

/// Owns the one route opened to present a placement mount.
final class PlacementPresentationController {
  PlacementPresentationController._(this._lease);
  final _PlacementRouteLease _lease;

  /// Closes only the route created for this presentation.
  void close() {
    final navigator = _lease.navigator;
    final route = _lease.route;
    if (!_lease.active ||
        navigator == null ||
        route == null ||
        !route.isActive) {
      return;
    }
    _lease.active = false;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }
}

/// Opens an ordinary route and grants presentation ownership to its root mount.
@internal
Future<void> presentPlacement(BuildContext context,
    {required Widget Function(
            BuildContext context, PlacementPresentationController presentation)
        builder}) async {
  final navigator = Navigator.of(context);
  final lease = _PlacementRouteLease()..navigator = navigator;
  final controller = PlacementPresentationController._(lease);
  final route = MaterialPageRoute<void>(builder: (routeContext) {
    final mount = lease.mount ??= builder(routeContext, controller);
    return _PlacementPresentationScope(lease: lease, child: mount);
  });
  lease.route = route;
  try {
    await navigator.push(route);
  } finally {
    lease.active = false;
  }
}

final _hostPresentationCurrency = Expando<bool Function()>();

@internal
bool placementHostIsCurrent(SurfaceHostContractV1 host) =>
    _hostPresentationCurrency[host]?.call() ?? true;

/// Keeps a host's declaration and local registration on the same mount lease.
@internal
final class PlacementHostDiscovery {
  PlacementHostDiscovery({
    required this.configurationGeneration,
    required this.discovery,
  });

  final int Function() configurationGeneration;
  final PlacementDiscovery? Function() discovery;
  PlacementMountBinding? _binding;
  PlacementDeclaration? _declaration;
  PlacementDiscoveryRegistration? _registration;
  int _generation = -1;

  PlacementDeclaration? get declaration => _declaration;

  PlacementDeclaration? capture(
      PlacementMountBinding? binding, Widget host, BuildContext context) {
    if (binding == null) {
      dispose();
      return null;
    }
    final generation = configurationGeneration();
    if (!binding.sameDeclarationAs(_binding) || _generation != generation) {
      dispose();
      _binding = binding;
      _generation = generation;
      final declaration = capturePlacementDeclaration(binding, host, context);
      _declaration = declaration;
      _registration = discovery()?.register(
        context: context,
        mount: declaration.mount,
        hostContract: declaration.host,
        isCurrent: () =>
            _generation == configurationGeneration() &&
            (_binding?.sameDeclarationAs(binding) ?? false) &&
            placementHostIsCurrent(declaration.host),
      );
    }
    return _declaration;
  }

  void markPainted() => _registration?.markPainted();

  void dispose() {
    _registration?.dispose();
    _registration = null;
    _binding = null;
    _declaration = null;
  }
}

final class _PlacementRouteLease {
  NavigatorState? navigator;
  Route<void>? route;
  Widget? mount;
  Element? rootHost;
  bool active = true;
}

final class _PlacementPresentationScope extends InheritedWidget {
  const _PlacementPresentationScope(
      {required this.lease, required super.child});
  final _PlacementRouteLease lease;
  @override
  bool updateShouldNotify(_PlacementPresentationScope oldWidget) => false;
}

/// Captures route ownership before any asynchronous input or request work.
@internal
PlacementDeclaration capturePlacementDeclaration(
    PlacementMountBinding binding, Widget host, BuildContext context) {
  final captured = binding.capture();
  final scope =
      context.getInheritedWidgetOfExactType<_PlacementPresentationScope>();
  var isRoot = false;
  if (scope != null && scope.lease.active) {
    isRoot = identical(host, scope.lease.mount);
    if (!isRoot) {
      context.visitAncestorElements((element) {
        if (identical(element.widget, scope.lease.mount)) {
          isRoot = true;
          return false;
        }
        if (element.widget is RestagePlacementMount) {
          return false;
        }
        return true;
      });
    }
    if (isRoot) {
      final element = context as Element;
      scope.lease.rootHost ??= element;
      isRoot = identical(scope.lease.rootHost, element);
    }
  }
  final original = captured.host;
  final hostContract = SurfaceHostContractV1(
      hosting: SurfaceHostingV1(
          contentKind: original.hosting.contentKind,
          presentation: isRoot
              ? SurfacePresentationV1.presented
              : SurfacePresentationV1.inline),
      providedContext: original.providedContext,
      handledEvents: original.handledEvents,
      flowBoundary: original.flowBoundary);
  _hostPresentationCurrency[hostContract] = () =>
      context.mounted &&
      context.widget is RestagePlacementMount &&
      ((context.widget as RestagePlacementMount)
              .placementBinding
              ?.sameDeclarationAs(binding) ??
          false) &&
      (!isRoot ||
          (scope!.lease.active && identical(scope.lease.rootHost, context)));
  return (
    mount: PlacementMountRequestV1(
        key: captured.mount.key,
        hostContractHash: hostContract.contentHash,
        defaultSurface: captured.mount.defaultSurface,
        surfaceType: captured.mount.surfaceType),
    host: hostContract
  );
}
