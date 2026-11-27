import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mint_and_friends/ui/theme.dart';
import 'package:mint_and_friends/ui/widgets/frame_box.dart';

/// 버튼 글자도 앱 글꼴이어야 한다 (D-105): 버튼 글자 모양은 화면 기본 글꼴을 물려받지 않아
/// 글꼴 이름이 빠지면 폰에서 시스템 글꼴로 나왔다.
void main() {
  test('버튼 글자 모양에 앱 글꼴이 들어 있다', () {
    expect(buttonTextStyle.fontFamily, isNotNull);
    for (final frame in ['button_green', 'button_white', 'button_gold']) {
      final st = framedButton(
        const ButtonStyle(),
        frame,
      ).textStyle!.resolve({});
      expect(st?.fontFamily, isNotNull, reason: frame);
    }
    final theme = buildTheme();
    for (final b in [
      theme.filledButtonTheme.style,
      theme.outlinedButtonTheme.style,
    ]) {
      expect(b!.textStyle!.resolve({})?.fontFamily, isNotNull);
    }
  });
}
