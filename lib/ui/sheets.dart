import 'dart:math';

import 'package:material_ui/material_ui.dart';

import 'widgets/top_toast.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../i18n/names.dart';
import '../services/audio_service.dart';
import '../services/analytics_service.dart';
import '../services/billing_service.dart';
import '../services/dev_log.dart';
import '../services/notify_service.dart';
import 'renew_ui.dart';
import 'theme.dart';
import 'widgets/frame_box.dart';
import 'widgets/icon_text.dart';

/// 게임 공통 아래 시트 (패널 프레임, 언어 · 상태가 바뀌면 다시 그림).
Future<void> showGameSheet(
  BuildContext context,
  Listenable listen,
  Widget Function() build,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true, // 상태표시줄 · 아래 내비게이션 바를 피한다
    // 패널 프레임이 있으면 시트 배경을 투명하게 하고 SheetFrame 이 프레임을 그린다
    backgroundColor: Art.frame('panel').available
        ? Colors.transparent
        : Palette.board,
    builder: (_) => ListenableBuilder(
      listenable: Listenable.merge([listen, L10n.instance]),
      builder: (context, _) => build(),
    ),
  );
}

// ---------------------------------------------------------------- 강화

Future<void> showUpgradesSheet(
  BuildContext context,
  GameState game, {
  VoidCallback? onRenew,
}) => showGameSheet(context, game, () {
  // 이 화면의 모든 비용은 같은 단위로 (가장 큰 값 기준)
  final unit = UnitFmt.of([
    for (final u in Upgrades.all)
      if (!game.upgradeMaxed(u.type)) game.upgradeCost(u.type),
    for (final f in Friends.all)
      if (game.friends.contains(f.id) &&
          game.friendLevel(f.id) < Friends.maxAffection)
        game.friendLevelCost(f.id),
  ]);
  return SheetFrame(
    title: tr('upgrade.title'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onRenew != null && RenewCard.visible(game))
          RenewCard(game: game, onOpen: onRenew),
        for (final u in Upgrades.all)
          _UpgradeRow(game: game, def: u, unit: unit),
        if (game.friends.isNotEmpty) ...[
          const SizedBox(height: 12),
          IconText(tr('upgrade.friends'), style: const TextStyle(fontSize: 18)),
          IconText(
            tr('upgrade.friendsNote'),
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          for (final f in Friends.all)
            if (game.friends.contains(f.id))
              _FriendLevelRow(game: game, def: f, unit: unit),
        ],
      ],
    ),
  );
});

class _FriendLevelRow extends StatelessWidget {
  const _FriendLevelRow({
    required this.game,
    required this.def,
    required this.unit,
  });
  final GameState game;
  final FriendDef def;
  final UnitFmt unit;

  @override
  Widget build(BuildContext context) {
    final lv = game.friendLevel(def.id);
    final hearts = game.affection(def.id);
    final maxed = lv >= Friends.maxAffection;
    final button = maxed
        ? tr('common.max')
        : lv >= hearts
        ? tr('upgrade.needHeart')
        : '[[coin]] ${unit(game.friendLevelCost(def.id))}';
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ArtImage(Art.friend(def, outfit: game.outfitOf(def.id)), size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${friendName(def.id)}  Lv.$lv',
                    style: const TextStyle(fontSize: 17),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: IconText(
                      maxed
                          ? buffText(def, lv)
                          : '${lv == 0 ? tr('book.noEffect') : buffText(def, lv)} → ${buffText(def, lv + 1)}',
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF5E6B5E),
                      ),
                    ),
                  ),
                  IconText(
                    '${lv < hearts ? tr('upgrade.canLevel', {'n': hearts}) : tr('upgrade.needMore')}  ·  ${lv < Friends.starMilestone
                        ? tr('upgrade.milestone5', {'n': Friends.starMilestone})
                        : lv < Friends.boostMilestone
                        ? tr('upgrade.milestone10', {'n': Friends.boostMilestone})
                        : lv < Friends.maxMilestone
                        ? tr('upgrade.milestone30', {'n': Friends.maxMilestone})
                        : tr('upgrade.milestoneDone')}',
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            CostButton(
              label: button,
              onPressed: game.canLevelFriend(def.id)
                  ? () => game.levelFriend(def.id)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 옷장 고르기: 데려온 친구 중 옷이 있는 친구를 골라 옷장을 연다.
Future<void> showWardrobePicker(BuildContext context, GameState game) =>
    showGameSheet(
      context,
      game,
      () => SheetFrame(
        title: tr('menu.wardrobe'),
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.85,
          children: [
            for (final f in Friends.all)
              if (game.friends.contains(f.id) && Art.outfitsFor(f).isNotEmpty)
                GestureDetector(
                  onTap: () => showOutfitSheet(context, game, f),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFE2D3B5),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ArtImage(
                          Art.friend(f, outfit: game.outfitOf(f.id)),
                          size: 64,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          friendName(f.id),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );

class _UpgradeRow extends StatelessWidget {
  const _UpgradeRow({
    required this.game,
    required this.def,
    required this.unit,
  });
  final GameState game;
  final UpgradeDef def;
  final UnitFmt unit;

  @override
  Widget build(BuildContext context) {
    final t = def.type;
    final lv = game.lv(t);
    final featureLocked = game.upgradeFeatureLocked(t);
    final maxed = game.upgradeMaxed(t);
    final capped = game.upgradeCapped(t);
    final featureLevel = Leveling.unlockLevel[def.feature ?? Feature.upgrades]!;
    String button;
    if (featureLocked) {
      button = tr('common.lockedLevel', {'n': featureLevel});
    } else if (maxed) {
      button = tr('common.max');
    } else if (capped) {
      button = tr('upgrade.needLevel', {'n': game.upgradeLevelNeeded(t)});
    } else {
      button = lv == 0 && def.unlockCost > 0
          ? '${tr('upgrade.open')} ${unit(game.upgradeCost(t))}'
          : '[[coin]] ${unit(game.upgradeCost(t))}';
    }
    return Opacity(
      opacity: 1,
      child: Card(
        color: Colors.white,
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ArtImage(IconText.resolve(def.icon), size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${upgradeTitle(t)}  Lv.$lv',
                      style: const TextStyle(fontSize: 17),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: IconText(
                        upgradeLine(t, lv, maxed: maxed),
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF5E6B5E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CostButton(
                label: button,
                onPressed: game.canBuyUpgrade(t)
                    ? () => game.buyUpgrade(t)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 꾸미기

Future<void> showDecorSheet(BuildContext context, GameState game) =>
    showGameSheet(context, game, () {
      final area = Garden.areaAt(game.currentArea);
      final done = game.placed.length;
      return SheetFrame(
        title: tr('decor.title', {'name': areaName(area)}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (game.areaLocked)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IconText(
                  tr('decor.areaLocked', {'n': game.areaRequiredLevel}),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFFB0640A),
                  ),
                ),
              ),
            LinearProgressIndicator(
              value: done / Garden.slotsPerArea,
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
            ),
            const SizedBox(height: 6),
            IconText(
              tr('decor.progress', {
                'done': done,
                'total': Garden.slotsPerArea,
                'stars': game.stars,
                'mult': game.gardenMultiplier.toStringAsFixed(1),
              }),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < area.decor.length; i++)
              _DecorRow(game: game, area: area, slot: i),
          ],
        ),
      );
    });

class _DecorRow extends StatelessWidget {
  const _DecorRow({required this.game, required this.area, required this.slot});
  final GameState game;
  final AreaDef area;
  final int slot;

  @override
  Widget build(BuildContext context) {
    final d = area.decor[slot];
    final placed = game.placed.contains(slot);
    final fid = d.bringsFriend;
    final newFriend = fid != null && !game.friends.contains(fid);
    return Card(
      color: placed ? const Color(0xFFE3F1DD) : Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: ArtImage(
          Art.decor(d, style: game.styleOf(game.currentArea, slot)),
          size: 40,
        ),
        title: Text(decorName(d), style: const TextStyle(fontSize: 17)),
        subtitle: newFriend
            ? IconText(
                tr('decor.bringsFriend', {
                  'emoji': friendToken(fid),
                  'name': friendName(fid),
                }),
              )
            : null,
        trailing: placed
            ? (Art.decorStyles(d).length > 1
                  ? CostButton(
                      label: tr('style.change'),
                      frame: 'button_white',
                      onPressed: () =>
                          showStyleSheet(context, game, game.currentArea, slot),
                    )
                  : SizedBox(
                      width: 108,
                      height: 44,
                      child: Center(
                        child: IconText(
                          tr('decor.done'),
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ))
            : CostButton(
                label: game.areaLocked
                    ? tr('common.lockedLevel', {'n': game.areaRequiredLevel})
                    : '[[star]] ${UnitFmt.of([for (var i = 0; i < Garden.slotsPerArea; i++) game.decorCost(i).toDouble()])(game.decorCost(slot))}',
                onPressed: game.canPlace(slot)
                    ? () => game.placeDecor(slot)
                    : null,
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 장식 디자인

/// 장식 디자인 고르기: 기본 · 고급(코인) · 특별(다이아). 산 디자인은 언제든 무료로 바꿔 놓는다.
Future<void> showStyleSheet(
  BuildContext context,
  GameState game,
  int area,
  int slot,
) => showGameSheet(context, game, () {
  final d = Garden.areaAt(area).decor[slot];
  final season = game.seasonStyleNow;
  // 시즌 디자인은 지금 시즌 것 + 이미 산 지난 시즌 것만
  final styles = [
    for (final s in Art.decorStyles(d))
      if (!Garden.isSeasonStyle(s) ||
          s == season ||
          game.ownsStyle(area, slot, s))
        s,
  ];
  // 이 구역에서 지금 시즌 그림이 있는 자리들 (세트 할인)
  final setSlots = [
    for (var i = 0; i < Garden.slotsPerArea; i++)
      if (Art.decorStyle(Garden.areaAt(area).decor[i], season).available) i,
  ];
  final cols = styles.length <= 3 ? styles.length : 2;
  final rows = <List<int>>[
    for (var i = 0; i < styles.length; i += cols)
      styles.sublist(i, min(i + cols, styles.length)),
  ];
  return SheetFrame(
    title: tr('style.title', {'name': decorName(d)}),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in rows) ...[
          Row(
            children: [
              for (final st in r)
                Expanded(
                  child: _StyleCard(
                    game: game,
                    area: area,
                    slot: slot,
                    style: st,
                  ),
                ),
              for (var k = r.length; k < cols; k++) const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (setSlots.length >= 2 && !game.ownsSeasonSet(area, setSlots))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FilledButton(
              style: framedButton(
                FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                'button_purple',
              ),
              onPressed: () {
                if (game.buySeasonSet(area, setSlots) == StyleResult.ok) {
                  sfx(Sfx.unlock);
                } else {
                  sfx(Sfx.error);
                  TopToast.show(context, tr('style.noGems'));
                }
              },
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: IconText(
                  tr('style.seasonSet', {
                    'season': tr('style.$season'),
                    'n': setSlots.length,
                    'cost': Garden.seasonSetGems,
                  }),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        if (area < DecorSets.areas) _SetEffectBox(game: game, area: area),
        IconText(
          tr('style.note'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
      ],
    ),
  );
});

/// 세트 효과 글자: 에너지 통 +5 · 에너지 회복 +5% · 오프라인 최대 +60분 …
String setEffectText(SetEffect e, double v) {
  final n = switch (e) {
    SetEffect.energyCap => '${v.round()}',
    SetEffect.offline => '${v.round()}',
    _ => (v * 100).toStringAsFixed(v * 100 % 1 == 0 ? 0 : 1),
  };
  return tr('set.effect.${e.name}', {'v': n});
}

/// 구역 세트 효과 (D-046): 특별 세트 · 고급 세트(40%) 진행과 꾸밈 점수.
class _SetEffectBox extends StatelessWidget {
  const _SetEffectBox({required this.game, required this.area});
  final GameState game;
  final int area;

  @override
  Widget build(BuildContext context) {
    final e = DecorSets.effects[area];
    final full = DecorSets.full[e]!;
    final p = game.setProgress(area);
    final tier = game.setTier(area);
    Widget row(String label, double v, int have, bool on) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: IconText(
              '$label  ${setEffectText(e, v)}',
              style: TextStyle(
                fontSize: 15,
                color: on ? Palette.primary : const Color(0xFF6B5A44),
              ),
            ),
          ),
          IconText(
            on ? '[[check]]' : '$have/${Garden.slotsPerArea}',
            style: const TextStyle(fontSize: 15, color: Color(0xFF6B5A44)),
          ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2C48E), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IconText(
            tr('set.title', {'area': areaName(Garden.areaAt(area))}),
            style: const TextStyle(fontSize: 16),
          ),
          row(tr('set.special'), full, p.special, tier == 2),
          row(
            tr('set.premium'),
            full * DecorSets.premiumRatio,
            p.premium,
            tier >= 1,
          ),
          IconText(
            tr('set.score', {
              'score': game.decorScore.toStringAsFixed(1),
              'pct': (game.decorScore * DecorSets.incomePerPoint * 100)
                  .toStringAsFixed(1),
            }),
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.game,
    required this.area,
    required this.slot,
    required this.style,
  });
  final GameState game;
  final int area;
  final int slot;
  final int style;

  @override
  Widget build(BuildContext context) {
    final d = Garden.areaAt(area).decor[slot];
    final current = game.styleOf(area, slot) == style;
    final owned = game.ownsStyle(area, slot, style);
    final label = owned
        ? (current ? tr('style.using') : tr('style.use'))
        : style == 1
        ? '[[coin]] ${fmt(game.styleCost(area, slot))}'
        : Garden.isSeasonStyle(style)
        ? '[[diamond]] ${Garden.seasonGems}'
        : '[[diamond]] ${Garden.styleGems(area)}';
    // 살 수 없으면(코인 · 다이아 부족) 흐린 버튼
    final affordable =
        owned ||
        (style == 1
            ? game.coins >= game.styleCost(area, slot)
            : game.gems >=
                  (Garden.isSeasonStyle(style)
                      ? Garden.seasonGems
                      : Garden.styleGems(area)));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      decoration: BoxDecoration(
        color: current ? const Color(0xFFE6F2DC) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: current ? Palette.accent : const Color(0xFFE2D3B5),
          width: current ? 2.5 : 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            tr('style.$style'),
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B5638)),
          ),
          const SizedBox(height: 4),
          ArtImage(
            style == 0 ? Art.decor(d) : Art.decorStyle(d, style),
            size: 72,
          ),
          const SizedBox(height: 6),
          FilledButton(
            style: framedButton(
              FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              current ? 'button_white' : 'button_green',
            ),
            onPressed: current || !affordable
                ? null
                : () {
                    switch (game.setStyle(area, slot, style)) {
                      case StyleResult.ok:
                        sfx(Sfx.unlock);
                      case StyleResult.noCoins || StyleResult.noGems:
                        sfx(Sfx.error);
                        TopToast.show(
                          context,
                          tr(style == 1 ? 'style.noCoins' : 'style.noGems'),
                        );
                      case StyleResult.notPlaced:
                        break;
                    }
                  },
            child: FittedBox(
              child: IconText(label, style: const TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 친구 의상

Future<void> showOutfitSheet(
  BuildContext context,
  GameState game,
  FriendDef def,
) => showGameSheet(
  context,
  game,
  () => SheetFrame(
    title: tr('outfit.title', {'name': friendName(def.id)}),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 옷이 늘어나면 3개씩 줄을 나눈다 (카드가 작아지지 않게)
        for (final r in _rowsOf3<OutfitDef?>([
          null,
          ...Art.outfitsFor(def),
        ])) ...[
          Row(
            children: [
              for (final o in r)
                Expanded(
                  child: _OutfitCard(game: game, def: def, outfit: o),
                ),
              for (var k = r.length; k < 3; k++) const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
        ],
        IconText(
          tr('outfit.note'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
      ],
    ),
  ),
);

List<List<T>> _rowsOf3<T>(List<T> xs) => [
  for (var i = 0; i < xs.length; i += 3) xs.sublist(i, min(i + 3, xs.length)),
];

class _OutfitCard extends StatelessWidget {
  const _OutfitCard({
    required this.game,
    required this.def,
    required this.outfit,
  });
  final GameState game;
  final FriendDef def;
  final OutfitDef? outfit;

  @override
  Widget build(BuildContext context) {
    final id = outfit?.id;
    final current = game.outfitOf(def.id) == id;
    final owned = id == null || game.ownsOutfit(def.id, id);
    final label = owned
        ? (current ? tr('outfit.using') : tr('outfit.wear'))
        : outfit!.limited
        ? tr('outfit.limited')
        : !outfit!.onSaleIn(game.now.month)
        ? tr('outfit.offSeason', {
            'from': outfit!.months!.first,
            'to': outfit!.months!.last,
          })
        : '[[diamond]] ${outfit!.gems}';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      decoration: BoxDecoration(
        color: current ? const Color(0xFFE6F2DC) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: current ? Palette.accent : const Color(0xFFE2D3B5),
          width: current ? 2.5 : 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            id == null ? tr('outfit.basic') : tr(outfit!.key),
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B5638)),
          ),
          const SizedBox(height: 4),
          ArtImage(Art.friend(def, outfit: id), size: 84),
          const SizedBox(height: 6),
          FilledButton(
            style: framedButton(
              FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              current ? 'button_white' : 'button_green',
            ),
            // 다이아가 모자라면 살 수 있는 것처럼 보이지 않게 (흐린 버튼)
            onPressed:
                current ||
                    (!owned &&
                        (outfit!.limited ||
                            !outfit!.onSaleIn(game.now.month) ||
                            game.gems < outfit!.gems))
                ? null
                : () {
                    final r = game.wearOutfit(def.id, id);
                    if (r == StyleResult.ok) {
                      sfx(Sfx.unlock);
                    } else if (r == StyleResult.noGems) {
                      sfx(Sfx.error);
                      TopToast.show(context, tr('style.noGems'));
                    }
                  },
            child: FittedBox(
              child: IconText(label, style: const TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 도감

Future<void> showCollectionSheet(
  BuildContext context,
  GameState game,
) => showGameSheet(
  context,
  game,
  () => SheetFrame(
    title: tr('book.title'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IconText(tr('book.friends'), style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.7,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final (i, f) in Friends.all.indexed)
              if (i < Friends.coreCount || Art.friend(f).available)
                _FriendCard(game: game, def: f),
          ],
        ),
        const SizedBox(height: 14),
        // 계절 컬렉션: 구역 × 계절 시즌 장식 모은 수 (8종 완성 = 계절 풍경 + 정원 매력)
        if (Garden.seasonStyles.keys.any(
          (st) => Art.decorStyle(Garden.areaAt(0).decor[0], st).available,
        )) ...[
          IconText(tr('book.seasons'), style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 2),
          IconText(
            tr('book.seasonsNote', {
              'n': (Garden.seasonSetBonus * 100).round(),
            }),
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          for (var a = 0; a <= game.currentArea && a < Garden.areas.length; a++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  ArtImage(Art.areaIcon(Garden.areaAt(a)), size: 26),
                  const SizedBox(width: 6),
                  for (final st in Garden.seasonOrder)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: game.seasonSetComplete(a, st)
                              ? const Color(0xFFFFF0B8)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: game.seasonSetComplete(a, st)
                                ? const Color(0xFFE0A21B)
                                : const Color(0xFFE2D3B5),
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: IconText(
                            game.seasonSetComplete(a, st)
                                ? '[[check]]${tr('style.$st')}'
                                : '${tr('style.$st')} ${game.seasonSetOwned(a, st)}/${Garden.slotsPerArea}',
                            iconScale: 1.0,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
        ],
        for (final chain in Chain.values.where(Chains.ready)) ...[
          Text(chainName(chain), style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var lv = 1; lv <= Chains.maxLevel(chain); lv++)
                _ItemChip(
                  chain: chain,
                  level: lv,
                  found: game.isUnlocked(Feature.snack) || chain == Chain.flower
                      ? lv <= (game.highest[chain] ?? 0)
                      : false,
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    ),
  ),
);

class _FriendCard extends StatelessWidget {
  const _FriendCard({required this.game, required this.def});
  final GameState game;
  final FriendDef def;

  @override
  Widget build(BuildContext context) {
    final has = game.friends.contains(def.id);
    final aff = game.affection(def.id);
    final flv = game.friendLevel(def.id);
    final dress = has && Art.outfitsFor(def).isNotEmpty;
    return GestureDetector(
      onTap: dress ? () => showOutfitSheet(context, game, def) : null,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: has ? Colors.white : const Color(0xFFEDE8DC),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Opacity(
              opacity: has ? 1 : 0.2,
              child: ArtImage(
                Art.friend(def, outfit: game.outfitOf(def.id)),
                size: 38,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    child: Text(
                      has
                          ? '${friendName(def.id)}  Lv.$flv'
                          : tr('book.unknown'),
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  if (has) ...[
                    IconText(
                      '[[heart]] $aff/${Friends.maxAffection}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB0506E),
                      ),
                    ),
                    FittedBox(
                      child: IconText(
                        flv == 0 ? tr('book.noEffect') : buffText(def, flv),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF5E6B5E),
                        ),
                      ),
                    ),
                  ] else
                    IconText(
                      tr('book.invite'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8A8A7A),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemChip extends StatelessWidget {
  const _ItemChip({
    required this.chain,
    required this.level,
    required this.found,
  });
  final Chain chain;
  final int level;
  final bool found;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: found
          ? 'Lv$level ${itemName(Chains.item(chain, level))}'
          : tr('book.unknown'),
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: found ? Colors.white : const Color(0xFFEDE8DC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: found
            ? ArtImage(Art.item(chain, level), size: 30)
            : Opacity(
                opacity: 0.3,
                child: ArtImage(Art.icon('unknown'), size: 24),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 보관함

/// 보관함: 칸을 누르면 판의 빈 칸으로 꺼낸다. 마지막 칸 뒤에 다음 칸 구매 버튼.
Future<void> showStorageSheet(
  BuildContext context,
  GameState game, {
  required void Function(String message) onMessage,
}) => showGameSheet(
  context,
  game,
  () => SheetFrame(
    title: tr('storage.title', {
      'used': game.storageUsed,
      'max': game.storage.length,
    }),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: IconText(
            tr('storage.body'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < game.storage.length; i++)
              _StorageSlot(
                item: game.storage[i],
                onTap: () {
                  if (game.storage[i] == null) return;
                  if (game.retrieve(i) == null)
                    onMessage(tr('storage.boardFull'));
                },
              ),
            if (!game.storageMaxed) _StorageBuySlot(game: game),
          ],
        ),
      ],
    ),
  ),
);

class _StorageSlot extends StatelessWidget {
  const _StorageSlot({required this.item, required this.onTap});
  final Item? item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final it = item;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 58,
        height: 58,
        alignment: Alignment.center,
        decoration: FrameBox.decorationFor(
          'slot',
          BoxDecoration(
            color: it == null ? const Color(0xFFEDE8DC) : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          corner: 12,
        ),
        child: it == null
            ? null
            : Stack(
                alignment: Alignment.center,
                children: [
                  ArtImage(Art.item(it.chain, it.level), size: 40),
                  Positioned(
                    right: 2,
                    bottom: 0,
                    child: Text(
                      '${it.level}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Palette.primary,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _StorageBuySlot extends StatelessWidget {
  const _StorageBuySlot({required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final can = game.canBuyStorageSlot;
    return GestureDetector(
      onTap: can ? game.buyStorageSlot : null,
      child: Opacity(
        opacity: can ? 1 : 0.55,
        child: Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFE4DCC8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ArtImage(Art.lock, size: 22),
              FittedBox(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: IconText(
                    '[[coin]]${fmt(game.nextStorageCost)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 상점

/// 상점: 다이아 팩 · 다이아로 에너지 충전 · 광고 제거(월 구독).
Future<void> showShopSheet(
  BuildContext context,
  BillingService billing,
  GameState game, {
  Future<bool> Function(AdKind kind)? watchAd,
  bool adFree = false,
}) {
  Analytics.instance.shopOpen(game, starter: game.starterVisible);
  if (game.starterVisible) Analytics.instance.starterView(game, 'shop');
  return _shopSheet(context, billing, game, watchAd: watchAd, adFree: adFree);
}

Future<void> _shopSheet(
  BuildContext context,
  BillingService billing,
  GameState game, {
  Future<bool> Function(AdKind kind)? watchAd,
  bool adFree = false,
}) => showGameSheet(context, Listenable.merge([billing, game]), () {
  final ad = adFree ? '' : '[[ad]] ';
  // 추천 아이템: 화면에 그린 상품 그대로 산다 (그사이 날이 바뀌면 사지 않고 새 상품을 보여 준다)
  final feat = game.featuredItem;
  return SheetFrame(
    title: tr('shop.title'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: IconText(
            tr('shop.have', {'n': fmt(game.gems.toDouble())}),
            style: const TextStyle(fontSize: 18),
          ),
        ),
        const SizedBox(height: 12),
        if (game.starterVisible) ...[
          StarterCard(billing: billing, game: game),
          const SizedBox(height: 14),
        ],
        // 오늘의 시장: 코인 4칸 + 다이아 1칸 + 광고 1칸 (3열 카드)
        if (game.dailyShopOpen) ...[
          // 시장은 날짜가 바뀌는 0시에 새로 들어온다 (game.offers 의 날짜 키)
          _ShopHeader(tr('market.titleRefresh', {'h': 0})),
          _CardGrid([
            for (var i = 0; i < game.offers.length; i++)
              _offerCard(context, game, i, watchAd, ad),
          ]),
          const SizedBox(height: 12),
        ],
        // 다이아 충전: 광고 1칸 + 팩 5칸
        _ShopHeader(tr('shop.gems')),
        // 광고 다이아는 한 줄로 (팩 6종은 3×2 로 맞춘다)
        if (watchAd != null)
          _ShopRow(
            icon: Art.icon('free_gift'),
            title: tr('shop.adGemsShort', {'n': GameConfig.adGems}),
            note: tr('energy.left', {'n': game.adsLeft(AdKind.gems)}),
            tag: tr('shop.freeTag'),
            button: game.gemAdAvailable
                ? '$ad+${GameConfig.adGems}'
                : tr('shop.adGemsDone'),
            ad: true,
            enabled: game.gemAdAvailable,
            onTap: () async {
              if (await watchAd(AdKind.gems)) {
                game.grantGemAd();
                sfx(Sfx.coin);
              }
            },
          ),
        _CardGrid([
          for (var i = 0; i < Gems.packs.length; i++)
            _gemPackCard(billing, game, Gems.packs[i], i),
        ]),
        if (!billing.available || billing.gemProducts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: IconText(
              tr('shop.storeSoon'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
        const SizedBox(height: 12),
        // 다이아로 사기: 에너지 · 코인 꾸러미 3 · 부스트 3 · 계절 효과
        // 다이아로 사기 3×3: 코인 꾸러미 3 · 부스트 3 · 에너지 · 깜짝 상자 · 계절 효과
        _ShopHeader(tr('shop.withGems')),
        _CardGrid([
          for (var i = 0; i < Gems.coinPacks.length; i++)
            _ShopCard(
              icon: Art.icon(const ['coins_s', 'coins_m', 'coins_l'][i]),
              title: '[[coin]] ${fmt(game.coinPackAmount(i))}',
              note: tr('shop.coinPack.$i'),
              button: '[[diamond]] ${Gems.coinPacks[i].$1}',
              enabled: game.gems >= Gems.coinPacks[i].$1,
              onTap: () {
                if (game.buyCoinPack(i)) sfx(Sfx.coin);
              },
            ),
          for (final k in BoostKind.values)
            _ShopCard(
              icon: Art.icon(boostIcon(k)),
              title: tr('boost.${k.name}'),
              note: tr('shop.boostTime', {'n': Boosts.perGems[k]!.inMinutes}),
              button: '[[diamond]] ${Boosts.gemCost[k]}',
              enabled: game.gems >= Boosts.gemCost[k]! && game.canAddBoostOf(k),
              onTap: () {
                if (game.buyBoost(k)) sfx(Sfx.coin);
              },
            ),
          _ShopCard(
            icon: Art.icon('energy_crate'),
            title: tr('shop.refillShort', {'n': Gems.refillEnergy}),
            button: '[[diamond]] ${game.refillCost}',
            enabled: game.gems >= game.refillCost,
            onTap: () {
              if (game.buyEnergyRefill()) sfx(Sfx.coin);
            },
          ),
          // 추천 아이템: 무엇이 들었는지 그림 · 이름 · 단계를 그대로 보여 준다 (무작위 상품 아님)
          _ShopCard(
            icon: Art.item(feat.$1, feat.$2),
            title: itemName(Chains.item(feat.$1, feat.$2)),
            note: tr('shop.featuredNote', {'n': feat.$2}),
            tag: tr('shop.featuredTag'),
            button: game.boardFull
                ? tr('market.boardFull')
                : '[[diamond]] ${game.surpriseGems}',
            enabled: !game.boardFull && game.gems >= game.surpriseGems,
            onTap: () {
              if (game.buySurprise(shown: feat)) sfx(Sfx.unlock);
            },
          ),
          // 계절 효과: 사고 나면 '보유 중' 으로 남겨 3×3 을 지킨다
          _ShopCard(
            icon: Art.icon('season_fx'),
            title: tr('shop.effect'),
            note: tr('shop.effectNote'),
            button: game.effects.contains(Starter.effect)
                ? tr('shop.owned')
                : '[[diamond]] ${Gems.effectGems}',
            enabled:
                !game.effects.contains(Starter.effect) &&
                game.gems >= Gems.effectGems,
            onTap: () {
              if (game.buyEffect(Starter.effect)) sfx(Sfx.unlock);
            },
          ),
        ]),
        const SizedBox(height: 12),
        _ShopHeader(tr('shop.adFreeTitle')),
        if (billing.adFree)
          IconText(
            tr('shop.active'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17),
          )
        else
          _ShopRow(
            icon: Art.icon('garden_pass'),
            title: tr('shop.adFree'),
            tag: tr('shop.passTag'),
            note: tr('shop.body', {
              'gems': OrderQuota.passDailyGems,
              'quota': OrderQuota.pass,
              'cells': GameConfig.passVault.length,
            }),
            button: billing.product == null
                ? tr('shop.connecting')
                : tr('shop.subscribe', {'price': billing.product!.price}),
            enabled: billing.product != null && !billing.purchasing,
            onTap: billing.buyRemoveAds,
          ),
        TextButton(
          onPressed: billing.restore,
          child: IconText(tr('shop.restore')),
        ),
      ],
    ),
  );
});

/// 오늘의 시장 카드 하나.
Widget _offerCard(
  BuildContext context,
  GameState game,
  int index,
  Future<bool> Function(AdKind kind)? watchAd,
  String ad,
) {
  final o = game.offers[index];
  final full = !o.sold && game.boardFull;
  final coinUnit = UnitFmt.of([
    for (final x in game.offers)
      if (x.kind <= 2) x.price.toDouble(),
  ]);
  final button = o.sold
      ? tr('market.sold')
      : full
      ? tr('market.boardFull')
      : switch (o.kind) {
          1 => tr('market.take'),
          3 => '[[diamond]] ${o.price}',
          4 => '$ad${tr('market.adTake')}',
          _ => '[[coin]] ${coinUnit(o.price)}',
        };
  final enabled =
      !o.sold &&
      !full &&
      switch (o.kind) {
        3 => game.gems >= o.price,
        4 => watchAd != null && game.canWatchAd(AdKind.market),
        _ => game.coins >= o.price,
      };
  return _ShopCard(
    icon: Art.item(o.chain, o.level),
    title: itemName(Chains.item(o.chain, o.level)),
    note: tr('market.level', {'n': o.level}),
    tag: switch (o.kind) {
      1 => tr('market.freeTag'),
      2 => tr('market.helperTag'),
      3 || 4 => tr('market.rareTag'),
      _ => null,
    },
    ad: o.kind == 4,
    button: button,
    enabled: enabled,
    onTap: () async {
      var watched = false;
      if (o.kind == 4) {
        watched = await watchAd!(AdKind.market);
        if (!watched) return;
      }
      if (game.buyOffer(index, adWatched: watched) == BuyResult.ok) {
        sfx(Sfx.coin);
      }
    },
  );
}

/// 다이아 팩 카드.
Widget _gemPackCard(
  BillingService billing,
  GameState game,
  GemPack pack,
  int index,
) {
  final d = billing.gemProducts[pack.id];
  final first = game.firstPackBonus(pack);
  return _ShopCard(
    // 팩 그림: 100 한 줌 · 430 바구니 · 900 주머니 · 2,000 상자 · 6,000 보물 상자 · 14,000 보물단지
    icon: Art.icon(
      const ['dia_1', 'dia_basket', 'dia_2', 'dia_3', 'dia_4', 'dia_5'][index],
    ),
    title: '[[diamond]] ${fmtInt(pack.gems)}',
    // 첫 구매: 같은 만큼 더 (2배)
    note: first
        ? tr('shop.firstBonus', {
            'n': fmtInt(pack.gems * (Gems.firstBuyMultiplier - 1)),
          })
        : null,
    // 첫 구매: 기본 팩(100개) 대비 얼마나 이득인지 % 딱지
    sticker: first
        ? (
            '+${(pack.valueX * Gems.firstBuyMultiplier * 100 - 100).round()}%',
            tr('shop.firstShort'),
          )
        : null,
    tag: first
        ? null
        : pack.valueX >= 1.95
        ? tr('shop.bonusX', {
            'n': pack.valueX.toStringAsFixed(pack.valueX < 3.05 ? 0 : 1),
          })
        : pack.bonusPct > 0
        ? tr('shop.bonus', {'n': pack.bonusPct})
        : null,
    button: d?.price ?? '₩${fmtInt(pack.krw)}',
    enabled: d != null && !billing.purchasing,
    onTap: () => billing.buyGems(pack),
  );
}

/// 상점 카드 격자: 3열 (휴대폰 폭이 좁으면 2열).
class _CardGrid extends StatelessWidget {
  const _CardGrid(this.cards);
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = c.maxWidth < 330 ? 2 : 3;
      const gap = 8.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final card in cards) SizedBox(width: w, child: card)],
      );
    },
  );
}

/// 상점 카드: 위 그림 · 이름 · 짧은 설명 · 아래 버튼 (가격).
class _ShopCard extends StatelessWidget {
  const _ShopCard({
    required this.icon,
    required this.title,
    required this.button,
    required this.enabled,
    required this.onTap,
    this.note,
    this.tag,
    this.sticker,
    this.ad = false,
  });
  final ArtRef icon;
  final String title;
  final String? note;
  final String? tag;

  /// 모서리에 걸치는 빨간 톱니 딱지 (큰 글자 · 작은 글자), 예: ('+177%', '첫 구매').
  final (String, String)? sticker;
  final String button;
  final bool enabled;
  final bool ad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 178,
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2D3B5), width: 1.5),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              SizedBox(
                height: 62,
                child: Center(child: ArtImage(icon, size: 58)),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: IconText(
                  title,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              SizedBox(
                height: 18,
                child: note == null
                    ? null
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: IconText(
                          note!,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8A7660),
                          ),
                        ),
                      ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: FilledButton(
                  style: framedButton(
                    FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      backgroundColor: ad ? Palette.ad : null,
                    ),
                    ad ? 'button_purple' : 'button_green',
                  ),
                  onPressed: enabled ? onTap : null,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: IconText(
                      button,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (sticker != null)
            Positioned(
              top: -16,
              right: -12,
              child: Transform.rotate(
                angle: 0.16,
                child: Container(
                  width: 62,
                  height: 62,
                  alignment: Alignment.center,
                  decoration: Art.frame('sale_badge').available
                      ? BoxDecoration(
                          image: DecorationImage(
                            image: AssetImage(Art.frame('sale_badge').path),
                            fit: BoxFit.contain,
                          ),
                        )
                      : const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFE0533D),
                        ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          sticker!.$1,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Text(
                        sticker!.$2,
                        style: const TextStyle(
                          fontSize: 9,
                          height: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (tag != null && sticker == null)
            Positioned(
              top: -12,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0533D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  tag!,
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 새싹 정원 패키지 카드 (상점 맨 위 · 팝업 공용).
class StarterCard extends StatelessWidget {
  const StarterCard({super.key, required this.billing, required this.game});
  final BillingService billing;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final d = billing.starter;
    final price = d?.price ?? '₩${fmtInt(Starter.krw)}';
    final hours =
        Starter.boosts.values.fold(0, (a, b) => a + b.inMinutes) ~/ 60;
    final pct = (100 - 100 * Starter.krw / Starter.worthKrw).round();
    // 무엇이 들었는지 한눈에: 큰 아이콘 + 큰 숫자
    final items = [
      ('garden_pass', tr('starter.passShort', {'d': Starter.pass.inDays})),
      ('diamond', '×${Starter.gems}'),
      ('energy_crate', '×${Starter.energy}'),
      ('boost_bundle', tr('starter.boostShort', {'h': hours})),
      ('season_fx', tr('starter.effectShort')),
      ('outfit', tr('starter.outfitShort')),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 14, right: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFF1B8), Color(0xFFFFD3E2)],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE0A21B), width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44E0A21B),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 제목 + 한 줄 미끼 (배지 자리만큼 오른쪽을 비운다)
                Padding(
                  padding: const EdgeInsets.only(right: 70),
                  child: Row(
                    children: [
                      if (Art.frame('promo_hero').available) ...[
                        Image.asset(Art.frame('promo_hero').path, width: 68),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IconText(
                              tr('starter.title'),
                              style: const TextStyle(
                                fontSize: 22,
                                color: Color(0xFF6B3A10),
                              ),
                            ),
                            IconText(
                              tr('starter.hook'),
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFFB0472E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 한정 기간: 빨간 알약 띠 + 자명종 + 남은 시간 (그림 대신 깔끔하게 그린다)
                Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFF26B4F), Color(0xFFD8392A)],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x44B0301F),
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: IconText(
                    game.starterOfferActive
                        ? tr('starter.timerBig', {
                            't': _clock(game.starterOfferLeft),
                          })
                        : tr('starter.once'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 1.2,
                  children: [
                    for (final (icon, label) in items)
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xE6FFFFFF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFF3D9A4),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ArtImage(Art.icon(icon), size: 38),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: IconText(
                                label,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Color(0xFF4A3A22),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                // 가격: 정가 줄긋기 → 판매가, 버튼은 살짝 숨 쉬듯 커졌다 작아진다
                _Pulse(
                  child: FilledButton(
                    style: framedButton(
                      FilledButton.styleFrom(minimumSize: const Size(0, 58)),
                      'button_green',
                    ),
                    onPressed: d == null || billing.purchasing
                        ? null
                        : billing.buyStarter,
                    child: d == null
                        ? IconText(
                            tr('shop.connecting'),
                            style: const TextStyle(fontSize: 18),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '₩${fmtInt(Starter.worthKrw)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xCCFFFFFF),
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                tr('starter.buy', {'p': price}),
                                style: const TextStyle(fontSize: 21),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
          // 할인 배지: 크게, 오른쪽 위 테두리에 걸쳐서 살짝 기울여
          Positioned(
            top: -16,
            right: -12,
            child: Transform.rotate(
              angle: 0.18,
              child: Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: Art.frame('sale_badge').available
                    ? BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage(Art.frame('sale_badge').path),
                          fit: BoxFit.contain,
                        ),
                      )
                    : BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [Color(0xFFFF6A4D), Color(0xFFD8392A)],
                        ),
                        border: Border.all(color: Colors.white, width: 3.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$pct%',
                      style: const TextStyle(
                        fontSize: 26,
                        height: 1,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      tr('starter.off'),
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.1,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 남은 시간 시계 표기: 47:59:12 (초까지 흘러가 보이게).
String _clock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hms =
      '${two(d.inHours % 24)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  return d.inDays > 0 ? tr('time.dayClock', {'d': d.inDays, 't': hms}) : hms;
}

/// 살짝 숨 쉬듯 커졌다 작아지는 강조 (구매 버튼).
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: Tween(
      begin: 0.97,
      end: 1.03,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: widget.child,
  );
}

/// 새싹 정원 패키지 팝업 (첫 구역 완성 직후 · 에너지가 떨어졌을 때 한 번 더).
Future<void> showStarterSheet(
  BuildContext context,
  BillingService billing,
  GameState game,
) {
  Analytics.instance.starterView(game, 'popup');
  return _starterSheet(context, billing, game);
}

Future<void> _starterSheet(
  BuildContext context,
  BillingService billing,
  GameState game,
) => showGameSheet(
  context,
  Listenable.merge([billing, game]),
  () => SheetFrame(
    title: tr('starter.sheetTitle'),
    child: game.starterBought
        ? IconText(
            tr('starter.thanks'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17),
          )
        : StarterCard(billing: billing, game: game),
  ),
);

/// 부스트 아이콘 (HUD · 창 공용).
String boostIcon(BoostKind k) => switch (k) {
  BoostKind.coins => 'coinbag',
  BoostKind.energy => 'energy_jar',
  BoostKind.lucky => 'sparkle',
};

/// 시간제 부스트 3종: 광고로 짧게, 다이아로 길게. 남은 시간은 쌓인다 (최대 60분).
Future<void> showBoostSheet(
  BuildContext context,
  GameState game, {
  required Future<bool> Function(AdKind kind) watchAd,
  required bool adFree,
}) => showGameSheet(
  context,
  game,
  () => SheetFrame(
    title: tr('boost.title'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: IconText(
            tr('shop.have', {'n': fmt(game.gems.toDouble())}),
            style: const TextStyle(fontSize: 17),
          ),
        ),
        const SizedBox(height: 10),
        for (final k in BoostKind.values)
          _BoostRow(game: game, kind: k, watchAd: watchAd, adFree: adFree),
        IconText(
          tr('boost.note', {'n': Boosts.max.inMinutes}),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
      ],
    ),
  ),
);

class _BoostRow extends StatelessWidget {
  const _BoostRow({
    required this.game,
    required this.kind,
    required this.watchAd,
    required this.adFree,
  });
  final GameState game;
  final BoostKind kind;
  final Future<bool> Function(AdKind kind) watchAd;
  final bool adFree;

  @override
  Widget build(BuildContext context) {
    final on = game.boosted(kind);
    final room = game.canAddBoostOf(kind);
    final cost = Boosts.gemCost[kind]!;
    final tokens = game.boostTokenCount(kind);
    final pack = game.boostTokenPack(kind);

    // 두 줄 버튼: 위 아이콘 · 값, 아래 설명 (두 버튼 모두 같은 크기)
    Widget btn({
      required String frame,
      required String top,
      required String bottom,
      required bool light,
      required VoidCallback? onTap,
    }) => Expanded(
      child: SizedBox(
        height: 60,
        child: FilledButton(
          style: framedButton(
            FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            frame,
          ),
          onPressed: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: IconText(
                  top,
                  iconScale: 1.1,
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.1,
                    color: light ? Colors.white : null,
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  bottom,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    color: light
                        ? const Color(0xE6FFFFFF)
                        : const Color(0xFF4A3A22),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: on ? const Color(0xFFFFF6D8) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: on ? Palette.accent : const Color(0xFFE2D3B5),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ArtImage(Art.icon(boostIcon(kind)), size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconText(
                      tr('boost.${kind.name}'),
                      style: const TextStyle(fontSize: 17),
                    ),
                    IconText(
                      tr('boost.${kind.name}.note', {
                        'n': (Boosts.energySaveChance * 100).round(),
                      }),
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: Color(0xFF5E6B5E),
                      ),
                    ),
                  ],
                ),
              ),
              if (on)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Palette.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconText(
                    '[[timer]]${fmtDuration(game.boostLeft(kind))}',
                    iconScale: 1.0,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              btn(
                frame: 'button_purple',
                top: adFree ? tr('boost.free') : '[[ad]]',
                bottom: tr('boost.minutes', {
                  'n': Boosts.perAd[kind]!.inMinutes,
                }),
                light: true,
                onTap: room && game.canWatchAd(AdKind.boost)
                    ? () async {
                        if (await watchAd(AdKind.boost)) {
                          game.grantBoostAd(kind);
                          sfx(Sfx.coin);
                        }
                      }
                    : null,
              ),
              const SizedBox(width: 10),
              tokens > 0
                  ? btn(
                      frame: 'button_green',
                      top:
                          '[[${boostIcon(kind)}]] ${tr('boost.count', {'n': tokens})}',
                      bottom: tr('boost.use', {'n': pack}),
                      light: false,
                      onTap: room
                          ? () {
                              if (game.useBoostToken(kind)) sfx(Sfx.coin);
                            }
                          : null,
                    )
                  : btn(
                      frame: 'button_green',
                      top: '[[diamond]] $cost',
                      bottom: tr('boost.minutes', {
                        'n': Boosts.perGems[kind]!.inMinutes,
                      }),
                      light: false,
                      onTap: room && game.gems >= cost
                          ? () {
                              if (game.buyBoost(kind)) sfx(Sfx.coin);
                            }
                          : null,
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShopHeader extends StatelessWidget {
  const _ShopHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6, left: 2),
    child: IconText(
      text,
      style: const TextStyle(fontSize: 15, color: Color(0xFF6B5638)),
    ),
  );
}

class _ShopRow extends StatelessWidget {
  const _ShopRow({
    required this.icon,
    required this.title,
    required this.button,
    required this.enabled,
    required this.onTap,
    this.note,
    this.tag,
    this.ad = false,
  });
  final ArtRef icon;
  final String title;
  final String? note;
  final String? tag;
  final String button;
  final bool enabled;
  final bool ad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2D3B5), width: 1.5),
      ),
      child: Row(
        children: [
          ArtImage(icon, size: 46),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 제목과 보너스 표시는 자리가 모자라면 다음 줄로
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconText(title, style: const TextStyle(fontSize: 17)),
                    if (tag != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE08A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tag!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7A4B00),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (note != null)
                  IconText(
                    note!,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: Color(0xFF5E6B5E),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CostButton(
            label: button,
            onPressed: enabled ? onTap : null,
            frame: ad ? 'button_purple' : 'button_green',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 설정

/// 설정: 언어 전환 + 계정 영역(로그인/연결/삭제는 accountSection 으로 주입).
Future<void> showSettingsSheet(
  BuildContext context, {
  required Listenable listen,
  required Widget Function() accountSection,
  String version = '',
  GameState? game,
}) => showGameSheet(
  context,
  listen,
  () => SheetFrame(
    title: tr('settings.title'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: AudioService.instance,
          builder: (context, _) => Column(
            children: [
              ListenableBuilder(
                listenable: NotifyService.instance,
                builder: (context, _) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    tr('settings.notify'),
                    style: const TextStyle(fontSize: 18),
                  ),
                  subtitle: Text(
                    tr('settings.notifyNote'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: NotifyService.instance.on,
                  onChanged: NotifyService.instance.setOn,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr('settings.music'),
                  style: const TextStyle(fontSize: 18),
                ),
                value: AudioService.instance.musicOn,
                onChanged: AudioService.instance.setMusic,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr('settings.sfx'),
                  style: const TextStyle(fontSize: 18),
                ),
                value: AudioService.instance.sfxOn,
                onChanged: (v) {
                  AudioService.instance.setSfx(v);
                  if (v) sfx(Sfx.tap);
                },
              ),
              if (game != null && game.effects.contains(Starter.effect))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    tr('settings.effect'),
                    style: const TextStyle(fontSize: 18),
                  ),
                  value: game.effectOn == Starter.effect,
                  onChanged: (v) => game.setEffect(v ? Starter.effect : null),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        IconText(tr('settings.language'), style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final e in L10n.supported.entries)
              ChoiceChip(
                label: Text(e.value, style: const TextStyle(fontSize: 16)),
                selected: L10n.instance.lang == e.key,
                onSelected: (_) => L10n.instance.setLanguage(e.key),
              ),
          ],
        ),
        const SizedBox(height: 18),
        IconText(tr('settings.account'), style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 6),
        accountSection(),
        if (version.isNotEmpty) ...[
          const SizedBox(height: 18),
          // 버전 글자를 7번 누르면 개발자 모드 (성장 로그)
          _VersionTap(version: version, game: game),
        ],
      ],
    ),
  ),
);

class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FrameBox(
      frame: 'panel',
      fallback: const BoxDecoration(),
      corner: 26,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                IconText(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(height: 12),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionTap extends StatefulWidget {
  const _VersionTap({required this.version, this.game});
  final String version;
  final GameState? game;

  @override
  State<_VersionTap> createState() => _VersionTapState();
}

class _VersionTapState extends State<_VersionTap> {
  int _taps = 0;
  DateTime _last = DateTime(2000);

  void _tap() {
    final now = DateTime.now();
    _taps = now.difference(_last).inSeconds > 2 ? 1 : _taps + 1;
    _last = now;
    if (_taps >= 7) {
      _taps = 0;
      DevLog.instance.toggle().then((_) {
        if (!mounted) return;
        TopToast.show(
          context,
          DevLog.instance.on ? '개발자 모드 켜짐: 성장 로그 보기 가능' : '개발자 모드 꺼짐',
        );
        setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DevLog.instance,
      builder: (context, _) => Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _tap,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: IconText(
                tr('settings.version', {'v': widget.version}),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black45),
              ),
            ),
          ),
          if (DevLog.instance.on) ...[
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: () => _showDevLog(context, widget.game),
              child: Text('성장 로그 (약 ${DevLog.instance.lineCount}줄)'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 개발자 전용: 성장 로그 보기 · 파일로 내보내기 · 비우기.
Future<void> _showDevLog(
  BuildContext context,
  GameState? game,
) => showGameSheet(context, DevLog.instance, () {
  final log = DevLog.instance;
  final kb = (log.bytes / 1024).round();
  return SheetFrame(
    title: '성장 로그',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '약 ${log.lineCount}줄 · ${kb}KB\n행동마다 · 1분마다 재화 · 5분마다 판 상태'
          '${log.problem == null ? '' : '\n저장 문제: ${log.problem}'}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        Container(
          height: 180,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F0E8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            reverse: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                log.recent.join('\n'),
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            FilledButton(
              onPressed: () async {
                final r = await log.exportFile();
                if (!context.mounted) return;
                final p = r.split(':');
                // 결과는 창 위에 뜨는 대화상자로 (아래 알림은 이 창에 가려진다)
                await showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    content: Text(
                      p.first == 'ok'
                          ? '${p[1]}줄을 공유 창으로 보냈어요.\n드라이브 · 카톡 등에 저장해서 Claude 에게 올려 주세요.'
                          : '공유 창을 열 수 없어 ${p[1]}줄 전체를 클립보드에 복사했어요.\n메모 앱 등에 붙여 넣어 보내 주세요.\n(${p.skip(2).join(':')})',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('확인'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('파일로 내보내기'),
            ),
            if (game != null && !game.starterBought)
              OutlinedButton(
                onPressed: game.grantStarter,
                child: const Text('패키지 테스트 지급'),
              ),
            OutlinedButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    content: const Text('기록을 모두 지울까요?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('아니요'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('지우기'),
                      ),
                    ],
                  ),
                );
                if (ok == true) await log.clear();
              },
              child: const Text('비우기'),
            ),
          ],
        ),
      ],
    ),
  );
});
