import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:build/build.dart';
import 'package:build_runner/src/build/resolver/analysis_driver_model.dart';
import 'package:build_runner/src/build/resolver/build_step_resolver.dart';
import 'package:build_runner/src/build/resolver/resolvers_impl.dart';
import 'package:build_runner/src/build/resolver/sdk_summary.dart';
import 'package:path/path.dart' as p;

// Shared by the test trees of this package, the widget catalog generator and
// the codegen package. Remove once build_runner writes the deps file
// atomically (2.17), which needs the analyzer 14 migration.

/// The resolvers every test build uses: [ensureSdkSummary] runs first.
class SummaryReadyResolvers extends ResolversImpl {
  /// Creates resolvers with a fresh analysis driver.
  SummaryReadyResolvers({super.packageConfig})
      : super(analysisDriverModel: AnalysisDriverModel());

  @override
  Future<BuildStepResolver> get(BuildStep buildStep) async {
    await ensureSdkSummary();
    return await super.get(buildStep);
  }
}

/// One shared instance per isolate, like build_test's default resolvers.
final Resolvers summaryReadyResolvers = SummaryReadyResolvers();

/// Makes the analyzer's SDK summary cache valid before this isolate resolves.
///
/// build_runner writes the cache's deps file non-atomically, so isolates that
/// build the cache at the same time can read it empty. One isolate builds it
/// while holding [sdkSummaryLockPath]. Every caller computes the same deps,
/// so once the cache is valid nothing rewrites it. A failure is retried on
/// the next call.
Future<void> ensureSdkSummary() => _sdkSummary ??= _ensureSdkSummary().then(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _sdkSummary = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );

Future<void>? _sdkSummary;

/// The lock file, created exclusively, that serializes summary builds.
final String sdkSummaryLockPath = p.join(
  '.dart_tool',
  'build_resolvers',
  'restage_test.lock',
);

/// A lock whose timestamp is older than this has no live heartbeat.
const Duration _staleAfter = Duration(minutes: 3);

/// How often a holder refreshes its lock's timestamp.
const Duration heartbeatEvery = Duration(seconds: 20);

/// How long a waiter waits before it says what it is waiting for.
const Duration _announceAfter = Duration(seconds: 2);

Future<void> _ensureSdkSummary() async {
  final lock = File(sdkSummaryLockPath);
  final owner = '$pid ${Isolate.current.hashCode} '
      '${DateTime.now().microsecondsSinceEpoch}';
  await _acquire(lock);
  Isolate? heartbeat;
  var ownerWritten = false;
  try {
    // A separate isolate, because the summary build can block this one.
    heartbeat = await Isolate.spawn(
      _heartbeat,
      (lock.path, owner, Isolate.current.controlPort),
    );
    // Written once the heartbeat runs, so an owned lock is always refreshed.
    lock.writeAsStringSync(owner, flush: true);
    ownerWritten = true;
    removeUndecodableDeps(File(p.join(lock.parent.path, 'sdk.sum.deps')));
    await defaultSdkSummaryGenerator();
  } finally {
    heartbeat?.kill(priority: Isolate.immediate);
    releaseLock(lock, ownerWritten ? owner : '');
  }
}

/// Refreshes a held lock's timestamp until its holder isolate exits, so the
/// age limit only breaks locks whose holder stopped.
void _heartbeat((String, String, SendPort) held) {
  final (path, owner, holderControl) = held;
  final holder = Isolate(holderControl);
  final holderExited = ReceivePort();
  final alive = ReceivePort();
  late final Timer beats;
  late Timer noReply;
  var missed = 0;
  var answered = false;
  void stop() {
    beats.cancel();
    noReply.cancel();
    holderExited.close();
    alive.close();
  }

  // Exit listeners are not sent for an isolate that is already dead, so two
  // pings in a row unanswered within 10 s also stop the heartbeat.
  void ping() {
    answered = false;
    noReply = Timer(const Duration(seconds: 10), () {
      if (++missed >= 2) stop();
    });
    holder.ping(alive.sendPort);
  }

  holder.addOnExitListener(holderExited.sendPort);
  holderExited.listen((_) => stop());
  alive.listen((_) {
    noReply.cancel();
    missed = 0;
    answered = true;
  });
  ping();
  beats = Timer.periodic(heartbeatEvery, (_) {
    // Refreshes only for a holder that answered the last ping.
    final holderAnswered = answered;
    ping();
    if (!holderAnswered) return;
    final lock = File(path);
    if (_readOwner(lock) != owner) return;
    try {
      lock.setLastModifiedSync(DateTime.now());
    } on FileSystemException {
      // Released or broken meanwhile.
    }
  });
}

/// Deletes [deps] when its bytes are not UTF-8 JSON: build_runner throws on
/// deps it cannot decode and rebuilds when they are absent.
void removeUndecodableDeps(File deps) {
  try {
    // Decoded here, because readAsStringSync reports malformed UTF-8 as a
    // FileSystemException.
    jsonDecode(utf8.decode(deps.readAsBytesSync()));
  } on PathNotFoundException {
    return;
  } on FormatException {
    try {
      deps.deleteSync();
    } on PathNotFoundException {
      // Already gone.
    }
  }
}

Future<void> _acquire(File lock) async {
  final waitingSince = DateTime.now();
  var announced = false;
  while (true) {
    lock.parent.createSync(recursive: true);
    try {
      await lock.create(exclusive: true);
      return;
    } on PathExistsException {
      final holder = _readOwner(lock);
      if (holder == null) continue;
      if (_isStale(lock, holder)) {
        _breakStale(lock, holder);
        continue;
      }
      if (!announced &&
          DateTime.now().difference(waitingSince) > _announceAfter) {
        announced = true;
        stderr.writeln('waiting for the analyzer SDK summary lock held by pid '
            '${holder.split(' ').first} (${lock.absolute.path})');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

/// The lock's owner line (empty until the holder writes it), or null when
/// the lock is gone.
String? _readOwner(File lock) {
  try {
    return lock.readAsStringSync();
  } on PathNotFoundException {
    return null;
  }
}

bool _isStale(File lock, String holder) {
  final holderPid = int.tryParse(holder.split(' ').first);
  // Only Linux exposes /proc; elsewhere, and for this process's own
  // isolates, the heartbeat age alone applies.
  if (holderPid != null &&
      holderPid != pid &&
      Directory('/proc').existsSync() &&
      !Directory('/proc/$holderPid').existsSync()) {
    return true;
  }
  final stat = lock.statSync();
  return stat.type != FileSystemEntityType.notFound &&
      DateTime.now().difference(stat.modified) > _staleAfter;
}

/// Moves the lock aside before deleting it, so two waiters breaking the same
/// stale lock cannot delete a fresh one.
void _breakStale(File lock, String holder) {
  final aside =
      File('${lock.path}.$pid.${DateTime.now().microsecondsSinceEpoch}');
  try {
    lock.renameSync(aside.path);
  } on PathNotFoundException {
    return;
  }
  if (aside.readAsStringSync() != holder && !lock.existsSync()) {
    // Took a fresh lock by mistake; put it back.
    aside.renameSync(lock.path);
    return;
  }
  aside.deleteSync();
}

/// Deletes [lock] when it still holds [owner]; an empty [owner] releases a
/// lock created but never written to.
void releaseLock(File lock, String owner) {
  if (_readOwner(lock) == owner) {
    try {
      lock.deleteSync();
    } on PathNotFoundException {
      // Broken as stale by a waiter.
    }
  }
}

/// Calls to build_test's resolving entry points under [dir] whose
/// `resolvers:` is not a [SummaryReadyResolvers], as `path:line`.
List<String> callsWithoutResolvers(Directory dir) {
  final offenders = <String>[];
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = entity.readAsStringSync();
    final unit = parseString(content: source, throwIfDiagnostics: false).unit;
    final visitor = _BuildCalls();
    unit.accept(visitor);
    for (final offset in visitor.unguarded) {
      final line = unit.lineInfo.getLocation(offset).lineNumber;
      offenders.add('${p.normalize(entity.path)}:$line');
    }
  }
  return offenders;
}

final class _BuildCalls extends RecursiveAstVisitor<void> {
  final unguarded = <int>[];

  static const _entryPoints = {
    'testBuilder',
    'testBuilders',
    'testBuilderFactories',
    'resolveSource',
    'resolveSources',
    'resolveAsset',
  };

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_entryPoints.contains(node.methodName.name) &&
        !node.argumentList.arguments.any(_namesSummaryReadyResolvers)) {
      unguarded.add(node.offset);
    }
    super.visitMethodInvocation(node);
  }

  static bool _namesSummaryReadyResolvers(Argument argument) {
    if (argument is! NamedArgument || argument.name.lexeme != 'resolvers') {
      return false;
    }
    final value = argument.argumentExpression;
    if (value is SimpleIdentifier) return value.name == 'summaryReadyResolvers';
    if (value is MethodInvocation) {
      return value.target == null &&
          value.methodName.name == 'SummaryReadyResolvers';
    }
    if (value is InstanceCreationExpression) {
      return value.constructorName.type.name.lexeme == 'SummaryReadyResolvers';
    }
    return false;
  }
}
