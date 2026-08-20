/// Tally theme — the "calm ledger" design system from docs/DESIGN.md.
///
/// Dark-first near-black ink surfaces, one warm-lime accent used sparingly,
/// oversized tabular-figure numerals, hairline borders, 20-24 px radii, and
/// fade-through page transitions.
library;

import 'package:flutter/material.dart';

// ---- tokens -----------------------------------------------------------------

/// Design tokens as a [ThemeExtension] so every widget reads
/// `context.tokens.*` instead of hard-coding colors.
class TallyTokens extends ThemeExtension<TallyTokens> {
  const TallyTokens({
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
    required this.income,
    required this.expense,
    required this.danger,
  });

  final Color bg;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color onAccent;
  final Color income;
  final Color expense;
  final Color danger;

  /// DESIGN.md dark token table, verbatim.
  static const dark = TallyTokens(
    bg: Color(0xFF0E0F0C),
    surface: Color(0xFF171814),
    surfaceRaised: Color(0xFF1E201A),
    border: Color(0x14FFFFFF),
    textPrimary: Color(0xFFF4F5EF),
    textSecondary: Color(0xFF9A9C92),
    accent: Color(0xFFC8F55A),
    onAccent: Color(0xFF10120B),
    income: Color(0xFFC8F55A),
    expense: Color(0xFFF4F5EF), // spending is normal life, not an error
    danger: Color(0xFFE86A5A),
  );

  /// Light mirror per DESIGN.md.
  static const light = TallyTokens(
    bg: Color(0xFFF7F7F2),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF1F2EA),
    border: Color(0x12000000),
    textPrimary: Color(0xFF191B14),
    textSecondary: Color(0xFF71746A),
    accent: Color(0xFF3E7C4F),
    onAccent: Color(0xFFF7F7F2),
    income: Color(0xFF3E7C4F),
    expense: Color(0xFF191B14),
    danger: Color(0xFFC44F3E),
  );

  @override
  TallyTokens copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? onAccent,
    Color? income,
    Color? expense,
    Color? danger,
  }) {
    return TallyTokens(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      income: income ?? this.income,
      expense: expense ?? this.expense,
      danger: danger ?? this.danger,
    );
  }

  @override
  TallyTokens lerp(TallyTokens? other, double t) {
    if (other == null) return this;
    return TallyTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension TallyTokensX on BuildContext {
  TallyTokens get tokens => Theme.of(this).extension<TallyTokens>()!;
}

// ---- helpers ------------------------------------------------------------------

/// Every money value in the app renders with tabular figures.
const List<FontFeature> kTabularFigures = [FontFeature.tabularFigures()];

const String kFontFamily = 'Manrope';

/// Adds tabular figures to any style — use for ALL money text.
TextStyle money(TextStyle base) => base.copyWith(fontFeatures: kTabularFigures);

/// Parses a contract `#RRGGBB` string into a [Color].
Color colorFromHex(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFF8E8E93);
}

// ---- motion ---------------------------------------------------------------------

/// Material fade-through used for every full-page transition
/// (250-300 ms, never a hard cut).
class FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeThroughPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeThroughTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// Incoming page fades in late + scales 0.97 -> 1; outgoing fades out early.
class FadeThroughTransition extends StatelessWidget {
  const FadeThroughTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fadeIn = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.30, 1.0, curve: Curves.easeOutCubic),
    );
    final scaleIn = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
    );
    final fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: const Interval(0.0, 0.35, curve: Curves.easeInCubic),
      ),
    );
    return FadeTransition(
      opacity: fadeOut,
      child: FadeTransition(
        opacity: fadeIn,
        child: ScaleTransition(scale: scaleIn, child: child),
      ),
    );
  }
}

// ---- theme ------------------------------------------------------------------------

ThemeData tallyTheme(Brightness brightness) {
  final t = brightness == Brightness.dark ? TallyTokens.dark : TallyTokens.light;

  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer: t.accent,
    onPrimaryContainer: t.onAccent,
    secondary: t.accent,
    onSecondary: t.onAccent,
    secondaryContainer: t.surfaceRaised,
    onSecondaryContainer: t.textPrimary,
    error: t.danger,
    onError: Colors.white,
    surface: t.surface,
    onSurface: t.textPrimary,
    onSurfaceVariant: t.textSecondary,
    outline: t.border,
    outlineVariant: t.border,
    surfaceContainerLowest: t.bg,
    surfaceContainerLow: t.surface,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.surfaceRaised,
    surfaceContainerHighest: t.surfaceRaised,
    inverseSurface: t.textPrimary,
    onInverseSurface: t.bg,
  );

  TextStyle style(double size, FontWeight weight,
      {double? spacing, double? height, Color? color}) {
    return TextStyle(
      fontFamily: kFontFamily,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: spacing,
      height: height,
      color: color ?? t.textPrimary,
    );
  }

  final textTheme = TextTheme(
    // Hero numerals — oversized, tight tracking (add kTabularFigures via money()).
    displayLarge: style(56, FontWeight.w800, spacing: -1.8, height: 1.02),
    displayMedium: style(40, FontWeight.w800, spacing: -1.2, height: 1.05),
    displaySmall: style(32, FontWeight.w800, spacing: -0.8, height: 1.1),
    headlineMedium: style(24, FontWeight.w700, spacing: -0.5),
    headlineSmall: style(20, FontWeight.w700, spacing: -0.4),
    titleLarge: style(22, FontWeight.w800, spacing: -0.5),
    titleMedium: style(16, FontWeight.w600, spacing: -0.2),
    titleSmall: style(14, FontWeight.w600),
    bodyLarge: style(15, FontWeight.w500),
    bodyMedium: style(14, FontWeight.w500),
    bodySmall: style(12, FontWeight.w400, color: t.textSecondary),
    labelLarge: style(15, FontWeight.w600),
    labelMedium: style(12, FontWeight.w600, spacing: 0.2),
    labelSmall:
        style(11, FontWeight.w700, spacing: 1.2, color: t.textSecondary),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: kFontFamily,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    textTheme: textTheme,
    extensions: [t],
    splashFactory: InkRipple.splashFactory,
    splashColor: t.textPrimary.withValues(alpha: 0.04),
    highlightColor: t.textPrimary.withValues(alpha: 0.03),
    hoverColor: t.textPrimary.withValues(alpha: 0.03),
    dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: t.textSecondary, size: 22),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeThroughPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeThroughPageTransitionsBuilder(),
        TargetPlatform.windows: FadeThroughPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeThroughPageTransitionsBuilder(),
        TargetPlatform.linux: FadeThroughPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeThroughPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
      iconTheme: IconThemeData(color: t.textPrimary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      hintStyle: textTheme.bodyLarge!.copyWith(color: t.textSecondary),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: t.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: t.accent, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: t.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: t.danger, width: 1.4),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: t.border),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.accent,
      selectionColor: t.accent.withValues(alpha: 0.28),
      selectionHandleColor: t.accent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surfaceRaised,
      contentTextStyle: textTheme.bodyLarge,
      actionTextColor: t.accent,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: t.border),
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: t.border),
      ),
      titleTextStyle: textTheme.headlineSmall,
      contentTextStyle: textTheme.bodyLarge!.copyWith(color: t.textSecondary),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: t.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      headerHeadlineStyle: textTheme.displaySmall,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: t.border),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accent,
      refreshBackgroundColor: t.surfaceRaised,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.accent,
        textStyle: textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w700),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.textSecondary,
      textColor: t.textPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
  );
}
