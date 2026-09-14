import 'canonical.dart';
import 'declared_answers.dart';
import 'identifiers.dart';

/// Maximum retained ordered occurrences in one capture session.
const measurementMaximumTimedOccurrencesPerRoot = 256;

/// Maximum retained ordered occurrences for one admitted point.
const measurementMaximumTimedOccurrencesPerRoute = 64;

/// Closed published channels available to ordered measurement capture.
enum MeasurementOccurrenceChannelV1 {
  presentation,
  interaction,
  completion,
  skip,
  dismiss,
}

/// One same-clock occurrence, ordered across every point in a capture session.
final class MeasurementTimedOccurrenceV1 extends CanonicalValue {
  MeasurementTimedOccurrenceV1({
    required this.ordinal,
    required this.channel,
    required this.elapsedMicros,
    this.answerValueV1,
  }) {
    if ((answerValueV1 != null &&
            channel != MeasurementOccurrenceChannelV1.interaction) ||
        ordinal <= 0 ||
        ordinal > measurementMaximumTimedOccurrencesPerRoot ||
        elapsedMicros < 0 ||
        elapsedMicros > 604800000000) {
      throw ArgumentError('Ordered occurrence exceeds its portable bounds');
    }
  }

  factory MeasurementTimedOccurrenceV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(json,
        allowedKeys: const {
          'ordinal',
          'channel',
          'elapsedMicros',
          'answerValueV1'
        },
        requiredKeys: const {'ordinal', 'channel', 'elapsedMicros'},
        path: 'measurementTimedOccurrenceV1');
    return MeasurementTimedOccurrenceV1(
      answerValueV1: reader.optionalObject('answerValueV1') == null
          ? null
          : MeasurementAnswerValueV1.fromJson(reader.object('answerValueV1')),
      ordinal: reader.integer('ordinal'),
      channel: MeasurementOccurrenceChannelV1.values
          .byName(reader.string('channel')),
      elapsedMicros: reader.integer('elapsedMicros'),
    );
  }

  final MeasurementAnswerValueV1? answerValueV1;
  final int ordinal;
  final MeasurementOccurrenceChannelV1 channel;
  final int elapsedMicros;

  @override
  Map<String, Object?> toJson() => {
        if (answerValueV1 != null) 'answerValueV1': answerValueV1!.toJson(),
        'ordinal': ordinal,
        'channel': channel.name,
        'elapsedMicros': elapsedMicros,
      };
}

/// Published admission for ordered capture at one exact point.
final class MeasurementOrderedCaptureRouteV1 extends CanonicalValue {
  MeasurementOrderedCaptureRouteV1({
    required this.occurrenceId,
    required this.lineageId,
    required List<MeasurementOccurrenceChannelV1> channels,
    this.lifecycle,
    this.declaredAnswerV1,
    this.answerCarrier,
  }) : channels = List.unmodifiable(channels) {
    if ((declaredAnswerV1 != null &&
            (answerCarrier == null ||
                answerCarrier!.isEmpty ||
                answerCarrier!.length > 1024 ||
                !channels
                    .contains(MeasurementOccurrenceChannelV1.interaction))) ||
        (declaredAnswerV1 == null && answerCarrier != null) ||
        channels.isEmpty ||
        channels.toSet().length != channels.length ||
        !channels.contains(MeasurementOccurrenceChannelV1.presentation)) {
      throw ArgumentError(
          'An ordered route requires distinct channels including presentation');
    }
  }

  factory MeasurementOrderedCaptureRouteV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(json,
        allowedKeys: const {
          'occurrenceId',
          'lineageId',
          'channels',
          'lifecycle',
          'declaredAnswerV1',
          'answerCarrier'
        },
        requiredKeys: const {'occurrenceId', 'lineageId', 'channels'},
        path: 'measurementOrderedCaptureRouteV1');
    return MeasurementOrderedCaptureRouteV1(
      declaredAnswerV1: reader.optionalObject('declaredAnswerV1') == null
          ? null
          : MeasurementDeclaredAnswerV1.fromJson(
              reader.object('declaredAnswerV1')),
      answerCarrier: reader.optionalString('answerCarrier'),
      lifecycle: reader.optionalObject('lifecycle') == null
          ? null
          : MeasurementLifecycleCaptureRouteV1.fromJson(
              reader.object('lifecycle')),
      occurrenceId: CanonicalDigest(reader.string('occurrenceId')),
      lineageId: PointLineageId(reader.string('lineageId')),
      channels: [
        for (final value in reader.list('channels'))
          MeasurementOccurrenceChannelV1.values
              .byName(requireCanonicalString(value, 'channel'))
      ],
    );
  }

  final MeasurementDeclaredAnswerV1? declaredAnswerV1;
  final String? answerCarrier;
  final MeasurementLifecycleCaptureRouteV1? lifecycle;
  final CanonicalDigest occurrenceId;
  final PointLineageId lineageId;
  final List<MeasurementOccurrenceChannelV1> channels;
  String get identity => '${occurrenceId.hex}\u0000${lineageId.value}';

  @override
  Map<String, Object?> toJson() => {
        if (declaredAnswerV1 != null)
          'declaredAnswerV1': declaredAnswerV1!.toJson(),
        if (answerCarrier != null) 'answerCarrier': answerCarrier,
        if (lifecycle != null) 'lifecycle': lifecycle!.toJson(),
        'occurrenceId': occurrenceId.hex,
        'lineageId': lineageId.value,
        'channels': [for (final channel in channels) channel.name]..sort(),
      };
}

/// Versioned ordered-capture capability bound to immutable publication routes.
final class MeasurementOrderedCaptureV1 extends CanonicalValue {
  MeasurementOrderedCaptureV1(
      {required List<MeasurementOrderedCaptureRouteV1> routes})
      : routes = List.unmodifiable(routes) {
    if (routes.isEmpty ||
        routes.length > 1024 ||
        routes.map((route) => route.identity).toSet().length != routes.length) {
      throw ArgumentError(
          'Ordered capture requires a bounded unique route set');
    }
    final lifecycleKeys = <String>{};
    final answerKeys = <String>{};
    for (final route in routes) {
      if (route.declaredAnswerV1 != null &&
          !answerKeys.add(route.declaredAnswerV1!.questionId))
        throw ArgumentError(
            'A question must have one exact published answer route');
      final lifecycle = route.lifecycle;
      if (lifecycle != null &&
          !lifecycleKeys.add(
              '${lifecycle.channel.name}\u0000${lifecycle.screenId ?? ''}')) {
        throw ArgumentError(
            'A lifecycle callback must have one exact published route');
      }
    }
  }

  factory MeasurementOrderedCaptureV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(json,
        allowedKeys: const {'kind', 'schemaVersion', 'routes'},
        requiredKeys: const {'kind', 'schemaVersion', 'routes'},
        path: 'measurementOrderedCaptureV1');
    if (reader.string('kind') != 'measurementOrderedCapture' ||
        reader.integer('schemaVersion') != 1) {
      throw const CanonicalFormatException(
          'Unsupported ordered capture capability');
    }
    return MeasurementOrderedCaptureV1(routes: [
      for (final route in reader.list('routes'))
        MeasurementOrderedCaptureRouteV1.fromJson(
            requireCanonicalObject(route, 'route')),
    ]);
  }

  final List<MeasurementOrderedCaptureRouteV1> routes;

  @override
  Map<String, Object?> toJson() => {
        'kind': 'measurementOrderedCapture',
        'schemaVersion': 1,
        'routes': [
          for (final route
              in (List.of(routes)
                ..sort((a, b) => a.identity.compareTo(b.identity))))
            route.toJson()
        ],
      };
}

/// Target-neutral capture channels for one compiler-owned source route.
final class MeasurementOrderedCaptureDeclarationV1 extends CanonicalValue {
  MeasurementOrderedCaptureDeclarationV1({
    required List<MeasurementOccurrenceChannelV1> channels,
    this.lifecycleChannel,
    this.screenId,
    this.declaredAnswerV1,
  }) : channels = List.unmodifiable(channels) {
    if (channels.isEmpty ||
        channels.toSet().length != channels.length ||
        !channels.contains(MeasurementOccurrenceChannelV1.presentation) ||
        (lifecycleChannel != null && !channels.contains(lifecycleChannel)) ||
        (screenId != null &&
            (lifecycleChannel == null ||
                screenId!.isEmpty ||
                screenId!.length > 256))) {
      throw ArgumentError('Invalid declared ordered capture channels');
    }
  }

  factory MeasurementOrderedCaptureDeclarationV1.fromJson(
      Map<String, Object?> json) {
    final reader = CanonicalObjectReader(json,
        allowedKeys: const {
          'channels',
          'lifecycleChannel',
          'screenId',
          'declaredAnswerV1'
        },
        requiredKeys: const {'channels'},
        path: 'orderedCaptureDeclarationV1');
    return MeasurementOrderedCaptureDeclarationV1(
      declaredAnswerV1: reader.optionalObject('declaredAnswerV1') == null
          ? null
          : MeasurementDeclaredAnswerV1.fromJson(
              reader.object('declaredAnswerV1')),
      channels: [
        for (final value in reader.list('channels'))
          MeasurementOccurrenceChannelV1.values
              .byName(requireCanonicalString(value, 'channel'))
      ],
      lifecycleChannel: reader.optionalString('lifecycleChannel') == null
          ? null
          : MeasurementOccurrenceChannelV1.values
              .byName(reader.string('lifecycleChannel')),
      screenId: reader.optionalString('screenId'),
    );
  }

  final MeasurementDeclaredAnswerV1? declaredAnswerV1;
  final List<MeasurementOccurrenceChannelV1> channels;
  final MeasurementOccurrenceChannelV1? lifecycleChannel;
  final String? screenId;

  @override
  Map<String, Object?> toJson() => {
        if (declaredAnswerV1 != null)
          'declaredAnswerV1': declaredAnswerV1!.toJson(),
        'channels': [for (final channel in channels) channel.name]..sort(),
        if (lifecycleChannel != null)
          'lifecycleChannel': lifecycleChannel!.name,
        if (screenId != null) 'screenId': screenId,
      };
}

/// Exact compiler-issued route for an actual root or authored-screen callback.
final class MeasurementLifecycleCaptureRouteV1 extends CanonicalValue {
  MeasurementLifecycleCaptureRouteV1(
      {required this.carrier, required this.channel, this.screenId}) {
    if (carrier.isEmpty ||
        carrier.length > 1024 ||
        (screenId != null && (screenId!.isEmpty || screenId!.length > 256)) ||
        channel == MeasurementOccurrenceChannelV1.interaction) {
      throw ArgumentError('Invalid published lifecycle route');
    }
  }

  factory MeasurementLifecycleCaptureRouteV1.fromJson(
      Map<String, Object?> json) {
    final reader = CanonicalObjectReader(json,
        allowedKeys: const {'carrier', 'channel', 'screenId'},
        requiredKeys: const {'carrier', 'channel'},
        path: 'lifecycleCaptureRouteV1');
    return MeasurementLifecycleCaptureRouteV1(
        carrier: reader.string('carrier'),
        channel: MeasurementOccurrenceChannelV1.values
            .byName(reader.string('channel')),
        screenId: reader.optionalString('screenId'));
  }

  final String carrier;
  final MeasurementOccurrenceChannelV1 channel;
  final String? screenId;

  @override
  Map<String, Object?> toJson() => {
        'carrier': carrier,
        'channel': channel.name,
        if (screenId != null) 'screenId': screenId
      };
}
