import 'package:restage_shared/src/capability/library_contract_header.dart';
import 'package:restage_shared/src/receipts/receipt_path.dart';

/// The project files under `.restage/` that builds read, listed under
/// `additional_public_assets` in `build.yaml`. Builds and pushes write under
/// `.restage/build/`, which must not be a build input.
const List<String> restageBuildStateInputs = <String>[
  '.restage/measurement-state.json',
  '.restage/wire-ids.events.jsonl',
  '$receiptsDirectory/**',
  '$libraryContractSnapshotDirectory/**',
];
