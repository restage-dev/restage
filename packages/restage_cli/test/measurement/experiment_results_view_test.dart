import 'package:restage_cli/src/measurement/page_views/experiment_results_view.dart';
import 'package:test/test.dart';

void main() {
  test('builds that cannot show a variant are listed after the changes', () {
    final out = StringBuffer();
    renderExperimentResultsPage(out, {
      'detail': {'lifecycle': 'active'},
      'changes': <Object?>[],
      'libraryRefusals': {
        'arms': [
          {
            'label': 'Annual first',
            'refusedBuilds': [
              {
                'appBuild': 412,
                'count': 7,
                'firstSeenMicros': DateTime.utc(
                  2026,
                  9,
                  8,
                ).microsecondsSinceEpoch,
              },
              {
                'appBuild': 0,
                'count': 1,
                'firstSeenMicros': DateTime.utc(
                  2026,
                  9,
                  9,
                ).microsecondsSinceEpoch,
              },
            ],
          },
        ],
        'declinedEnrollments': [
          {
            'appBuild': 412,
            'count': 5,
            'firstSeenMicros': DateTime.utc(2026, 9, 8).microsecondsSinceEpoch,
          },
          {
            'appBuild': 0,
            'count': 2,
            'firstSeenMicros': DateTime.utc(2026, 9, 8).microsecondsSinceEpoch,
          },
        ],
      },
    }, 5);

    expect(
      out.toString(),
      allOf(
        contains(
          "Annual first can't show on build 412.\n  7 times since 2026-09-08.",
        ),
        contains(
          "Annual first can't show on an unreported build.\n  1 time since 2026-09-09.",
        ),
        contains(
          "Build 412 can't show every variant.\n  5 times not enrolled.",
        ),
        contains(
          "An unreported build can't show every variant.\n  2 times not enrolled.",
        ),
      ),
    );
  });

  test('a page with no refusals states nothing about builds', () {
    final out = StringBuffer();
    renderExperimentResultsPage(out, {
      'detail': {'lifecycle': 'active'},
      'libraryRefusals': {
        'arms': <Object?>[],
        'declinedEnrollments': <Object?>[],
      },
    }, 5);

    expect(out.toString(), isNot(contains("can't show")));
  });
}
