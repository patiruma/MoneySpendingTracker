import 'package:flutter_test/flutter_test.dart';
import 'package:money_spending_tracker/core/money.dart';

void main() {
  group('Money.tryParse', () {
    test('parses comma-separated thousands', () {
      expect(Money.tryParse('1,234.56'), 123456);
    });

    test('parses plain integer', () {
      expect(Money.tryParse('1234'), 123400);
    });

    test('parses leading-dot decimals', () {
      expect(Money.tryParse('.5'), 50);
    });

    test('parses single-digit cents', () {
      expect(Money.tryParse('1.5'), 150);
    });

    test('rejects zero', () {
      expect(Money.tryParse('0'), isNull);
    });

    test('rejects zero decimal', () {
      expect(Money.tryParse('0.00'), isNull);
    });

    test('rejects negative numbers', () {
      expect(Money.tryParse('-5'), isNull);
    });

    test('rejects non-numeric input', () {
      expect(Money.tryParse('abc'), isNull);
    });

    test('rejects empty input', () {
      expect(Money.tryParse(''), isNull);
    });

    test('rejects blank input', () {
      expect(Money.tryParse('   '), isNull);
    });

    test('rejects garbage with digits', () {
      expect(Money.tryParse('12a34'), isNull);
    });

    test('rejects more than two decimal places', () {
      expect(Money.tryParse('1.005'), isNull);
    });
  });

  group('Money.toDecimalString', () {
    test('formats whole dollars', () {
      expect(Money.toDecimalString(123400), '1234.00');
    });

    test('formats with cents', () {
      expect(Money.toDecimalString(123456), '1234.56');
    });

    test('pads single-digit cents', () {
      expect(Money.toDecimalString(105), '1.05');
    });
  });
}
