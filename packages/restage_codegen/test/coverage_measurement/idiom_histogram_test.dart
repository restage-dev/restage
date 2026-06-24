import 'package:restage_codegen/src/coverage_measurement/idiom_histogram.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:test/test.dart';

/// A one-blocker imperative verdict, for compact test fixtures. [subject] is
/// the structured aggregation subject the producer threads onto the blocker;
/// when omitted the histogram falls back to the raw [detail].
ImperativeWidget _imp(
  String key,
  BlockerKind kind,
  String detail, {
  String? subject,
}) =>
    ImperativeWidget(
      key,
      blockers: [
        Blocker(
          kind: kind,
          location: '$key@1:1',
          detail: detail,
          idiomSubject: subject,
        ),
      ],
    );

void main() {
  test('aggregates blocker kinds with detail heads and counts', () {
    final classifications = <String, WidgetClassification>{
      'pkg#A': _imp(
        'pkg#A',
        BlockerKind.unrecognisedComposedWidget,
        'LayoutBuilder(builder: (c, x) => ...)',
        subject: 'LayoutBuilder',
      ),
      'pkg#B': ImperativeWidget(
        'pkg#B',
        blockers: const [
          Blocker(
            kind: BlockerKind.unrecognisedComposedWidget,
            location: 'pkg#B@2:2',
            detail: 'LayoutBuilder(builder: (c, y) => ...)',
            idiomSubject: 'LayoutBuilder',
          ),
          Blocker(
            kind: BlockerKind.customPainter,
            location: 'pkg#B@3:3',
            detail: 'CustomPaint(painter: _P())',
            idiomSubject: 'CustomPaint',
          ),
        ],
      ),
    };

    final hist = IdiomHistogram.from(classifications);

    final layout = hist.rows.firstWhere(
      (r) => r.label == 'unrecognisedComposedWidget · LayoutBuilder',
    );
    expect(layout.count, 2);
    expect(layout.isUnrecognisedComposition, isTrue);
    expect(layout.disposition, CustomWidgetDisposition.reducible);

    final paint = hist.rows.firstWhere(
      (r) => r.label.startsWith('customPainter'),
    );
    expect(paint.count, 1);
    expect(paint.isUnrecognisedComposition, isFalse);
    expect(paint.disposition, CustomWidgetDisposition.deadEnd);
  });

  test('records unclassifiable reasons and composable mechanisms', () {
    final classifications = <String, WidgetClassification>{
      'pkg#U': const UnclassifiableWidget(
        'pkg#U',
        reason: 'build() body is not a single returned expression',
      ),
      'pkg#C': ComposableWidget(
        'pkg#C',
        requiredMechanisms: {InliningMechanism.themeAsData},
        composedCustomWidgets: const [],
      ),
      'pkg#D': ComposableWidget(
        'pkg#D',
        requiredMechanisms: const {},
        composedCustomWidgets: const [],
      ),
    };
    final hist = IdiomHistogram.from(classifications);
    expect(
      hist.rows.any((r) => r.label.startsWith('unclassifiable ·')),
      isTrue,
    );
    expect(hist.rows.any((r) => r.label.contains('themeAsData')), isTrue);
    expect(
      hist.rows.any((r) => r.label == 'composable · composition-only'),
      isTrue,
    );
  });

  test('aggregates on the producer-threaded subject for prose / call details',
      () {
    final classifications = <String, WidgetClassification>{
      // A lifecycle blocker — the producer threads the method name.
      'pkg#A': _imp(
        'pkg#A',
        BlockerKind.asyncOrLifecycle,
        'the State lifecycle method initState()',
        subject: 'initState',
      ),
      // A non-primitive State field — the producer threads the field name.
      'pkg#B': _imp(
        'pkg#B',
        BlockerKind.nonSimpleState,
        "the non-primitive State field 'controller'",
        subject: 'controller',
      ),
      // A dotted static-method call — the producer threads receiver.method.
      'pkg#C': _imp(
        'pkg#C',
        BlockerKind.dartCall,
        'ButtonStyle.styleFrom(foregroundColor: x)',
        subject: 'ButtonStyle.styleFrom',
      ),
    };
    final hist = IdiomHistogram.from(classifications);
    expect(
      hist.rows.any((r) => r.label == 'asyncOrLifecycle · initState'),
      isTrue,
    );
    expect(
      hist.rows.any((r) => r.label == 'nonSimpleState · controller'),
      isTrue,
    );
    expect(
      hist.rows.any((r) => r.label == 'dartCall · ButtonStyle.styleFrom'),
      isTrue,
    );
  });

  test('renders a deterministic table separating artifacts from gaps', () {
    final classifications = <String, WidgetClassification>{
      'pkg#A': _imp('pkg#A', BlockerKind.dartCall, 'formatPrice(amount)'),
      'pkg#B': _imp(
        'pkg#B',
        BlockerKind.unrecognisedComposedWidget,
        '_RawGap(amount)',
      ),
    };
    final out = IdiomHistogram.from(classifications).render();
    expect(out, contains('dartCall'));
    expect(out, contains('formatPrice'));
    // Unrecognised compositions are rendered under their own heading.
    expect(out, contains('Unrecognised compositions'));
    expect(out, contains('_RawGap'));
  });

  test('toJson is stable and count-sorted', () {
    final classifications = <String, WidgetClassification>{
      'pkg#A': _imp('pkg#A', BlockerKind.dartCall, 'foo()', subject: 'foo'),
      'pkg#B': _imp('pkg#B', BlockerKind.dartCall, 'foo()', subject: 'foo'),
      'pkg#C': _imp(
        'pkg#C',
        BlockerKind.runtimeComputedValue,
        'w * 0.8',
        subject: 'w',
      ),
    };
    final json = IdiomHistogram.from(classifications).toJson();
    // dartCall · foo (count 2) sorts before runtimeComputedValue (count 1).
    expect(json.first['label'], 'dartCall · foo');
    expect(json.first['count'], 2);
    expect(json.first['unrecognisedComposition'], isFalse);
  });

  test('rows carry a structured kind/subject key, not just a label', () {
    final classifications = <String, WidgetClassification>{
      'pkg#A': _imp(
        'pkg#A',
        BlockerKind.dartCall,
        'ButtonStyle.styleFrom(foregroundColor: x)',
        subject: 'ButtonStyle.styleFrom',
      ),
    };
    final row = IdiomHistogram.from(classifications).rows.single;
    expect(row.key.kind, 'dartCall');
    expect(row.key.subject, 'ButtonStyle.styleFrom');
    expect(row.label, 'dartCall · ButtonStyle.styleFrom'); // back-compat
  });

  test('toJson exposes kind and subject as separate fields', () {
    final classifications = <String, WidgetClassification>{
      'pkg#A': _imp('pkg#A', BlockerKind.dartCall, 'foo()', subject: 'foo'),
    };
    final json = IdiomHistogram.from(classifications).toJson().single;
    expect(json['kind'], 'dartCall');
    expect(json['subject'], 'foo');
    expect(json['label'], 'dartCall · foo'); // retained for back-compat
  });

  test(
      'the histogram keys on the blocker structured idiomSubject, not the '
      'detail string', () {
    // The producer threads the AST-resolved subject onto the blocker, so the
    // histogram reads it directly rather than recovering it from the
    // human-facing detail. A subject that differs from anything the detail
    // string would yield proves the structured field — not a parse — drives
    // aggregation.
    final classifications = <String, WidgetClassification>{
      'pkg#A': ImperativeWidget(
        'pkg#A',
        blockers: const [
          Blocker(
            kind: BlockerKind.dartCall,
            location: 'pkg#A@1:1',
            detail: 'ButtonStyle.styleFrom(elevation: 2, padding: ...)',
            idiomSubject: 'ButtonStyle.styleFrom',
          ),
        ],
      ),
    };
    final row = IdiomHistogram.from(classifications).rows.single;
    expect(row.key.subject, 'ButtonStyle.styleFrom');
    expect(row.label, 'dartCall · ButtonStyle.styleFrom');
  });
}
