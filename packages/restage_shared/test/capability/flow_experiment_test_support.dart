import 'package:restage_shared/flow_experiment.dart';
import 'package:restage_shared/restage_shared.dart';

const _emptyObjectSchema = FlowActionSchema.object({});
const _boolSchema = FlowActionSchema.bool();

FlowDocument experimentDocument({
  String flow = 'first_run',
  int version = 1,
  int minClient = 3,
  FlowDeliveryMode deliveryMode = FlowDeliveryMode.typed,
  Map<String, FlowActionContract> actions = const {},
  Map<String, FlowStateDeclaration> flowState = const {},
  FlowOutboundDeclarations outbound = const FlowOutboundDeclarations(),
  Map<String, FlowState>? states,
}) {
  return FlowDocument(
    flow: flow,
    version: version,
    schemaVersion: 1,
    minClient: minClient,
    initial: states == null ? 'done' : states.keys.first,
    actions: actions,
    flowState: flowState,
    outbound: outbound,
    legacyTerminalResultPassthrough: flowState.isEmpty && outbound.isEmpty,
    screenArtifacts: const {},
    states: states ??
        const {
          'done': EndFlowState(result: {'completed': true}),
        },
    deliveryMode: deliveryMode,
  );
}

FlowActionContract experimentAction({
  String name = 'request_notifications',
  int minClient = 1,
}) {
  return FlowActionContract(
    actionName: name,
    contractVersion: 1,
    argsSchema: _emptyObjectSchema,
    resultSchema: _boolSchema,
    minClient: minClient,
    idempotent: false,
  );
}

FlowActionBindingFingerprint experimentBinding({
  String actionId = 'request_notifications',
  String actionName = 'request_notifications',
  int minClient = 1,
}) {
  return FlowActionBindingFingerprint(
    actionId: actionId,
    actionName: actionName,
    contractVersion: 1,
    argsSchemaHash: FlowActionSchema.hashFor(
      contractKind: 'args',
      schema: _emptyObjectSchema,
    ),
    resultSchemaHash: FlowActionSchema.hashFor(
      contractKind: 'result',
      schema: _boolSchema,
    ),
    minClient: minClient,
    idempotent: false,
  );
}

FlowExperimentDocumentContract experimentDocumentContract({
  FlowDocument? document,
  Surface surfaceType = Surface.onboarding,
  List<LibraryRequirement> requiredLibraries = const [],
}) {
  final resolved = document ?? experimentDocument();
  return FlowExperimentDocumentContract(
    surfaceType: surfaceType,
    flowId: resolved.flow,
    version: resolved.version,
    schemaVersion: resolved.schemaVersion,
    minClient: resolved.minClient,
    contentHash: FlowContentHash.compute(
      FlowDocumentCodec.encodeCanonicalJson(resolved),
    ),
    requiredLibraries: requiredLibraries,
    flowDocument: resolved,
  );
}

FlowExperimentClientContractV1 experimentClientContract({
  FlowExperimentDescriptor descriptor = const FlowExperimentDescriptor(
    id: 'first_run',
    version: 1,
    minClient: 3,
  ),
  List<FlowExperimentDocumentContract>? documents,
  InstalledCapability? installedCapability,
  List<FlowActionBindingFingerprint> actionBindings = const [],
  List<String> installedSignals = const [],
  Surface surfaceType = Surface.onboarding,
  FlowDeliveryMode deliveryMode = FlowDeliveryMode.typed,
}) {
  return FlowExperimentClientContractV1(
    surfaceType: surfaceType,
    deliveryMode: deliveryMode,
    descriptor: descriptor,
    documents: documents ?? [experimentDocumentContract()],
    installedCapability: installedCapability ??
        InstalledCapability(
          builtInCatalogVersion: 5,
          installedLibraries: const [],
        ),
    actionBindings: actionBindings,
    installedSignals: installedSignals,
  );
}

const verifiedIntegrity = FlowExperimentArtifactIntegrity(
  payloadIntegrityVerified: true,
  screenIntegrityVerified: true,
  rfwIntegrityVerified: true,
);

FlowExperimentClosure experimentClosure({
  required FlowExperimentDocumentContract root,
  List<FlowExperimentDocumentContract>? documents,
  int rootCapability = 3,
  FlowExperimentArtifactIntegrity integrity = verifiedIntegrity,
}) {
  return FlowExperimentClosure(
    root: root,
    rootCapability: rootCapability,
    documents: documents ?? [root],
    integrity: integrity,
  );
}
