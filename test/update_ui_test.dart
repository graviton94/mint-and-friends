import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mint_and_friends/art/art.dart';
import 'package:mint_and_friends/i18n/l10n.dart';
import 'package:mint_and_friends/ui/theme.dart';
import 'package:mint_and_friends/ui/update_ui.dart';
import 'package:mint_and_friends/ui/widgets/frame_box.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('업데이트 알약을 여러 번 눌러도 다 받음 창은 하나만 뜬다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      await L10n.instance.init();
      await L10n.instance.setLanguage('ko');
      await Art.init();
    });
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold();
          },
        ),
      ),
    );
    showUpdateReady(ctx);
    showUpdateReady(ctx);
    showUpdateReady(ctx);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(GameDialog), findsOneWidget);
    expect(updateReadyOpen, isTrue);
    Navigator.of(ctx).pop();
    await tester.pump(const Duration(milliseconds: 400));
    expect(updateReadyOpen, isFalse);
    showUpdateReady(ctx); // 닫은 뒤에는 다시 열린다
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(GameDialog), findsOneWidget);
  });
}
