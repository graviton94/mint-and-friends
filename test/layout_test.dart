import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mint_and_friends/art/art.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';
import 'package:mint_and_friends/i18n/l10n.dart';
import 'package:mint_and_friends/services/ads_service.dart';
import 'package:mint_and_friends/services/billing_service.dart';
import 'package:mint_and_friends/ui/home_screen.dart';
import 'package:mint_and_friends/ui/meta_ui.dart';
import 'package:mint_and_friends/ui/sheets.dart';
import 'package:mint_and_friends/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 출시 전 화면 점검: 세 언어 × 작은 폰 · 큰 폰에서 주요 화면을 그려
/// 글자 넘침(RenderFlex overflow 등) 오류가 하나도 없어야 한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GameState richGame(DateTime now) {
    final g = GameState(random: Random(3), clock: () => now);
    g.level = 30;
    g.coins = 987654321;
    g.stars = 123456;
    g.gems = 98765;
    g.currentArea = 2;
    g.placed = {0, 1, 2, 3, 4};
    g.friends.addAll(['dubu', 'kwak', 'nabi', 'dotori', 'mochi']);
    g.unlockedCells.addAll(List.generate(GameConfig.cellCount, (i) => i));
    final cells = g.unlockedCells.toList()..sort();
    for (var i = 0; i < cells.length; i++) {
      g.board[cells[i]] = Item(
        i + 1,
        i.isEven ? Chain.flower : Chain.snack,
        1 + i % 15,
      );
    }
    g.grantBoost();
    // 새 기능이 모두 켜진 상태: 부스트 3종 · 보관 부스트 · 패키지 타이머 · 시즌 장식 · 의상
    g.grantBoostAd(BoostKind.energy);
    g.grantBoostAd(BoostKind.lucky);
    g.boostTokens[BoostKind.coins] = 60;
    g.showStarterOffer();
    g.decorStyle['2:0'] = 3;
    g.ownedStyles.add('2:0:3');
    g.ownedOutfits.add('dubu:winter');
    g.effects.add(Starter.effect);
    g.effectOn = Starter.effect;
    return g;
  }

  final screens =
      <String, void Function(BuildContext, GameState, BillingService)>{
        'shop': (c, g, b) => showShopSheet(c, b, g),
        'decor': (c, g, b) => showDecorSheet(c, g),
        'upgrade': (c, g, b) => showUpgradesSheet(c, g),
        'book': (c, g, b) => showCollectionSheet(c, g),
        'achievements': (c, g, b) => showAchievementsSheet(c, g),
        'mail': (c, g, b) => showMailSheet(c, g),
        'checkIn': (c, g, b) => showCheckInSheet(c, g),
        'boost': (c, g, b) =>
            showBoostSheet(c, g, watchAd: (_) async => true, adFree: false),
        'style': (c, g, b) => showStyleSheet(c, g, 2, 0),
        'outfit': (c, g, b) => showOutfitSheet(c, g, Friends.byId('dubu')),
        'starter': (c, g, b) => showStarterSheet(c, b, g),
        'storage': (c, g, b) => showStorageSheet(c, g, onMessage: (_) {}),
      };

  for (final lang in ['ko', 'en', 'ja']) {
    for (final size in [const Size(720, 1280), const Size(1080, 2400)]) {
      testWidgets(
        '글자 넘침 없음: $lang ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          SharedPreferences.setMockInitialValues({
            'tutorial_v1': 99,
            'feature_tips_seen': [
              for (final f in Feature.values) f.name,
              'gems',
              'checkIn',
              'market',
              'basket',
              'design',
              'wardrobe',
              'friends',
            ],
          });
          await tester.runAsync(() async {
            await L10n.instance.init();
            await L10n.instance.setLanguage(lang);
            await Art.init();
          });
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = size.width / 360;
          addTearDown(tester.view.reset);
          final now = DateTime(2026, 1, 1, 12);
          final g = richGame(now);
          final billing = BillingService();
          final ads = AdsService(isAdFree: () => false);
          late BuildContext ctx;
          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(),
              home: Builder(
                builder: (c) {
                  ctx = c;
                  return HomeScreen(
                    game: g,
                    ads: ads,
                    billing: billing,
                    openSettings: (_) {},
                  );
                },
              ),
            ),
          );
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 300));
          }
          expect(tester.takeException(), isNull, reason: '홈 화면 $lang');
          for (final e in screens.entries) {
            // 열려 있는 시트 닫기
            final nav = Navigator.of(ctx);
            while (nav.canPop()) {
              nav.pop();
              await tester.pump(const Duration(milliseconds: 400));
            }
            e.value(ctx, g, billing);
            for (var i = 0; i < 4; i++) {
              await tester.pump(const Duration(milliseconds: 300));
            }
            expect(tester.takeException(), isNull, reason: '${e.key} $lang');
          }
        },
      );
    }
  }
}
