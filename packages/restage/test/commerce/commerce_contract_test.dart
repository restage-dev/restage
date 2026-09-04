import 'package:flutter_test/flutter_test.dart';
import 'package:restage/commerce.dart' as commerce;
import 'package:restage/restage.dart' show Restage, RestageEnvironment;

void main() {
  group('commerce values', () {
    test('offer IDs preserve valid logical selectors and reject invalid input',
        () {
      final first = commerce.CommerceOfferId('offer.monthly_intro');
      final equal = commerce.CommerceOfferId('offer.monthly_intro');

      expect(first.value, 'offer.monthly_intro');
      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(first.toString(), 'offer.monthly_intro');
      expect(
        () => commerce.CommerceOfferId('Offer/monthly'),
        throwsFormatException,
      );
    });

    test('open codes retain known values and preserve unknown values', () {
      final capability = commerce.CommerceCapabilityCode('purchase');
      final futureCapability = commerce.CommerceCapabilityCode('future.code');
      final status = commerce.CommerceActionStatusCode('pending');
      final failure = commerce.CommerceFailureCode('not_activated');
      final purchaserState = commerce.CommercePurchaserStateStatusCode('stale');

      expect(capability, same(commerce.CommerceCapabilityCode.purchase));
      expect(capability.isKnown, isTrue);
      expect(futureCapability.value, 'future.code');
      expect(futureCapability.isKnown, isFalse);
      expect(status, same(commerce.CommerceActionStatusCode.pending));
      expect(failure, same(commerce.CommerceFailureCode.notActivated));
      expect(
        purchaserState,
        same(commerce.CommercePurchaserStateStatusCode.stale),
      );
      expect(
        () => commerce.CommerceFailureCode('NotActivated'),
        throwsFormatException,
      );
    });

    test('typed requests use value equality and response bounds', () {
      final offer = commerce.CommerceOfferId('offer.monthly');
      final availability = commerce.CommerceAvailabilityRequest(
        commerce.CommerceCapabilityCode.purchase,
        offerId: offer,
      );

      expect(
        availability,
        commerce.CommerceAvailabilityRequest(
          commerce.CommerceCapabilityCode('purchase'),
          offerId: commerce.CommerceOfferId('offer.monthly'),
        ),
      );
      expect(
        commerce.CommercePurchaseRequest(offer),
        commerce.CommercePurchaseRequest(
            commerce.CommerceOfferId('offer.monthly')),
      );
      expect(
        const commerce.CommerceRestoreRequest(),
        const commerce.CommerceRestoreRequest(),
      );
      expect(
        const commerce.CommerceRefreshRequest(),
        const commerce.CommerceRefreshRequest(),
      );
      expect(
        availability,
        isA<commerce.CommerceRequest<commerce.CommerceAvailability>>(),
      );
      expect(
        commerce.CommercePurchaseRequest(offer),
        isA<commerce.CommerceRequest<commerce.CommerceActionResult>>(),
      );
    });
  });

  group('commerce facade', () {
    test('is retained across reset and replays unavailable state', () async {
      final facade = Restage.commerce;
      final currentState = facade.currentState;
      final states = <commerce.CommercePurchaserState>[];
      final subscription = facade.states.listen(states.add);
      addTearDown(subscription.cancel);

      Restage.reset();

      expect(Restage.commerce, same(facade));
      expect(facade.currentState, same(currentState));
      expect(
        currentState.status,
        same(commerce.CommercePurchaserStateStatusCode.unavailable),
      );
      expect(states, [same(currentState)]);
      expect(await facade.refresh(), same(currentState));
    });

    test('reports unavailable operations without changing purchaser state',
        () async {
      final facade = Restage.commerce;
      final state = facade.currentState;
      final offer = commerce.CommerceOfferId('offer.monthly');

      final available = await facade.availability(
        commerce.CommerceAvailabilityRequest(
          commerce.CommerceCapabilityCode.purchase,
          offerId: offer,
        ),
      );
      final unknown = await facade.availability(
        commerce.CommerceAvailabilityRequest(
          commerce.CommerceCapabilityCode('future.capability'),
        ),
      );
      final invalid = await facade.availability(
        commerce.CommerceAvailabilityRequest(
          commerce.CommerceCapabilityCode.restore,
          offerId: offer,
        ),
      );
      final purchase = await facade.purchase(
        commerce.CommercePurchaseRequest(offer),
      );
      final restore = await facade.restore();
      final matchingAvailability = await facade.availability(
        commerce.CommerceAvailabilityRequest(
          commerce.CommerceCapabilityCode('purchase'),
          offerId: commerce.CommerceOfferId('offer.monthly'),
        ),
      );
      final matchingPurchase = await facade.purchase(
        commerce.CommercePurchaseRequest(
          commerce.CommerceOfferId('offer.monthly'),
        ),
      );
      final matchingRestore = await facade.restore();
      final performed = await facade.perform(
        const commerce.CommerceRefreshRequest(),
      );

      expect(available.available, isFalse);
      expect(
        available.failureCode,
        same(commerce.CommerceFailureCode.notActivated),
      );
      expect(
        unknown.failureCode,
        same(commerce.CommerceFailureCode.unsupportedCapability),
      );
      expect(
        invalid.failureCode,
        same(commerce.CommerceFailureCode.invalidRequest),
      );
      expect(available, matchingAvailability);
      expect(available.hashCode, matchingAvailability.hashCode);
      expect(purchase, matchingPurchase);
      expect(purchase.hashCode, matchingPurchase.hashCode);
      expect(restore, matchingRestore);
      expect(restore.hashCode, matchingRestore.hashCode);
      for (final result in [purchase, restore]) {
        expect(
          result.status,
          same(commerce.CommerceActionStatusCode.unavailable),
        );
        expect(
          result.failureCode,
          same(commerce.CommerceFailureCode.notActivated),
        );
      }
      expect(performed, same(state));
      expect(facade.currentState, same(state));
    });

    test('ordinary configuration does not activate or replace commerce',
        () async {
      Restage.debugReset();
      addTearDown(Restage.debugReset);

      final facade = Restage.commerce;
      final initialState = facade.currentState;
      final observedStates = <commerce.CommercePurchaserState>[];
      final subscription = facade.states.listen(observedStates.add);
      addTearDown(subscription.cancel);
      final offer = commerce.CommerceOfferId('offer.monthly');

      Restage.configure(
        apiKey: 'rs_pk_test',
        baseUrl: 'https://api.example.com',
        environment: RestageEnvironment.sandbox,
      );

      final availability = await facade.availability(
        commerce.CommerceAvailabilityRequest(
          commerce.CommerceCapabilityCode.purchase,
          offerId: offer,
        ),
      );
      final purchase = await facade.purchase(
        commerce.CommercePurchaseRequest(offer),
      );

      expect(Restage.commerce, same(facade));
      expect(facade.currentState, same(initialState));
      expect(observedStates, [same(initialState)]);
      expect(availability.available, isFalse);
      expect(
        availability.failureCode,
        same(commerce.CommerceFailureCode.notActivated),
      );
      expect(
        purchase.status,
        same(commerce.CommerceActionStatusCode.unavailable),
      );
      expect(
        purchase.failureCode,
        same(commerce.CommerceFailureCode.notActivated),
      );
    });
  });
}
