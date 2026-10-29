import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// What the CLI and MCP say about a revision an experiment cannot use because
/// it was pushed before its contract version changed.
String supersededRevisionSentence(ExperimentSupersededRevisionV1 revision) =>
    'Revision ${revision.publishedRevision} of `${revision.surfaceSlug}` was '
    "pushed before version ${revision.contractVersion}'s contract changed. "
    "Experiments can't use it. Use revision "
    '${revision.definedFromRevision} or later.';
