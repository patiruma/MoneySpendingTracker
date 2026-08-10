import 'package:intl/intl.dart';

/// Money is always represented as integer cents. Parsing and formatting to/from
/// user-facing text happens only here, at the UI edge.
abstract final class Money {
  static final RegExp _validInput = RegExp(r'^\d{0,3}(,\d{3})*(\.\d{0,2})?$|^\d*(\.\d{0,2})?$');

  /// Parses user-entered text (e.g. "1,234.56", "1234", ".5") into cents.
  /// Returns null for anything <= 0, negative, or non-numeric.
  static int? tryParse(String input) {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    if (!_validInput.hasMatch(trimmed)) return null;

    final String withoutCommas = trimmed.replaceAll(',', '');
    if (withoutCommas.isEmpty || withoutCommas == '.') return null;

    final double? value = double.tryParse(withoutCommas);
    if (value == null) return null;

    final int cents = (value * 100).round();
    if (cents <= 0) return null;
    return cents;
  }

  /// Formats cents as a locale-aware currency string for display.
  static String format(int cents, {String? locale}) {
    final NumberFormat formatter = NumberFormat.simpleCurrency(locale: locale);
    return formatter.format(cents / 100);
  }

  /// Formats cents as a plain decimal string (e.g. for CSV export): "12.34".
  static String toDecimalString(int cents) {
    final bool negative = cents < 0;
    final int absCents = cents.abs();
    final String result = '${absCents ~/ 100}.${(absCents % 100).toString().padLeft(2, '0')}';
    return negative ? '-$result' : result;
  }
}
