import 'dart:typed_data';

import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;

/// SDK-local RFW namespace that owns the private presentation bridge.
const List<String> _measurementPresentationRfwLibraryPartsV1 = <String>[
  'restage',
  'measurement',
];

/// Private RFW constructor inserted around an event-owning widget occurrence.
const String _measurementPresentedConstructorV1 = 'MeasurementPresented';

/// Private presentation wrapper argument containing exact final route carriers.
const String _measurementPresentedCarriersArgumentV1 = 'carriers';

/// Private presentation wrapper argument containing compact point tokens.
const String _measurementPresentedPointTokensArgumentV1 = 'pointTokens';

/// Private presentation wrapper argument retaining the original widget.
const String _measurementPresentedChildArgumentV1 = 'child';

/// Result of replacing transient compiler markers in one RFW library.
final class MeasurementRfwRouteComposition {
  /// Creates a composed RFW artifact result.
  MeasurementRfwRouteComposition({
    required List<int> blob,
    required Set<String> generatedReferences,
  })  : blob = Uint8List.fromList(blob),
        generatedReferences = Set.unmodifiable(generatedReferences);

  /// Final encoded RFW blob containing strict route carriers.
  final Uint8List blob;

  /// Generated references whose markers were consumed in this blob.
  final Set<String> generatedReferences;
}

/// Replaces compiler-only event markers with the frozen private route carrier.
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
    final routes = {
      for (final route in routePlan.routes)
        route.generatedReferenceId.value: route,
    };
    final consumed = <String>{};
    final presentation = _PresentationRewriteTracker();
    final library = fmt.decodeLibraryBlob(Uint8List.fromList(blob));
    final rewritten = _rewriteLibrary(
      library,
      routes,
      consumed,
      presentation,
    );
    return MeasurementRfwRouteComposition(
      blob: fmt.encodeLibraryBlob(rewritten),
      generatedReferences: consumed,
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
    final marker = RegExp(
      '${RegExp.escape(kMeasurementRouteReferenceMarkerKeyV1)}: "'
      '${RegExp.escape(kMeasurementRouteReferenceMarkerPrefixV1)}[^"]+"',
    );
    var result = text.replaceAll(RegExp(',\\s*${marker.pattern}'), '');
    result = result.replaceAll(RegExp('${marker.pattern}\\s*,\\s*'), '');
    result = result.replaceAll(marker, '');
    if (result.contains(kMeasurementRouteReferenceMarkerKeyV1) ||
        result.contains(kMeasurementRouteReferenceMarkerPrefixV1)) {
      throw const FormatException(
        'RFW inspection text retained an unresolved Measurement marker',
      );
    }
    return result;
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

  static fmt.RemoteWidgetLibrary _rewriteLibrary(
    fmt.RemoteWidgetLibrary library,
    Map<String, MeasurementPublicationDraftRouteV1> routes,
    Set<String> consumed,
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
                  consumed,
                  presentation,
                ),
          _rewriteNode(widget.root, routes, consumed, presentation),
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
    Set<String> consumed,
    _PresentationRewriteTracker presentation,
  ) {
    switch (node) {
      case final fmt.ConstructorCall call:
        final arguments = _rewriteMap(
          call.arguments,
          routes,
          consumed,
          presentation,
        );
        final rewritten = fmt.ConstructorCall(
          call.name,
          arguments,
        );
        final presentationRoutes = _directPresentationRoutes(arguments);
        if (presentationRoutes.isEmpty) return rewritten;
        presentation.didWrap = true;
        return fmt.ConstructorCall(
          _measurementPresentedConstructorV1,
          <String, Object?>{
            _measurementPresentedCarriersArgumentV1: [
              for (final route in presentationRoutes) route.carrier,
            ],
            _measurementPresentedPointTokensArgumentV1: [
              for (final route in presentationRoutes) route.compactToken,
            ],
            _measurementPresentedChildArgumentV1: rewritten,
          },
        );
      case final fmt.EventHandler event:
        return _rewriteEvent(event, routes, consumed, presentation);
      case final fmt.WidgetBuilderDeclaration builder:
        return fmt.WidgetBuilderDeclaration(
          builder.argumentName,
          _rewriteNode(builder.widget, routes, consumed, presentation),
        );
      case final fmt.Loop loop:
        return fmt.Loop(
          _rewriteRequiredValue(loop.input, routes, consumed, presentation),
          _rewriteRequiredValue(loop.output, routes, consumed, presentation),
        );
      case final fmt.Switch switchNode:
        return fmt.Switch(
          _rewriteRequiredValue(
            switchNode.input,
            routes,
            consumed,
            presentation,
          ),
          {
            for (final entry in switchNode.outputs.entries)
              entry.key: _rewriteRequiredValue(
                entry.value,
                routes,
                consumed,
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
    Set<String> consumed,
    _PresentationRewriteTracker presentation,
  ) =>
      _rewriteValue(value, routes, consumed, presentation) ??
      (throw const FormatException('RFW route composition produced null'));

  static Object? _rewriteValue(
    Object? value,
    Map<String, MeasurementPublicationDraftRouteV1> routes,
    Set<String> consumed,
    _PresentationRewriteTracker presentation,
  ) {
    if (value is fmt.BlobNode) {
      return _rewriteNode(value, routes, consumed, presentation);
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key: _rewriteValue(
            entry.value,
            routes,
            consumed,
            presentation,
          ),
      };
    }
    if (value is List) {
      return [
        for (final item in value)
          _rewriteValue(item, routes, consumed, presentation),
      ];
    }
    return value;
  }

  static fmt.DynamicMap _rewriteMap(
    fmt.DynamicMap value,
    Map<String, MeasurementPublicationDraftRouteV1> routes,
    Set<String> consumed,
    _PresentationRewriteTracker presentation,
  ) =>
      <String, Object?>{
        for (final entry in value.entries)
          entry.key: _rewriteValue(
            entry.value,
            routes,
            consumed,
            presentation,
          ),
      };

  static fmt.EventHandler _rewriteEvent(
    fmt.EventHandler event,
    Map<String, MeasurementPublicationDraftRouteV1> routes,
    Set<String> consumed,
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
          consumed,
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

  static List<_PresentationRoute> _directPresentationRoutes(
    fmt.DynamicMap arguments,
  ) {
    final carriers = <String>{};

    void visit(Object? value) {
      switch (value) {
        case final fmt.EventHandler handler:
          final carrier =
              handler.eventArguments[kMeasurementRouteArgumentKeyV1];
          if (carrier is String) carriers.add(carrier);
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
    final sortedCarriers = carriers.toList()..sort();
    return List<_PresentationRoute>.unmodifiable([
      for (final carrier in sortedCarriers)
        _PresentationRoute(
          carrier: carrier,
          compactToken:
              MeasurementCompactPointTokenEmitter.fromRouteCarrier(carrier),
        ),
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
          (widget) => widget.name == _measurementPresentedConstructorV1,
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
  _PresentationRewriteTracker();

  bool didWrap = false;
}

final class _PresentationRoute {
  const _PresentationRoute({
    required this.carrier,
    required this.compactToken,
  });

  final String carrier;
  final String compactToken;
}
