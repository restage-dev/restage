part of 'restage_event.dart';

/// Fired after Measurement first retains a presented point in the session.
@immutable
final class SurfacePointPresented extends RestageEvent {
  /// Creates a point-presentation event from canonical Measurement identity.
  const SurfacePointPresented({
    required this.occurrenceId,
    required this.lineageId,
    super.firedAt,
    super.attribution,
  });

  /// Exact occurrence in the rendered publication.
  final String occurrenceId;

  /// Stable lineage identity shared by compatible revisions.
  final String lineageId;

  @override
  String get name => 'surface_point_presented';

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'occurrenceId': occurrenceId,
        'lineageId': lineageId,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}

/// Fired after Measurement acknowledges a recorded point interaction.
@immutable
final class SurfacePointInteracted extends RestageEvent {
  /// Creates a point-interaction event from canonical Measurement identity.
  const SurfacePointInteracted({
    required this.occurrenceId,
    required this.lineageId,
    super.firedAt,
    super.attribution,
  });

  /// Exact occurrence in the rendered publication.
  final String occurrenceId;

  /// Stable lineage identity shared by compatible revisions.
  final String lineageId;

  @override
  String get name => 'surface_point_interacted';

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'occurrenceId': occurrenceId,
        'lineageId': lineageId,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}

/// Fired after a pager settles on a different page.
@immutable
final class PagerPageChanged extends RestageEvent {
  /// Creates a pager page event.
  PagerPageChanged({
    required this.pageIndex,
    required this.pageCount,
    super.firedAt,
    super.attribution,
  }) {
    if (pageCount <= 0) {
      throw ArgumentError.value(
        pageCount,
        'pageCount',
        'must be greater than zero',
      );
    }
    if (pageIndex < 0 || pageIndex >= pageCount) {
      throw ArgumentError.value(
        pageIndex,
        'pageIndex',
        'must be within the pager page range',
      );
    }
  }

  /// Zero-based index reported by the pager.
  final int pageIndex;

  /// Number of pages available in the pager.
  final int pageCount;

  @override
  String get name => 'page_changed';

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'pageIndex': pageIndex,
        'pageCount': pageCount,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}

/// Fired when a declared answer changes after a flow trigger settles, on any
/// typed flow surface: onboarding, message or survey.
@immutable
final class SurveyQuestionResponded extends RestageEvent {
  /// Creates an answer event.
  SurveyQuestionResponded({
    required this.questionId,
    required this.questionIndex,
    super.firedAt,
    super.attribution,
  }) {
    if (questionId.isEmpty) {
      throw ArgumentError.value(
        questionId,
        'questionId',
        'must not be empty',
      );
    }
    if (questionIndex < 0) {
      throw ArgumentError.value(
        questionIndex,
        'questionIndex',
        'must not be negative',
      );
    }
  }

  /// Stable question identifier from the flow document.
  final String questionId;

  /// Zero-based question position from the flow document.
  final int questionIndex;

  @override
  String get name => 'paywall_survey_responded';

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'questionId': questionId,
        'questionIndex': questionIndex,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}

/// Author-fired paywall event. The [eventName] and [args] preserve the values
/// supplied by the application.
final class PaywallCustomEvent extends RestageEvent {
  /// Const constructor.
  const PaywallCustomEvent({
    required String super.paywallId,
    required this.eventName,
    required this.args,
    super.firedAt,
    super.attribution,
  });

  /// The author-supplied event name.
  final String eventName;

  /// Author-supplied arguments. Spread into [toMap] for analytics.
  final Map<String, Object?> args;

  @override
  String get name => 'paywall_custom_event';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
        'eventName': eventName,
        ...args,
      };
}
