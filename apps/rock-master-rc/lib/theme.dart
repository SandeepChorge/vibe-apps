import 'package:material_ui/material_ui.dart';

class AppColors {
  static const Color bg = Color(0xFF0B0F14);
  static const Color surface = Color(0xFF151C24);
  static const Color surfaceAlt = Color(0xFF1C2630);
  static const Color border = Color(0xFF2A3542);
  static const Color teal = Color(0xFF2EE6C7);
  static const Color tealDim = Color(0xFF1A6F64);
  static const Color amber = Color(0xFFFFC857);
  static const Color rose = Color(0xFFFF6B6B);
  static const Color blue = Color(0xFF5B8CFF);
  static const Color text = Color(0xFFE8EEF4);
  static const Color muted = Color(0xFF8B9AAB);
}

ThemeData buildAppTheme() {
  const ColorScheme scheme = ColorScheme.dark(
    primary: AppColors.teal,
    onPrimary: Color(0xFF04221E),
    secondary: AppColors.amber,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.rose,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: false,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.teal,
      inactiveTrackColor: AppColors.border,
      thumbColor: AppColors.teal,
      overlayColor: AppColors.teal.withValues(alpha: 0.18),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceAlt,
      contentTextStyle: TextStyle(color: AppColors.text),
    ),
  );
}
