import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color f1Red = Color(0xFFFF1E00);
  static const Color background = Color(0xFF0C0C0E);
  static const Color cardBg = Color(0xFF141418);
  static const Color glassBorder = Color(0xFF2C2C35);
  static const Color textPrimary = Color(0xFFFAFAFA);
  static const Color textSecondary = Color(0xFFA0A0AB);
  static const Color accentNeonGreen = Color(0xFF00FF66);
  static const Color accentNeonBlue = Color(0xFF00E5FF);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.f1Red,
      scaffoldBackgroundColor: AppColors.background,
      cardColor: AppColors.cardBg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.f1Red,
        secondary: AppColors.accentNeonBlue,
        surface: AppColors.cardBg,
        error: Colors.redAccent,
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        const TextTheme(
          displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          bodyLarge: TextStyle(fontSize: 16, color: AppColors.textPrimary),
          bodyMedium: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.glassBorder,
        thickness: 1.0,
      ),
    );
  }
}

// Glassmorphism Card Wrapper Widget
class GlassCard extends StatelessWidget {
  final Widget child;
  final double blur;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const GlassCard({
    super.key,
    required this.child,
    this.blur = 10.0,
    this.borderRadius = 16.0,
    this.padding = const EdgeInsets.all(16.0),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.cardBg.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: AppColors.glassBorder.withValues(alpha: 0.5),
              width: 1.0,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
