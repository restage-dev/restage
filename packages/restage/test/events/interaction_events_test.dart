import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

void main() {
  test('PaywallCustomEvent toMap merges name + paywallId + eventName + args',
      () {
    const e = PaywallCustomEvent(
      paywallId: 'pro_upgrade',
      eventName: 'subscribe',
      args: {'plan': 'monthly', 'priceMicros': 9990000},
    );
    expect(e.name, 'paywall_custom_event');
    final map = e.toMap();
    expect(map['name'], 'paywall_custom_event');
    expect(map['paywallId'], 'pro_upgrade');
    expect(map['eventName'], 'subscribe');
    expect(map['plan'], 'monthly');
    expect(map['priceMicros'], 9990000);
  });

  test('PagerPageChanged validates and maps its wire properties', () {
    final event = PagerPageChanged(pageIndex: 1, pageCount: 3);

    expect(event.name, 'page_changed');
    expect(
      event.toMap(),
      <String, Object?>{
        'name': 'page_changed',
        'pageIndex': 1,
        'pageCount': 3,
      },
    );
    expect(
      () => PagerPageChanged(pageIndex: 0, pageCount: 0),
      throwsArgumentError,
    );
    expect(
      () => PagerPageChanged(pageIndex: -1, pageCount: 1),
      throwsArgumentError,
    );
    expect(
      () => PagerPageChanged(pageIndex: 1, pageCount: 1),
      throwsArgumentError,
    );
  });

  test('SurveyQuestionResponded validates and maps its wire properties', () {
    final event = SurveyQuestionResponded(
      questionId: 'favorite_color',
      questionIndex: 2,
    );

    expect(event.name, 'paywall_survey_responded');
    expect(
      event.toMap(),
      <String, Object?>{
        'name': 'paywall_survey_responded',
        'questionId': 'favorite_color',
        'questionIndex': 2,
      },
    );
    expect(
      () => SurveyQuestionResponded(questionId: '', questionIndex: 0),
      throwsArgumentError,
    );
    expect(
      () => SurveyQuestionResponded(
          questionId: 'favorite_color', questionIndex: -1),
      throwsArgumentError,
    );
  });
}
