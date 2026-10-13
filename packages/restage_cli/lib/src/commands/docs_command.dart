import 'dart:convert';
import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/docs/docs_search.dart';

/// `restage docs`: search and read the published documentation.
class DocsCommand extends Command<int> {
  /// Construct the command group.
  DocsCommand({
    required StringSink stdout,
    required StringSink stderr,
    http.Client? httpClient,
    Map<String, String>? environment,
  }) {
    addSubcommand(
      DocsSearchCommand(
        stdout: stdout,
        stderr: stderr,
        httpClient: httpClient,
        environment: environment,
      ),
    );
    addSubcommand(
      DocsReadCommand(
        stdout: stdout,
        stderr: stderr,
        httpClient: httpClient,
        environment: environment,
      ),
    );
  }

  @override
  String get name => 'docs';

  @override
  String get description => 'Search and read the Restage documentation.';
}

abstract class _DocsLeaf extends Command<int> {
  _DocsLeaf({
    required this.stdout,
    required this.stderr,
    required this.httpClient,
    required this.environment,
  });

  final StringSink stdout;
  final StringSink stderr;
  final http.Client? httpClient;
  final Map<String, String>? environment;

  Future<int> withClient(Future<int> Function(DocsClient docs) body) async {
    final DocsClient docs;
    try {
      docs = DocsClient.fromEnvironment(
        environment ?? io.Platform.environment,
        httpClient: httpClient,
      );
    } on DocsException catch (error) {
      stderr.writeln(error.message);
      return 1;
    }
    try {
      return await body(docs);
    } on DocsException catch (error) {
      stderr.writeln(error.message);
      return 1;
    } finally {
      docs.close();
    }
  }
}

/// `restage docs search <query>`.
class DocsSearchCommand extends _DocsLeaf {
  /// Construct the command.
  DocsSearchCommand({
    required super.stdout,
    required super.stderr,
    super.httpClient,
    super.environment,
  }) {
    argParser
      ..addOption('limit', defaultsTo: '8', help: 'The most sections to list.')
      ..addFlag('json', negatable: false, help: 'Print the results as JSON.');
  }

  @override
  String get name => 'search';

  @override
  String get description =>
      'Find the docs sections that match a query, with their URLs.';

  @override
  String get invocation => 'restage docs search <query>';

  @override
  Future<int> run() async {
    final query = argResults!.rest.join(' ').trim();
    if (query.isEmpty) usageException('Give a search query.');
    final limit = int.tryParse(argResults!['limit'] as String);
    if (limit == null || limit < 1) {
      usageException('--limit must be 1 or more.');
    }
    return withClient((docs) async {
      final hits = await docs.search(query, limit: limit);
      if (argResults!['json'] == true) {
        stdout.writeln(
          const JsonEncoder.withIndent('  ').convert({
            'query': query,
            'results': [for (final hit in hits) hit.toJson()],
          }),
        );
        return 0;
      }
      if (hits.isEmpty) {
        stdout.writeln('No docs match "$query".');
        return 0;
      }
      for (final hit in hits) {
        final section = hit.section;
        final heading = section.headings.isEmpty
            ? section.title
            : '${section.title} › ${section.headings.join(' › ')}';
        stdout
          ..writeln(heading)
          ..writeln('  ${section.url}')
          ..writeln('  ${hit.snippet}')
          ..writeln();
      }
      stdout.writeln('Read a page with `restage docs read <url>`.');
      return 0;
    });
  }
}

/// `restage docs read <path-or-url>`.
class DocsReadCommand extends _DocsLeaf {
  /// Construct the command.
  DocsReadCommand({
    required super.stdout,
    required super.stderr,
    super.httpClient,
    super.environment,
  });

  @override
  String get name => 'read';

  @override
  String get description =>
      'Print a docs page, or one section with #anchor, as Markdown.';

  @override
  String get invocation => 'restage docs read <path-or-url>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Give one docs path or URL, such as /quickstart.');
    }
    return withClient((docs) async {
      stdout.writeln((await docs.read(rest.single)).trimRight());
      return 0;
    });
  }
}
