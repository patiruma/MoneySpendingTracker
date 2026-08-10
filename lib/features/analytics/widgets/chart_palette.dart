import 'package:flutter/material.dart';

/// Chart color roles, mode-aware.
///
/// These are the documented data-viz palette's slot-1 blue and chrome inks,
/// validated against both surfaces (all six checks pass in light and dark).
/// They are deliberately *not* derived from the app's Material seed color:
/// `ColorScheme` steps are tuned for UI affordances, not for the lightness
/// band and contrast floor that chart marks have to clear.
///
/// Only one hue is needed anywhere in this view. Both charts carry a single
/// series — spending over time, and spending per category — and a nominal
/// breakdown never spends the identity channel re-encoding what bar length
/// already shows. So there is no categorical slot list to cycle through.
class ChartPalette {
  const ChartPalette._({
    required this.series,
    required this.surface,
    required this.gridline,
    required this.axis,
    required this.mutedInk,
    required this.primaryInk,
  });

  factory ChartPalette.of(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const ChartPalette._(
            series: Color(0xFF3987E5),
            surface: Color(0xFF1A1A19),
            gridline: Color(0xFF2C2C2A),
            axis: Color(0xFF383835),
            mutedInk: Color(0xFF898781),
            primaryInk: Color(0xFFFFFFFF),
          )
        : const ChartPalette._(
            series: Color(0xFF2A78D6),
            surface: Color(0xFFFCFCFB),
            gridline: Color(0xFFE1E0D9),
            axis: Color(0xFFC3C2B7),
            mutedInk: Color(0xFF898781),
            primaryInk: Color(0xFF0B0B0B),
          );
  }

  /// Categorical slot 1. The only data hue in this view.
  final Color series;

  /// The color the 2px surface gaps and marker rings are painted in, so
  /// touching marks separate with negative space rather than a stroke.
  final Color surface;

  final Color gridline;
  final Color axis;
  final Color mutedInk;
  final Color primaryInk;

  /// The ~10% wash under the line. Never a saturated block.
  Color get areaFill => series.withValues(alpha: 0.10);
}
