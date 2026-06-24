import 'package:restage_cli/src/output/formatter.dart';
import 'package:test/test.dart';

void main() {
  group('HumanOutputFormatter', () {
    test('status writes a line to the sink', () {
      final sink = StringBuffer();
      HumanOutputFormatter(sink).status('Hello.');
      expect(sink.toString(), 'Hello.\n');
    });

    test('data renders a string verbatim', () {
      final sink = StringBuffer();
      HumanOutputFormatter(sink).data('payload');
      expect(sink.toString(), 'payload\n');
    });

    test('data renders null as an empty line', () {
      final sink = StringBuffer();
      HumanOutputFormatter(sink).data(null);
      expect(sink.toString(), isEmpty);
    });
  });
}
