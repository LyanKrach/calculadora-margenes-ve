import 'package:flutter/material.dart';

/// Tokens de color del sistema de diseño de MargenCalcu (estilo ArbiCalc en capas + verde de marca).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.borderSubtle,
    required this.borderStrong,
    required this.primary,
    required this.primaryDark,
    required this.heroGradientStart,
    required this.heroGradientEnd,
    required this.heroBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.amber,
    required this.blue,
    required this.danger,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color borderSubtle;
  final Color borderStrong;
  final Color primary;
  final Color primaryDark;
  final Color heroGradientStart;
  final Color heroGradientEnd;
  final Color heroBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color amber;
  final Color blue;
  final Color danger;

  static const AppColors dark = AppColors(
    background: Color(0xFF080C10),
    surface: Color(0xFF111821),
    surfaceElevated: Color(0xFF18222F),
    borderSubtle: Color(0xFF243244),
    borderStrong: Color(0xFF33465E),
    primary: Color(0xFF22C55E),
    primaryDark: Color(0xFF16A34A),
    heroGradientStart: Color(0xFF16A34A),
    heroGradientEnd: Color(0xFF15803D),
    heroBorder: Color(0xCC4ADE80),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFCBD5E1),
    textMuted: Color(0xFF94A3B8),
    amber: Color(0xFFF59E0B),
    blue: Color(0xFF3B82F6),
    danger: Color(0xFFEF4444),
  );

  static const AppColors light = AppColors(
    background: Color(0xFFF1F5F9),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFE8EEF5),
    borderSubtle: Color(0xFFD8E1EC),
    borderStrong: Color(0xFFCBD5E1),
    primary: Color(0xFF16A34A),
    primaryDark: Color(0xFF15803D),
    heroGradientStart: Color(0xFF16A34A),
    heroGradientEnd: Color(0xFF15803D),
    heroBorder: Color(0xFF22C55E),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF64748B),
    amber: Color(0xFFD97706),
    blue: Color(0xFF2563EB),
    danger: Color(0xFFDC2626),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? borderSubtle,
    Color? borderStrong,
    Color? primary,
    Color? primaryDark,
    Color? heroGradientStart,
    Color? heroGradientEnd,
    Color? heroBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? amber,
    Color? blue,
    Color? danger,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      primary: primary ?? this.primary,
      primaryDark: primaryDark ?? this.primaryDark,
      heroGradientStart: heroGradientStart ?? this.heroGradientStart,
      heroGradientEnd: heroGradientEnd ?? this.heroGradientEnd,
      heroBorder: heroBorder ?? this.heroBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      amber: amber ?? this.amber,
      blue: blue ?? this.blue,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      heroGradientStart: Color.lerp(
        heroGradientStart,
        other.heroGradientStart,
        t,
      )!,
      heroGradientEnd: Color.lerp(heroGradientEnd, other.heroGradientEnd, t)!,
      heroBorder: Color.lerp(heroBorder, other.heroBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// Acceso directo a los tokens [AppColors] desde cualquier [BuildContext].
extension AppThemeContext on BuildContext {
  AppColors get appColors {
    final ext = Theme.of(this).extension<AppColors>();
    if (ext != null) return ext;
    return Theme.of(this).brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;
  }
}

/// Jerarquía tipográfica propia usando la fuente del sistema con números tabulares.
class AppTypography {
  const AppTypography._();

  static TextStyle heroPrice(BuildContext context) {
    return TextStyle(
      fontSize: 44,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
      height: 1.05,
      color: context.appColors.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle sectionTitle(BuildContext context) {
    return TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      color: context.appColors.textPrimary,
    );
  }

  static TextStyle overlineLabel(BuildContext context) {
    return TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.7,
      color: context.appColors.textSecondary,
    );
  }

  static TextStyle rateValue(BuildContext context) {
    return TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w800,
      color: context.appColors.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

/// Definición centralizada de [ThemeData] oscuro y claro para MargenCalcu.
class AppTheme {
  const AppTheme._();

  static const Color brandSeedColor = Color(0xFF22C55E);

  static ThemeData get darkTheme =>
      _buildTheme(brightness: Brightness.dark, colors: AppColors.dark);

  static ThemeData get lightTheme =>
      _buildTheme(brightness: Brightness.light, colors: AppColors.light);

  static ThemeData _buildTheme({
    required Brightness brightness,
    required AppColors colors,
  }) {
    final isDark = brightness == Brightness.dark;
    final baseScheme = ColorScheme.fromSeed(
      seedColor: brandSeedColor,
      brightness: brightness,
      primary: colors.primary,
      onPrimary: isDark ? const Color(0xFF04140A) : Colors.white,
      surface: colors.surface,
      onSurface: colors.textPrimary,
    );

    final colorScheme = baseScheme.copyWith(
      primaryContainer: isDark
          ? const Color(0xFF133322)
          : const Color(0xFFDCFCE7),
      onPrimaryContainer: isDark
          ? const Color(0xFFDCFCE7)
          : const Color(0xFF052E16),
      surfaceContainerHighest: colors.surfaceElevated,
      outline: colors.borderStrong,
      outlineVariant: colors.borderSubtle,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.surface,
      dividerColor: colors.borderSubtle,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 54,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: colors.textPrimary,
        ),
        iconTheme: IconThemeData(color: colors.textSecondary),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.borderSubtle),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        labelStyle: TextStyle(
          color: colors.textMuted,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: TextStyle(
          color: colors.primary,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
        prefixStyle: TextStyle(
          color: colors.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        suffixStyle: TextStyle(
          color: colors.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.danger, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.danger, width: 1.8),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 60,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: const Color(0xFF22C55E),
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? const Color(0xFF04140A) : colors.textMuted,
            size: 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? colors.primary : colors.textMuted,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceElevated,
        selectedColor: colors.primary.withValues(alpha: 0.22),
        side: WidgetStateBorderSide.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return BorderSide(
            color: selected ? colors.primary : colors.borderSubtle,
            width: selected ? 1.4 : 1.0,
          );
        }),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        labelStyle: WidgetStateTextStyle.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? colors.primary : colors.textSecondary,
          );
        }),
        secondaryLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: colors.primary,
        ),
        checkmarkColor: colors.primary,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.primary;
            }
            return colors.surfaceElevated;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return isDark ? const Color(0xFF04140A) : Colors.white;
            }
            return colors.textSecondary;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return BorderSide(color: colors.primary);
            }
            return BorderSide(color: colors.borderSubtle);
          }),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF22C55E),
          foregroundColor: const Color(0xFF04140A),
          disabledBackgroundColor: colors.surfaceElevated,
          disabledForegroundColor: colors.textMuted,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.borderStrong, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: const Color(0xFF22C55E),
        foregroundColor: const Color(0xFF04140A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        elevation: 4,
        extendedTextStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13.5,
          letterSpacing: 0.1,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: colors.primary,
        labelColor: colors.primary,
        unselectedLabelColor: colors.textSecondary,
        dividerColor: colors.borderSubtle,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      dividerTheme: DividerThemeData(color: colors.borderSubtle, thickness: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.borderSubtle),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceElevated,
        contentTextStyle: TextStyle(color: colors.textPrimary, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.borderStrong),
        ),
      ),
    );
  }
}
