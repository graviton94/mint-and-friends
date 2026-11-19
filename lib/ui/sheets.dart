import 'package:material_ui/material_ui.dart';

import '../game/config.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../services/billing_service.dart';
import 'theme.dart';

Future<void> showUpgradesSheet(BuildContext context, GameState game) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.board,
    builder: (_) => ListenableBuilder(
      listenable: game,
      builder: (context, _) => SheetFrame(
        title: '⬆️ 강화',
        child: Column(
          children: [
            for (final u in Upgrades.all) _UpgradeRow(game: game, def: u),
          ],
        ),
      ),
    ),
  );
}

class _UpgradeRow extends StatelessWidget {
  const _UpgradeRow({required this.game, required this.def});
  final GameState game;
  final UpgradeDef def;

  @override
  Widget build(BuildContext context) {
    final lv = game.lv(def.type);
    final maxed = game.upgradeMaxed(def.type);
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Text(def.icon, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${def.title}  Lv.$lv',
                    style: const TextStyle(fontSize: 17),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    maxed
                        ? Upgrades.describe(def.type, lv)
                        : '${Upgrades.describe(def.type, lv)} → ${Upgrades.describe(def.type, lv + 1)}',
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
              onPressed: game.canBuyUpgrade(def.type)
                  ? () => game.buyUpgrade(def.type)
                  : null,
              child: Text(
                maxed ? 'MAX' : '🪙 ${fmt(game.upgradeCost(def.type))}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 꾸미기 목록. 정원 씬의 빈 자리를 탭해도 같은 일을 한다.
Future<void> showDecorSheet(BuildContext context, GameState game) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.board,
    builder: (_) => ListenableBuilder(
      listenable: game,
      builder: (context, _) {
        final area = Garden.areaAt(game.currentArea);
        final done = game.placed.length;
        return SheetFrame(
          title: '🔨 ${area.name} 꾸미기',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: done / Garden.slotsPerArea,
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 6),
              Text(
                '$done / ${Garden.slotsPerArea} 완성 · 보유 ⭐${game.stars} · 정원 매력 x${game.gardenMultiplier.toStringAsFixed(1)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < area.decor.length; i++)
                _DecorRow(game: game, area: area, slot: i),
            ],
          ),
        );
      },
    ),
  );
}

class _DecorRow extends StatelessWidget {
  const _DecorRow({required this.game, required this.area, required this.slot});
  final GameState game;
  final AreaDef area;
  final int slot;

  @override
  Widget build(BuildContext context) {
    final d = area.decor[slot];
    final placed = game.placed.contains(slot);
    final friend = d.bringsFriend == null
        ? null
        : Friends.byId(d.bringsFriend!);
    final newFriend = friend != null && !game.friends.contains(friend.id);
    return Card(
      color: placed ? const Color(0xFFE3F1DD) : Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Text(d.emoji, style: const TextStyle(fontSize: 30)),
        title: Text(d.name, style: const TextStyle(fontSize: 17)),
        subtitle: newFriend
            ? Text('${friend.emoji} ${friend.name}(이)가 놀러 와요!')
            : null,
        trailing: placed
            ? const Text('완료 ✅', style: TextStyle(fontSize: 15))
            : FilledButton(
                onPressed: game.canPlace(slot)
                    ? () => game.placeDecor(slot)
                    : null,
                child: Text('⭐ ${game.decorCost(slot)}'),
              ),
      ),
    );
  }
}

/// 도감: 친구(호감도, 효과)와 발견한 아이템.
Future<void> showCollectionSheet(BuildContext context, GameState game) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.board,
    builder: (_) => ListenableBuilder(
      listenable: game,
      builder: (context, _) => SheetFrame(
        title: '📖 도감',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('친구들', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.0,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final f in Friends.all) _FriendCard(game: game, def: f),
              ],
            ),
            const SizedBox(height: 14),
            for (final chain in Chain.values) ...[
              Text(
                chain == Chain.flower ? '꽃' : '간식',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var lv = 1; lv <= GameConfig.maxLevel; lv++)
                    _ItemChip(
                      def: Chains.item(chain, lv),
                      level: lv,
                      found: lv <= (game.highest[chain] ?? 1),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ),
  );
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({required this.game, required this.def});
  final GameState game;
  final FriendDef def;

  @override
  Widget build(BuildContext context) {
    final has = game.friends.contains(def.id);
    final aff = game.affection(def.id);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: has ? Colors.white : const Color(0xFFEDE8DC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: has ? 1 : 0.25,
            child: Text(
              has ? def.emoji : '❔',
              style: const TextStyle(fontSize: 34),
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
                    has ? '${def.name} (${def.species})' : '???',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                if (has) ...[
                  Text(
                    '💗' * (aff ~/ 2) + (aff.isOdd ? '🩷' : ''),
                    style: const TextStyle(fontSize: 10),
                  ),
                  FittedBox(
                    child: Text(
                      aff == 0 ? '부탁을 들어주면 효과 발동' : def.buffText(aff),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5E6B5E),
                      ),
                    ),
                  ),
                ] else
                  const Text(
                    '꾸미기로 초대',
                    style: TextStyle(fontSize: 12, color: Color(0xFF8A8A7A)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemChip extends StatelessWidget {
  const _ItemChip({
    required this.def,
    required this.level,
    required this.found,
  });
  final ItemDef def;
  final int level;
  final bool found;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: found ? 'Lv$level ${def.name}' : '???',
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: found ? Colors.white : const Color(0xFFEDE8DC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          found ? def.emoji : '❔',
          style: TextStyle(fontSize: 24, color: found ? null : Colors.black26),
        ),
      ),
    );
  }
}

Future<void> showShopSheet(BuildContext context, BillingService billing) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Palette.board,
    builder: (_) => ListenableBuilder(
      listenable: billing,
      builder: (context, _) => SheetFrame(
        title: '🚫 광고 제거 (1개월)',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '• 배너·전면 광고가 사라져요\n• 보상 광고 보상을 광고 없이 바로 받아요\n• 매월 자동 갱신, Play 스토어에서 언제든 해지',
              style: TextStyle(fontSize: 16, height: 1.6),
            ),
            const SizedBox(height: 16),
            if (billing.adFree)
              const Text(
                '✅ 광고 제거 이용 중',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              )
            else
              FilledButton(
                onPressed: billing.product == null || billing.purchasing
                    ? null
                    : billing.buyRemoveAds,
                child: Text(
                  billing.product == null
                      ? '스토어 연결 중…'
                      : '${billing.product!.price} / 월 구독하기',
                ),
              ),
            TextButton(onPressed: billing.restore, child: const Text('구매 복원')),
          ],
        ),
      ),
    ),
  );
}

class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
              Text(
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
    );
  }
}
