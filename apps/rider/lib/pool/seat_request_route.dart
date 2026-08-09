import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../trip/trip_models.dart' show Corridor;
import 'seat_request_api.dart';
import 'seat_request_form_controller.dart';
import 'seat_request_screen.dart';
import 'seat_requests_controller.dart';

/// Opens «اطلب مقعد» for [corridor] and reloads the rider's requests on success.
///
/// The form controller is owned by the route (`create:`), so leaving the screen
/// disposes it — a half-filled request is not state anything else should hold.
/// The list controller, by contrast, lives at the app shell and is only *told*
/// that something changed, which is what makes the new request already be there
/// when the rider reaches حجوزاتي instead of appearing a poll later.
Future<void> openSeatRequest(BuildContext context, Corridor corridor) async {
  final api = context.read<SeatRequestApi>();
  final requests = context.read<SeatRequestsController>();

  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<SeatRequestFormController>(
        create: (_) => SeatRequestFormController(
          api: api,
          corridorId: corridor.id,
          originCity: corridor.originCity,
          destCity: corridor.destCity,
          // The corridor's suggested price IS the pooled price: a system trip
          // has no driver at request time to set one. That is why this number
          // may be shown to a rider here while `Corridor.suggestedPricePerSeat`
          // must never be shown as "the price" on a driver-posted trip.
          pricePerSeat: corridor.suggestedPricePerSeat,
        ),
        child: const SeatRequestScreen(),
      ),
    ),
  );

  // Silent: the rider is back on the results list and did not ask for this.
  // A failure here costs nothing — the next poll of حجوزاتي picks it up.
  await requests.refreshSilently();
}
