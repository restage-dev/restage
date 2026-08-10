import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('README states the bounded RFW structured-value contract', () {
    final readme = File('README.md').readAsStringSync();
    final prose = readme
        .replaceAll(RegExp(r'^>\s?', multiLine: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    final staleRoadmapClaim = ['planned, ', 'not yet available'].join();

    expect(readme, isNot(contains(staleRoadmapClaim)));
    expect(
      prose,
      contains(
        'RFW delivery admits supported customer structured objects, maps, '
        'records, and lists only when Restage can form a reconstruction plan',
      ),
    );
    expect(
      prose,
      contains('Unsupported structured shapes fail generation loudly'),
    );
  });
}
