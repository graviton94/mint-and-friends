import 'package:material_ui/material_ui.dart';

import 'widgets/frame_box.dart';

/// 아트가 들어오기 전 임시 팔레트. 3~50대 대상: 큰 글씨, 높은 대비, 부드러운 색.
class Palette {
  static const bgTop = Color(0xFFE8F5E1);
  static const bgBottom = Color(0xFFCDE8C4);
  static const board = Color(0xFFF7F1E3);
  static const cell = Color(0xFFEDE3CC);
  static const cellAlt = Color(0xFFE6DABF);
  static const primary = Color(0xFF3E8E5A);
  static const accent = Color(0xFFF2A541);
  static const ad = Color(0xFF7B61C9);
  static const text = Color(0xFF2F3B2F);
  static const coin = Color(0xFFE0A100);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Jua',
    colorScheme: ColorScheme.fromSeed(
      seedColor: Palette.primary,
      brightness: Brightness.light,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Palette.text,
      displayColor: Palette.text,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: framedButton(
        FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        'button_green',
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: framedButton(
        OutlinedButton.styleFrom(minimumSize: const Size(48, 44)),
        'button_white',
      ),
    ),
  );
}
