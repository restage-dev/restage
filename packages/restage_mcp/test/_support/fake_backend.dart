import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart' show encodeByteDataWire;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show DeliveryMeasurementMutationReviewV1, CanonicalDigest;

/// One backend call a fake answers: the endpoint path and the JSON body.
class BackendCall {
  BackendCall(this.endpoint, this.body);

  final String endpoint;
  final Map<String, dynamic> body;

  String get method => body['method'] as String;
}

/// A target the discovery fake lists.
typedef FakeTarget = ({int id, String slug, String plane});

/// The default targets: `staging` on the sandbox plane, `production` on
/// both planes.
const List<FakeTarget> defaultTargets = [
  (id: 42, slug: 'staging', plane: 'sandbox'),
  (id: 43, slug: 'production', plane: 'sandbox'),
  (id: 44, slug: 'production', plane: 'live'),
];

/// A mock backend that answers organization, app and target discovery, and
/// hands every other call to [handler]. Records every call in [calls].
MockClient fakeBackend(
  Future<http.Response> Function(BackendCall call) handler, {
  List<BackendCall>? calls,
  List<Map<String, Object?>> organizations = const [
    {'organizationId': 7, 'slug': 'acme', 'name': 'Acme', 'role': 'admin'},
  ],
  String appSlug = 'mobile',
  List<FakeTarget> targets = defaultTargets,
  List<Map<String, Object?>> scopeSurfaces = const [],
  bool withDefaultSurfaceReview = true,
}) {
  return MockClient((request) async {
    final call = BackendCall(
      request.url.pathSegments.isEmpty ? '' : request.url.pathSegments.last,
      jsonDecode(request.body) as Map<String, dynamic>,
    );
    calls?.add(call);
    if (withDefaultSurfaceReview &&
        call.endpoint == 'surface' &&
        call.method == 'reviewDeliveryImpact') {
      final review = DeliveryMeasurementMutationReviewV1(
        operation: call.body['operation'] as String,
        reviews: const [],
        dependencyDigest: CanonicalDigest('a' * 64),
      );
      return http.Response(
        jsonEncode(encodeByteDataWire(review.canonicalBytes)),
        200,
      );
    }
    switch (call.method) {
      case 'read':
        if (call.endpoint != 'scope') break;
        final selectedOrganizationId =
            call.body['organizationId'] as int? ??
            (organizations.firstOrNull?['organizationId'] as int? ?? 0);
        return http.Response(
          jsonEncode({
            'organizationId': selectedOrganizationId,
            'session': {
              'memberships': organizations,
              'workspaceExperiences': <Object>[],
            },
            'projects': [
              for (final slug in ['demo', 'default', 'checkout', 'project'])
                {'id': 1, 'slug': slug, 'name': slug},
            ],
            'apps': [
              {'id': 11, 'projectId': 1, 'slug': appSlug, 'name': appSlug},
            ],
            'environments': [
              for (final target in targets)
                {
                  'id': target.id,
                  'appId': 11,
                  'namedEnvironmentId': target.id * 10,
                  'slug': target.slug,
                },
            ],
            'environmentTargets': [
              for (final target in targets) _targetJson(target),
            ],
            'surfaces': [
              for (final surface in scopeSurfaces) {'appId': 11, ...surface},
            ],
            'apiKeys': <Object>[],
          }),
          200,
        );
      case 'listMine':
        return http.Response(jsonEncode(organizations), 200);
      case 'listApps':
        return http.Response(
          jsonEncode([
            {'id': 11, 'slug': appSlug, 'name': 'Mobile'},
          ]),
          200,
        );
      case 'listEnvironmentTargets':
        final plane = call.body['runtimePlane'] as String?;
        return http.Response(
          jsonEncode([
            for (final target in targets)
              if (plane == null || target.plane == plane)
                {
                  'environmentTargetId': target.id,
                  'namedEnvironmentId': target.id * 10,
                  'environmentSlug': target.slug,
                  'runtimePlane': target.plane,
                },
          ]),
          200,
        );
      case 'resolveTarget':
        return _resolveTarget(call.body, organizations, appSlug, targets);
    }
    return handler(call);
  });
}

Map<String, Object?> _targetJson(FakeTarget target) => {
  'environmentTargetId': target.id,
  'namedEnvironmentId': target.id * 10,
  'environmentSlug': target.slug,
  'runtimePlane': target.plane,
};

/// The server's `environment.resolveTarget` over the fake's discovery data.
http.Response _resolveTarget(
  Map<String, dynamic> body,
  List<Map<String, Object?>> organizations,
  String appSlug,
  List<FakeTarget> targets,
) {
  final organizationId = body['organizationId'] as int?;
  final organizationSlug = body['organizationSlug'] as String?;
  final named = organizationId != null || organizationSlug != null;
  final matching = [
    for (final organization in organizations)
      if ((organizationId == null ||
              organization['organizationId'] == organizationId) &&
          (organizationSlug == null ||
              organization['slug'] == organizationSlug))
        organization,
  ];
  if (organizations.isEmpty) {
    return typedError('TargetSelectionRefusedException', {
      'reason': 'noOrganization',
    });
  }
  if (named && matching.isEmpty) {
    return typedError('TargetSelectionRefusedException', {
      'reason': 'organizationNotFound',
    });
  }
  if (!named && matching.length > 1) {
    return typedError('TargetSelectionRefusedException', {
      'reason': 'multipleOrganizations',
      'organizationSlugs': [for (final o in matching) o['slug']],
    });
  }
  final organization = matching.first;
  final environment = body['environmentSlug'] as String?;
  final plane = body['runtimePlane'] as String?;
  final targetId = body['environmentTargetId'] as int?;
  Map<String, Object?>? target;
  if (environment == null && (plane != null || targetId != null)) {
    return typedError('TargetSelectionRefusedException', {
      'reason': 'environmentNotFound',
      'environmentSlug': '',
    });
  }
  if (environment != null) {
    final bySlug = [
      for (final t in targets)
        if (t.slug == environment) t,
    ];
    final hits = [
      for (final t in bySlug)
        if ((plane == null || t.plane == plane) &&
            (targetId == null || t.id == targetId))
          t,
    ];
    if (hits.length != 1) {
      return typedError('TargetSelectionRefusedException', {
        'reason': hits.length > 1
            ? 'environmentOnBothPlanes'
            : bySlug.isNotEmpty && plane != null && targetId == null
            ? 'noTargetOnPlane'
            : 'environmentNotFound',
        'environmentSlug': environment,
        if (hits.length > 1)
          'candidates': {
            'items': [for (final t in hits) _targetJson(t)],
          },
      });
    }
    target = _targetJson(hits.single);
  }
  return http.Response(
    jsonEncode({
      'organizationId': organization['organizationId'],
      'organizationSlug': organization['slug'],
      'projectSlug': body['projectSlug'],
      'appId': 11,
      'appSlug': appSlug,
      'target': ?target,
    }),
    200,
  );
}

/// A typed backend refusal body with [className] and [data].
http.Response typedError(
  String className,
  Map<String, Object?> data, {
  int status = 400,
}) => http.Response(
  jsonEncode({
    'className': className,
    'data': {'__className__': className, ...data},
  }),
  status,
);
