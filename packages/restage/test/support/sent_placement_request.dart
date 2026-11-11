import 'package:restage_shared/restage_shared.dart';

final _sentBuilds = <String, PlacementBuildContractV1>{};

/// Decodes a placement request the client sent, as a service holding every
/// build it was sent would.
PlacementBatchRequestV1 sentPlacementRequest(List<int> bytes) {
  final request = PlacementBatchRequestV1.fromCanonicalBytes(bytes,
      verifiedBuildContract: (hash) => _sentBuilds[hash]);
  _sentBuilds[request.appBuildContractHash] = request.buildContract;
  return request;
}

/// Forgets every build sent so far, as a service seeing this app for the first
/// time would.
void forgetSentBuilds() => _sentBuilds.clear();
