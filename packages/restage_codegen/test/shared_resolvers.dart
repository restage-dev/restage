import 'package:build/build.dart';
import 'package:build_runner/src/build/resolver/analysis_driver_model.dart';
import 'package:build_runner/src/build/resolver/resolvers_impl.dart';

/// Shares analyzer state across sequential test builds in one isolate.
/// Pass as `resolvers:` to `testBuilder` or `resolveSources`.
final Resolvers sharedResolvers = ResolversImpl.custom(
  analysisDriverModel: AnalysisDriverModel(),
);

/// Resolvers with an independent analysis driver for each build.
/// Prevents a test from reusing another scenario's source at the same asset path.
Resolvers freshResolvers() => ResolversImpl.custom(
      analysisDriverModel: AnalysisDriverModel(),
    );
