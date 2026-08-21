import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

/// One complete final-entry input for target-profile composition.
///
/// Every entry carries its own exact candidate proof, reference, declared-byte
/// authority, final binding, and registered attestation. The packager still
/// independently replays that proof against the selected bundle closure.
final class MeasurementBundledTargetProfilePackageRequest {
  /// Creates an explicit target-profile packaging request.
  MeasurementBundledTargetProfilePackageRequest({
    required Iterable<MeasurementPublicationBundledRegistryEntryV1>
    finalizationEntries,
    required Iterable<File> selectedBundleFiles,
  }) : finalizationEntries = _boundedImmutableList(
         finalizationEntries,
         maximumLength: kMaximumMeasurementPublicationBundledRegistryEntryCount,
         label: 'finalization entries',
       ),
       selectedBundleFiles = _boundedImmutableList(
         selectedBundleFiles,
         maximumLength: kMaximumMeasurementBundledTargetProfileBundleCount,
         label: 'selected bundle files',
       );

  /// Complete final entries and their closed candidate evidence.
  ///
  /// Their immutable bindings determine the only target the profile may carry.
  final List<MeasurementPublicationBundledRegistryEntryV1> finalizationEntries;

  /// Exact source-owned bundle files selected for this target profile.
  final List<File> selectedBundleFiles;
}

List<T> _boundedImmutableList<T>(
  Iterable<T> values, {
  required int maximumLength,
  required String label,
}) {
  final bounded = <T>[];
  for (final value in values) {
    if (bounded.length == maximumLength) {
      throw ArgumentError.value(
        maximumLength + 1,
        label,
        'permits at most $maximumLength values',
      );
    }
    bounded.add(value);
  }
  return List<T>.unmodifiable(bounded);
}

/// A deterministic crash injection point used by recovery controls.
enum MeasurementBundledTargetProfileCrashPoint {
  /// The next profile bytes exist only at the private stage path.
  afterStageWrite,

  /// The recovery journal durably names the expected next profile bytes.
  afterJournalWrite,

  /// The previous complete profile has moved to the private backup path.
  afterBackupMove,

  /// The next complete profile has reached the single public asset path.
  afterInstallMove,
}

/// Raised when target-profile composition cannot preserve a complete profile.
final class MeasurementBundledTargetProfilePackagingException
    implements Exception {
  /// Creates a packaging failure with a safe diagnostic message.
  const MeasurementBundledTargetProfilePackagingException(this.message);

  /// Safe failure detail.
  final String message;

  @override
  String toString() =>
      'MeasurementBundledTargetProfilePackagingException: '
      '$message';
}

/// Atomically composes the separate Measurement target-profile asset.
///
/// The transaction never writes `.rsbundle` files. It verifies the supplied
/// final entries against the selected source-bundle closure, seals the
/// exact bundle hashes into one profile asset, and atomically replaces that
/// asset with a same-directory stage/journal/backup protocol. Same-root calls
/// serialize in-process and through a durable filesystem lock. No discovery,
/// active/current selection, or fallback exists.
final class MeasurementBundledTargetProfilePackager {
  /// Creates a packager. [onCrashPoint] is an injectable fault seam.
  MeasurementBundledTargetProfilePackager({
    FutureOr<void> Function(MeasurementBundledTargetProfileCrashPoint)?
    onCrashPoint,
  }) : _onCrashPoint = onCrashPoint;

  final FutureOr<void> Function(MeasurementBundledTargetProfileCrashPoint)?
  _onCrashPoint;

  /// Builds and installs one profile from complete final entries.
  Future<MeasurementBundledTargetProfileV1> package({
    required Directory packageRoot,
    required MeasurementBundledTargetProfilePackageRequest request,
  }) => _withPackageLock(
    packageRoot,
    (files) =>
        _package(files: files, packageRoot: packageRoot, request: request),
  );

  /// Exports one committed final entry without replacing older exact entries.
  ///
  /// This is a local packaging operation over the response already committed
  /// by the single publication transaction. It performs no registration or
  /// delivery-selection operation of its own.
  Future<MeasurementBundledTargetProfileV1> packageFinalizedEntry({
    required Directory packageRoot,
    required MeasurementPublicationBundledRegistryEntryV1 entry,
    required Iterable<File> selectedBundleFiles,
  }) => _withPackageLock(
    packageRoot,
    (files) => _packageFinalizedEntry(
      files: files,
      packageRoot: packageRoot,
      entry: entry,
      selectedBundleFiles: selectedBundleFiles,
    ),
  );

  /// Recovers one interrupted replacement and returns its installed profile.
  ///
  /// A stage file is never a candidate without a canonical journal. With a
  /// trusted journal, a matching installed profile wins; otherwise a complete
  /// backup wins before a staged initial install. With no trustworthy journal,
  /// a complete installed profile wins before a complete backup.
  Future<MeasurementBundledTargetProfileV1?> recover({
    required Directory packageRoot,
  }) => _withPackageLock(packageRoot, _recover);

  Future<MeasurementBundledTargetProfileV1> _package({
    required _TargetProfileFiles files,
    required Directory packageRoot,
    required MeasurementBundledTargetProfilePackageRequest request,
    Map<String, String> expectedExistingBundleHashes = const <String, String>{},
  }) async {
    await _recover(files);
    if (request.finalizationEntries.isEmpty) {
      throw const MeasurementBundledTargetProfilePackagingException(
        'A target profile requires finalization entries.',
      );
    }
    if (request.selectedBundleFiles.isEmpty ||
        request.selectedBundleFiles.length >
            kMaximumMeasurementBundledTargetProfileBundleCount) {
      throw const MeasurementBundledTargetProfilePackagingException(
        'A target profile requires a bounded selected bundle closure.',
      );
    }

    final target = request
        .finalizationEntries
        .first
        .binding
        .completeMeasurementManifest
        .target;

    final registry = MeasurementPublicationBundledRegistryV1(
      target: target,
      entries: request.finalizationEntries,
    );
    final requiredArtifacts = _requiredArtifacts(request.finalizationEntries);
    final selectedBundles = await _readSelectedBundles(
      packageRoot: packageRoot,
      selectedBundleFiles: request.selectedBundleFiles,
    );
    _validateExpectedBundleHashes(
      expected: expectedExistingBundleHashes,
      selectedBundles: selectedBundles,
    );
    _validateSelectedBundleClosure(
      requiredArtifacts: requiredArtifacts,
      selectedBundles: selectedBundles,
    );

    final profile = MeasurementBundledTargetProfileV1(
      targetCanonicalBytes: target.canonicalBytes,
      registryCanonicalBytes: registry.canonicalBytes,
      bundles: <MeasurementBundledTargetProfileBundle>[
        for (final bundle in selectedBundles) bundle.profileBundle,
      ],
    );
    await _install(
      files,
      profile,
      revalidateSelectedBundles: () async {
        final refreshedBundles = await _readSelectedBundles(
          packageRoot: packageRoot,
          selectedBundleFiles: request.selectedBundleFiles,
        );
        _validateExpectedBundleHashes(
          expected: expectedExistingBundleHashes,
          selectedBundles: refreshedBundles,
        );
        _validateSelectedBundleSnapshot(
          expected: selectedBundles,
          actual: refreshedBundles,
        );
        _validateSelectedBundleClosure(
          requiredArtifacts: requiredArtifacts,
          selectedBundles: refreshedBundles,
        );
      },
    );
    return profile;
  }

  Future<MeasurementBundledTargetProfileV1> _packageFinalizedEntry({
    required _TargetProfileFiles files,
    required Directory packageRoot,
    required MeasurementPublicationBundledRegistryEntryV1 entry,
    required Iterable<File> selectedBundleFiles,
  }) async {
    final existingProfile = await _recover(files);
    final target = entry.binding.completeMeasurementManifest.target;
    final existingEntries = <MeasurementPublicationBundledRegistryEntryV1>[];
    final existingBundleFiles = <File>[];
    final expectedExistingBundleHashes = <String, String>{};

    if (existingProfile != null) {
      final existingTarget = _decodeProfileTarget(existingProfile);
      if (existingTarget != target) {
        throw const MeasurementBundledTargetProfilePackagingException(
          'The installed Measurement target profile names a different target.',
        );
      }
      final existingRegistry = _decodeProfileRegistry(existingProfile);
      if (existingRegistry.target != target) {
        throw const MeasurementBundledTargetProfilePackagingException(
          'The installed Measurement registry does not match its target.',
        );
      }
      existingEntries.addAll(existingRegistry.entries);
      for (final bundle in existingProfile.bundles) {
        existingBundleFiles.add(_profileBundleFile(packageRoot, bundle));
        expectedExistingBundleHashes[bundle.assetPath] = bundle.sha256;
      }
    }

    final mergedEntries = _mergeFinalizationEntries(existingEntries, entry);
    final mergedBundleFiles = await _deduplicateBundleFiles(<File>[
      ...existingBundleFiles,
      ...selectedBundleFiles,
    ]);
    return _package(
      files: files,
      packageRoot: packageRoot,
      request: MeasurementBundledTargetProfilePackageRequest(
        finalizationEntries: mergedEntries,
        selectedBundleFiles: mergedBundleFiles,
      ),
      expectedExistingBundleHashes: expectedExistingBundleHashes,
    );
  }

  Future<MeasurementBundledTargetProfileV1?> _recover(
    _TargetProfileFiles files,
  ) async {
    final expectedSha256 = await _readCanonicalJournal(files.journal);
    if (expectedSha256 == null) {
      return _recoverWithoutTrustedJournal(files);
    }

    final installed = await _readProfile(files.live);
    if (installed != null && installed.sha256 == expectedSha256) {
      await _cleanup(files);
      return installed.profile;
    }

    final backup = await _readProfile(files.backup);
    if (backup != null) {
      await _deleteIfExists(files.live);
      await files.backup.rename(files.live.path);
      await _deleteIfExists(files.stage);
      await _deleteIfExists(files.journal);
      return backup.profile;
    }

    if (installed != null) {
      await _deleteIfExists(files.stage);
      await _deleteIfExists(files.journal);
      return installed.profile;
    }

    final staged = await _readProfile(files.stage);
    if (staged != null && staged.sha256 == expectedSha256) {
      await _deleteIfExists(files.live);
      await files.stage.rename(files.live.path);
      await _deleteIfExists(files.backup);
      await _deleteIfExists(files.journal);
      return staged.profile;
    }

    throw const MeasurementBundledTargetProfilePackagingException(
      'No complete Measurement target profile is available for recovery.',
    );
  }

  Future<MeasurementBundledTargetProfileV1?> _recoverWithoutTrustedJournal(
    _TargetProfileFiles files,
  ) async {
    final installed = await _readProfile(files.live);
    if (installed != null) {
      await _cleanup(files);
      return installed.profile;
    }

    final backup = await _readProfile(files.backup);
    if (backup != null) {
      await _deleteIfExists(files.live);
      await files.backup.rename(files.live.path);
      await _deleteIfExists(files.stage);
      await _deleteIfExists(files.journal);
      return backup.profile;
    }

    await _deleteIfExists(files.stage);
    await _deleteIfExists(files.journal);
    if (await files.live.exists()) {
      throw const MeasurementBundledTargetProfilePackagingException(
        'The installed Measurement target profile is not canonical.',
      );
    }
    await _deleteIfExists(files.backup);
    return null;
  }

  Future<void> _install(
    _TargetProfileFiles files,
    MeasurementBundledTargetProfileV1 profile, {
    required Future<void> Function() revalidateSelectedBundles,
  }) async {
    await files.live.parent.create(recursive: true);
    await _deleteIfExists(files.stage);
    await _deleteIfExists(files.backup);
    await _deleteIfExists(files.journal);

    final bytes = profile.canonicalBytes;
    await files.stage.writeAsBytes(bytes, flush: true);
    await _checkpoint(
      MeasurementBundledTargetProfileCrashPoint.afterStageWrite,
    );

    final expectedSha256 = _sha256(bytes);
    await files.journal.writeAsString(
      _encodeJournal(expectedSha256),
      flush: true,
    );
    await _checkpoint(
      MeasurementBundledTargetProfileCrashPoint.afterJournalWrite,
    );
    try {
      await revalidateSelectedBundles();
    } on Object {
      await _deleteIfExists(files.stage);
      await _deleteIfExists(files.journal);
      rethrow;
    }

    if (await files.live.exists()) {
      await files.live.rename(files.backup.path);
    }
    await _checkpoint(
      MeasurementBundledTargetProfileCrashPoint.afterBackupMove,
    );

    await files.stage.rename(files.live.path);
    await _checkpoint(
      MeasurementBundledTargetProfileCrashPoint.afterInstallMove,
    );

    final installed = await _readProfile(files.live);
    if (installed == null || installed.sha256 != expectedSha256) {
      throw const MeasurementBundledTargetProfilePackagingException(
        'The installed Measurement target profile did not verify.',
      );
    }
    await _cleanup(files);
  }

  Future<void> _checkpoint(
    MeasurementBundledTargetProfileCrashPoint point,
  ) async {
    await _onCrashPoint?.call(point);
  }
}

final Map<String, Future<void>> _inProcessPackageLocks =
    <String, Future<void>>{};

Future<T> _withPackageLock<T>(
  Directory packageRoot,
  Future<T> Function(_TargetProfileFiles files) action,
) async {
  final files = await _profileFiles(packageRoot);
  return _withInProcessPackageLock(files.lock.path, () async {
    await files.lock.parent.create(recursive: true);
    final handle = await files.lock.open(mode: FileMode.append);
    var locked = false;
    try {
      await handle.lock(FileLock.blockingExclusive);
      locked = true;
      return await action(files);
    } finally {
      if (locked) {
        try {
          await handle.unlock();
        } finally {
          await handle.close();
        }
      } else {
        await handle.close();
      }
    }
  });
}

Future<T> _withInProcessPackageLock<T>(
  String key,
  Future<T> Function() action,
) async {
  final predecessor = _inProcessPackageLocks[key];
  final completion = Completer<void>();
  _inProcessPackageLocks[key] = completion.future;
  if (predecessor != null) await predecessor;
  try {
    return await action();
  } finally {
    completion.complete();
    if (identical(_inProcessPackageLocks[key], completion.future)) {
      _inProcessPackageLocks.remove(key);
    }
  }
}

Future<List<_SelectedBundle>> _readSelectedBundles({
  required Directory packageRoot,
  required Iterable<File> selectedBundleFiles,
}) async {
  final root = p.normalize(await packageRoot.resolveSymbolicLinks());
  final bundles = <_SelectedBundle>[];
  final selectedPaths = <String>{};
  for (final bundleFile in selectedBundleFiles) {
    final resolved = await _resolveSelectedBundle(bundleFile);
    final relative = p.relative(resolved.path, from: root);
    if (relative == '..' || relative.startsWith('..${p.separator}')) {
      throw const MeasurementBundledTargetProfilePackagingException(
        'A selected bundle escapes its package root.',
      );
    }
    final assetPath = p.posix.joinAll(p.split(relative));
    final bytes = await _readBoundedFileBytes(
      resolved,
      maximumBytes: kRestageBundleMaxClassicZipValue,
      failureMessage:
          'Selected bundle "$assetPath" exceeds the classic-ZIP '
          'byte bound or changed while it was read.',
    );
    final RestageBundle bundle;
    try {
      bundle = RestageBundleCodec.decode(bytes);
    } on Object {
      throw MeasurementBundledTargetProfilePackagingException(
        'Selected bundle "$assetPath" is not a valid .rsbundle.',
      );
    }
    final MeasurementBundledTargetProfileBundle profileBundle;
    try {
      profileBundle = MeasurementBundledTargetProfileBundle(
        assetPath: assetPath,
        sha256: _sha256(bytes),
      );
    } on Object {
      throw MeasurementBundledTargetProfilePackagingException(
        'Selected bundle "$assetPath" is not in the source-owned asset '
        'profile.',
      );
    }
    if (!selectedPaths.add(profileBundle.assetPath)) {
      throw const MeasurementBundledTargetProfilePackagingException(
        'The selected bundle closure repeats one physical asset path.',
      );
    }
    bundles.add(_SelectedBundle(profileBundle: profileBundle, bundle: bundle));
  }
  return List.unmodifiable(bundles);
}

Future<File> _resolveSelectedBundle(File bundleFile) async {
  try {
    return File(await bundleFile.resolveSymbolicLinks());
  } on FileSystemException {
    throw const MeasurementBundledTargetProfilePackagingException(
      'A selected bundle file could not be resolved.',
    );
  }
}

Map<String, _RequiredDeliveryArtifact> _requiredArtifacts(
  Iterable<MeasurementPublicationBundledRegistryEntryV1> entries,
) {
  final required = <String, _RequiredDeliveryArtifact>{};
  for (final entry in entries) {
    _verifyDeclaredArtifactTupleDigest(entry);
    for (final tuple in entry.candidateProof.declaredArtifactTuples) {
      final artifact = _requiredArtifactFromTuple(tuple);
      final existing = required[artifact.path];
      if (existing != null && !existing.sameAs(artifact)) {
        throw const MeasurementBundledTargetProfilePackagingException(
          'Finalization entries have conflicting declared artifacts.',
        );
      }
      required[artifact.path] = artifact;
    }
  }
  if (required.isEmpty) {
    throw const MeasurementBundledTargetProfilePackagingException(
      'Finalization entries have no declared delivery artifacts.',
    );
  }
  return required;
}

void _verifyDeclaredArtifactTupleDigest(
  MeasurementPublicationBundledRegistryEntryV1 entry,
) {
  final tuples =
      List<MeasurementPublicationCandidateArtifactTupleV1>.of(
        entry.candidateProof.declaredArtifactTuples,
      )..sort(
        (left, right) =>
            _compareBytes(left.canonicalTupleBytes, right.canonicalTupleBytes),
      );
  final tupleObjects = <Object?>[];
  try {
    for (final tuple in tuples) {
      tupleObjects.add(CanonicalJsonCodec.decode(tuple.canonicalTupleBytes));
    }
  } on Object {
    throw const MeasurementBundledTargetProfilePackagingException(
      'A finalization entry has invalid canonical artifact tuples.',
    );
  }
  final preimage = BytesBuilder(copy: false)
    ..add(
      utf8.encode(
        'restage-surface-publication-declared-artifact-bytes-v1\u0000',
      ),
    )
    ..add(
      CanonicalJsonCodec.encode(<String, Object?>{
        'kind': 'restageSurfacePublicationDeclaredArtifactBytes',
        'schemaVersion': 1,
        'tuples': tupleObjects,
      }),
    );
  final recomputedDigest = crypto.sha256
      .convert(preimage.takeBytes())
      .toString();
  final authority = entry.reference.publicationAuthorityReference;
  if (recomputedDigest !=
          entry.candidateProof.declaredArtifactBytesDigest.hex ||
      recomputedDigest !=
          entry.candidateProof.reference.declaredArtifactBytesDigest.hex ||
      recomputedDigest != entry.declaredArtifactBytesDigest.hex ||
      recomputedDigest != authority.declaredArtifactBytesDigest.hex) {
    throw const MeasurementBundledTargetProfilePackagingException(
      'A finalization entry does not prove its declared artifact closure.',
    );
  }
}

int _compareBytes(List<int> left, List<int> right) {
  final sharedLength = left.length < right.length ? left.length : right.length;
  for (var index = 0; index < sharedLength; index += 1) {
    final comparison = left[index].compareTo(right[index]);
    if (comparison != 0) return comparison;
  }
  return left.length.compareTo(right.length);
}

bool _sameBytes(List<int> left, List<int> right) =>
    _compareBytes(left, right) == 0;

_RequiredDeliveryArtifact _requiredArtifactFromTuple(
  MeasurementPublicationCandidateArtifactTupleV1 tuple,
) {
  try {
    final decoded = CanonicalJsonCodec.decode(tuple.canonicalTupleBytes);
    if (decoded is! Map) throw const FormatException('tuple is not an object');
    final json = <String, Object?>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException('tuple key is not a string');
      }
      json[entry.key as String] = entry.value;
    }
    if (json['kind'] != 'restageSurfacePublicationDeclaredArtifactTuple' ||
        json['schemaVersion'] != 1) {
      throw const FormatException('unsupported tuple kind');
    }
    final roleValue = json['role'];
    if (roleValue is! String) throw const FormatException('missing tuple role');
    final manifestRole = SurfacePublicationArtifactRole.fromWireName(roleValue);
    final expectedKeys = <String>{
      'byteLength',
      'kind',
      'path',
      'role',
      'schemaVersion',
      'sha256',
    };
    if (manifestRole != SurfacePublicationArtifactRole.flowDocument) {
      expectedKeys.add('id');
    }
    if (json.length != expectedKeys.length ||
        !json.keys.toSet().containsAll(expectedKeys)) {
      throw const FormatException('tuple fields do not match its role');
    }
    final path = json['path'];
    final byteLength = json['byteLength'];
    final sha256 = json['sha256'];
    if (path is! String ||
        byteLength is! int ||
        byteLength < 0 ||
        sha256 is! String) {
      throw const FormatException('tuple fields are invalid');
    }
    final artifact = SurfacePublicationArtifact(
      contentHash: 'sha256:$sha256',
      path: path,
      role: manifestRole,
      id: switch (manifestRole) {
        SurfacePublicationArtifactRole.flowDocument => null,
        _ => json['id'] as String?,
      },
    );
    return _RequiredDeliveryArtifact(
      path: artifact.path,
      role: RestageBundleEntryRole.fromManifestRole(artifact.role),
      byteLength: byteLength,
      sha256: artifact.contentHash,
    );
  } on Object {
    throw const MeasurementBundledTargetProfilePackagingException(
      'A finalization entry has an invalid declared artifact tuple.',
    );
  }
}

void _validateSelectedBundleClosure({
  required Map<String, _RequiredDeliveryArtifact> requiredArtifacts,
  required Iterable<_SelectedBundle> selectedBundles,
}) {
  final selectedArtifacts = <String, _SelectedDeliveryArtifact>{};
  for (final selectedBundle in selectedBundles) {
    for (final entry in selectedBundle.bundle.entries) {
      if (entry.role == RestageBundleEntryRole.rfwText) continue;
      final artifact = _SelectedDeliveryArtifact.fromEntry(entry);
      final existing = selectedArtifacts[artifact.path];
      if (existing != null && !existing.sameAs(artifact)) {
        throw const MeasurementBundledTargetProfilePackagingException(
          'The selected bundle closure has conflicting delivery artifacts.',
        );
      }
      selectedArtifacts[artifact.path] = artifact;
    }
  }
  for (final required in requiredArtifacts.values) {
    final selected = selectedArtifacts[required.path];
    if (selected == null || !required.matches(selected)) {
      throw const MeasurementBundledTargetProfilePackagingException(
        'The selected bundle closure omits a required delivery artifact.',
      );
    }
  }
}

void _validateSelectedBundleSnapshot({
  required Iterable<_SelectedBundle> expected,
  required Iterable<_SelectedBundle> actual,
}) {
  final expectedByPath = <String, MeasurementBundledTargetProfileBundle>{
    for (final bundle in expected)
      bundle.profileBundle.assetPath: bundle.profileBundle,
  };
  final actualByPath = <String, MeasurementBundledTargetProfileBundle>{
    for (final bundle in actual)
      bundle.profileBundle.assetPath: bundle.profileBundle,
  };
  if (expectedByPath.length != actualByPath.length) {
    throw const MeasurementBundledTargetProfilePackagingException(
      'A selected bundle changed during target-profile packaging.',
    );
  }
  for (final entry in expectedByPath.entries) {
    if (actualByPath[entry.key]?.sha256 != entry.value.sha256) {
      throw const MeasurementBundledTargetProfilePackagingException(
        'A selected bundle changed during target-profile packaging.',
      );
    }
  }
}

void _validateExpectedBundleHashes({
  required Map<String, String> expected,
  required Iterable<_SelectedBundle> selectedBundles,
}) {
  if (expected.isEmpty) return;
  final actual = <String, String>{
    for (final bundle in selectedBundles)
      bundle.profileBundle.assetPath: bundle.profileBundle.sha256,
  };
  for (final entry in expected.entries) {
    if (actual[entry.key] != entry.value) {
      throw const MeasurementBundledTargetProfilePackagingException(
        'A previously packaged bundle no longer matches its target profile.',
      );
    }
  }
}

TargetCoordinate _decodeProfileTarget(
  MeasurementBundledTargetProfileV1 profile,
) {
  try {
    return TargetCoordinate.fromCanonicalBytes(profile.targetCanonicalBytes);
  } on Object {
    throw const MeasurementBundledTargetProfilePackagingException(
      'The installed Measurement target profile has invalid target bytes.',
    );
  }
}

MeasurementPublicationBundledRegistryV1 _decodeProfileRegistry(
  MeasurementBundledTargetProfileV1 profile,
) {
  try {
    return MeasurementPublicationBundledRegistryV1.fromCanonicalBytes(
      profile.registryCanonicalBytes,
    );
  } on Object {
    throw const MeasurementBundledTargetProfilePackagingException(
      'The installed Measurement target profile has invalid registry bytes.',
    );
  }
}

File _profileBundleFile(
  Directory packageRoot,
  MeasurementBundledTargetProfileBundle bundle,
) => File(
  p.join(packageRoot.absolute.path, p.joinAll(p.posix.split(bundle.assetPath))),
);

List<MeasurementPublicationBundledRegistryEntryV1> _mergeFinalizationEntries(
  Iterable<MeasurementPublicationBundledRegistryEntryV1> existing,
  MeasurementPublicationBundledRegistryEntryV1 entry,
) {
  final merged = <MeasurementPublicationBundledRegistryEntryV1>[];
  for (final prior in existing) {
    if (prior.reference == entry.reference) {
      if (!_sameBytes(prior.canonicalBytes, entry.canonicalBytes)) {
        throw const MeasurementBundledTargetProfilePackagingException(
          'The committed final entry conflicts with an installed exact entry.',
        );
      }
      return List<MeasurementPublicationBundledRegistryEntryV1>.unmodifiable(
        existing,
      );
    }
    merged.add(prior);
  }
  merged.add(entry);
  return List<MeasurementPublicationBundledRegistryEntryV1>.unmodifiable(
    merged,
  );
}

Future<List<File>> _deduplicateBundleFiles(Iterable<File> files) async {
  final unique = <String, File>{};
  for (final file in files) {
    final resolved = await _resolveSelectedBundle(file);
    unique.putIfAbsent(p.normalize(resolved.path), () => resolved);
  }
  return List<File>.unmodifiable(unique.values);
}

Future<_TargetProfileFiles> _profileFiles(Directory packageRoot) async {
  final root = await packageRoot.resolveSymbolicLinks();
  final live = File(p.join(root, kMeasurementBundledTargetProfileAssetPath));
  return _TargetProfileFiles(
    live: live,
    stage: File('${live.path}.stage'),
    backup: File('${live.path}.backup'),
    journal: File('${live.path}.transaction'),
    lock: File(p.join(root, '.restage', 'measurement-target-profile.v1.lock')),
  );
}

// `{"expectedProfileSha256":"sha256:<64 lowercase hex>","schemaVersion":1}`.
const int _kTargetProfileJournalCanonicalBytes = 117;

Future<_ProfileSnapshot?> _readProfile(File file) async {
  if (!await file.exists()) return null;
  try {
    final bytes = await _readBoundedFileBytes(
      file,
      maximumBytes: kMaximumMeasurementBundledTargetProfileAssetBytes,
      failureMessage:
          'Measurement target profile exceeds its raw byte bound '
          'or changed while it was read.',
    );
    final profile = MeasurementBundledTargetProfileV1.fromCanonicalBytes(bytes);
    return _ProfileSnapshot(profile: profile, sha256: _sha256(bytes));
  } on Object {
    return null;
  }
}

Future<String?> _readCanonicalJournal(File journal) async {
  if (!await journal.exists()) return null;
  try {
    final bytes = await _readBoundedFileBytes(
      journal,
      maximumBytes: _kTargetProfileJournalCanonicalBytes,
      failureMessage: 'Measurement target-profile recovery journal is invalid.',
    );
    if (bytes.length != _kTargetProfileJournalCanonicalBytes) return null;
    final source = utf8.decode(bytes, allowMalformed: false);
    final value = jsonDecode(source);
    if (value is! Map<Object?, Object?> ||
        value.length != 2 ||
        value['schemaVersion'] != 1 ||
        value['expectedProfileSha256'] is! String) {
      return null;
    }
    final expectedSha256 = value['expectedProfileSha256']! as String;
    if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(expectedSha256) ||
        source != _encodeJournal(expectedSha256)) {
      return null;
    }
    return expectedSha256;
  } on Object {
    return null;
  }
}

Future<Uint8List> _readBoundedFileBytes(
  File file, {
  required int maximumBytes,
  required String failureMessage,
}) async {
  final FileStat before;
  try {
    before = await file.stat();
  } on FileSystemException {
    throw MeasurementBundledTargetProfilePackagingException(failureMessage);
  }
  if (before.type != FileSystemEntityType.file ||
      before.size < 0 ||
      before.size > maximumBytes) {
    throw MeasurementBundledTargetProfilePackagingException(failureMessage);
  }

  RandomAccessFile? handle;
  try {
    handle = await file.open(mode: FileMode.read);
    final bytes = await handle.read(before.size);
    if (bytes.length != before.size || await handle.length() != before.size) {
      throw MeasurementBundledTargetProfilePackagingException(failureMessage);
    }
    return bytes;
  } on MeasurementBundledTargetProfilePackagingException {
    rethrow;
  } on FileSystemException {
    throw MeasurementBundledTargetProfilePackagingException(failureMessage);
  } finally {
    await handle?.close();
  }
}

Future<void> _cleanup(_TargetProfileFiles files) async {
  await _deleteIfExists(files.stage);
  await _deleteIfExists(files.backup);
  await _deleteIfExists(files.journal);
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) await file.delete();
}

String _sha256(List<int> bytes) => 'sha256:${crypto.sha256.convert(bytes)}';

String _encodeJournal(String expectedSha256) =>
    '{"expectedProfileSha256":"$expectedSha256","schemaVersion":1}';

final class _SelectedBundle {
  const _SelectedBundle({required this.profileBundle, required this.bundle});

  final MeasurementBundledTargetProfileBundle profileBundle;
  final RestageBundle bundle;
}

final class _ProfileSnapshot {
  const _ProfileSnapshot({required this.profile, required this.sha256});

  final MeasurementBundledTargetProfileV1 profile;
  final String sha256;
}

final class _RequiredDeliveryArtifact {
  const _RequiredDeliveryArtifact({
    required this.path,
    required this.role,
    required this.byteLength,
    required this.sha256,
  });

  final String path;
  final RestageBundleEntryRole role;
  final int byteLength;
  final String sha256;

  bool sameAs(_RequiredDeliveryArtifact other) =>
      path == other.path &&
      role == other.role &&
      byteLength == other.byteLength &&
      sha256 == other.sha256;

  bool matches(_SelectedDeliveryArtifact other) =>
      role == other.role &&
      byteLength == other.byteLength &&
      sha256 == other.sha256;
}

final class _SelectedDeliveryArtifact {
  const _SelectedDeliveryArtifact({
    required this.path,
    required this.role,
    required this.byteLength,
    required this.sha256,
  });

  factory _SelectedDeliveryArtifact.fromEntry(RestageBundleEntry entry) =>
      _SelectedDeliveryArtifact(
        path: entry.logicalPath,
        role: entry.role,
        byteLength: entry.byteLength,
        sha256: entry.sha256,
      );

  final String path;
  final RestageBundleEntryRole role;
  final int byteLength;
  final String sha256;

  bool sameAs(_SelectedDeliveryArtifact other) =>
      path == other.path &&
      role == other.role &&
      byteLength == other.byteLength &&
      sha256 == other.sha256;
}

final class _TargetProfileFiles {
  const _TargetProfileFiles({
    required this.live,
    required this.stage,
    required this.backup,
    required this.journal,
    required this.lock,
  });

  final File live;
  final File stage;
  final File backup;
  final File journal;
  final File lock;
}
