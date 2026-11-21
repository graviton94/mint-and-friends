import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../services/audio_service.dart';
import 'sheets.dart';
import 'widgets/frame_box.dart';
import 'widgets/icon_text.dart';

/// 정원 재단장 (D-031): 강화 화면 맨 위 칸 · 확인 창 · 완료 창 · 황금 씨앗 강화 시트.

/// 강화 화면 맨 위: 이번 회차에 번 코인 · 지금 하면 받는 씨앗. 바구니 등급 Lv.5 부터 (또는 2회차부터) 보인다.
class RenewCard extends StatelessWidget {
  const RenewCard({super.key, required this.game, required this.onOpen});
  final GameState game;
  final VoidCallback onOpen;

  static bool visible(GameState g) =>
      g.renewCount > 1 || g.lv(UpgradeType.basketTier) >= 5;

  @override
  Widget build(BuildContext context) {
    final ready = game.canRenew;
    final tier = game.lv(UpgradeType.basketTier);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFF3C9), Color(0xFFFFE08A)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFC98B1C), width: 3),
            ),
            child: Row(
              children: [
                GlowHalo(
                  size: 76,
                  child: ArtImage(Art.icon('golden_seed'), size: 58),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: IconText(
                              '${tr('renew.title')}  ·  ${tr('renew.round', {'n': game.renewCount})}',
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                          if (game.renewRecommended) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8739A),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                tr('renew.recommend'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      IconText(
                        tr('renew.runCoins', {'v': fmt(game.lifetimeCoins)}),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF7A5A22),
                        ),
                      ),
                      IconText(
                        ready
                            ? tr('renew.preview', {'n': game.renewSeedsPreview})
                            : tier < Renewal.needBasketTier
                            ? tr('renew.need', {
                                'n': Renewal.needBasketTier,
                                'now': tier,
                              })
                            // 등급은 됐지만 다음 씨앗까지 코인이 모자라다
                            : tr('renew.needCoins', {
                                'n': fmt(game.coinsToNextSeed),
                              }),
                        style: const TextStyle(fontSize: 15),
                      ),
                      if (ready)
                        IconText(
                          tr('renew.multChangeShort', {
                            'a': game.seedMultiplier.toStringAsFixed(1),
                            'b': game.seedMultiplierAfterRenew.toStringAsFixed(
                              1,
                            ),
                          }),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7A5A22),
                          ),
                        )
                      else if (game.seedsTotal > 0)
                        IconText(
                          tr('renew.mult', {
                            'v': game.seedMultiplier.toStringAsFixed(1),
                          }),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7A5A22),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: framedButton(
                    FilledButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      backgroundColor: const Color(0xFFF2C14E),
                      foregroundColor: const Color(0xFF5A3A08),
                    ),
                    'button_gold',
                  ),
                  onPressed: ready ? onOpen : null,
                  child: IconText(
                    '[[renew]] ${tr('renew.open')}',
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
              ),
              if (game.renewCount > 1) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: framedButton(
                      FilledButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF4A3A22),
                      ),
                      'button_white',
                    ),
                    onPressed: () => showSeedSheet(context, game),
                    child: IconText(
                      '[[golden_seed]] ${game.seeds}',
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 재단장 확인 창. 광고를 보면 씨앗 1.5배. 결과: null(취소) · false(그냥) · true(광고).
Future<bool?> showRenewConfirm(
  BuildContext context,
  GameState game, {
  required bool adFree,
}) {
  final n = game.renewSeedsPreview;
  final adN = (n * Renewal.adBonus).round();
  final after = 1 + Renewal.seedIncome * (game.seedsTotal + n);
  Widget column(String title, String body, Color bg, Color ink) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 15, color: ink)),
          const SizedBox(height: 4),
          IconText(
            body,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: Color(0xFF4A3A2A),
            ),
          ),
        ],
      ),
    ),
  );
  return showDialog<bool>(
    context: context,
    builder: (ctx) => GameDialog(
      banner: 'gold',
      title: IconText(tr('renew.title'), textAlign: TextAlign.center),
      onClose: () => Navigator.pop(ctx),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupHero(
            art: GlowHalo(
              size: 170,
              child: ArtImage(Art.frame('renew_hero'), size: 150),
            ),
            big: '[[golden_seed]] +$n',
            note: tr('renew.multChange', {
              'a': game.seedMultiplier.toStringAsFixed(1),
              'b': after.toStringAsFixed(1),
            }),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column(
                tr('renew.resetTitle'),
                tr('renew.resetBody'),
                const Color(0xFFFBE9E4),
                const Color(0xFFA2462E),
              ),
              const SizedBox(width: 8),
              column(
                tr('renew.keepTitle'),
                tr('renew.keepBody'),
                const Color(0xFFE6F2DC),
                const Color(0xFF3E7A38),
              ),
            ],
          ),
        ],
      ),
      actions: [
        DialogAdButton(
          label: tr('reward.times', {'n': '1.5'}),
          sub: '[[golden_seed]] +$adN',
          adFree: adFree,
          onTap: () => Navigator.pop(ctx, true),
        ),
        DialogPlainButton(
          label: '${tr('renew.do')}  [[golden_seed]] +$n',
          onTap: () => Navigator.pop(ctx, false),
        ),
      ],
    ),
  );
}

/// 재단장 완료 창.
Future<void> showRenewDone(BuildContext context, GameState game, int got) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => GameDialog(
        banner: 'gold',
        title: IconText(
          tr('renew.doneTitle', {'n': game.renewCount}),
          textAlign: TextAlign.center,
        ),
        onClose: () => Navigator.pop(ctx),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlowHalo(
              size: 180,
              child: ArtImage(Art.frame('renew_done'), size: 160),
            ),
            IconText(
              tr('renew.doneNote'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Color(0xFF6B5A44)),
            ),
            const SizedBox(height: 8),
            for (final (icon, label, value) in [
              ('golden_seed', tr('renew.seeds'), '+$got'),
              (
                'coin',
                tr('renew.income'),
                '×${game.seedMultiplier.toStringAsFixed(1)}',
              ),
              ('decorate', tr('renew.kept'), tr('renew.keptValue')),
            ])
              Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    ArtImage(Art.icon(icon), size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(label, style: const TextStyle(fontSize: 15)),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 17,
                        color: Color(0xFFB0640A),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          FilledButton(
            style: framedButton(
              FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: const Color(0xFFF2C14E),
                foregroundColor: const Color(0xFF5A3A08),
              ),
              'button_gold',
            ),
            onPressed: () {
              Navigator.pop(ctx);
              showSeedSheet(context, game);
            },
            child: IconText(
              tr('renew.toSeeds'),
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );

/// 황금 씨앗 영구 강화 시트.
Future<void> showSeedSheet(BuildContext context, GameState game) =>
    showGameSheet(
      context,
      game,
      () => SheetFrame(
        title: tr('seeds.title'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IconText(
              tr('seeds.summary', {
                'n': game.seeds,
                'v': game.seedMultiplier.toStringAsFixed(1),
                'r': game.renewCount,
              }),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Color(0xFF6B5638)),
            ),
            IconText(
              tr('seeds.note'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Colors.black45),
            ),
            const SizedBox(height: 6),
            for (final d in Renewal.perks) _PerkRow(game: game, def: d),
          ],
        ),
      ),
    );

class _PerkRow extends StatelessWidget {
  const _PerkRow({required this.game, required this.def});
  final GameState game;
  final SeedPerkDef def;

  @override
  Widget build(BuildContext context) {
    final lv = game.perkLv(def.perk);
    final maxed = lv >= def.maxLevel;
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ArtImage(Art.icon(def.icon), size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${tr('seeds.${def.perk.name}')}  Lv.$lv',
                    style: const TextStyle(fontSize: 16),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: IconText(
                      tr('seeds.${def.perk.name}.desc'),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF5E6B5E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            CostButton(
              frame: 'button_gold',
              label: maxed
                  ? tr('common.max')
                  : '[[golden_seed]] ${def.costAt(lv)}',
              onPressed: game.canBuyPerk(def.perk)
                  ? () {
                      if (game.buyPerk(def.perk)) sfx(Sfx.unlock);
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
