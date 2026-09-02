import 'package:meta/meta.dart';
import 'package:restage_codegen/src/measurement/measurement_event_occurrence.dart';
import 'package:restage_codegen/src/measurement/measurement_source_discovery.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// The exact private argument key in the final generated RFW event map.
const String kMeasurementRouteArgumentKeyV1 =
    kMeasurementPublicationRouteArgumentKeyV1;

/// Internal compiler-only key used to carry a generated-reference marker from
/// the expression translator to the package publication compiler.
///
/// The marker is never an output contract. It is replaced with the strict
/// [kMeasurementRouteArgumentKeyV1] carrier before an artifact is hashed or
/// exposed as a package publication.
const String kMeasurementRouteReferenceMarkerKeyV1 =
    '__restage_measurement_route_ref_v1';

/// Internal marker value prefix. The suffix is an exact
/// [GeneratedReferenceId], never a source path, event name, label, key, or
/// collection ordinal.
const String kMeasurementRouteReferenceMarkerPrefixV1 =
    '__restage_measurement_route_ref_v1:';

/// Emits the compact opaque token carried beside one final route carrier.
///
/// The token is the already-derived 192-bit local portion of the strict route
/// carrier. It is selected while artifacts are composed, before a mounted
/// runtime can receive it; it carries no event name, Flutter key, text, or
/// customer value.
@internal
abstract final class MeasurementCompactPointTokenEmitter {
  /// Extracts the bounded local token from one strict final route carrier.
  static String fromRouteCarrier(String routeCarrier) {
    MeasurementPublicationRouteCarrierV1.parse(routeCarrier);
    final separator = routeCarrier.lastIndexOf('.');
    final compactToken = routeCarrier.substring(separator + 1);
    if (compactToken.length !=
        kMeasurementPublicationRouteCarrierLocalTokenLength) {
      throw ArgumentError.value(
        routeCarrier,
        'routeCarrier',
        'Expected a final route carrier with one compact point token',
      );
    }
    return compactToken;
  }
}

/// One exact event-occurrence to generated-reference binding.
@immutable
final class MeasurementRouteEmissionBinding {
  /// Creates an explicit compiler binding for one route.
  const MeasurementRouteEmissionBinding({
    required this.occurrence,
    required this.generatedReferenceId,
  });

  /// Structural position capable of emitting this route marker.
  final MeasurementEventOccurrence occurrence;

  /// Generated reference selected by the target-neutral draft route.
  final GeneratedReferenceId generatedReferenceId;
}

/// Exact structural event bindings used by the RFW translation pass.
@immutable
final class MeasurementRouteEmissionPlan {
  /// Creates a plan from explicit structural event bindings.
  factory MeasurementRouteEmissionPlan(
    Iterable<MeasurementRouteEmissionBinding> bindings,
  ) {
    final markerByOccurrence = <MeasurementEventOccurrence, String>{};
    final refs = <String>{};
    String? sourceRootIdentity;
    for (final binding in bindings) {
      final reference = binding.generatedReferenceId.value;
      if (!refs.add(reference)) {
        throw ArgumentError(
          'A measurement route emission plan cannot reuse a generated '
          'reference',
        );
      }
      final marker = markerForGeneratedReference(binding.generatedReferenceId);
      final occurrence = binding.occurrence;
      sourceRootIdentity ??= occurrence.sourceRootIdentity;
      if (sourceRootIdentity != occurrence.sourceRootIdentity) {
        throw ArgumentError(
          'A measurement route emission plan must have one source root',
        );
      }
      final previous = markerByOccurrence[occurrence];
      if (previous != null && previous != marker) {
        throw ArgumentError(
          'One exact event occurrence cannot carry two measurement routes',
        );
      }
      markerByOccurrence[occurrence] = marker;
    }
    return MeasurementRouteEmissionPlan._(
      markerByOccurrence,
      sourceRootIdentity == null
          ? null
          : MeasurementOccurrenceScope.root(sourceRootIdentity),
    );
  }

  const MeasurementRouteEmissionPlan._(
    this._markerByOccurrence,
    this.rootScope,
  );

  /// Builds a plan by reconciling resolved source discovery to the exact
  /// target-neutral publication draft.
  ///
  /// [codeIdentityByStructuralOccurrenceKey] is the compiler's explicit
  /// ledger reconciliation. It is not reconstructed from widget order or
  /// source text.
  factory MeasurementRouteEmissionPlan.fromDiscovery({
    required MeasurementSourceDiscoveryResult discovery,
    required MeasurementPublicationRoutePlanV1 routePlan,
    required Map<String, CodeIdentityId> codeIdentityByStructuralOccurrenceKey,
  }) {
    final routeEvents = <String, MeasurementPublicationDraftEventV1>{
      for (final event in routePlan.events)
        '${event.nodeCodeIdentityId.value}\u0000'
            '${event.sourceEventIdentity.value}': event,
    };
    final routesByReference = <String, MeasurementPublicationDraftRouteV1>{
      for (final route in routePlan.routes)
        route.generatedReferenceId.value: route,
    };
    final bindings = <MeasurementRouteEmissionBinding>[];
    for (final discovered in discovery.events) {
      final codeIdentity = codeIdentityByStructuralOccurrenceKey[
          discovered.node.structuralOccurrenceKey];
      if (codeIdentity == null) {
        throw ArgumentError(
          'Every discovered measurement event must reconcile to one code '
          'identity before carrier emission',
        );
      }
      final eventKey = '${codeIdentity.value}\u0000'
          '${discovered.resolvedEvent.sourceEventIdentity.value}';
      final event = routeEvents[eventKey];
      if (event == null) {
        throw ArgumentError(
          'Every discovered measurement event must reconcile to one route-plan '
          'event by exact node and source-event identity',
        );
      }
      if (event.collectionClass == MeasurementCollectionClass.prohibited) {
        continue;
      }
      final route = routesByReference[event.generatedReferenceId.value];
      if (route == null) {
        throw ArgumentError(
          'Every admitted draft event must have one derived route',
        );
      }
      bindings.add(
        MeasurementRouteEmissionBinding(
          occurrence: discovered.emissionOccurrence,
          generatedReferenceId: route.generatedReferenceId,
        ),
      );
    }
    return MeasurementRouteEmissionPlan(bindings);
  }

  final Map<MeasurementEventOccurrence, String> _markerByOccurrence;

  /// Structural source scope used to begin translation.
  final MeasurementOccurrenceScope? rootScope;

  /// Returns the marker for this exact structural event occurrence.
  String? markerFor(MeasurementEventOccurrence occurrence) =>
      _markerByOccurrence[occurrence];

  /// Returns the marker spelling used in the transient RFW handoff.
  static String markerForGeneratedReference(
    GeneratedReferenceId generatedReferenceId,
  ) =>
      '$kMeasurementRouteReferenceMarkerPrefixV1'
      '${generatedReferenceId.value}';
}

/// Strictly validates and emits a transient event marker from translated RFW
/// event DSL. The package compiler performs the final carrier replacement.
abstract final class MeasurementRouteEventMarkerEmitter {
  /// Adds one generated-reference marker to an RFW event map.
  static String attach(
    String dsl, {
    required String? marker,
  }) {
    final map = _eventArgumentMap(dsl);
    if (map == null) return dsl;
    final keys = _topLevelMapKeys(map.body);
    for (final key in keys) {
      if (key.startsWith(kMeasurementPublicationReservedArgumentPrefixV1)) {
        throw ArgumentError(
          'Authored RFW event arguments may not use the reserved Measurement '
          'prefix',
        );
      }
    }
    if (marker == null) return dsl;
    final body = map.body.trim();
    final separator = body.isEmpty ? '' : ', ';
    return '${dsl.substring(0, map.open + 1)}$body$separator'
        '$kMeasurementRouteReferenceMarkerKeyV1: ${_quote(marker)}'
        '${dsl.substring(map.close)}';
  }

  static _EventMap? _eventArgumentMap(String dsl) {
    final eventStart = dsl.indexOf('event ');
    if (eventStart < 0 || dsl.substring(0, eventStart).trim().isNotEmpty) {
      return null;
    }
    final open = dsl.indexOf('{', eventStart);
    if (open < 0) return null;
    final close = _matchingBrace(dsl, open);
    if (close < 0 || dsl.substring(close + 1).trim().isNotEmpty) return null;
    return _EventMap(
      open: open,
      close: close,
      body: dsl.substring(open + 1, close),
    );
  }

  static int _matchingBrace(String value, int open) {
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (var index = open; index < value.length; index++) {
      final char = value[index];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          quoted = false;
        }
        continue;
      }
      if (char == '"') {
        quoted = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}' && --depth == 0) {
        return index;
      }
    }
    return -1;
  }

  static Set<String> _topLevelMapKeys(String body) {
    final keys = <String>{};
    var index = 0;
    while (index < body.length) {
      while (index < body.length &&
          (body[index].trim().isEmpty || body[index] == ',')) {
        index++;
      }
      if (index >= body.length) {
        break;
      }
      final keyStart = index;
      String key;
      if (body[index] == '"') {
        final end = _quotedEnd(body, index);
        if (end < 0) {
          break;
        }
        key = body.substring(index + 1, end);
        index = end + 1;
      } else {
        while (index < body.length &&
            body[index] != ':' &&
            body[index].trim().isNotEmpty) {
          index++;
        }
        key = body.substring(keyStart, index);
      }
      while (index < body.length && body[index].trim().isEmpty) {
        index++;
      }
      if (index >= body.length || body[index] != ':') {
        break;
      }
      keys.add(key);
      index = _nextTopLevelComma(body, index + 1);
    }
    return keys;
  }

  static int _nextTopLevelComma(String body, int start) {
    var braces = 0;
    var brackets = 0;
    var parentheses = 0;
    var quoted = false;
    var escaped = false;
    for (var index = start; index < body.length; index++) {
      final char = body[index];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          quoted = false;
        }
        continue;
      }
      if (char == '"') {
        quoted = true;
      } else if (char == '{') {
        braces++;
      } else if (char == '}') {
        braces--;
      } else if (char == '[') {
        brackets++;
      } else if (char == ']') {
        brackets--;
      } else if (char == '(') {
        parentheses++;
      } else if (char == ')') {
        parentheses--;
      } else if (char == ',' &&
          braces == 0 &&
          brackets == 0 &&
          parentheses == 0) {
        return index;
      }
    }
    return body.length;
  }

  static int _quotedEnd(String value, int start) {
    var escaped = false;
    for (var index = start + 1; index < value.length; index++) {
      final char = value[index];
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        return index;
      }
    }
    return -1;
  }

  static String _quote(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

@immutable
final class _EventMap {
  const _EventMap({
    required this.open,
    required this.close,
    required this.body,
  });

  final int open;
  final int close;
  final String body;
}
