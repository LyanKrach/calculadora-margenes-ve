import 'package:flutter/material.dart';

/// Tokens de color del sistema de diseño de MargenCalcu para modo oscuro y claro.
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
    background: Color(0xFF0A0E13),
    surface: Color(0xFF12181F),
    surfaceElevated: Color(0xFF1A222C),
    borderSubtle: Color(0x14FFFFFF), // blanco al 8%
    borderStrong: Color(0x24FFFFFF), // blanco al 14%
    primary: Color(0xFF22C55E),
    primaryDark: Color(0xFF16A34A),
    heroGradientStart: Color(0xFF133322),
    heroGradientEnd: Color(0xFF0D1C14),
    heroBorder: Color(0x7322C55E),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFF94A3B8),
    textMuted: Color(0xFF64748B),
    amber: Color(0xFFF59E0B),
    blue: Color(0xFF3B82F6),
    danger: Color(0xFFEF4444),
  );

  static const AppColors light = AppColors(
    background: Color(0xFFF4F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFEDF2F7),
    borderSubtle: Color(0xFFE2E8F0),
    borderStrong: Color(0xFFCBD5E1),
    primary: Color(0xFF16A34A),
    primaryDark: Color(0xFF15803D),
    heroGradientStart: Color(0xFFECFDF5),
    heroGradientEnd: Color(0xFFD1FAE5),
    heroBorder: Color(0x6616A34A),
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
      heroGradientStart:
          Color.lerp(heroGradientStart, other.heroGradientStart, t)!,
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
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      color: context.appColors.textPrimary,
    );
  }

  static TextStyle overlineLabel(BuildContext context) {
    return TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.7,
      color: context.appColors.textSecondary,
    );
  }

  static TextStyle rateValue(BuildContext context) {
    return TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: context.appColors.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

/// Definición centralizada de [ThemeData] oscuro y claro para MargenCalcu.
class AppTheme {
  const AppTheme._();

  static const Color brandSeedColor = Color(0xFF22C55E);

  static ThemeData get darkTheme => _buildTheme(
        brightness: Brightness.dark,
        colors: AppColors.dark,
      );

  static ThemeData get lightTheme => _buildTheme(
        brightness: Brightness.light,
        colors: AppColors.light,
      );

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
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
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
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.borderSubtle),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceElevated,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
        hintStyle: TextStyle(color: colors.textMuted, fontSize: 14),
        prefixStyle: TextStyle(
          color: colors.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        suffixStyle: TextStyle(
          color: colors.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.danger, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.danger, width: 1.8),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        elevation: 0,
        height: 70,
        indicatorColor: colors.primary.withValues(alpha: isDark ? 0.18 : 0.14),
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? colors.primary : colors.textSecondary,
            size: 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? colors.primary : colors.textSecondary,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surface,
        selectedColor: colors.primary.withValues(alpha: isDark ? 0.18 : 0.14),
        side: BorderSide(color: colors.borderSubtle),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
        secondaryLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: colors.primary,
        ),
        checkmarkColor: colors.primary,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.primary.withValues(alpha: isDark ? 0.20 : 0.14);
            }
            return colors.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.primary;
            }
            return colors.textSecondary;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return BorderSide(color: colors.primary.withValues(alpha: 0.7));
            }
            return BorderSide(color: colors.borderSubtle);
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: isDark ? const Color(0xFF04140A) : Colors.white,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.borderStrong),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primary,
        foregroundColor: isDark ? const Color(0xFF04140A) : Colors.white,
        shape: const StadiumBorder(),
        elevation: 2,
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: colors.primary,
        labelColor: colors.primary,
        unselectedLabelColor: colors.textSecondary,
        dividerColor: colors.borderSubtle,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
      ),
      dividerTheme: DividerThemeData(
        color: colors.borderSubtle,
        thickness: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.borderSubtle),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceElevated,
        contentTextStyle: TextStyle(color: colors.textPrimary, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.borderSubtle),
        ),
      ),
    );
  }
}
