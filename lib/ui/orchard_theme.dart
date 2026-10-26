import 'package:flutter/material.dart';

/// Shared tokens sampled from the supplied OrchardAtlas icon.
abstract final class OrchardBrand {
  static const forest = Color(0xff19492D);
  static const leaf = Color(0xff507A32);
  static const apple = Color(0xffBB2D27);
  static const ivory = Color(0xffF7F4E9);
  static const ink = Color(0xff203728);
  static const line = Color(0xffB8C2AA);
  static const logo = 'assets/branding/orchard_atlas.png';
}

ThemeData orchardTheme() {
  final colors = ColorScheme.fromSeed(seedColor: OrchardBrand.forest).copyWith(
    primary: OrchardBrand.forest,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xffDFEAD5),
    onPrimaryContainer: OrchardBrand.forest,
    secondary: OrchardBrand.leaf,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xffE8EDD9),
    onSecondaryContainer: OrchardBrand.ink,
    tertiary: OrchardBrand.apple,
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xffFBE2DA),
    onTertiaryContainer: const Color(0xff79201D),
    error: const Color(0xffA1231D),
    onError: Colors.white,
    surface: OrchardBrand.ivory,
    onSurface: OrchardBrand.ink,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xffFAF8F0),
    surfaceContainer: const Color(0xffEFEEE1),
    surfaceContainerHigh: const Color(0xffE8EBDD),
    onSurfaceVariant: const Color(0xff4C5D4B),
    outline: const Color(0xff73836B),
    outlineVariant: OrchardBrand.line,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: OrchardBrand.ivory,
    visualDensity: VisualDensity.standard,
  );
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: OrchardBrand.line),
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: OrchardBrand.forest,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: OrchardBrand.forest, width: 2),
      ),
      errorBorder: border.copyWith(borderSide: BorderSide(color: colors.error)),
      focusedErrorBorder: border.copyWith(
        borderSide: BorderSide(color: colors.error, width: 2),
      ),
      floatingLabelStyle: const TextStyle(
        color: OrchardBrand.forest,
        fontWeight: FontWeight.w600,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: shape,
        side: const BorderSide(color: OrchardBrand.line),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: shape,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: OrchardBrand.forest,
      foregroundColor: Colors.white,
      shape: shape,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: OrchardBrand.line),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: OrchardBrand.ivory,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: OrchardBrand.ivory,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: const Color(0xffD5E2CA),
      indicatorColor: const Color(0xffD5E2CA),
      dividerColor: OrchardBrand.leaf,
      overlayColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: .08)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: const Color(0xffE8EDD9),
      selectedColor: const Color(0xffDFEAD5),
      side: const BorderSide(color: OrchardBrand.line),
      shape: shape,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: OrchardBrand.leaf,
    ),
    dividerTheme: const DividerThemeData(color: OrchardBrand.line, space: 24),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: OrchardBrand.forest,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class FormIntro extends StatelessWidget {
  const FormIntro({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.park_outlined,
  });
  final String title, subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: OrchardBrand.forest),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: OrchardBrand.forest,
                ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Consistent, readable form spacing on phones and a bounded width on tablets.
class OrchardForm extends StatelessWidget {
  const OrchardForm({
    super.key,
    required this.children,
    this.title,
    this.subtitle,
    this.icon = Icons.park_outlined,
  });
  final List<Widget> children;
  final String? title, subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          if (title != null)
            FormIntro(title: title!, subtitle: subtitle ?? '', icon: icon),
          for (final child in children)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
        ],
      ),
    ),
  );
}
