import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/audit_rendering.dart';
import 'package:restage_cli/src/commands/audit_support.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';

/// Parent for organization-scoped audit reads.
class AuditCommand extends Command<int> {
  /// Construct the audit command group.
  AuditCommand({
    required StringSink stdout,
    required StringSink stderr,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) {
    addSubcommand(
      _AuditLogCommand(
        stdout: stdout,
        stderr: stderr,
        credentialStore: credentialStore,
        httpClient: httpClient,
      ),
    );
    addSubcommand(
      _AuditExportCommand(
        stdout: stdout,
        stderr: stderr,
        credentialStore: credentialStore,
        httpClient: httpClient,
      ),
    );
    addSubcommand(
      _AuditVerdictCommand(
        stdout: stdout,
        stderr: stderr,
        credentialStore: credentialStore,
        httpClient: httpClient,
      ),
    );
  }

  @override
  String get name => 'audit';

  @override
  String get description => 'Read server audit logs and compliance exports.';
}

abstract class _AuditReadCommand extends Command<int> {
  _AuditReadCommand({
    required StringSink stdout,
    required StringSink stderr,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _stdout = stdout,
       _stderr = stderr,
       _credentialStore = credentialStore,
       _httpClient = httpClient {
    addAuditContextOptions(argParser);
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Emit JSON instead of the default human-readable output.',
    );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  bool get emitJson => argResults?['json'] as bool? ?? false;

  Future<int> withAuditApi(
    Future<int> Function(SurfaceApi api, AuditContext context) run,
  ) async {
    final context = await loadAuditContext(
      argResults: argResults,
      stderr: _stderr,
      credentialStore: _credentialStore,
      httpClient: _httpClient,
    );
    if (context == null) return 1;

    final RestageApi api;
    try {
      api = RestageApi(
        endpoint: context.apiEndpoint,
        httpClient: _httpClient,
        credential: context.credential,
      );
    } on InsecureEndpointException catch (e) {
      _stderr.writeln(e.toString());
      return 1;
    }

    try {
      return await run(SurfaceApi(api), context);
    } on RestageApiException catch (e) {
      return _renderError(e);
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  int _renderError(RestageApiException e) {
    final outcome = renderGenericTypedError(e);
    if (outcome != null) {
      _stderr.writeln(outcome.message);
      return outcome.exitCode;
    }
    _stderr.writeln(e.toString());
    return 1;
  }
}

class _AuditLogCommand extends _AuditReadCommand {
  _AuditLogCommand({
    required super.stdout,
    required super.stderr,
    super.credentialStore,
    super.httpClient,
  });

  @override
  String get name => 'log';

  @override
  String get description => 'Show the organization server audit log.';

  @override
  Future<int> run() {
    return withAuditApi((api, context) async {
      final rows = await api.listAuditLog(
        organizationId: context.organizationId,
      );
      if (emitJson) {
        writeAuditLogJson(_stdout, rows);
      } else {
        writeAuditLogTable(_stdout, rows);
      }
      return 0;
    });
  }
}

class _AuditExportCommand extends _AuditReadCommand {
  _AuditExportCommand({
    required super.stdout,
    required super.stderr,
    super.credentialStore,
    super.httpClient,
  });

  @override
  String get name => 'export';

  @override
  String get description => 'Export compliance audit rows as CSV.';

  @override
  Future<int> run() {
    return withAuditApi((api, context) async {
      final rows = await api.exportComplianceAudit(
        organizationId: context.organizationId,
      );
      if (emitJson) {
        writeComplianceExportJson(_stdout, rows);
      } else {
        writeComplianceExportCsv(_stdout, rows);
      }
      return 0;
    });
  }
}

class _AuditVerdictCommand extends _AuditReadCommand {
  _AuditVerdictCommand({
    required super.stdout,
    required super.stderr,
    super.credentialStore,
    super.httpClient,
  });

  @override
  String get name => 'verdict';

  @override
  String get description => 'Show the surface audit chain verdict.';

  @override
  Future<int> run() {
    return withAuditApi((api, context) async {
      final verdict = await api.surfaceChainVerdict(
        organizationId: context.organizationId,
      );
      if (emitJson) {
        writeVerdictJson(_stdout, verdict);
      } else {
        writeVerdictText(_stdout, verdict);
      }
      return 0;
    });
  }
}
