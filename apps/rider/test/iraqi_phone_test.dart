import 'package:flutter_test/flutter_test.dart';
import 'package:rider/core/iraqi_phone.dart';

void main() {
  group('IraqiPhone.normalize', () {
    test('accepts local, national, +964 and 00964 forms', () {
      const canonical = '+9647701234567';
      expect(IraqiPhone.normalize('07701234567'), canonical); // local
      expect(IraqiPhone.normalize('7701234567'), canonical); // national
      expect(IraqiPhone.normalize('+9647701234567'), canonical); // e164
      expect(IraqiPhone.normalize('9647701234567'), canonical); // no +
      expect(IraqiPhone.normalize('009647701234567'), canonical); // 00 intl
      expect(IraqiPhone.normalize('077 0123 4567'), canonical); // spaced
      expect(IraqiPhone.normalize('(077)0-123-4567'), canonical); // punctuation
    });

    test('rejects non-Iraqi-mobile numbers', () {
      expect(IraqiPhone.normalize(''), isNull);
      expect(IraqiPhone.normalize('12345'), isNull); // too short
      expect(IraqiPhone.normalize('06701234567'), isNull); // not a 7-prefix
      expect(IraqiPhone.normalize('077012345678'), isNull); // too long
      expect(IraqiPhone.normalize('+9639771234567'), isNull); // wrong country
      expect(IraqiPhone.normalize('abcdefghij'), isNull);
    });

    test('isValid mirrors normalize', () {
      expect(IraqiPhone.isValid('07701234567'), isTrue);
      expect(IraqiPhone.isValid('123'), isFalse);
    });
  });
}
