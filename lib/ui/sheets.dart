import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../i18n/names.dart';
import '../services/audio_service.dart';
import '../services/billing_service.dart';
import 'theme.dart';
import 'widgets/frame_box.dart';
import 'widgets/icon_text.dart';

Future<void> _sheet(
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

Future<void> showUpgradesSheet(BuildContext context, GameState game) => _sheet(
  context,
  game,
  () => SheetFrame(
    title: tr('upgrade.title'),
    child: Column(
      children: [for (final u in Upgrades.all) _UpgradeRow(game: game, def: u)],
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
      button = tr('upgrade.needLevel', {'n': game.level + 1});
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
              ArtImage(Art.icon(def.icon), size: 34),
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

Future<void> showDecorSheet(BuildContext context, GameState game) => _sheet(
  context,
  game,
  () {
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
                style: const TextStyle(fontSize: 16, color: Color(0xFFB0640A)),
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
  },
);

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
        leading: ArtImage(Art.decor(d), size: 40),
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
            ? IconText(tr('decor.done'), style: const TextStyle(fontSize: 15))
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

// ---------------------------------------------------------------- 도감

Future<void> showCollectionSheet(
  BuildContext context,
  GameState game,
) => _sheet(
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
          childAspectRatio: 2.0,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final f in Friends.all) _FriendCard(game: game, def: f),
          ],
        ),
        const SizedBox(height: 14),
        for (final chain in Chain.values) ...[
          Text(chainName(chain), style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var lv = 1; lv <= GameConfig.maxLevel; lv++)
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
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: has ? Colors.white : const Color(0xFFEDE8DC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: has ? 1 : 0.2,
            child: ArtImage(Art.friend(def), size: 38),
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
}) => _sheet(
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

Future<void> showShopSheet(BuildContext context, BillingService billing) =>
    _sheet(
      context,
      billing,
      () => SheetFrame(
        title: tr('shop.title'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IconText(
              tr('shop.body'),
              style: const TextStyle(fontSize: 16, height: 1.6),
            ),
            const SizedBox(height: 16),
            if (billing.adFree)
              IconText(
                tr('shop.active'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              )
            else
              FilledButton(
                onPressed: billing.product == null || billing.purchasing
                    ? null
                    : billing.buyRemoveAds,
                child: IconText(
                  billing.product == null
                      ? tr('shop.connecting')
                      : tr('shop.subscribe', {'price': billing.product!.price}),
                ),
              ),
            TextButton(
              onPressed: billing.restore,
              child: IconText(tr('shop.restore')),
            ),
          ],
        ),
      ),
    );

// ---------------------------------------------------------------- 설정

/// 설정: 언어 전환 + 계정 영역(로그인/연결/삭제는 accountSection 으로 주입).
Future<void> showSettingsSheet(
  BuildContext context, {
  required Listenable listen,
  required Widget Function() accountSection,
  String version = '',
}) => _sheet(
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
          IconText(
            tr('settings.version', {'v': version}),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black45),
          ),
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
