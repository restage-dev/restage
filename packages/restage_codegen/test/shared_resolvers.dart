import 'package:build/build.dart';

import '../../rfw_catalog_compiler/test/support/summary_ready_resolvers.dart';

export '../../rfw_catalog_compiler/test/support/summary_ready_resolvers.dart'
    show SummaryReadyResolvers, ensureSdkSummary;

/// Shares analyzer state across sequential test builds in one isolate.
/// Pass as `resolvers:` to `testBuilder` or `resolveSources`.
final Resolvers sharedResolvers = SummaryReadyResolvers();

/// Resolvers with an independent analysis driver for each build.
/// Prevents a test from reusing another scenario's source at the same asset path.
Resolvers freshResolvers() => SummaryReadyResolvers();
