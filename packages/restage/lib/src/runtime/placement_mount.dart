import 'package:flutter/widgets.dart' show Widget;
import 'package:meta/meta.dart' show internal;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show DeliveryFamilySelectorV1, DeliverySurfaceTypeId, PlacementKeyV1;
import 'package:restage_shared/restage_shared.dart'
    show
        DeliverySurfaceLocatorV1,
        PlacementMountRequestV1,
        Surface,
        SurfaceHostContractV1;

import '../flow/flow_descriptors.dart';
import '../surface_screen/surface_screen_runtime_provenance.dart';
import 'surface_vocabulary.dart';

/// The default surface and immutable host facts of a generated mount.
final class GeneratedPlacementDefinition implements RestageSurfaceRef {
  /// Creates a definition that agrees with its exact generated reference.
  GeneratedPlacementDefinition({
    required this.defaultSurface,
    required this.defaultSurfaceLocator,
    required this.key,
    required SurfaceHostContractV1 hostContract,
    required this.vocabulary,
  })  : _hostContract = hostContract,
        _hostContractJson = null {
    _check();
  }

  GeneratedPlacementDefinition._decoding({
    required this.defaultSurface,
    required this.defaultSurfaceLocator,
    required this.key,
    required Map<String, Object?> hostContractJson,
    required this.vocabulary,
  }) : _hostContractJson = hostContractJson {
    _check();
  }

  void _check() {
    final (surfaceType, slug, family) = switch (defaultSurface) {
      PaywallRef(:final id) => (
          DeliverySurfaceTypeId(Surface.paywall.wireName),
          id,
          const DeliveryFamilySelectorV1.general(),
        ),
      SurfaceScreenRef<Object?>(
        :final surface,
        :final slug,
        :final contractVersion
      ) =>
        (
          DeliverySurfaceTypeId(surface.wireName),
          slug,
          DeliveryFamilySelectorV1.screenContract(
            contractVersion: contractVersion,
          ),
        ),
      SurfaceFlowRef<Object?>(:final surface, :final id) => (
          DeliverySurfaceTypeId(surface.wireName),
          id,
          const DeliveryFamilySelectorV1.general(),
        ),
      _ => throw ArgumentError.value(defaultSurface, 'defaultSurface'),
    };
    if (defaultSurfaceLocator.surfaceType != surfaceType ||
        defaultSurfaceLocator.slug != slug ||
        defaultSurfaceLocator.family != family) {
      throw ArgumentError.value(defaultSurfaceLocator, 'defaultSurfaceLocator');
    }
    if (key !=
        PlacementKeyV1.generatedDefault(surfaceType: surfaceType, slug: slug)) {
      throw ArgumentError.value(key, 'key');
    }
  }

  /// Decodes the compiler's static facts and derives its namespaced default key.
  factory GeneratedPlacementDefinition.generated({
    required RestageSurfaceRef defaultSurface,
    required Map<String, Object?> defaultSurfaceLocatorJson,
    required Map<String, Object?> hostContractJson,
    required SurfaceVocabulary vocabulary,
  }) {
    final locator =
        DeliverySurfaceLocatorV1.fromJson(defaultSurfaceLocatorJson);
    return GeneratedPlacementDefinition._decoding(
      defaultSurface: defaultSurface,
      defaultSurfaceLocator: locator,
      key: PlacementKeyV1.generatedDefault(
        surfaceType: locator.surfaceType,
        slug: locator.slug,
      ),
      hostContractJson: hostContractJson,
      vocabulary: vocabulary,
    );
  }

  /// The original generated reference, retaining its decoder and fallback.
  final RestageSurfaceRef defaultSurface;

  /// The target-free default surface with its exact delivery family.
  final DeliverySurfaceLocatorV1 defaultSurfaceLocator;

  /// The default placement coordinate, namespaced by surface category.
  final PlacementKeyV1 key;

  /// The host's statically declared input and output boundary, decoded
  /// from the generated facts when first read.
  SurfaceHostContractV1 get hostContract =>
      _hostContract ??= SurfaceHostContractV1.fromJson(_hostContractJson!);
  SurfaceHostContractV1? _hostContract;
  final Map<String, Object?>? _hostContractJson;

  /// The generated host facts not decoded yet, if any.
  @internal
  Map<String, Object?>? get undecodedHostContract =>
      _hostContract == null ? _hostContractJson : null;

  /// Takes [contract], decoded elsewhere from [undecodedHostContract].
  @internal
  void adoptHostContract(SurfaceHostContractV1 contract) =>
      _hostContract ??= contract;

  /// The default screen's provenance while its schemas are not decoded yet.
  @internal
  SurfaceScreenRuntimeProvenance? get undecodedScreen =>
      switch (defaultSurface) {
        SurfaceScreenRef<Object?>(:final provenance)
            when provenance.undecodedContract != null =>
          provenance,
        _ => null,
      };

  /// Widgets and icons the compiled default draws.
  final SurfaceVocabulary vocabulary;
}

/// The placement declaration consumed by the existing surface host.
final class PlacementMountBinding {
  /// Creates a binding using a typed generated definition provider.
  const PlacementMountBinding(
      {required GeneratedPlacementDefinition Function() definition, this.name})
      : _definition = definition,
        _mount = null,
        _host = null;

  /// Carries an explicitly declared mount without inventing generated facts.
  @internal
  const PlacementMountBinding.request(
      {required PlacementMountRequestV1 mount,
      required SurfaceHostContractV1 hostContract})
      : _mount = mount,
        _host = hostContract,
        _definition = null,
        name = null;

  final GeneratedPlacementDefinition Function()? _definition;
  final PlacementMountRequestV1? _mount;
  final SurfaceHostContractV1? _host;

  /// Supplies the original surface and its immutable host contract.
  GeneratedPlacementDefinition Function() get definition =>
      _definition ?? (throw StateError('This mount has an explicit contract.'));

  /// An explicit named placement, or null for the generated default.
  final String? name;

  @internal
  bool get isExplicit => _mount != null;

  /// The surface category an explicit mount declares, if any.
  @internal
  Surface? get declaredSurface {
    final mount = _mount;
    final type = mount?.surfaceType ?? mount?.defaultSurface?.surfaceType;
    for (final surface in Surface.values) {
      if (surface.wireName == type?.value) return surface;
    }
    return null;
  }

  /// Compares the declaration provider and placement name, or explicit facts.
  @internal
  bool sameDeclarationAs(PlacementMountBinding? other) =>
      other != null &&
      _definition == other._definition &&
      name == other.name &&
      _mount == other._mount &&
      _host == other._host;

  /// Captures generated or explicit facts once for a mounted host.
  @internal
  ({PlacementMountRequestV1 mount, SurfaceHostContractV1 host}) capture() {
    final explicit = _mount;
    if (explicit != null) return (mount: explicit, host: _host!);
    final generated = definition();
    generated.vocabulary.addToInstalled();
    return (
      mount: PlacementMountRequestV1(
        key: name == null ? generated.key : PlacementKeyV1.named(slug: name!),
        hostContractHash: generated.hostContract.contentHash,
        defaultSurface: generated.defaultSurfaceLocator,
      ),
      host: generated.hostContract
    );
  }
}

/// An SDK host exposing its optional generated placement binding.
abstract interface class RestagePlacementMount implements Widget {
  /// The default definition and any explicit product placement name.
  PlacementMountBinding? get placementBinding;
}

/// Narrows a candidate's proven presentation modes.
enum SurfacePresentationRequirement {
  /// Infer modes from the complete compiled rendering closure.
  infer,

  /// Require an in-tree host owned by the application.
  inline,

  /// Require a presented route owned by the SDK.
  presented,
}
