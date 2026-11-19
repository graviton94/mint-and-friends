import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../i18n/names.dart';
import '../services/ad_ids.dart';
import '../services/ads_service.dart';
import '../services/billing_service.dart';
import 'board/board_view.dart';
import 'garden/garden_scene.dart';
import 'orders_bar.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets/icon_text.dart';
import 'widgets/frame_box.dart';

/// 메인 화면. 배치(위→아래): 상단 HUD / 정원 씬 / 부탁 / 머지 보드 / 정보 줄 / 광고·바구니 / 배너
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.game,
    required this.ads,
    required this.billing,
    required this.openSettings,
    this.extraListenable,
  });
  final GameState game;
  final AdsService ads;
  final BillingService billing;
  final void Function(BuildContext context) openSettings;
  final Listenable? extraListenable;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<GameEvent>? _sub;
  final List<_Toast> _toasts = [];
  int _toastId = 0;
  late int _viewArea;
  int? _selected;
  final List<LevelUpEvent> _levelUps = [];
  bool _levelDialogOpen = false;

  GameState get game => widget.game;
  bool get adFree => widget.billing.adFree;

  @override
  void initState() {
    super.initState();
    _viewArea = game.currentArea;
    _sub = game.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- 이벤트

  void _onEvent(GameEvent e) {
    switch (e) {
      case DiscoveryEvent(:final chain, :final level, :final bonus):
        final d = Chains.item(chain, level);
        _toast(
          tr('toast.discovery', {
            'emoji': itemToken(d.chain, d.level),
            'name': itemName(d),
            'coins': fmt(bonus),
          }),
        );
      case MaxMergeEvent(:final payout):
        _toast(tr('toast.maxMerge', {'coins': fmt(payout)}));
      case OrderDeliveredEvent(
        :final friendId,
        :final stars,
        :final affectionUp,
      ):
        _toast(
          tr('toast.thanks', {'emoji': friendToken(friendId), 'stars': stars}) +
              (affectionUp ? tr('toast.affectionUp') : ''),
        );
      case DecorPlacedEvent(:final area, :final slot):
        final d = Garden.areaAt(area).decor[slot];
        _toast(
          tr('toast.decorDone', {'emoji': decorToken(d), 'name': decorName(d)}),
        );
        setState(() => _viewArea = area);
        widget.ads.maybeShowInterstitial();
      case FriendJoinedEvent(:final friendId):
        _toast(
          tr('toast.friendJoined', {
            'emoji': friendToken(friendId),
            'name': friendName(friendId),
          }),
        );
      case AreaCompletedEvent(:final area):
        _toast(tr('toast.areaDone', {'name': areaName(Garden.areaAt(area))}));
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _viewArea = game.currentArea);
        });
      case LevelUpEvent():
        _levelUps.add(e);
        _showLevelUps();
      case BubbleEvent():
        _toast(tr('toast.bubble'));
      case SoldEvent(:final price):
        _toast(tr('toast.sold', {'coins': fmt(price)}));
      case MergedEvent():
        break;
    }
  }

  void _toast(String msg) {
    final t = _Toast(_toastId++, msg);
    setState(() {
      _toasts.add(t);
      if (_toasts.length > 3) _toasts.removeAt(0);
    });
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _toasts.remove(t));
    });
  }

  Future<void> _showLevelUps() async {
    if (_levelDialogOpen || _levelUps.isEmpty || !mounted) return;
    _levelDialogOpen = true;
    final e = _levelUps.removeAt(0);
    await showDialog<void>(
      context: context,
      builder: (ctx) => GameDialog(
        title: IconText(
          tr('levelUp.title', {'n': e.level}),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconText(
              tr('levelUp.reward', {'coins': fmt(e.coins), 'energy': e.energy}),
              style: const TextStyle(fontSize: 20),
            ),
            if (e.unlocked.isNotEmpty) ...[
              const SizedBox(height: 14),
              IconText(
                tr('levelUp.unlocked'),
                style: const TextStyle(fontSize: 15, color: Colors.black54),
              ),
              const SizedBox(height: 6),
              for (final f in e.unlocked)
                IconText(featureName(f), style: const TextStyle(fontSize: 19)),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: IconText(tr('levelUp.ok')),
          ),
        ],
      ),
    );
    _levelDialogOpen = false;
    _showLevelUps();
  }

  // ---------------------------------------------------------------- 행동

  Future<bool> _rewarded() async {
    final ok = await widget.ads.showRewarded();
    if (!ok) _toast(tr('toast.adLoading'));
    return ok;
  }

  bool _gate(Feature f) {
    if (game.isUnlocked(f)) return true;
    _toast(tr('toast.featureLocked', {'n': Leveling.unlockLevel[f]}));
    return false;
  }

  /// 하루 상한이 있는 광고: 남은 횟수 확인 → 시청 → 기록.
  Future<bool> _rewardedCapped(AdKind kind) async {
    if (!game.canWatchAd(kind)) {
      _toast(tr('toast.adLimit'));
      return false;
    }
    if (!await _rewarded()) return false;
    game.recordAd(kind);
    return true;
  }

  Future<void> _onSpawnerTap() async {
    if (game.tapSpawner() == TapResult.noEnergy) await _energyDialog();
  }

  Future<void> _energyDialog() async {
    final canAd =
        game.isUnlocked(Feature.energyAd) && game.canWatchAd(AdKind.energy);
    final watch = await showDialog<bool>(
      context: context,
      builder: (ctx) => GameDialog(
        title: IconText(tr('energy.title'), textAlign: TextAlign.center),
        content: IconText(
          tr('energy.body', {
                'cap': GameConfig.energyCap,
                'time': fmtDuration(game.energyNextIn),
              }) +
              (game.isUnlocked(Feature.energyAd)
                  ? '\n${tr('energy.left', {'n': game.adsLeft(AdKind.energy)})}'
                  : ''),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: IconText(tr('energy.wait')),
          ),
          if (canAd)
            FilledButton(
              style: framedButton(
                FilledButton.styleFrom(backgroundColor: Palette.ad),
                'button_purple',
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: IconText(
                _adLabel(tr('energy.watch', {'n': GameConfig.energyAdAmount})),
              ),
            ),
        ],
      ),
    );
    if (watch == true && await _rewardedCapped(AdKind.energy))
      game.grantEnergyAd();
  }

  Future<void> _watchBoost() async {
    if (!_gate(Feature.boost)) return;
    if (await _rewardedCapped(AdKind.boost)) {
      game.grantBoost();
      _toast(tr('toast.boost', {'time': fmtDuration(game.boostRemaining)}));
    }
  }

  Future<void> _watchCoinBag() async {
    if (!_gate(Feature.coinBag)) return;
    if (await _rewardedCapped(AdKind.coinBag))
      _toast(tr('toast.coins', {'coins': fmt(game.grantCoinBag())}));
  }

  Future<void> _refreshOrder(int i) async {
    if (await _rewardedCapped(AdKind.refresh)) game.refreshOrder(i);
  }

  void _onSlotTap(int slot) {
    if (game.areaLocked) {
      _toast(tr('toast.areaLocked', {'n': game.areaRequiredLevel}));
    } else if (game.canPlace(slot)) {
      game.placeDecor(slot);
    } else {
      final d = Garden.areaAt(game.currentArea).decor[slot];
      _toast(
        tr('toast.needStars', {
          'emoji': decorToken(d),
          'name': decorName(d),
          'cost': game.decorCost(slot),
        }),
      );
    }
  }

  Future<void> _onLockedCell(int cell) async {
    if (game.level < game.nextCellLevel) {
      _toast(tr('cell.needLevel', {'n': game.nextCellLevel}));
      return;
    }
    final cost = game.nextCellCost;
    final enough = game.coins >= cost;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => GameDialog(
        title: IconText(tr('cell.title'), textAlign: TextAlign.center),
        content: IconText(
          tr('cell.body', {'cost': fmt(cost)}),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: IconText(tr('common.cancel')),
          ),
          FilledButton(
            onPressed: enough ? () => Navigator.pop(ctx, true) : null,
            child: IconText(
              enough
                  ? tr('cell.open')
                  : tr('cell.needCoins', {'cost': fmt(cost)}),
            ),
          ),
        ],
      ),
    );
    if (ok == true) game.buyCell(cell);
  }

  Future<void> _onBubble(int cell) async {
    if (await _rewarded()) game.popBubble(cell);
  }

  Future<void> _onVisitorTap() async {
    final withAd = await showDialog<bool>(
      context: context,
      builder: (ctx) => GameDialog(
        title: IconText(tr('visitor.title'), textAlign: TextAlign.center),
        content: IconText(
          tr('visitor.body'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: IconText(
              tr('visitor.take', {
                'coins': fmt(game.visitorCoins(withAd: false)),
              }),
            ),
          ),
          FilledButton(
            style: framedButton(
              FilledButton.styleFrom(backgroundColor: Palette.ad),
              'button_purple',
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: IconText(
              _adLabel(
                tr('visitor.takeBig', {
                  'coins': fmt(game.visitorCoins(withAd: true)),
                  'stars': GameConfig.visitorAdStars,
                }),
              ),
            ),
          ),
        ],
      ),
    );
    if (withAd == null) return;
    final ok = withAd ? await widget.ads.showRewarded() : false;
    final r = game.claimVisitor(withAd: ok);
    if (r != null) {
      _toast(
        tr('toast.gift', {'coins': fmt(r.coins)}) +
            (r.stars > 0 ? tr('toast.giftStars', {'stars': r.stars}) : ''),
      );
    }
  }

  String _adLabel(String label) =>
      adFree ? label : tr('ctrl.ad', {'label': label});

  // ---------------------------------------------------------------- 화면

  @override
  Widget build(BuildContext context) {
    final extra = widget.extraListenable;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Palette.bgTop, Palette.bgBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([
              game,
              widget.ads,
              widget.billing,
              L10n.instance,
              ?extra,
            ]),
            builder: (context, _) {
              final sel = _selected;
              if (sel != null &&
                  (game.board[sel] == null || game.board[sel]!.isBubble))
                _selected = null;
              if (_viewArea > game.currentArea) _viewArea = game.currentArea;
              return Column(
                children: [
                  _topBar(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                      child: _sceneArea(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: OrdersBar(
                      game: game,
                      onRefresh: _refreshOrder,
                      adFree: adFree,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                    child: BoardView(
                      game: game,
                      selected: _selected,
                      onSelect: (c) => setState(() => _selected = c),
                      onLockedTap: _onLockedCell,
                      onBubbleTap: _onBubble,
                    ),
                  ),
                  _infoBar(),
                  _controls(),
                  if (!adFree) const BannerSlot(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          _LevelBadge(level: game.level, progress: game.xp / game.xpToNext),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: FrameBox(
                    frame: 'capsule',
                    fallback: const BoxDecoration(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    corner: 14,
                    child: Row(
                      children: [
                        ArtImage(Art.coin, size: 24),
                        Text(
                          ' ${fmt(game.coins)}',
                          style: const TextStyle(fontSize: 22),
                        ),
                        const SizedBox(width: 12),
                        ArtImage(Art.star, size: 24),
                        Text(
                          ' ${game.stars}',
                          style: const TextStyle(fontSize: 22),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: _energyDialog,
                          child: IconText(
                            '[[energy]]${game.energy}/${GameConfig.energyCap}',
                            style: TextStyle(
                              fontSize: 22,
                              color: game.energy == 0
                                  ? const Color(0xFFB0640A)
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      IconText(
                        tr('hud.perSec', {'v': fmt(game.incomePerSec)}),
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (game.boostActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Palette.ad,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: IconText(
                            tr('hud.boost', {
                              'time': fmtDuration(game.boostRemaining),
                            }),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!adFree) ...[
            _MenuButton(
              icon: 'no_ads',
              label: tr('menu.removeAds'),
              onTap: () => showShopSheet(context, widget.billing),
            ),
            const SizedBox(width: 5),
          ],
          _MenuButton(
            icon: 'settings',
            label: tr('menu.settings'),
            onTap: () => widget.openSettings(context),
          ),
        ],
      ),
    );
  }

  Widget _sceneArea() {
    final canDecorate = List.generate(
      Garden.slotsPerArea,
      game.canPlace,
    ).any((x) => x);
    return GardenScene(
      game: game,
      area: _viewArea,
      onSlotTap: _onSlotTap,
      onVisitorTap: _onVisitorTap,
      overlay: [
        // L3: 구역 이름과 이동
        Positioned(
          left: 6,
          top: 6,
          child: Row(
            children: [
              if (_viewArea > 0)
                _RoundButton(
                  label: 'arrow_left',
                  onTap: () => setState(() => _viewArea--),
                ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconText(
                  areaLabel(game, _viewArea),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (_viewArea < game.currentArea)
                _RoundButton(
                  label: 'arrow_right',
                  onTap: () => setState(() => _viewArea++),
                ),
            ],
          ),
        ),
        // L3: 메뉴 (하늘 영역 오른쪽 위, 장식 자리와 겹치지 않음)
        Positioned(
          right: 6,
          top: 6,
          child: Row(
            children: [
              _MenuButton(
                icon: 'book',
                label: tr('menu.book'),
                small: true,
                onTap: () => showCollectionSheet(context, game),
              ),
              const SizedBox(width: 4),
              _MenuButton(
                icon: game.isUnlocked(Feature.upgrades) ? 'upgrade' : 'lock',
                label: tr('menu.upgrade'),
                small: true,
                badge: Upgrades.all.any((u) => game.canBuyUpgrade(u.type)),
                onTap: () {
                  if (_gate(Feature.upgrades)) showUpgradesSheet(context, game);
                },
              ),
              const SizedBox(width: 4),
              _MenuButton(
                icon: 'decorate',
                label: tr('menu.decorate'),
                small: true,
                badge: canDecorate,
                onTap: () {
                  setState(() => _viewArea = game.currentArea);
                  showDecorSheet(context, game);
                },
              ),
            ],
          ),
        ),
        // 알림
        Positioned(
          left: 10,
          right: 10,
          top: 56,
          child: IgnorePointer(
            child: Column(
              children: [
                for (final t in _toasts)
                  _ToastView(key: ValueKey(t.id), text: t.text),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 보드 아래 한 줄: 선택한 아이템 정보·판매 / 되돌리기 / 막힘 안내 / 도움말.
  Widget _infoBar() {
    final idx = _selected;
    final sel = idx == null ? null : game.board[idx];
    Widget child;
    if (idx != null && sel != null) {
      child = Row(
        children: [
          ArtImage(Art.item(sel.chain, sel.level), size: 26),
          const SizedBox(width: 6),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: IconText(
                tr('board.selected', {
                  'lv': sel.level,
                  'name': itemName(sel.def),
                  'v': fmt(GameConfig.incomeOf(sel.level)),
                }),
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ),
          FilledButton(
            style: plainButton(
              FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE07A5F),
                minimumSize: const Size(40, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
            onPressed: () {
              game.sell(idx);
              setState(() => _selected = null);
            },
            child: IconText(
              tr('board.sell', {'price': fmt(game.sellPrice(sel))}),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      );
    } else if (game.canUndoSell) {
      child = Center(
        child: TextButton(
          onPressed: game.undoSell,
          child: IconText(
            tr('board.undo'),
            style: const TextStyle(fontSize: 16),
          ),
        ),
      );
    } else {
      final stuck = game.boardStuck;
      child = Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: IconText(
            tr(stuck ? 'board.stuck' : 'board.hint'),
            style: TextStyle(
              fontSize: 14,
              color: stuck ? const Color(0xFFB0640A) : Colors.black45,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: child,
      ),
    );
  }

  Widget _controls() {
    final boostOpen = game.isUnlocked(Feature.boost);
    final bagOpen = game.isUnlocked(Feature.coinBag);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: _AdButton(
              label: boostOpen ? _adLabel(tr('ctrl.boost')) : tr('ctrl.boost'),
              sub: !boostOpen
                  ? tr('common.lockedLevel', {
                      'n': Leveling.unlockLevel[Feature.boost],
                    })
                  : '${game.boostActive ? tr('ctrl.boost.extend') : tr('ctrl.boost.duration')} · ${tr('ctrl.left', {'n': game.adsLeft(AdKind.boost)})}',
              onTap:
                  !boostOpen || (game.canAddBoost && widget.ads.rewardedReady)
                  ? _watchBoost
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          _Spawner(game: game, onTap: _onSpawnerTap),
          const SizedBox(width: 10),
          Expanded(
            child: _AdButton(
              label: bagOpen
                  ? _adLabel(tr('ctrl.coinBag'))
                  : tr('ctrl.coinBag'),
              sub: !bagOpen
                  ? tr('common.lockedLevel', {
                      'n': Leveling.unlockLevel[Feature.coinBag],
                    })
                  : !game.canWatchAd(AdKind.coinBag)
                  ? tr('ctrl.left', {'n': 0})
                  : game.coinBagReady
                  ? '[[coin]]${fmt(game.coinBagAmount)}'
                  : fmtDuration(game.coinBagCooldownLeft),
              onTap: !bagOpen || (game.coinBagReady && widget.ads.rewardedReady)
                  ? _watchCoinBag
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 작은 위젯들

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, required this.progress});
  final int level;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: CircularProgressIndicator(
              value: progress.clamp(0, 1),
              strokeWidth: 5,
              backgroundColor: Colors.white70,
              color: Palette.accent,
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Palette.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: IconText(
                  tr('hud.level', {'n': level}),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Spawner extends StatelessWidget {
  const _Spawner({required this.game, required this.onTap});
  final GameState game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final full = game.boardFull;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 70,
        height: 70,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 70,
              height: 70,
              child: CircularProgressIndicator(
                value: full
                    ? 1
                    : (game.spawnProgress / game.spawnInterval).clamp(0, 1),
                strokeWidth: 6,
                backgroundColor: Colors.white70,
                color: full ? Colors.redAccent : Palette.primary,
              ),
            ),
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ArtImage(Art.basket, size: 26),
                  IconText(
                    full ? tr('spawner.full') : '[[energy]]${game.energy}',
                    style: const TextStyle(fontSize: 11),
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

class _AdButton extends StatelessWidget {
  const _AdButton({
    required this.label,
    required this.sub,
    required this.onTap,
  });
  final String label;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: framedButton(
        FilledButton.styleFrom(
          backgroundColor: Palette.ad,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        ),
        'button_purple',
      ),
      onPressed: onTap,
      child: Column(
        children: [
          FittedBox(
            child: IconText(label, style: const TextStyle(fontSize: 15)),
          ),
          FittedBox(child: IconText(sub, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = false,
    this.small = false,
  });
  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool badge;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final w = small ? 46.0 : 50.0;
    final h = small ? 44.0 : 48.0;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: w,
            height: h,
            decoration: FrameBox.decorationFor(
              'tile',
              BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              corner: 14,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ArtImage(Art.icon(icon), size: small ? 20 : 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 11, color: Palette.text),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (badge)
            const Positioned(
              right: -3,
              top: -3,
              child: CircleAvatar(radius: 7, backgroundColor: Colors.redAccent),
            ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        shape: BoxShape.circle,
      ),
      child: ArtImage(Art.icon(label), size: 16),
    ),
  );
}

class _Toast {
  final int id;
  final String text;
  _Toast(this.id, this.text);
}

class _ToastView extends StatelessWidget {
  const _ToastView({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * -12),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: FrameBox.decorationFor(
          'toast',
          BoxDecoration(
            color: const Color(0xEE2F3B2F),
            borderRadius: BorderRadius.circular(14),
          ),
          corner: 16,
        ),
        child: IconText(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
    );
  }
}

/// 하단 적응형 배너.
class BannerSlot extends StatefulWidget {
  const BannerSlot({super.key});

  @override
  State<BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<BannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      _load();
    }
  }

  Future<void> _load() async {
    final width = MediaQuery.of(context).size.width.truncate();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;
    _ad = BannerAd(
      adUnitId: AdIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox(height: 50);
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
