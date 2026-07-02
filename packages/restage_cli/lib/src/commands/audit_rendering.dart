import 'dart:convert';

import 'package:restage_cli/src/api/surface_models.dart';

/// Render audit timeline rows as JSON.
void writeAuditLogJson(StringSink stdout, List<SurfaceAuditLogEntry> rows) {
  stdout.writeln(jsonEncode([for (final row in rows) row.toJson()]));
}

/// Render audit timeline rows as a tab-separated table.
void writeAuditLogTable(StringSink stdout, List<SurfaceAuditLogEntry> rows) {
  stdout.writeln('WHEN\tACTION\tACTOR\tOUTCOME\tCHAIN\tREASON');
  for (final row in rows) {
    stdout.writeln(
      '${_iso(row.occurredAt)}\t${row.action}\t${row.actorEmail ?? row.actorType}'
      '\t${row.outcome}\t${auditChainLabel(row)}\t${row.reason ?? '-'}',
    );
  }
}

/// Render export rows as JSON.
void writeComplianceExportJson(
  StringSink stdout,
  List<SurfaceComplianceExportRow> rows,
) {
  stdout.writeln(jsonEncode([for (final row in rows) row.toJson()]));
}

/// Render export rows as RFC-4180-style CSV.
void writeComplianceExportCsv(
  StringSink stdout,
  List<SurfaceComplianceExportRow> rows,
) {
  stdout.writeln(
    'occurredAt,action,surfaceType,surfaceSlug,environmentSlug,version,'
    'actorEmail,reason,chainState,chainVerified,entryId',
  );
  for (final row in rows) {
    stdout.writeln(
      [
        _iso(row.occurredAt),
        row.action,
        row.surfaceType,
        row.surfaceSlug,
        row.environmentSlug,
        row.version?.toString(),
        row.actorEmail,
        row.reason,
        row.chainState,
        row.chainVerified.toString(),
        row.entryId?.toString(),
      ].map(_csvCell).join(','),
    );
  }
}

/// Render a chain verdict as JSON.
void writeVerdictJson(StringSink stdout, SurfaceChainVerdictResult verdict) {
  stdout.writeln(jsonEncode(verdict.toJson()));
}

/// Render a chain verdict as human-readable lines.
void writeVerdictText(StringSink stdout, SurfaceChainVerdictResult verdict) {
  stdout.writeln('status: ${verdict.status}');
  if (verdict.verifiedThroughEntryId != null) {
    stdout.writeln('verified through entry: ${verdict.verifiedThroughEntryId}');
  }
  if (verdict.verifiedThroughOccurredAt != null) {
    stdout.writeln(
      'verified through time: ${_iso(verdict.verifiedThroughOccurredAt!)}',
    );
  }
  if (verdict.failedEntryId != null) {
    stdout.writeln('failed entry: ${verdict.failedEntryId}');
  }
  if (verdict.failedCheck != null) {
    stdout.writeln('failed check: ${verdict.failedCheck}');
  }
  if (verdict.lastRunAt != null) {
    stdout.writeln('last run: ${_iso(verdict.lastRunAt!)}');
  }
}

/// User-facing chain label for timeline rows.
String auditChainLabel(SurfaceAuditLogEntry row) {
  if (row.chainState == 'pendingChain') return 'pending';
  return row.chainVerified ? 'verified' : 'unverified';
}

String _csvCell(String? value) {
  final raw = value ?? '';
  if (!raw.contains(',') &&
      !raw.contains('"') &&
      !raw.contains('\n') &&
      !raw.contains('\r')) {
    return raw;
  }
  return '"${raw.replaceAll('"', '""')}"';
}

String _iso(DateTime value) => value.toUtc().toIso8601String();
