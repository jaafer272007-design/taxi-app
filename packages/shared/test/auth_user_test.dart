import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('AuthUser.fromJson', () {
    test('parses gender + profileComplete from the backend', () {
      final u = AuthUser.fromJson(const {
        'id': 'u1',
        'phone': '+9647701234567',
        'name': 'علي حسن',
        'gender': 'MALE',
        'roles': ['RIDER'],
        'profileComplete': true,
      });
      expect(u.gender, Gender.male);
      expect(u.profileComplete, isTrue);
      expect(u.hasName, isTrue);
    });

    test('FEMALE maps to Gender.female', () {
      final u = AuthUser.fromJson(const {
        'id': 'u1',
        'phone': '+9647701234567',
        'name': 'سارة',
        'gender': 'FEMALE',
        'roles': ['RIDER'],
        'profileComplete': true,
      });
      expect(u.gender, Gender.female);
    });

    test('null gender → not complete, even with a name', () {
      final u = AuthUser.fromJson(const {
        'id': 'u1',
        'phone': '+9647701234567',
        'name': 'علي',
        'gender': null,
        'roles': ['RIDER'],
        'profileComplete': false,
      });
      expect(u.gender, isNull);
      expect(u.profileComplete, isFalse);
    });

    test('missing profileComplete falls back to name+gender locally', () {
      final u = AuthUser.fromJson(const {
        'id': 'u1',
        'phone': '+9647701234567',
        'name': 'علي',
        'gender': 'MALE',
        'roles': ['RIDER'],
      });
      expect(u.profileComplete, isTrue);
    });
  });

  group('GenderApi.apiValue', () {
    test('male → MALE, female → FEMALE', () {
      expect(Gender.male.apiValue, 'MALE');
      expect(Gender.female.apiValue, 'FEMALE');
    });
  });
}
