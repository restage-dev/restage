import 'dart:typed_data';

import 'package:restage_codegen/src/measurement/measurement_rfw_presentation_discovery.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;

/// SDK-local RFW namespace that owns the presentation bridge.
const List<String> _measurementPresentationRfwLibraryPartsV1 = <String>[
  'restage',
  'measurement',
];

/// RFW constructor inserted around an event-owning widget occurrence.
const String _measurementPresentedConstructorV1 = 'MeasurementPresented';

/// RFW constructor inserted around a source-event-owning widget occurrence.
const String _measurementSourcePresentedConstructorV1 =
    'MeasurementSourcePresented';

/// Presentation wrapper argument containing exact final route carriers.
const String _measurementPresentedCarriersArgumentV1 = 'carriers';

/// Presentation wrapper argument containing compact point tokens.
const String _measurementPresentedPointTokensArgumentV1 = 'pointTokens';

/// Presentation wrapper argument retaining the original widget.
const String _measurementPresentedChildArgumentV1 = 'child';

/// Result of replacing transient compiler markers in one RFW library.
final class MeasurementRfwRouteComposition {
  /// Creates a composed RFW artifact result.
  MeasurementRfwRouteComposition({
    required List<int> blob,
    required Set<String> generatedReferences,
    Set<String> generatedPresentationReferences = const <String>{},
  })  : blob = Uint8List.fromList(blob),
        generatedReferences = Set.unmodifiable(generatedReferences),
        generatedPresentationReferences = Set.unmodifiable(
          generatedPresentationReferences,
        );

  /// Final encoded RFW blob containing strict route carriers.
  final Uint8List blob;

  /// Generated references whose markers were consumed in this blob.
  final Set<String> generatedReferences;

  /// Generated presentation references whose markers were consumed in this
  /// blob.
  final Set<String> generatedPresentationReferences;
}

/// Replaces compiler-only event markers with the frozen route carrier.
///
/// This is the package-publication boundary: route carriers are present before
/// artifact hashes, capability sidecars, manifests, and candidate bytes are
/// assembled. The transformation operates on explicit generated-reference
/// markers in the decoded RFW model; it never searches event names, labels,
/// source paths, Flutter keys, or ordinals.
abstract final class MeasurementRfwRouteComposer {
  /// Composes one blob and records every generated reference it consumed.
  static MeasurementRfwRouteComposition composeBlob({
    required List<int> blob,
    required MeasurementPublicationRoutePlanV1 routePlan,
  }) {
    if (routePlan.presentationRoutes.isNotEmpty) {
      throw const FormatException(
        'Presentation routes require an exact parsed RFW materialization',
      );
    }
    final library = fmt.decodeLibraryBlob(Uint8List.fromList(blob));
    return _composeLibrary(
      library: library,
      routePlan: routePlan,
      presentationMaterialization: null,
    );
  }

  /// Composes one exact parsed RFW library with its presentation witnesses.
  ///
  /// The materialization retains object-identity joins to this library, so the
  /// composer never reconstructs a call from source text, a path, or an
  /// ordinal.
  static MeasurementRfwRouteComposition composeMaterializedLibrary({
    required MeasurementPublicationRoutePlanV1 routePlan,
    required MeasurementRfwPresentationArtifactMaterialization
        presentationMaterialization,
  }) {
    if (presentationMaterialization.joins.any(
      (join) =>
          join.routeDraftClosureDigest != routePlan.routeDraftClosureDigest,
    )) {
      throw const FormatException(
        'Presentation materialization belongs to another route closure',
      );
    }
    return _composeLibrary(
      library: presentationMaterialization.finalLibrary,
      routePlan: routePlan,
      presentationMaterialization: presentationMaterialization,
    );
  }

  static MeasurementRfwRouteComposition _composeLibrary({
    required fmt.RemoteWidgetLibrary library,
    required MeasurementPublicationRoutePlanV1 routePlan,
    required MeasurementRfwPresentationArtifactMaterialization?
        presentationMaterialization,
  }) {
    final routes = {
      for (final route in routePlan.routes)
        route.generatedReferenceId.value: route,
    };
    final presentationRoutes = {
      for (final route in routePlan.presentationRoutes)
        route.generatedPresentationReferenceId.value: route,
    };
    final consumed = <String>{};
    final consumedPresentations = <String>{};
    final presentationRoutesByCall = Map<fmt.ConstructorCall,
        MeasurementPublicationDraftPresentationRouteV1>.identity();
    if (presentationMaterialization != null) {
      for (final join in presentationMaterialization.joins) {
        if (presentationRoutesByCall.putIfAbsent(
              join.constructorCall,
              () => join.presentationRoute,
            ) !=
            join.presentationRoute) {
          throw const FormatException(
            'One RFW constructor has multiple presentation witnesses',
          );
        }
      }
    }
    final presentation = _PresentationRewriteTracker(
      presentationRoutesByCall: presentationRoutesByCall,
    );
    final rewritten = _rewriteLibrary(
      library,
      routes,
      presentationRoutes,
      consumed,
      consumedPresentations,
      presentation,
    );
    return MeasurementRfwRouteComposition(
      blob: fmt.encodeLibraryBlob(rewritten),
      generatedReferences: consumed,
      generatedPresentationReferences: consumedPresentations,
    );
  }

  /// Rewrites the matching transient markers in an RFW text artifact.
  ///
  /// The text artifact is an inspection companion to the binary blob. It is
  /// rewritten by exact marker spelling rather than by line/ordinal position.
  static String composeText({
    required String text,
    required MeasurementPublicationRoutePlanV1 routePlan,
    Set<String>? generatedReferences,
  }) {
    final references = generatedReferences ??
        {
          for (final route in routePlan.routes)
            route.generatedReferenceId.value,
        };
    var result = text;
    for (final route in routePlan.routes) {
      if (!references.contains(route.generatedReferenceId.value)) continue;
      final marker = MeasurementRouteEmissionPlan.markerForGeneratedReference(
        route.generatedReferenceId,
      );
      final needle = '$kMeasurementRouteReferenceMarkerKeyV1: '
          '${_quote(marker)}';
      final replacement = '$kMeasurementRouteArgumentKeyV1: '
          '${_quote(route.carrier)}';
      final occurrences = _occurrences(result, needle);
      if (occurrences != 1) {
        throw FormatException(
          'Expected exactly one RFW text marker for generated reference '
          '${route.generatedReferenceId.value}; found $occurrences',
        );
      }
      result = result.replaceFirst(needle, replacement);
    }
    if (result.contains(kMeasurementRouteReferenceMarkerKeyV1) ||
        result.contains(kMeasurementRouteReferenceMarkerPrefixV1)) {
      throw const FormatException(
        'RFW text retained an unresolved Measurement route marker',
      );
    }
    return result;
  }

  /// Removes compiler-only markers from an inspection text artifact.
  ///
  /// Inspection text is not delivered and cannot carry a publication-specific
  /// route when one source template participates in more than one publication.
  /// The final binary artifacts remain the carrier authority.
  static String stripTransientMarkersFromText(String text) {
    final result = _stripTextMarker(
      text,
      key: kMeasurementRouteReferenceMarkerKeyV1,
      prefix: kMeasurementRouteReferenceMarkerPrefixV1,
    );
    if (result.contains(kMeasurementRouteReferenceMarkerKeyV1) ||
        result.contains(kMeasurementRouteReferenceMarkerPrefixV1)) {
      throw const FormatException(
        'RFW inspection text retained an unresolved Measurement marker',
      );
    }
    return result;
  }

  static String _stripTextMarker(
    String text, {
    required String key,
    required String prefix,
  }) {
    final marker = RegExp(
      '${RegExp.escape(key)}: "${RegExp.escape(prefix)}[^"]+"',
    );
    var result = text.replaceAll(RegExp(',\\s*${marker.pattern}'), '');
    result = result.replaceAll(RegExp('${marker.pattern}\\s*,\\s*'), '');
    return result.replaceAll(marker, '');
  }

  /// Requires every eligible draft route to have exactly one emitted marker.
  static void requireCompleteRouteClosure({
    required MeasurementPublicationRoutePlanV1 routePlan,
    required Set<String> consumedReferences,
  }) {
    final required = {
      for (final route in routePlan.routes) route.generatedReferenceId.value,
    };
    if (required.length != consumedReferences.length ||
        !required.containsAll(consumedReferences) ||
        !consumedReferences.containsAll(required)) {
      final missing = required.difference(consumedReferences).toList()..sort();
      final unexpected = consumedReferences.difference(required).toList()
        ..sort();
      throw FormatException(
        'Measurement route marker closure disagrees with the publication '
        'route plan (missing: $missing, unexpected: $unexpected)',
      );
    }
  }

  /// Requires every presentation route to have exactly one widget marker.
  static void requireCompletePresentationRouteClosure({
    required MeasurementPublicationRoutePlanV1 routePlan,
    required Set<String> consumedPresentationReferences,
  }) {
    final required = {
      for (final route in routePlan.presentationRoutes)
        route.generatedPresentationReferenceId.value,
    };
    if (required.length != consumedPresentationReferences.length ||
        !required.containsAll(consumedPresentationReferences) ||
        !consumedPresentationReferences.containsAll(required)) {
      final missing =
          required.difference(consumedPresentationReferences).toList()..sort();
      final unexpected =
          consumedPresentationReferences.difference(required).toList()..sort();
      throw FormatException(
        'Measurement presentation marker closure disagrees with the '
        'publication route plan (missing: $missing, unexpected: $unexpected)',
      );
    }
  }

  static fmt.RemoteWidgetLibrary _rewriteLibrary(
    fmt.RemoteWidgetLibrary library,
    Map<String, MeasurementPublicationDraftRouteV1> routes,
    Map<String, MeasurementPublicationDraftPresentationRouteV1>
        presentationRoutes,
    Set<String> consumed,
    Set<String> consumedPresentations,
    _PresentationRewriteTracker presentation,
  ) {
    final widgets = [
      for (final widget in library.widgets)
        fmt.WidgetDeclaration(
          widget.name,
          widget.initialState == null
              ? null
              : _rewriteMap(
                  widget.initialState!,
                  routes,
                  presentationRoutes,
                  consumed,
                  consumedPresentations,
                  presentation,
                ),
          _rewriteNode(
            widget.root,
            routes,
            presentationRoutes,
            consumed,
            consumedPresentations,
            presentation,
          ),
        ),
    ];
    if (!presentation.didWrap) {
      return fmt.RemoteWidgetLibrary(library.imports, widgets);
    }
    _rejectReservedPresentationLibraryImport(library);
    _rejectPresentationConstructorCollision(library);
    return fmt.RemoteWidgetLibrary(
      [
        const fmt.Import(
          fmt.LibraryName(_measurementPresentationRfwLibraryPartsV1),
        ),
        ...library.imports,
      ],
      widgets,
    );
  }

  static fmt.BlobNode _rewriteNode(
    fmt.BlobNode node,
    Map<String, MeasurementPublicationDraftRouteV1> routes,
    Map<String, MeasurementPublicationDraftPresentationRouteV1>
        presentationRoutesByReference,
    Set<String> consumed,
    Set<String> consumedPresentations,
    _PresentationRewriteTracker presentation,
  ) {
    switch (node) {
      case final fmt.ConstructorCall call:
        final arguments = _rewriteMap(
          call.arguments,
          routes,
          presentationRoutesByReference,
          consumed,
          consumedPresentations,
          presentation,
        );
        _rejectReservedConstructorArguments(arguments);
        final rewritten = fmt.ConstructorCall(
          call.name,
          arguments,
        );
        final directRoute = presentation.presentationRoutesByCall[call];
        final sourceRoutes = _directSourceRoutes(arguments);
        final presentationRoutes = _directPresentationRoutes(
          directRoute == null
              ? null
              : _presentationRouteForRoute(
                  directRoute,
                  consumedPresentations,
                ),
        );
        var wrapped = rewritten;
        if (sourceRoutes.isNotEmpty) {
          presentation.didWrap = true;
          wrapped = _presentationWrapper(
            constructorName: _measurementSourcePresentedConstructorV1,
            routes: sourceRoutes,
            child: wrapped,
          );
        }
        if (presentationRoutes.isNotEmpty) {
          presentation.didWrap = true;
          wrapped = _presentationWrapper(
            constructorName: _measurementPresentedConstructorV1,
            routes: presentationRoutes,
            child: wrapped,
          );
        }
        return wrapped;
      case final fmt.EventHandler event:
        return _rewriteEvent(
          event,
          routes,
          presentationRoutesByReference,
          consumed,
          consumedPresentations,
          presentation,
        );
      case final fmt.WidgetBuilderDeclaration builder:
        return fmt.WidgetBuilderDeclaration(
          builder.argumentName,
          _rewriteNode(
            builder.widget,
            routes,
            presentationRoutesByReference,
            consumed,
            consumedPresentations,
            presentation,
          ),
        );
      case final fmt.Loop loop:
        return fmt.Loop(
          _rewriteRequiredValue(
            loop.input,
            routes,
            presentationRoutesByReference,
            consumed,
            consumedPresentations,
            presentation,
          ),
          _rewriteRequiredValue(
            loop.output,
            routes,
            presentationRoutesByReference,
            consumed,
            consumedPresentations,
            presentation,
          ),
        );
      case final fmt.Switch switchNode:
        return fmt.Switch(
          _rewriteRequiredValue(
            switchNode.input,
            routes,
            presentationRoutesByReference,
            consumed,
            consumedPresentations,
            presentation,
          ),
          {
            for (final entry in switchNode.outputs.entries)
              entry.key: _rewriteRequiredValue(
                entry.value,
                routes,
                presentationRoutesByReference,
                consumed,
                consumedPresentations,
                presentation,
              ),
          },
        );
      default:
        return node;
    }
  }

  static Object _rewriteRequiredValue(
    Object value,
    Map<String, MeasurementPublicationDraftRouteV1> routes,
    Map<String, MeasurementPublicationDraftPresentationRouteV1>
        presentationRoutesByReference,
    Set<String> consumed,
    Set<String> consumedPresentations,
    _PresentationRewriteTracker presentation,
  ) =>
      _rewriteValue(
        value,
        routes,
        presentationRoutesByReference,
        consumed,
        consumedPresentations,
        presentation,
      ) ??
      (throw const FormatException('RFW route composition produced null'));

  static Object? _rewriteValue(
    Object? value,
    Map<String, MeasurementPublicationDraftRouteV1> routes,
    Map<String, MeasurementPublicationDraftPresentationRouteV1>
        presentationRoutesByReference,
    Set<String> consumed,
    Set<String> consumedPresentations,
    _PresentationRewriteTracker presentation,
  ) {
    if (value is fmt.BlobNode) {
      return _rewriteNode(
        value,
        routes,
        presentationRoutesByReference,
        consumed,
        consumedPresentations,
        presentation,
      );
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key: _rewriteValue(
            entry.value,
            routes,
            presentationRoutesByReference,
            consumed,
            consumedPresentations,
            presentation,
          ),
      };
    }
    if (value is List) {
      return [
        for (final item in value)
          _rewriteValue(
            item,
            routes,
            presentationRoutesByReference,
            consumed,
            consumedPresentations,
            presentation,
          ),
      ];
    }
    return value;
  }

  static fmt.DynamicMap _rewriteMap(
    fmt.DynamicMap value,
    Map<String, MeasurementPublicationDraftRouteV1> routes,
    Map<String, MeasurementPublicationDraftPresentationRouteV1>
        presentationRoutesByReference,
    Set<String> consumed,
    Set<String> consumedPresentations,
    _PresentationRewriteTracker presentation,
  ) =>
      <String, Object?>{
        for (final entry in value.entries)
          entry.key: _rewriteValue(
            entry.value,
            routes,
            presentationRoutesByReference,
            consumed,
            consumedPresentations,
            presentation,
          ),
      };

  static fmt.EventHandler _rewriteEvent(
    fmt.EventHandler event,
    Map<String, MeasurementPublicationDraftRouteV1> routes,
    Map<String, MeasurementPublicationDraftPresentationRouteV1>
        presentationRoutesByReference,
    Set<String> consumed,
    Set<String> consumedPresentations,
    _PresentationRewriteTracker presentation,
  ) {
    String? generatedReference;
    final businessArguments = <String, Object?>{};
    for (final entry in event.eventArguments.entries) {
      final key = entry.key;
      if (!key.startsWith(kMeasurementPublicationReservedArgumentPrefixV1)) {
        businessArguments[key] = _rewriteValue(
          entry.value,
          routes,
          presentationRoutesByReference,
          consumed,
          consumedPresentations,
          presentation,
        );
        continue;
      }
      final markerValue = entry.value;
      if (key != kMeasurementRouteReferenceMarkerKeyV1 ||
          markerValue is! String ||
          !markerValue.startsWith(kMeasurementRouteReferenceMarkerPrefixV1)) {
        throw FormatException(
          'RFW event ${event.eventName} contains an authored or malformed '
          'Measurement-reserved argument',
        );
      }
      if (generatedReference != null) {
        throw const FormatException(
          'RFW event contains duplicate Measurement route markers',
        );
      }
      generatedReference = markerValue
          .substring(kMeasurementRouteReferenceMarkerPrefixV1.length);
      if (generatedReference.isEmpty) {
        throw const FormatException(
          'RFW Measurement route marker has no generated reference',
        );
      }
    }

    if (generatedReference != null) {
      final route = routes[generatedReference];
      if (route == null) {
        throw FormatException(
          'RFW Measurement route marker names an unknown generated reference '
          '$generatedReference',
        );
      }
      if (!consumed.add(generatedReference)) {
        throw FormatException(
          'Generated reference $generatedReference appears in more than one '
          'emitted RFW event',
        );
      }
      businessArguments[kMeasurementRouteArgumentKeyV1] = route.carrier;
    }
    return fmt.EventHandler(event.eventName, businessArguments);
  }

  static void _rejectReservedConstructorArguments(fmt.DynamicMap arguments) {
    for (final key in arguments.keys) {
      if (key.startsWith(kMeasurementPublicationReservedArgumentPrefixV1)) {
        throw const FormatException(
          'RFW widget contains an authored Measurement-reserved argument',
        );
      }
    }
  }

  static _PresentationRoute _presentationRouteForRoute(
    MeasurementPublicationDraftPresentationRouteV1 route,
    Set<String> consumed,
  ) {
    final reference = route.generatedPresentationReferenceId.value;
    if (!consumed.add(reference)) {
      throw FormatException(
        'Generated presentation reference $reference appears in more than '
        'one emitted RFW widget',
      );
    }
    return _PresentationRoute(
      carrier: route.carrier,
      compactToken: MeasurementCompactPointTokenEmitter.fromRouteCarrier(
        route.carrier,
      ),
    );
  }

  static fmt.ConstructorCall _presentationWrapper({
    required String constructorName,
    required List<_PresentationRoute> routes,
    required fmt.ConstructorCall child,
  }) =>
      fmt.ConstructorCall(
        constructorName,
        <String, Object?>{
          _measurementPresentedCarriersArgumentV1: [
            for (final route in routes) route.carrier,
          ],
          _measurementPresentedPointTokensArgumentV1: [
            for (final route in routes) route.compactToken,
          ],
          _measurementPresentedChildArgumentV1: child,
        },
      );

  /// Presentation wrappers carry only exact synthetic presentation routes.
  static List<_PresentationRoute> _directPresentationRoutes(
    _PresentationRoute? directPresentationRoute,
  ) =>
      directPresentationRoute == null
          ? const <_PresentationRoute>[]
          : <_PresentationRoute>[directPresentationRoute];

  /// Source-event wrappers retain routes that record presence and counters.
  static List<_PresentationRoute> _directSourceRoutes(
    fmt.DynamicMap arguments,
  ) {
    final routesByCarrier = <String, _PresentationRoute>{};

    void visit(Object? value) {
      switch (value) {
        case final fmt.EventHandler handler:
          final carrier =
              handler.eventArguments[kMeasurementRouteArgumentKeyV1];
          if (carrier is String) {
            routesByCarrier[carrier] = _PresentationRoute(
              carrier: carrier,
              compactToken:
                  MeasurementCompactPointTokenEmitter.fromRouteCarrier(carrier),
            );
          }
        case fmt.ConstructorCall _:
        case fmt.WidgetBuilderDeclaration _:
        case fmt.Loop _:
        case fmt.Switch _:
          return;
        case final Map<Object?, Object?> map:
          map.values.forEach(visit);
        case final List<Object?> list:
          list.forEach(visit);
        default:
          return;
      }
    }

    arguments.values.forEach(visit);
    final sortedCarriers = routesByCarrier.keys.toList()..sort();
    return List<_PresentationRoute>.unmodifiable([
      for (final carrier in sortedCarriers) routesByCarrier[carrier]!,
    ]);
  }

  static void _rejectReservedPresentationLibraryImport(
    fmt.RemoteWidgetLibrary library,
  ) {
    if (library.imports.any(_isPresentationLibrary)) {
      throw const FormatException(
        'RFW artifact already imports the reserved Measurement presentation '
        'library',
      );
    }
  }

  static bool _isPresentationLibrary(fmt.Import value) =>
      value.name.parts.length ==
          _measurementPresentationRfwLibraryPartsV1.length &&
      value.name.parts.asMap().entries.every(
            (entry) =>
                entry.value ==
                _measurementPresentationRfwLibraryPartsV1[entry.key],
          );

  static void _rejectPresentationConstructorCollision(
    fmt.RemoteWidgetLibrary library,
  ) {
    if (library.widgets.any(
          (widget) =>
              widget.name == _measurementPresentedConstructorV1 ||
              widget.name == _measurementSourcePresentedConstructorV1,
        ) ||
        library.widgets.any(
          (widget) =>
              _containsPresentationConstructor(widget.initialState) ||
              _containsPresentationConstructor(widget.root),
        )) {
      throw const FormatException(
        'RFW artifact uses the reserved Measurement presentation constructor',
      );
    }
  }

  static bool _containsPresentationConstructor(Object? value) {
    switch (value) {
      case final fmt.ConstructorCall call:
        return call.name == _measurementPresentedConstructorV1 ||
            call.name == _measurementSourcePresentedConstructorV1 ||
            _containsPresentationConstructor(call.arguments);
      case final fmt.EventHandler handler:
        return _containsPresentationConstructor(handler.eventArguments);
      case final fmt.WidgetBuilderDeclaration builder:
        return _containsPresentationConstructor(builder.widget);
      case final fmt.Loop loop:
        return _containsPresentationConstructor(loop.input) ||
            _containsPresentationConstructor(loop.output);
      case final fmt.Switch switchNode:
        return _containsPresentationConstructor(switchNode.input) ||
            switchNode.outputs.values.any(_containsPresentationConstructor);
      case final Map<Object?, Object?> map:
        return map.values.any(_containsPresentationConstructor);
      case final List<Object?> list:
        return list.any(_containsPresentationConstructor);
      default:
        return false;
    }
  }

  static int _occurrences(String value, String needle) {
    var count = 0;
    var offset = 0;
    while (true) {
      final found = value.indexOf(needle, offset);
      if (found < 0) return count;
      count++;
      offset = found + needle.length;
    }
  }

  static String _quote(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

final class _PresentationRewriteTracker {
  _PresentationRewriteTracker({
    required this.presentationRoutesByCall,
  });

  bool didWrap = false;

  final Map<fmt.ConstructorCall, MeasurementPublicationDraftPresentationRouteV1>
      presentationRoutesByCall;
}

final class _PresentationRoute {
  const _PresentationRoute({
    required this.carrier,
    required this.compactToken,
  });

  final String carrier;
  final String compactToken;
}
