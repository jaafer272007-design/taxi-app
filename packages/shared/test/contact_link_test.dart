import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

/// The URI rules, as pure string assertions.
///
/// Every one of these is a mistake that fails ONLY on a real device: a `+` in a
/// wa.me link lands on WhatsApp's "invalid number" page, a `geo:` without `q=`
/// centres the map without dropping a pin, and a local-format `tel:` fails from
/// a roaming SIM. None of them throw, none of them log, and none of them are
/// visible from inside the app — which is exactly why they are pinned here.
void main() {
  const phone = '+9647701234567';

  group('ContactLink.tel', () {
    test('keeps the + and the country code', () {
      expect(ContactLink.tel(phone).toString(), 'tel:+9647701234567');
    });

    test('promotes the local 0770… form to E.164', () {
      // A number typed by hand into the database dials fine inside Iraq and
      // fails from abroad. Normalising means the dialer always gets E.164.
      expect(ContactLink.tel('07701234567').toString(), 'tel:+9647701234567');
    });

    test('strips spaces and dashes a human typed', () {
      expect(ContactLink.tel('+964 770 123 4567').toString(), 'tel:+9647701234567');
      expect(ContactLink.tel('+964-770-123-4567').toString(), 'tel:+9647701234567');
    });
  });

  group('ContactLink.whatsApp', () {
    test('has NO plus sign — wa.me takes bare digits', () {
      // The single character this function exists for.
      final uri = ContactLink.whatsApp(phone);
      expect(uri.toString(), 'https://wa.me/9647701234567');
      expect(uri.toString(), isNot(contains('+')));
    });

    test('strips separators too', () {
      expect(ContactLink.whatsApp('+964 770 123 4567').toString(),
          'https://wa.me/9647701234567');
    });

    test('normalises the local form before stripping', () {
      expect(ContactLink.whatsApp('07701234567').toString(),
          'https://wa.me/9647701234567');
    });
  });

  group('ContactLink.geo', () {
    test('drops a pin, not just a centre', () {
      final uri = ContactLink.geo(32.616, 44.0242, label: 'كراج النجف');
      expect(uri.toString(), startsWith('geo:32.616000,44.024200?q='));
      // `q=` is what makes it a pin. Without it a maps app just centres there.
      expect(Uri.decodeFull(uri.toString()),
          'geo:32.616000,44.024200?q=32.616000,44.024200(كراج النجف)');
    });

    test('omits the empty label rather than emitting "()"', () {
      final uri = ContactLink.geo(32.616, 44.0242);
      expect(Uri.decodeFull(uri.toString()),
          'geo:32.616000,44.024200?q=32.616000,44.024200');
    });

    test('percent-encodes an Arabic label', () {
      final uri = ContactLink.geo(32.0, 44.0, label: 'حي الزيتون');
      // Raw Arabic in a URI is what makes an intent silently fail to resolve.
      expect(uri.toString(), isNot(contains('حي')));
      expect(Uri.decodeFull(uri.toString()), contains('(حي الزيتون)'));
    });
  });

  test('ContactLink.mapsWeb is a universal link, so it works with no maps app',
      () {
    expect(
      ContactLink.mapsWeb(32.616, 44.0242).toString(),
      'https://www.google.com/maps/search/?api=1&query=32.616000,44.024200',
    );
  });

  test('navigation tries geo: first, then the web fallback', () {
    final uris = ContactLink.navigation(
        const LocationPoint(lat: 32.616, lng: 44.0242, label: 'الحرم'));

    expect(uris, hasLength(2));
    expect(uris.first.scheme, 'geo');
    expect(uris.last.scheme, 'https');
  });

  group('ContactLink.display', () {
    test('groups as +964 771 234 5678, in WESTERN digits', () {
      // Deliberate deviation from the Arabic-Indic display rule: a phone number
      // is an identifier to dial and match against the contact list, not a
      // quantity. See docs/PHASE1_BUILD_BRIEF.md.
      expect(ContactLink.display('+9647712345678'), '+964 771 234 5678');
      expect(ContactLink.display('+9647712345678'), isNot(matches(RegExp(r'[٠-٩]'))));
    });

    test('falls back to the raw E.164 for anything unexpected', () {
      // Never throws on bad data: a malformed number still has to render, and a
      // crash on a contact card is worse than an ugly one.
      expect(ContactLink.display('+1234'), '+1234');
    });
  });
}
