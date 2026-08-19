part of '../../flow_experiment.dart';

/// Frozen wire discriminator for a V1 flow-experiment client contract.
const String kFlowExperimentClientContractKindV1 =
    'flowExperimentClientContract';

/// Frozen route/storage discriminator for flow experiment contracts.
///
/// This is intentionally distinct from the canonical JSON object's
/// [kFlowExperimentClientContractKindV1] discriminator.
const String kFlowExperimentContractKind = 'flow';

/// Frozen wire version for a V1 flow-experiment client contract.
const int kFlowExperimentClientContractVersionV1 = 1;
const int _flowDocumentSchemaVersion = 1;
const int _maxFlowExperimentClosureDepth = 4;
const String _flowExperimentHashDomain =
    'restage.flow-experiment-client-contract.v1\n';

final RegExp _flowExperimentIdentifierPattern =
    RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$');
final RegExp _flowExperimentNamespacePattern =
    RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$');

/// The generated root-flow descriptor represented in a V1 client contract.
@immutable
final class FlowExperimentDescriptorV1 {
  /// Creates a descriptor. Its domains are checked by the enclosing contract.
  const FlowExperimentDescriptorV1({
    required this.id,
    required this.version,
    required this.minClient,
  });

  /// Stable root flow identifier.
  final String id;

  /// Exact generated root version.
  final int version;

  /// Installed capability floor of the generated root reference.
  final int minClient;
}

/// One deep-frozen installed action binding represented in a V1 contract.
@immutable
final class FlowActionBindingFingerprintV1 {
  /// Creates and validates an action-binding fingerprint.
  factory FlowActionBindingFingerprintV1({
    required String actionId,
    required String actionName,
    required int contractVersion,
    required FlowContentHash argsSchemaHash,
    required FlowContentHash resultSchemaHash,
    required int minClient,
    required bool idempotent,
  }) {
    _checkIdentifier(actionId, r'$.actionId');
    _checkIdentifier(actionName, r'$.actionName');
    _checkPositiveInt(contractVersion, r'$.contractVersion');
    _checkPositiveInt(minClient, r'$.minClient');
    return FlowActionBindingFingerprintV1._(
      actionId: actionId,
      actionName: actionName,
      contractVersion: contractVersion,
      argsSchemaHash: argsSchemaHash,
      resultSchemaHash: resultSchemaHash,
      minClient: minClient,
      idempotent: idempotent,
    );
  }

  const FlowActionBindingFingerprintV1._({
    required this.actionId,
    required this.actionName,
    required this.contractVersion,
    required this.argsSchemaHash,
    required this.resultSchemaHash,
    required this.minClient,
    required this.idempotent,
  });

  /// Registry map key.
  final String actionId;

  /// Installed action name.
  final String actionName;

  /// Installed action contract version.
  final int contractVersion;

  /// Canonical installed argument-schema hash.
  final FlowContentHash argsSchemaHash;

  /// Canonical installed result-schema hash.
  final FlowContentHash resultSchemaHash;

  /// Highest document action floor this binding supports.
  final int minClient;

  /// Whether the installed action is idempotent.
  final bool idempotent;
}

/// One exact document in a V1 flow closure.
@immutable
final class FlowExperimentDocumentContractV1 {
  /// Creates and independently validates a document wrapper.
  factory FlowExperimentDocumentContractV1({
    required Surface surfaceType,
    required String flowId,
    required int version,
    required int schemaVersion,
    required int minClient,
    required FlowContentHash contentHash,
    required List<LibraryRequirement> requiredLibraries,
    required FlowDocument flowDocument,
  }) {
    _checkIdentifier(flowId, r'$.flowId');
    _checkPositiveInt(version, r'$.version');
    if (schemaVersion != _flowDocumentSchemaVersion) {
      throw FormatException(
        'Unsupported flow document schemaVersion $schemaVersion.',
      );
    }
    _checkPositiveInt(minClient, r'$.minClient');

    final canonicalLibraries = _canonicalRequiredLibraries(
      requiredLibraries,
      r'$.requiredLibraries',
    );
    final productionBytes =
        Uint8List.fromList(FlowDocumentCodec.encodeCanonicalJson(flowDocument));
    final actualHash = FlowContentHash.compute(productionBytes);
    if (actualHash != contentHash) {
      throw FormatException(
        'Flow document contentHash mismatch for "$flowId": expected '
        '${contentHash.value}, got ${actualHash.value}.',
      );
    }
    if (flowDocument.flow != flowId ||
        flowDocument.version != version ||
        flowDocument.schemaVersion != schemaVersion ||
        flowDocument.minClient != minClient) {
      throw FormatException(
        'Flow document wrapper metadata does not match "$flowId".',
      );
    }

    final parsedProduction = _StrictJsonParser(productionBytes).parse();
    final nestedCanonicalBytes =
        Uint8List.fromList(_CanonicalJsonWriter.encode(parsedProduction));
    return FlowExperimentDocumentContractV1._(
      surfaceType: surfaceType,
      flowId: flowId,
      version: version,
      schemaVersion: schemaVersion,
      minClient: minClient,
      contentHash: contentHash,
      requiredLibraries: canonicalLibraries,
      productionFlowDocumentBytes: productionBytes,
      canonicalFlowDocumentBytes: nestedCanonicalBytes,
    );
  }

  FlowExperimentDocumentContractV1._({
    required this.surfaceType,
    required this.flowId,
    required this.version,
    required this.schemaVersion,
    required this.minClient,
    required this.contentHash,
    required List<LibraryRequirement> requiredLibraries,
    required Uint8List productionFlowDocumentBytes,
    required Uint8List canonicalFlowDocumentBytes,
  })  : requiredLibraries = List.unmodifiable(requiredLibraries),
        _productionFlowDocumentBytes =
            Uint8List.fromList(productionFlowDocumentBytes),
        _canonicalFlowDocumentBytes =
            Uint8List.fromList(canonicalFlowDocumentBytes);

  /// Surface category of this closure node.
  final Surface surfaceType;

  /// Exact flow identifier.
  final String flowId;

  /// Exact flow version.
  final int version;

  /// Supported flow schema version. V1 accepts exactly schema 1.
  final int schemaVersion;

  /// Document capability floor.
  final int minClient;

  /// Hash of the production canonical FlowDocument bytes.
  final FlowContentHash contentHash;

  /// Custom libraries required by the surface payload.
  final List<LibraryRequirement> requiredLibraries;

  final Uint8List _productionFlowDocumentBytes;
  final Uint8List _canonicalFlowDocumentBytes;

  /// A fresh document decoded through the production FlowDocument codec.
  FlowDocument get flowDocument => FlowDocumentCodec.decodeJson(
        utf8.decode(_productionFlowDocumentBytes),
      );

  /// FlowDocument JSON as nested in the V1 canonical contract.
  Uint8List get canonicalFlowDocumentBytes =>
      Uint8List.fromList(_canonicalFlowDocumentBytes);
}

/// The exact immutable V1 client flow-experiment contract.
@immutable
final class FlowExperimentClientContractV1 {
  /// Creates and validates a complete baseline closure and capability snapshot.
  factory FlowExperimentClientContractV1({
    required Surface surfaceType,
    required FlowDeliveryMode deliveryMode,
    required FlowExperimentDescriptorV1 descriptor,
    required List<FlowExperimentDocumentContractV1> documents,
    required InstalledCapability installedCapability,
    required List<FlowActionBindingFingerprintV1> actionBindings,
    required List<String> installedSignals,
  }) {
    _checkIdentifier(descriptor.id, r'$.descriptor.id');
    _checkPositiveInt(descriptor.version, r'$.descriptor.version');
    _checkPositiveInt(descriptor.minClient, r'$.descriptor.minClient');

    final canonicalDocuments = _canonicalDocuments(documents);
    final canonicalInstalled =
        _canonicalInstalledCapability(installedCapability);
    final canonicalActions = _canonicalActionBindings(actionBindings);
    final canonicalSignals = _canonicalSignals(installedSignals);
    _checkCompleteBaselineClosure(
      surfaceType: surfaceType,
      deliveryMode: deliveryMode,
      descriptor: descriptor,
      documents: canonicalDocuments,
    );

    return FlowExperimentClientContractV1._(
      surfaceType: surfaceType,
      deliveryMode: deliveryMode,
      descriptor: descriptor,
      documents: canonicalDocuments,
      installedCapability: canonicalInstalled,
      actionBindings: canonicalActions,
      installedSignals: canonicalSignals,
    );
  }

  FlowExperimentClientContractV1._({
    required this.surfaceType,
    required this.deliveryMode,
    required this.descriptor,
    required List<FlowExperimentDocumentContractV1> documents,
    required this.installedCapability,
    required List<FlowActionBindingFingerprintV1> actionBindings,
    required List<String> installedSignals,
  })  : documents = List.unmodifiable(documents),
        actionBindings = List.unmodifiable(actionBindings),
        installedSignals = List.unmodifiable(installedSignals);

  /// Strictly decodes exact canonical V1 UTF-8 JSON bytes.
  ///
  /// Duplicate object keys are rejected by the byte parser before any map is
  /// materialized. The decoded value is then re-encoded and must match the
  /// input byte-for-byte, so whitespace and noncanonical ordering fail closed.
  static FlowExperimentClientContractV1 decode(List<int> bytes) {
    try {
      final frozenBytes = Uint8List.fromList(bytes);
      final parsed = _StrictJsonParser(frozenBytes).parse();
      final root = _asJsonObject(parsed, r'$');
      final contract = _decodeClientContract(root);
      if (!_bytesEqual(frozenBytes, contract.canonicalBytes)) {
        throw const FormatException(
          'Flow experiment contract is not exact canonical JSON.',
        );
      }
      return contract;
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('Invalid flow experiment contract: $error');
    }
  }

  /// Surface category of this snapshot.
  final Surface surfaceType;

  /// Typed or general flow delivery mode.
  final FlowDeliveryMode deliveryMode;

  /// Generated root descriptor.
  final FlowExperimentDescriptorV1 descriptor;

  /// Complete exact baseline closure in canonical semantic order.
  final List<FlowExperimentDocumentContractV1> documents;

  /// Deep-frozen installed renderer capability.
  final InstalledCapability installedCapability;

  /// Complete installed action mount set in canonical semantic order.
  final List<FlowActionBindingFingerprintV1> actionBindings;

  /// Exact installed signal union in canonical semantic order.
  final List<String> installedSignals;

  /// Exact compact canonical V1 bytes.
  Uint8List get canonicalBytes =>
      Uint8List.fromList(_encodeClientContract(this));

  /// Domain-separated SHA-256 hash of [canonicalBytes].
  FlowContentHash get contentHash {
    return FlowContentHash.compute([
      ...utf8.encode(_flowExperimentHashDomain),
      ...canonicalBytes,
    ]);
  }
}

FlowExperimentClientContractV1 _decodeClientContract(
  Map<String, Object?> json,
) {
  _checkExactKeys(
    json,
    const {
      'actionBindings',
      'contractVersion',
      'deliveryMode',
      'descriptor',
      'documents',
      'installedCapability',
      'installedSignals',
      'kind',
      'surfaceType',
    },
    r'$',
  );
  final kind = _requiredString(json, 'kind', r'$');
  if (kind != kFlowExperimentClientContractKindV1) {
    throw FormatException('Unsupported flow experiment contract kind "$kind".');
  }
  final contractVersion = _requiredPositiveInt(
    json,
    'contractVersion',
    r'$',
  );
  if (contractVersion != kFlowExperimentClientContractVersionV1) {
    throw FormatException(
      'Unsupported flow experiment contractVersion $contractVersion.',
    );
  }

  final descriptorJson = _requiredObject(json, 'descriptor', r'$.descriptor');
  _checkExactKeys(
    descriptorJson,
    const {'id', 'minClient', 'version'},
    r'$.descriptor',
  );
  final descriptor = FlowExperimentDescriptorV1(
    id: _requiredString(descriptorJson, 'id', r'$.descriptor'),
    version: _requiredPositiveInt(
      descriptorJson,
      'version',
      r'$.descriptor',
    ),
    minClient: _requiredPositiveInt(
      descriptorJson,
      'minClient',
      r'$.descriptor',
    ),
  );

  final documentsJson = _requiredList(json, 'documents', r'$.documents');
  final documents = <FlowExperimentDocumentContractV1>[
    for (var index = 0; index < documentsJson.length; index += 1)
      _decodeDocumentContract(
        _asJsonObject(documentsJson[index], r'$.documents'),
        r'$.documents[$index]',
      ),
  ];

  final installedJson = _requiredObject(
    json,
    'installedCapability',
    r'$.installedCapability',
  );
  final installedCapability = _decodeInstalledCapability(installedJson);

  final actionJson = _requiredList(json, 'actionBindings', r'$.actionBindings');
  final actions = <FlowActionBindingFingerprintV1>[
    for (var index = 0; index < actionJson.length; index += 1)
      _decodeActionBinding(
        _asJsonObject(actionJson[index], r'$.actionBindings'),
        r'$.actionBindings[$index]',
      ),
  ];

  final signalJson =
      _requiredList(json, 'installedSignals', r'$.installedSignals');
  final signals = <String>[
    for (var index = 0; index < signalJson.length; index += 1)
      _asJsonString(signalJson[index], r'$.installedSignals[$index]'),
  ];

  return FlowExperimentClientContractV1(
    surfaceType: Surface.fromWireName(
      _requiredString(json, 'surfaceType', r'$'),
    ),
    deliveryMode: FlowDeliveryMode.fromWireName(
      _requiredString(json, 'deliveryMode', r'$'),
    ),
    descriptor: descriptor,
    documents: documents,
    installedCapability: installedCapability,
    actionBindings: actions,
    installedSignals: signals,
  );
}

FlowExperimentDocumentContractV1 _decodeDocumentContract(
  Map<String, Object?> json,
  String path,
) {
  _checkExactKeys(
    json,
    const {
      'contentHash',
      'flowDocument',
      'flowId',
      'minClient',
      'requiredLibraries',
      'schemaVersion',
      'surfaceType',
      'version',
    },
    path,
  );
  final librariesJson =
      _requiredList(json, 'requiredLibraries', '$path.requiredLibraries');
  final libraries = <LibraryRequirement>[
    for (var index = 0; index < librariesJson.length; index += 1)
      _decodeRequiredLibrary(
        _asJsonObject(librariesJson[index], '$path.requiredLibraries'),
        '$path.requiredLibraries[$index]',
      ),
  ];
  final flowJson = _requiredObject(json, 'flowDocument', '$path.flowDocument');
  final flowDocument = FlowDocumentCodec.decodeJson(jsonEncode(flowJson));

  return FlowExperimentDocumentContractV1(
    surfaceType: Surface.fromWireName(
      _requiredString(json, 'surfaceType', path),
    ),
    flowId: _requiredString(json, 'flowId', path),
    version: _requiredPositiveInt(json, 'version', path),
    schemaVersion: _requiredPositiveInt(json, 'schemaVersion', path),
    minClient: _requiredPositiveInt(json, 'minClient', path),
    contentHash: FlowContentHash.parse(
      _requiredString(json, 'contentHash', path),
    ),
    requiredLibraries: libraries,
    flowDocument: flowDocument,
  );
}

LibraryRequirement _decodeRequiredLibrary(
  Map<String, Object?> json,
  String path,
) {
  _checkExactKeys(json, const {'minVersion', 'namespace'}, path);
  final namespace = _requiredString(json, 'namespace', path);
  _checkNamespace(namespace, '$path.namespace');
  return LibraryRequirement(
    namespace: namespace,
    minVersion: _requiredPositiveInt(json, 'minVersion', path),
  );
}

InstalledCapability _decodeInstalledCapability(
  Map<String, Object?> json,
) {
  const path = r'$.installedCapability';
  _checkExactKeys(
    json,
    const {'builtInCatalogVersion', 'installedLibraries'},
    path,
  );
  final librariesJson =
      _requiredList(json, 'installedLibraries', '$path.installedLibraries');
  final libraries = <InstalledLibrary>[
    for (var index = 0; index < librariesJson.length; index += 1)
      _decodeInstalledLibrary(
        _asJsonObject(librariesJson[index], '$path.installedLibraries'),
        '$path.installedLibraries[$index]',
      ),
  ];
  return InstalledCapability(
    builtInCatalogVersion:
        _requiredPositiveInt(json, 'builtInCatalogVersion', path),
    installedLibraries: libraries,
  );
}

InstalledLibrary _decodeInstalledLibrary(
  Map<String, Object?> json,
  String path,
) {
  _checkExactKeys(json, const {'namespace', 'version'}, path);
  final namespace = _requiredString(json, 'namespace', path);
  _checkNamespace(namespace, '$path.namespace');
  if (!json.containsKey('version')) {
    throw FormatException('Missing required field "$path.version".');
  }
  final version = json['version'];
  if (version != null && (version is! int || version < 1)) {
    throw FormatException(
      'Expected "$path.version" to be null or a positive integer.',
    );
  }
  return InstalledLibrary(namespace: namespace, version: version as int?);
}

FlowActionBindingFingerprintV1 _decodeActionBinding(
  Map<String, Object?> json,
  String path,
) {
  _checkExactKeys(
    json,
    const {
      'actionId',
      'actionName',
      'argsSchemaHash',
      'contractVersion',
      'idempotent',
      'minClient',
      'resultSchemaHash',
    },
    path,
  );
  return FlowActionBindingFingerprintV1(
    actionId: _requiredString(json, 'actionId', path),
    actionName: _requiredString(json, 'actionName', path),
    contractVersion: _requiredPositiveInt(json, 'contractVersion', path),
    argsSchemaHash: FlowContentHash.parse(
      _requiredString(json, 'argsSchemaHash', path),
    ),
    resultSchemaHash: FlowContentHash.parse(
      _requiredString(json, 'resultSchemaHash', path),
    ),
    minClient: _requiredPositiveInt(json, 'minClient', path),
    idempotent: _requiredBool(json, 'idempotent', path),
  );
}

List<int> _encodeClientContract(FlowExperimentClientContractV1 contract) {
  final tree = <String, Object?>{
    'kind': kFlowExperimentClientContractKindV1,
    'contractVersion': kFlowExperimentClientContractVersionV1,
    'surfaceType': contract.surfaceType.wireName,
    'deliveryMode': contract.deliveryMode.wireName,
    'descriptor': <String, Object?>{
      'id': contract.descriptor.id,
      'version': contract.descriptor.version,
      'minClient': contract.descriptor.minClient,
    },
    'documents': <Object?>[
      for (final document in contract.documents)
        <String, Object?>{
          'surfaceType': document.surfaceType.wireName,
          'flowId': document.flowId,
          'version': document.version,
          'schemaVersion': document.schemaVersion,
          'minClient': document.minClient,
          'contentHash': document.contentHash.value,
          'requiredLibraries': <Object?>[
            for (final requirement in document.requiredLibraries)
              <String, Object?>{
                'namespace': requirement.namespace,
                'minVersion': requirement.minVersion,
              },
          ],
          'flowDocument': _CanonicalJsonFragment(
            document._canonicalFlowDocumentBytes,
          ),
        },
    ],
    'installedCapability': <String, Object?>{
      'builtInCatalogVersion':
          contract.installedCapability.builtInCatalogVersion,
      'installedLibraries': <Object?>[
        for (final library in contract.installedCapability.installedLibraries)
          <String, Object?>{
            'namespace': library.namespace,
            'version': library.version,
          },
      ],
    },
    'actionBindings': <Object?>[
      for (final action in contract.actionBindings)
        <String, Object?>{
          'actionId': action.actionId,
          'actionName': action.actionName,
          'contractVersion': action.contractVersion,
          'argsSchemaHash': action.argsSchemaHash.value,
          'resultSchemaHash': action.resultSchemaHash.value,
          'minClient': action.minClient,
          'idempotent': action.idempotent,
        },
    ],
    'installedSignals': <Object?>[...contract.installedSignals],
  };
  return _CanonicalJsonWriter.encode(tree);
}

List<FlowExperimentDocumentContractV1> _canonicalDocuments(
  List<FlowExperimentDocumentContractV1> documents,
) {
  if (documents.isEmpty) {
    throw const FormatException(
      'Flow experiment documents must contain a root document.',
    );
  }
  final identities = <String>{};
  final canonical = List<FlowExperimentDocumentContractV1>.of(documents);
  for (final document in canonical) {
    final identity = _documentIdentity(document);
    if (!identities.add(identity)) {
      throw FormatException(
        'Duplicate flow document identity '
        '"${document.surfaceType.wireName}/${document.flowId}/'
        '${document.version}".',
      );
    }
  }
  canonical.sort(_compareDocuments);
  return List.unmodifiable(canonical);
}

InstalledCapability _canonicalInstalledCapability(
  InstalledCapability installed,
) {
  _checkPositiveInt(
    installed.builtInCatalogVersion,
    r'$.installedCapability.builtInCatalogVersion',
  );
  final namespaces = <String>{};
  final libraries = List<InstalledLibrary>.of(installed.installedLibraries);
  for (final library in libraries) {
    _checkNamespace(
      library.namespace,
      r'$.installedCapability.installedLibraries.namespace',
    );
    final version = library.version;
    if (version != null) {
      _checkPositiveInt(
        version,
        r'$.installedCapability.installedLibraries.version',
      );
    }
    if (!namespaces.add(library.namespace)) {
      throw FormatException(
        'Duplicate installed library namespace "${library.namespace}".',
      );
    }
  }
  libraries.sort(
    (a, b) => _compareUnsignedUtf8(a.namespace, b.namespace),
  );
  return InstalledCapability(
    builtInCatalogVersion: installed.builtInCatalogVersion,
    installedLibraries: libraries,
  );
}

List<FlowActionBindingFingerprintV1> _canonicalActionBindings(
  List<FlowActionBindingFingerprintV1> actions,
) {
  final ids = <String>{};
  final canonical = List<FlowActionBindingFingerprintV1>.of(actions);
  for (final action in canonical) {
    _checkIdentifier(action.actionId, r'$.actionBindings.actionId');
    _checkIdentifier(action.actionName, r'$.actionBindings.actionName');
    _checkPositiveInt(
      action.contractVersion,
      r'$.actionBindings.contractVersion',
    );
    _checkPositiveInt(action.minClient, r'$.actionBindings.minClient');
    if (!ids.add(action.actionId)) {
      throw FormatException(
        'Duplicate action binding ID "${action.actionId}".',
      );
    }
  }
  canonical.sort((a, b) {
    final id = _compareUnsignedUtf8(a.actionId, b.actionId);
    return id != 0 ? id : _compareUnsignedUtf8(a.actionName, b.actionName);
  });
  return List.unmodifiable(canonical);
}

List<String> _canonicalSignals(List<String> signals) {
  final seen = <String>{};
  final canonical = List<String>.of(signals);
  for (final signal in canonical) {
    _checkIdentifier(signal, r'$.installedSignals');
    if (!seen.add(signal)) {
      throw FormatException('Duplicate installed signal "$signal".');
    }
  }
  canonical.sort(_compareUnsignedUtf8);
  return List.unmodifiable(canonical);
}

List<LibraryRequirement> _canonicalRequiredLibraries(
  List<LibraryRequirement> required,
  String path,
) {
  final seen = <String>{};
  final canonical = List<LibraryRequirement>.of(required);
  for (final requirement in canonical) {
    _checkNamespace(requirement.namespace, '$path.namespace');
    _checkPositiveInt(requirement.minVersion, '$path.minVersion');
    if (!seen.add(requirement.namespace)) {
      throw FormatException(
        'Duplicate required library namespace "${requirement.namespace}".',
      );
    }
  }
  canonical.sort(
    (a, b) => _compareUnsignedUtf8(a.namespace, b.namespace),
  );
  return List.unmodifiable(canonical);
}

void _checkCompleteBaselineClosure({
  required Surface surfaceType,
  required FlowDeliveryMode deliveryMode,
  required FlowExperimentDescriptorV1 descriptor,
  required List<FlowExperimentDocumentContractV1> documents,
}) {
  final byIdentity = {
    for (final document in documents) _documentIdentity(document): document,
  };
  final rootIdentity = _documentIdentityParts(
    surfaceType,
    descriptor.id,
    descriptor.version,
  );
  final root = byIdentity[rootIdentity];
  if (root == null) {
    throw const FormatException(
      'Flow experiment baseline closure is missing its exact root.',
    );
  }
  if (root.minClient > descriptor.minClient) {
    throw FormatException(
      'Root minClient ${root.minClient} exceeds descriptor minClient '
      '${descriptor.minClient}.',
    );
  }

  final reached = <String>{};
  _walkExactClosure(
    node: root,
    availableCapability: descriptor.minClient,
    expectedSurface: surfaceType,
    expectedMode: deliveryMode,
    byIdentity: byIdentity,
    reached: reached,
    path: <String>{},
    depth: 0,
  );
  if (reached.length != documents.length) {
    throw const FormatException(
      'Flow experiment baseline closure contains unreachable documents.',
    );
  }
}

void _walkExactClosure({
  required FlowExperimentDocumentContractV1 node,
  required int availableCapability,
  required Surface expectedSurface,
  required FlowDeliveryMode expectedMode,
  required Map<String, FlowExperimentDocumentContractV1> byIdentity,
  required Set<String> reached,
  required Set<String> path,
  required int depth,
}) {
  final identity = _documentIdentity(node);
  if (path.contains(identity)) {
    throw FormatException(
      'Flow experiment closure contains a cycle at $identity.',
    );
  }
  if (node.surfaceType != expectedSurface ||
      node.flowDocument.deliveryMode != expectedMode) {
    throw FormatException(
      'Flow experiment closure node ${node.flowId} crosses surface or mode.',
    );
  }
  if (node.minClient > availableCapability) {
    throw FormatException(
      'Flow experiment closure node ${node.flowId} raises minClient.',
    );
  }
  reached.add(identity);
  final nextPath = {...path, identity};
  for (final state in node.flowDocument.states.values) {
    if (state is! SubFlowState) continue;
    final childIdentity = _documentIdentityParts(
      expectedSurface,
      state.flow,
      state.version,
    );
    if (nextPath.contains(childIdentity)) {
      throw FormatException(
        'Flow experiment closure contains a cycle at $childIdentity.',
      );
    }
    if (depth >= _maxFlowExperimentClosureDepth) {
      throw const FormatException(
        'Flow experiment closure exceeds maximum sub-flow depth 4.',
      );
    }
    final child = byIdentity[childIdentity];
    if (child == null) {
      throw FormatException(
        'Flow experiment closure is missing sub-flow "${state.flow}".',
      );
    }
    if (child.schemaVersion != state.schemaVersion ||
        child.minClient != state.minClient ||
        child.contentHash != state.contentHash) {
      throw FormatException(
        'Flow experiment sub-flow "${state.flow}" does not match its exact '
        'reference.',
      );
    }
    _walkExactClosure(
      node: child,
      availableCapability: state.minClient,
      expectedSurface: expectedSurface,
      expectedMode: expectedMode,
      byIdentity: byIdentity,
      reached: reached,
      path: nextPath,
      depth: depth + 1,
    );
  }
}

int _compareDocuments(
  FlowExperimentDocumentContractV1 a,
  FlowExperimentDocumentContractV1 b,
) {
  final surface = _compareUnsignedUtf8(
    a.surfaceType.wireName,
    b.surfaceType.wireName,
  );
  if (surface != 0) return surface;
  final flow = _compareUnsignedUtf8(a.flowId, b.flowId);
  return flow != 0 ? flow : a.version.compareTo(b.version);
}

String _documentIdentity(FlowExperimentDocumentContractV1 document) {
  return _documentIdentityParts(
    document.surfaceType,
    document.flowId,
    document.version,
  );
}

String _documentIdentityParts(
  Surface surface,
  String flowId,
  int version,
) {
  return '${surface.wireName}\u0000$flowId\u0000$version';
}

int _compareUnsignedUtf8(String a, String b) {
  final aBytes = utf8.encode(a);
  final bBytes = utf8.encode(b);
  final common = aBytes.length < bBytes.length ? aBytes.length : bBytes.length;
  for (var index = 0; index < common; index += 1) {
    final comparison = aBytes[index].compareTo(bBytes[index]);
    if (comparison != 0) return comparison;
  }
  return aBytes.length.compareTo(bBytes.length);
}

void _checkIdentifier(String value, String path) {
  if (!_flowExperimentIdentifierPattern.hasMatch(value)) {
    throw FormatException('Invalid ASCII identifier at "$path".');
  }
}

void _checkNamespace(String value, String path) {
  if (!_flowExperimentNamespacePattern.hasMatch(value)) {
    throw FormatException('Invalid library namespace at "$path".');
  }
}

void _checkPositiveInt(int value, String path) {
  if (value < 1) {
    throw FormatException('Expected "$path" to be a positive integer.');
  }
}

void _checkExactKeys(
  Map<String, Object?> json,
  Set<String> expected,
  String path,
) {
  for (final key in json.keys) {
    if (!expected.contains(key)) {
      throw FormatException('Unsupported field "$path.$key".');
    }
  }
  for (final key in expected) {
    if (!json.containsKey(key)) {
      throw FormatException('Missing required field "$path.$key".');
    }
  }
}

Object? _requiredValue(
  Map<String, Object?> json,
  String key,
  String path,
) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing required field "$path.$key".');
  }
  final value = json[key];
  if (value == null) {
    throw FormatException('Field "$path.$key" cannot be null.');
  }
  return value;
}

String _requiredString(
  Map<String, Object?> json,
  String key,
  String path,
) {
  return _asJsonString(_requiredValue(json, key, path), '$path.$key');
}

String _asJsonString(Object? value, String path) {
  if (value is String) return value;
  throw FormatException('Expected "$path" to be a string.');
}

int _requiredPositiveInt(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = _requiredValue(json, key, path);
  if (value is! int || value < 1) {
    throw FormatException('Expected "$path.$key" to be a positive integer.');
  }
  return value;
}

bool _requiredBool(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = _requiredValue(json, key, path);
  if (value is bool) return value;
  throw FormatException('Expected "$path.$key" to be a boolean.');
}

Map<String, Object?> _requiredObject(
  Map<String, Object?> json,
  String key,
  String path,
) {
  return _asJsonObject(_requiredValue(json, key, path), path);
}

Map<String, Object?> _asJsonObject(Object? value, String path) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('Expected "$path" to be an object.');
}

List<Object?> _requiredList(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = _requiredValue(json, key, path);
  if (value is List<Object?>) return value;
  throw FormatException('Expected "$path" to be an array.');
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

final class _CanonicalJsonFragment {
  const _CanonicalJsonFragment(this.bytes);

  final List<int> bytes;
}

abstract final class _CanonicalJsonWriter {
  static List<int> encode(Object? value) {
    final output = BytesBuilder(copy: false);
    _write(value, output);
    return output.takeBytes();
  }

  static void _write(Object? value, BytesBuilder output) {
    switch (value) {
      case null:
        output.add(const [0x6E, 0x75, 0x6C, 0x6C]);
      case String():
        output.add(utf8.encode(jsonEncode(value)));
      case bool() || int():
        output.add(utf8.encode(value.toString()));
      case double():
        throw const FormatException(
          'Floating-point JSON values are unsupported.',
        );
      case _CanonicalJsonFragment():
        output.add(value.bytes);
      case List<Object?>():
        output.addByte(0x5B);
        for (var index = 0; index < value.length; index += 1) {
          if (index != 0) output.addByte(0x2C);
          _write(value[index], output);
        }
        output.addByte(0x5D);
      case Map<String, Object?>():
        final keys = value.keys.toList()..sort(_compareUnsignedUtf8);
        output.addByte(0x7B);
        for (var index = 0; index < keys.length; index += 1) {
          if (index != 0) output.addByte(0x2C);
          final key = keys[index];
          output
            ..add(utf8.encode(jsonEncode(key)))
            ..addByte(0x3A);
          _write(value[key], output);
        }
        output.addByte(0x7D);
      default:
        throw FormatException(
          'Unsupported canonical JSON value ${value.runtimeType}.',
        );
    }
  }
}

final class _StrictJsonParser {
  _StrictJsonParser(List<int> bytes) {
    try {
      _source = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const FormatException('Malformed UTF-8 in flow contract.');
    }
    if (_source.startsWith('\uFEFF')) {
      throw const FormatException('UTF-8 BOM is not permitted.');
    }
  }

  late final String _source;
  int _offset = 0;

  Object? parse() {
    final value = _parseValue(0);
    _skipWhitespace();
    if (_offset != _source.length) {
      throw FormatException('Trailing JSON input at offset $_offset.');
    }
    return value;
  }

  Object? _parseValue(int depth) {
    if (depth > 128) {
      throw const FormatException('JSON nesting exceeds the supported depth.');
    }
    _skipWhitespace();
    if (_offset >= _source.length) {
      throw const FormatException('Unexpected end of JSON input.');
    }
    return switch (_source.codeUnitAt(_offset)) {
      0x7B => _parseObject(depth + 1),
      0x5B => _parseArray(depth + 1),
      0x22 => _parseString(),
      0x74 => _parseLiteral('true', true),
      0x66 => _parseLiteral('false', false),
      0x6E => _parseLiteral('null', null),
      0x2D => _parseInteger(),
      >= 0x30 && <= 0x39 => _parseInteger(),
      _ => throw FormatException('Invalid JSON token at offset $_offset.'),
    };
  }

  Map<String, Object?> _parseObject(int depth) {
    _offset += 1;
    final result = <String, Object?>{};
    _skipWhitespace();
    if (_consume(0x7D)) return result;
    while (true) {
      _skipWhitespace();
      if (_offset >= _source.length || _source.codeUnitAt(_offset) != 0x22) {
        throw FormatException(
          'Expected object key at offset $_offset.',
        );
      }
      final key = _parseString();
      if (result.containsKey(key)) {
        throw FormatException('Duplicate object key "$key".');
      }
      _skipWhitespace();
      _expect(0x3A, '":" after object key');
      result[key] = _parseValue(depth);
      _skipWhitespace();
      if (_consume(0x7D)) return result;
      _expect(0x2C, '"," between object entries');
    }
  }

  List<Object?> _parseArray(int depth) {
    _offset += 1;
    final result = <Object?>[];
    _skipWhitespace();
    if (_consume(0x5D)) return result;
    while (true) {
      result.add(_parseValue(depth));
      _skipWhitespace();
      if (_consume(0x5D)) return result;
      _expect(0x2C, '"," between array entries');
    }
  }

  String _parseString() {
    _expect(0x22, 'opening quote');
    final output = StringBuffer();
    while (_offset < _source.length) {
      final codeUnit = _source.codeUnitAt(_offset++);
      if (codeUnit == 0x22) return output.toString();
      if (codeUnit == 0x5C) {
        _parseEscape(output);
        continue;
      }
      if (codeUnit < 0x20) {
        throw const FormatException('Unescaped control character in string.');
      }
      if (_isHighSurrogate(codeUnit)) {
        if (_offset >= _source.length) {
          throw const FormatException('Lone high surrogate in JSON string.');
        }
        final low = _source.codeUnitAt(_offset++);
        if (!_isLowSurrogate(low)) {
          throw const FormatException('Lone high surrogate in JSON string.');
        }
        output
          ..writeCharCode(codeUnit)
          ..writeCharCode(low);
        continue;
      }
      if (_isLowSurrogate(codeUnit)) {
        throw const FormatException('Lone low surrogate in JSON string.');
      }
      output.writeCharCode(codeUnit);
    }
    throw const FormatException('Unterminated JSON string.');
  }

  void _parseEscape(StringBuffer output) {
    if (_offset >= _source.length) {
      throw const FormatException('Unterminated JSON escape.');
    }
    final escaped = _source.codeUnitAt(_offset++);
    switch (escaped) {
      case 0x22:
      case 0x5C:
      case 0x2F:
        output.writeCharCode(escaped);
      case 0x62:
        output.writeCharCode(0x08);
      case 0x66:
        output.writeCharCode(0x0C);
      case 0x6E:
        output.writeCharCode(0x0A);
      case 0x72:
        output.writeCharCode(0x0D);
      case 0x74:
        output.writeCharCode(0x09);
      case 0x75:
        final first = _parseHexCodeUnit();
        if (_isHighSurrogate(first)) {
          if (_offset + 2 > _source.length ||
              _source.codeUnitAt(_offset) != 0x5C ||
              _source.codeUnitAt(_offset + 1) != 0x75) {
            throw const FormatException('Lone high surrogate escape.');
          }
          _offset += 2;
          final second = _parseHexCodeUnit();
          if (!_isLowSurrogate(second)) {
            throw const FormatException('Invalid surrogate pair escape.');
          }
          output
            ..writeCharCode(first)
            ..writeCharCode(second);
        } else if (_isLowSurrogate(first)) {
          throw const FormatException('Lone low surrogate escape.');
        } else {
          output.writeCharCode(first);
        }
      default:
        throw FormatException('Unsupported JSON escape at offset $_offset.');
    }
  }

  int _parseHexCodeUnit() {
    if (_offset + 4 > _source.length) {
      throw const FormatException('Truncated Unicode escape.');
    }
    var value = 0;
    for (var index = 0; index < 4; index += 1) {
      final unit = _source.codeUnitAt(_offset++);
      final digit = switch (unit) {
        >= 0x30 && <= 0x39 => unit - 0x30,
        >= 0x41 && <= 0x46 => unit - 0x41 + 10,
        >= 0x61 && <= 0x66 => unit - 0x61 + 10,
        _ => -1,
      };
      if (digit < 0) {
        throw const FormatException('Invalid Unicode escape.');
      }
      value = (value << 4) | digit;
    }
    return value;
  }

  int _parseInteger() {
    final start = _offset;
    _consume(0x2D);
    if (_offset >= _source.length) {
      throw const FormatException('Truncated JSON number.');
    }
    if (_consume(0x30)) {
      if (_offset < _source.length) {
        final next = _source.codeUnitAt(_offset);
        if (next >= 0x30 && next <= 0x39) {
          throw const FormatException('Leading zero in JSON number.');
        }
      }
    } else {
      final first = _source.codeUnitAt(_offset);
      if (first < 0x31 || first > 0x39) {
        throw FormatException('Invalid JSON number at offset $start.');
      }
      while (_offset < _source.length) {
        final unit = _source.codeUnitAt(_offset);
        if (unit < 0x30 || unit > 0x39) break;
        _offset += 1;
      }
    }
    if (_offset < _source.length) {
      final unit = _source.codeUnitAt(_offset);
      if (unit == 0x2E || unit == 0x65 || unit == 0x45) {
        throw const FormatException(
          'Floating-point JSON numbers are unsupported.',
        );
      }
    }
    final parsed = int.tryParse(_source.substring(start, _offset));
    if (parsed == null) {
      throw const FormatException('JSON integer is outside the valid domain.');
    }
    return parsed;
  }

  Object? _parseLiteral(String spelling, Object? value) {
    if (!_source.startsWith(spelling, _offset)) {
      throw FormatException('Invalid JSON literal at offset $_offset.');
    }
    _offset += spelling.length;
    return value;
  }

  void _skipWhitespace() {
    while (_offset < _source.length) {
      final unit = _source.codeUnitAt(_offset);
      if (unit != 0x20 && unit != 0x0A && unit != 0x0D && unit != 0x09) {
        return;
      }
      _offset += 1;
    }
  }

  bool _consume(int expected) {
    if (_offset >= _source.length || _source.codeUnitAt(_offset) != expected) {
      return false;
    }
    _offset += 1;
    return true;
  }

  void _expect(int expected, String description) {
    if (!_consume(expected)) {
      throw FormatException('Expected $description at offset $_offset.');
    }
  }

  static bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;

  static bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;
}
