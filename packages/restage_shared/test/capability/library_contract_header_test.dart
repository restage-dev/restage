import 'dart:convert';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('LibraryContractHeader', () {
    test('reads the header keys and ignores the contract', () {
      final header = LibraryContractHeader.decode(
        jsonEncode({
          'namespace': 'app',
          'capabilityVersion': 4,
          'compatibleSince': 4,
          'schemaVersion': 1,
          'widgets': <String, Object?>{},
        }),
        'app/v4.json',
      );
      expect(
        header,
        LibraryContractHeader(
          namespace: 'app',
          capabilityVersion: 4,
          compatibleSince: 4,
        ),
      );
    });

    test('refuses a file that is not a contract', () {
      expect(
        () => LibraryContractHeader.decode('not json', 'app/v1.json'),
        throwsFormatException,
      );
      expect(
        () => LibraryContractHeader.decode('[]', 'app/v1.json'),
        throwsFormatException,
      );
    });

    test('refuses missing or out-of-range keys', () {
      for (final json in [
        {'capabilityVersion': 1, 'compatibleSince': 1},
        {'namespace': '', 'capabilityVersion': 1, 'compatibleSince': 1},
        {'namespace': 'app', 'capabilityVersion': 0, 'compatibleSince': 1},
        {'namespace': 'app', 'capabilityVersion': 2, 'compatibleSince': 0},
        {'namespace': 'app', 'capabilityVersion': 2, 'compatibleSince': 3},
        {'namespace': 'app', 'capabilityVersion': '2', 'compatibleSince': 1},
      ]) {
        expect(
          () => LibraryContractHeader.decode(jsonEncode(json), 'app/v2.json'),
          throwsFormatException,
          reason: '$json',
        );
      }
    });
  });

  group('snapshot file names', () {
    test('name a positive capability version', () {
      expect(libraryContractSnapshotVersion('v1.json'), 1);
      expect(libraryContractSnapshotVersion('v12.json'), 12);
      for (final name in ['v0.json', 'v01.json', 'v1.jsonl', '1.json', 'x']) {
        expect(libraryContractSnapshotVersion(name), isNull, reason: name);
      }
    });

    test('live under the snapshot directory', () {
      expect(libraryContractSnapshotDirectory, '.restage/library-contracts');
    });
  });
}
