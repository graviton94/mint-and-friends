import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../i18n/names.dart';
import '../services/audio_service.dart';
import '../services/billing_service.dart';
import '../services/dev_log.dart';
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

Future<void> showUpgradesSheet(BuildContext context, GameState game) =>
    showGameSheet(
      context,
      game,
      () => SheetFrame(
        title: tr('upgrade.title'),
        child: Column(
          children: [
            for (final u in Upgrades.all) _UpgradeRow(game: game, def: u),
          ],
        ),
      ),
    );

class _UpgradeRow extends StatelessWidget {
  const _UpgradeRow({required this.game, required this.def});
  final GameState game;
  final UpgradeDef def;

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
      button = '[[coin]] ${fmt(game.upgradeCost(t))}';
    }
    return Opacity(
      opacity: featureLocked ? 0.55 : 1,
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
                    IconText(
                      maxed
                          ? upgradeDescribe(t, lv)
                          : '${upgradeDescribe(t, lv)} → ${upgradeDescribe(t, lv + 1)}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF5E6B5E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: game.canBuyUpgrade(t)
                    ? () => game.buyUpgrade(t)
                    : null,
                child: IconText(button),
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
                  ? OutlinedButton(
                      onPressed: () =>
                          showStyleSheet(context, game, game.currentArea, slot),
                      child: IconText(tr('style.change')),
                    )
                  : IconText(
                      tr('decor.done'),
                      style: const TextStyle(fontSize: 15),
                    ))
            : FilledButton(
                onPressed: game.canPlace(slot)
                    ? () => game.placeDecor(slot)
                    : null,
                child: IconText(
                  game.areaLocked
                      ? tr('common.lockedLevel', {'n': game.areaRequiredLevel})
                      : '[[star]] ${game.decorCost(slot)}',
                ),
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
                  ScaffoldMessenger.maybeOf(
                    context,
                  )?.showSnackBar(SnackBar(content: Text(tr('style.noGems'))));
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
        IconText(
          tr('style.note'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
      ],
    ),
  );
});

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
        ? '[[coin]] ${fmtInt(Garden.styleCoins(area, slot))}'
        : Garden.isSeasonStyle(style)
        ? '[[diamond]] ${Garden.seasonGems}'
        : '[[diamond]] ${Garden.styleGems(area)}';
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
            onPressed: current
                ? null
                : () {
                    switch (game.setStyle(area, slot, style)) {
                      case StyleResult.ok:
                        sfx(Sfx.unlock);
                      case StyleResult.noCoins || StyleResult.noGems:
                        sfx(Sfx.error);
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          SnackBar(
                            content: Text(
                              tr(style == 1 ? 'style.noCoins' : 'style.noGems'),
                            ),
                          ),
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
            onPressed:
                current ||
                    (!owned &&
                        (outfit!.limited || !outfit!.onSaleIn(game.now.month)))
                ? null
                : () {
                    final r = game.wearOutfit(def.id, id);
                    if (r == StyleResult.ok) {
                      sfx(Sfx.unlock);
                    } else if (r == StyleResult.noGems) {
                      sfx(Sfx.error);
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(content: Text(tr('style.noGems'))),
                      );
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
                  for (final st in Garden.seasonStyles.keys)
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
                          ? '${friendName(def.id)} (${friendSpecies(def.id)})'
                          : tr('book.unknown'),
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                  if (has) ...[
                    Row(
                      children: [
                        for (var h = 0; h < Friends.maxAffection ~/ 2; h++)
                          Opacity(
                            opacity: h * 2 + 2 <= aff
                                ? 1
                                : (h * 2 + 1 <= aff ? 0.6 : 0.15),
                            child: ArtImage(Art.icon('heart'), size: 11),
                          ),
                      ],
                    ),
                    FittedBox(
                      child: IconText(
                        aff == 0 ? tr('book.noEffect') : buffText(def, aff),
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
  GameState game,
) => showGameSheet(
  context,
  Listenable.merge([billing, game]),
  () => SheetFrame(
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
        if (!game.starterBought) ...[
          StarterCard(billing: billing, game: game),
          const SizedBox(height: 14),
        ],
        if (game.dailyShopOpen) ...[
          _ShopHeader(tr('market.title')),
          for (var i = 0; i < game.offers.length; i++)
            _OfferRow(game: game, index: i),
          const SizedBox(height: 12),
        ],
        _ShopHeader(tr('shop.gems')),
        for (var i = 0; i < Gems.packs.length; i++)
          _GemPackRow(billing: billing, pack: Gems.packs[i], index: i),
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
        _ShopHeader(tr('shop.withGems')),
        _ShopRow(
          icon: Art.icon('energy_jar'),
          title: tr('shop.refill', {'n': Gems.refillEnergy}),
          note: tr('shop.refillNote'),
          button: '[[diamond]] ${game.refillCost}',
          enabled: game.gems >= game.refillCost,
          onTap: () {
            if (game.buyEnergyRefill()) sfx(Sfx.coin);
          },
        ),
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
            icon: Art.icon('no_ads'),
            title: tr('shop.adFree'),
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
  ),
);

/// 새싹 정원 패키지 카드 (상점 맨 위 · 팝업 공용).
class StarterCard extends StatelessWidget {
  const StarterCard({super.key, required this.billing, required this.game});
  final BillingService billing;
  final GameState game;

  @override
  Widget build(BuildContext context) {
    Widget line(String icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          ArtImage(Art.icon(icon), size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: IconText(
              text,
              style: const TextStyle(fontSize: 15, height: 1.25),
            ),
          ),
        ],
      ),
    );
    final d = billing.starter;
    final price = d?.price ?? '₩${fmtInt(Starter.krw)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF4C9), Color(0xFFFFE3EC)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0A21B), width: 2.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: IconText(
                  tr('starter.title'),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0533D),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tr('starter.deal'),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          IconText(
            tr('starter.worth', {'w': fmtInt(Starter.worthKrw)}),
            style: const TextStyle(fontSize: 13, color: Color(0xFF8A5A2B)),
          ),
          if (game.starterOfferActive)
            IconText(
              tr('starter.timer', {'t': fmtDuration(game.starterOfferLeft)}),
              style: const TextStyle(fontSize: 13, color: Color(0xFFE0533D)),
            ),
          const SizedBox(height: 8),
          line('no_ads', tr('starter.pass', {'d': Starter.pass.inDays})),
          line('diamond', tr('starter.gems', {'n': Starter.gems})),
          line('energy_jar', tr('starter.energy', {'n': Starter.energy})),
          line('boost', tr('starter.boosts')),
          line('sparkle', tr('starter.effect')),
          line('outfit', tr('starter.outfit')),
          const SizedBox(height: 10),
          FilledButton(
            style: framedButton(
              FilledButton.styleFrom(minimumSize: const Size(0, 50)),
              'button_green',
            ),
            onPressed: d == null || billing.purchasing
                ? null
                : billing.buyStarter,
            child: IconText(
              d == null ? tr('shop.connecting') : price,
              style: const TextStyle(fontSize: 19),
            ),
          ),
        ],
      ),
    );
  }
}

/// 새싹 정원 패키지 팝업 (첫 구역 완성 직후 · 에너지가 떨어졌을 때 한 번 더).
Future<void> showStarterSheet(
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
                      tr('boost.${kind.name}.note'),
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

class _OfferRow extends StatelessWidget {
  const _OfferRow({required this.game, required this.index});
  final GameState game;
  final int index;

  @override
  Widget build(BuildContext context) {
    final o = game.offers[index];
    final full = !o.sold && game.boardFull;
    final need = o.kind == 2
        ? game.orders
              .where((x) => x.chain == o.chain && x.level == o.level + 1)
              .firstOrNull
        : null;
    return _ShopRow(
      icon: Art.item(o.chain, o.level),
      title: itemName(Chains.item(o.chain, o.level)),
      note: switch (o.kind) {
        1 => tr('market.free'),
        2 when need != null => tr('market.helper', {
          'name': friendName(need.friendId),
        }),
        _ => tr('market.level', {'n': o.level}),
      },
      tag: o.kind == 1 ? tr('market.freeTag') : null,
      // 판이 가득하면 버튼에 이유를 바로 보여 준다 (누르면 아무 일도 안 일어나는 것처럼 보이지 않게)
      button: o.sold
          ? tr('market.sold')
          : full
          ? tr('market.boardFull')
          : o.price == 0
          ? tr('market.take')
          : '[[coin]] ${fmtInt(o.price)}',
      enabled: !o.sold && !full && game.coins >= o.price,
      onTap: () {
        if (game.buyOffer(index) == BuyResult.ok) sfx(Sfx.coin);
      },
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

class _GemPackRow extends StatelessWidget {
  const _GemPackRow({
    required this.billing,
    required this.pack,
    required this.index,
  });
  final BillingService billing;
  final GemPack pack;
  final int index;

  @override
  Widget build(BuildContext context) {
    final d = billing.gemProducts[pack.id];
    final price = d?.price ?? '₩${fmtInt(pack.krw)}';
    return _ShopRow(
      icon: Art.icon('dia_${index + 1}'),
      title: tr('shop.pack.$index'),
      note: '[[diamond]] ${fmtInt(pack.gems)}',
      tag: pack.valueX >= 1.95
          ? tr('shop.bonusX', {
              'n': pack.valueX.toStringAsFixed(pack.valueX < 3.05 ? 0 : 1),
            })
          : pack.bonusPct > 0
          ? tr('shop.bonus', {'n': pack.bonusPct})
          : null,
      button: price,
      enabled: d != null && !billing.purchasing,
      onTap: () => billing.buyGems(pack),
    );
  }
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
  });
  final ArtRef icon;
  final String title;
  final String? note;
  final String? tag;
  final String button;
  final bool enabled;
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 124),
            child: FilledButton(
              style: framedButton(
                FilledButton.styleFrom(
                  minimumSize: const Size(92, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                'button_green',
              ),
              onPressed: enabled ? onTap : null,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: IconText(button, style: const TextStyle(fontSize: 15)),
              ),
            ),
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
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              DevLog.instance.on ? '개발자 모드 켜짐: 성장 로그 보기 가능' : '개발자 모드 꺼짐',
            ),
          ),
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
