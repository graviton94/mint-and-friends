import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

/// 줄바꿈 점검 (D-106): 4개 언어 × 작은 폰에서 주요 화면의 모든 글자를 실제 글꼴로 그려
/// 낱말 중간 줄바꿈(영어 · 스페인어 · 한국어 낱말, 일본어 말 덩어리)과 한 글자만 넘어간 줄을 찾는다.
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
        'settings': (c, g, b) => showSettingsSheet(
          c,
          listen: g,
          game: g,
          version: '1.0.21 (1040)',
          accountSection: () => const SizedBox(),
        ),
        'pass': (c, g, b) => showPassSheet(c, g),
      };

  Future<void> loadFonts() async {
    for (final (family, file) in [
      ('Jua', 'assets/fonts/Jua.ttf'),
      ('MochiyPop', 'assets/fonts/MochiyPopOne-ja.ttf'),
    ]) {
      final l = FontLoader(family)..addFont(rootBundle.load(file));
      await l.load();
    }
  }

  bool latin(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      (c >= 0xC0 && c <= 0x24F);
  bool hangul(int c) => c >= 0xAC00 && c <= 0xD7A3;
  const punct = '.,!?。、！？・…)）」』:%';

  /// 이 화면의 글자 중 이상한 줄바꿈 목록.
  List<String> badBreaks(WidgetTester tester) {
    final out = <String>[];
    for (final e in tester.allElements) {
      final ro = e.renderObject;
      if (ro is! RenderParagraph || !ro.hasSize || !ro.attached) continue;
      final text = ro.text.toPlainText(includeSemanticsLabels: false);
      if (text.length < 2) continue;
      // 글자마다 상자의 위치로 줄이 바뀐 자리를 찾는다
      final starts = <int>[];
      double? lastTop;
      for (var i = 0; i < text.length; i++) {
        // 폭 없는 기호(줄 바꾸지 않음 · 줄 바꿔도 됨)는 위치가 들쭉날쭉해 건너뛴다
        final cu = text.codeUnitAt(i);
        // 아이콘 자리(U+FFFC)는 아이콘 크기로 가운데 맞춤이라 글자와 높이가 달라 건너뛴다
        if (cu == 0x2060 || cu == 0x200B || cu == 0xFFFC) continue;
        final boxes = ro.getBoxesForSelection(
          TextSelection(baseOffset: i, extentOffset: i + 1),
        );
        if (boxes.isEmpty) continue;
        // 다른 글꼴로 그려지는 기호(×, –)는 상자 위치가 조금 다르다: 줄 높이의 절반 넘게 내려가야 새 줄
        final box = boxes.first;
        final mid = (box.top + box.bottom) / 2;
        final h = box.bottom - box.top;
        if (lastTop != null && h > 0 && mid > lastTop + h * 0.6 && i > 0) {
          starts.add(i);
        }
        if (h > 0) lastTop = mid;
      }
      if (starts.isEmpty) continue;
      final clean = text.replaceAll('\u2060', '');
      for (final i in starts) {
        final b = text.codeUnitAt(i);
        // 줄 앞 글자: 사이의 폭 없는 기호를 건너 실제 앞 글자, 사이에 '줄 바꾸지 않음'이 있었는지
        var k = i - 1;
        var glued = false;
        while (k > 0 &&
            (text.codeUnitAt(k) == 0x2060 || text.codeUnitAt(k) == 0x200B)) {
          if (text.codeUnitAt(k) == 0x2060) glued = true;
          if (text.codeUnitAt(k) == 0x200B) glued = false;
          k--;
        }
        final a = glued ? 0x2060 : text.codeUnitAt(k);
        if (a == 0x0A ||
            a == 0x20 ||
            b == 0x20 ||
            a == 0x2D ||
            a == 0xFFFC ||
            b == 0xFFFC)
          continue;
        String why = '';
        if (latin(a) && latin(b)) why = '낱말 중간';
        if (hangul(a) && hangul(b)) why = '한글 낱말 중간';
        if (a == 0x2060 || b == 0x2060) why = '말 덩어리 중간';
        if (why.isNotEmpty) {
          final s = text.substring(
            (i - 12).clamp(0, text.length),
            (i + 12).clamp(0, text.length),
          );
          out.add(
            '$why: «${s.replaceAll('\u2060', '').replaceAll('\n', '⏎')}» (${clean.length}자)',
          );
        }
      }
      // 마지막 줄에 글자 하나만 (문장부호 빼고)
      final lastLine = text
          .substring(starts.last)
          .replaceAll('\u2060', '')
          .trim();
      final core = lastLine.split('').where((ch) => !punct.contains(ch)).join();
      if (core.runes.length == 1 &&
          !text.substring(0, starts.last).endsWith('\n')) {
        out.add(
          '한 글자 줄: «${clean.length > 30 ? '…${clean.substring(clean.length - 30)}' : clean}»'
              .replaceAll('\n', '⏎'),
        );
      }
    }
    return out;
  }

  for (final lang in ['ko', 'en', 'ja', 'es']) {
    testWidgets('줄바꿈 점검: $lang', (tester) async {
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
        await loadFonts();
        await L10n.instance.init();
        await L10n.instance.setLanguage(lang);
        await Art.init();
      });
      const size = Size(720, 1280);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final g = richGame(DateTime(2026, 1, 1, 12));
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
      final found = <String>{...badBreaks(tester).map((s) => 'home: $s')};
      for (final e in screens.entries) {
        final nav = Navigator.of(ctx);
        while (nav.canPop()) {
          nav.pop();
          await tester.pump(const Duration(milliseconds: 400));
        }
        e.value(ctx, g, billing);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
        found.addAll(badBreaks(tester).map((s) => '${e.key}: $s'));
      }
      tester.takeException();
      // ignore: avoid_print
      print('== $lang: ${found.length}\n${found.join('\n')}');
      expect(found, isEmpty, reason: '$lang 줄바꿈');
    });
  }
}
