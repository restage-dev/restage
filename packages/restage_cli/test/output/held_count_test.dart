import 'package:restage_cli/src/output/held_count.dart';
import 'package:test/test.dart';

void main() {
  test('one view is singular; every other count is plural', () {
    expect(viewsText('1'), '1 view');
    expect(viewsText('0'), '0 views');
    expect(viewsText('1,200'), '1,200 views');
    expect(viewsText(heldCountText(5)), '<5 views');
  });
}
