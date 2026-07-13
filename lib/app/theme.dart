/// lib/app/theme.dart
///
/// The app's single visual language (Section 10). One deliberate point of
/// view: a dark, instrument-panel look for a voice-first wearable assistant —
/// near-black blue surfaces, a single cyan accent, and a fixed color per
/// pipeline phase so "what is the assistant doing right now" is readable at a
/// glance from across a room. Every screen pulls from here; no screen defines
/// its own colors.
library;

import 'package:flutter/material.dart';

/// Fixed colors for the assistant's pipeline phases. Exposed as a
/// [ThemeExtension] so widgets read them from context instead of hardcoding.
@immutable
class PhaseColors extends ThemeExtension<PhaseColors> {
  final Color idle;
  final Color listening;
  final Color thinking;
  final Color speaking;
  final Color error;

  const PhaseColors({
    required this.idle,
    required this.listening,
    required this.thinking,
    required this.speaking,
    required this.error,
  });

  static const dark = PhaseColors(
    idle: Color(0xFF5C6B7A),
    listening: Color(0xFF35E0D0),
    thinking: Color(0xFFFFC24B),
    speaking: Color(0xFF6FE08A),
    error: Color(0xFFFF6B6B),
  );

  @override
  PhaseColors copyWith({
    Color? idle,
    Color? listening,
    Color? thinking,
    Color? speaking,
    Color? error,
  }) =>
      PhaseColors(
        idle: idle ?? this.idle,
        listening: listening ?? this.listening,
        thinking: thinking ?? this.thinking,
        speaking: speaking ?? this.speaking,
        error: error ?? this.error,
      );

  @override
  PhaseColors lerp(PhaseColors? other, double t) {
    if (other == null) return this;
    return PhaseColors(
      idle: Color.lerp(idle, other.idle, t)!,
      listening: Color.lerp(listening, other.listening, t)!,
      thinking: Color.lerp(thinking, other.thinking, t)!,
      speaking: Color.lerp(speaking, other.speaking, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  // Core palette.
  static const Color _bg = Color(0xFF0B1016); // near-black blue
  static const Color _surface = Color(0xFF121A23);
  static const Color _surfaceHigh = Color(0xFF1B2530);
  static const Color _accent = Color(0xFF35E0D0); // cyan
  static const Color _onBg = Color(0xFFE8EEF4);
  static const Color _onMuted = Color(0xFF8CA0B3);

  /// Spacing scale — use these instead of ad-hoc numbers.
  static const double s1 = 4, s2 = 8, s3 = 12, s4 = 16, s5 = 24, s6 = 32;

  /// One shared corner radius.
  static const double radius = 14;

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: _accent,
          onPrimary: const Color(0xFF04211E),
          surface: _bg,
          onSurface: _onBg,
          surfaceContainerLow: _surface,
          surfaceContainerHighest: _surfaceHigh,
          onSurfaceVariant: _onMuted,
          error: PhaseColors.dark.error,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: _bg,
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );

    return base.copyWith(
      extensions: const [PhaseColors.dark],
      textTheme: base.textTheme
          .apply(bodyColor: _onBg, displayColor: _onBg)
          .copyWith(
            headlineSmall: base.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
            titleMedium: base.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            labelSmall: base.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              color: _onMuted,
            ),
            bodySmall: base.textTheme.bodySmall?.copyWith(color: _onMuted),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        foregroundColor: _onBg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _onBg,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 0,
        shape: shape,
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: const Color(0xFF04211E),
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: s5, vertical: s4),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _onBg,
          side: const BorderSide(color: _surfaceHigh),
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: s4, vertical: s3),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        hintStyle: const TextStyle(color: _onMuted),
        labelStyle: const TextStyle(color: _onMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: _surfaceHigh),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: _surfaceHigh),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: _surfaceHigh,
        side: BorderSide.none,
        labelStyle: const TextStyle(color: _onBg, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius / 2),
        ),
      ),
      dividerTheme: const DividerThemeData(color: _surfaceHigh, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _surfaceHigh,
        contentTextStyle: const TextStyle(color: _onBg),
        behavior: SnackBarBehavior.floating,
        shape: shape,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: _accent),
      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: _onMuted,
        collapsedIconColor: _onMuted,
        textColor: _onBg,
        collapsedTextColor: _onBg,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: _onBg,
        iconColor: _onMuted,
      ),
    );
  }
}
