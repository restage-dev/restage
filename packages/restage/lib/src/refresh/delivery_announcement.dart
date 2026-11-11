import 'dart:async';

import 'package:meta/meta.dart' show immutable, internal;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import 'surface_update_channel.dart';

/// A change signal for one delivery scope, with the publication it announces.
@internal
@immutable
final class DeliveryAnnouncement {
  /// Creates an announcement; without [generation] it announces nothing.
  const DeliveryAnnouncement(this.scope, {this.generation, this.want});

  /// The scope that may have changed.
  final DeliveryPolicyScopeV1 scope;

  /// The publication pass that changed it; frames of one pass share it.
  final int? generation;

  /// The records that pass changed, for the resolve to read.
  final String? want;
}

/// A delivery channel whose signals name the publication they announce.
@internal
abstract interface class AnnouncingDeliveryUpdateChannel
    implements DeliveryUpdateChannel {
  /// Like [watchDelivery], with each signal's announcement.
  Stream<DeliveryAnnouncement> watchAnnounced(
    DeliveryPolicyScopeV1 scope, {
    PlacementDeliveryWatchV1? watch,
    Future<PlacementRefreshProbeV1> Function()? reconnectProbe,
  });
}

/// The request a refresh sent for an announcement, and whether an answer to
/// it was taken.
@internal
final class AnnouncedWant {
  /// Creates one for [records]; null names none.
  AnnouncedWant(this.records);

  /// The records the request names, or null.
  final String? records;

  /// Whether an answer to a request carrying this was taken.
  bool met = false;

  /// What that answer read in place of what was named: `key=digest` pairs,
  /// or `*` when the service did not say.
  String? served;

  /// Set by the registry once it records the answer as read.
  void Function()? onDropped;

  /// The surface took the answer but did not show it, so it is not read.
  void drop() {
    met = false;
    final dropped = onDropped;
    onDropped = null;
    dropped?.call();
  }
}

const _announcedWantKey = #restageAnnouncedWant;

/// Runs [body] so the resolves it starts carry [want].
@internal
Future<T> withAnnouncedWant<T>(AnnouncedWant want, Future<T> Function() body) =>
    runZoned(body, zoneValues: {_announcedWantKey: want});

/// The announcement a resolve started here answers, if any.
@internal
AnnouncedWant? get currentAnnouncedWant =>
    Zone.current[_announcedWantKey] as AnnouncedWant?;

/// [earlier] and [later] as one announcement: every record either names, with
/// [later]'s digest where both do, and the newer generation.
@internal
DeliveryAnnouncement mergeAnnouncements(
    DeliveryAnnouncement? earlier, DeliveryAnnouncement later) {
  if (earlier == null) return later;
  final generations = [earlier.generation, later.generation].nonNulls;
  return DeliveryAnnouncement(later.scope,
      generation: generations.isEmpty
          ? null
          : generations.reduce((a, b) => a > b ? a : b),
      want: mergeWantRecords([earlier.want, later.want]));
}

/// The records several wants name together; `*` once any is `*` or the list
/// grows past the header's limit.
@internal
String? mergeWantRecords(Iterable<String?> wants) {
  final named = <String, String>{};
  for (final want in wants.nonNulls) {
    if (want == '*') return '*';
    for (final pair in want.split(',')) {
      final split = pair.lastIndexOf('=');
      if (split <= 0) continue;
      final key = pair.substring(0, split);
      named.remove(key);
      named[key] = pair.substring(split + 1);
    }
  }
  if (named.isEmpty) return null;
  final merged = [
    for (final MapEntry(:key, :value) in named.entries) '$key=$value',
  ].join(',');
  return merged.length >= 2048 ? '*' : merged;
}
