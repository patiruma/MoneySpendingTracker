import 'package:flutter_test/flutter_test.dart';
import 'package:money_spending_tracker/core/ids.dart';

void main() {
  test('newId generates unique UUID v7 strings', () {
    final String a = newId();
    final String b = newId();
    expect(a, isNot(equals(b)));
    expect(a, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
  });
}
