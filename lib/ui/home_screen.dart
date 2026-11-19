import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../i18n/names.dart';
import '../services/ads_service.dart';
import '../services/audio_service.dart';
import '../services/billing_service.dart';
import 'board/board_view.dart';
import 'garden/garden_scene.dart';
import 'garden/garden_screen.dart';
import 'orders_bar.dart';
import 'sheets.dart';
import 'theme.dart';
import 'tutorial.dart';
import 'widgets/icon_text.dart';
import 'widgets/frame_box.dart';

/// 메인 화면. 배치(위→아래): HUD / 정원 창(남는 높이 전부) / 정원 도구줄 / 부탁 / 머지 보드 / 정보 줄 / 광고·바구니.
/// 배너 광고는 두지 않는다 (보상형 · 전면만).
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
    _loadTutorial();
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
        sfx(Sfx.coin);
        final d = Chains.item(chain, level);
        _toast(
          tr('toast.discovery', {
            'emoji': itemToken(d.chain, d.level),
            'name': itemName(d),
            'coins': fmt(bonus),
          }),
        );
      case MaxMergeEvent(:final payout):
        sfx(Sfx.mergeBig);
        _toast(tr('toast.maxMerge', {'coins': fmt(payout)}));
      case OrderDeliveredEvent(
        :final friendId,
        :final stars,
        :final affectionUp,
      ):
        sfx(Sfx.deliver);
        _tutorialEvent(e);
        _toast(
          tr('toast.thanks', {'emoji': friendToken(friendId), 'stars': stars}) +
              (affectionUp ? tr('toast.affectionUp') : ''),
        );
      case DecorPlacedEvent(:final area, :final slot):
        sfx(Sfx.place);
        _tutorialEvent(e);
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
        sfx(Sfx.levelup);
        _levelUps.add(e);
        _showLevelUps();
      case BubbleEvent():
        sfx(Sfx.bubble);
        _toast(tr('toast.bubble'));
      case SoldEvent(:final price):
        sfx(Sfx.sell);
        _toast(tr('toast.sold', {'coins': fmt(price)}));
      case MergedEvent(:final level):
        sfx(level >= 6 ? Sfx.mergeBig : Sfx.merge);
        _tutorialEvent(e);
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
        banner: 'gold',
        emblem: 'levelup_burst',
        emblemText: '${e.level}',
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
              for (final f in e.unlocked) ...[
                IconText(featureName(f), style: const TextStyle(fontSize: 19)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: IconText(
                    tr('feature.${f.name}.desc'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Colors.black54,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
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
    switch (game.tapSpawner()) {
      case TapResult.noEnergy:
        sfx(Sfx.error);
        await _energyDialog();
      case TapResult.boardFull:
        sfx(Sfx.error);
        _toast(tr('toast.boardFull'));
      default:
        sfx(Sfx.spawn);
    }
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
    if (await _rewardedCapped(AdKind.coinBag)) {
      sfx(Sfx.coin);
      _toast(tr('toast.coins', {'coins': fmt(game.grantCoinBag())}));
    }
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
    if (ok == true && game.buyCell(cell)) sfx(Sfx.unlock);
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

  // 튜토리얼이 가리키는 위치
  final _kSpawner = GlobalKey();
  final _kBoard = GlobalKey();
  final _kOrders = GlobalKey();
  final _kDecor = GlobalKey();
  final _kGarden = GlobalKey();
  final _kStack = GlobalKey();

  // ---------------------------------------------------------------- 튜토리얼
  // 0 인사 → 1 바구니 3번 → 2 합치기 → 3 부탁 → 4 꾸미기 → 5 정원 · 방치 수익 → 끝(99)
  static const _tutPref = 'tutorial_v1';
  static const _tutDone = 99;
  int _tut = _tutDone;

  Future<void> _loadTutorial() async {
    final p = await SharedPreferences.getInstance();
    var step = p.getInt(_tutPref) ?? 0;
    // 이미 한참 진행한 플레이어에게는 다시 보여 주지 않는다
    if (step == 0 && (game.level >= 3 || game.totalMerges > 20))
      step = _tutDone;
    if (mounted) setState(() => _tut = step);
    // 레이아웃이 끝난 뒤 위치를 다시 잰다
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _setTutorial(int step) async {
    setState(() => _tut = step);
    (await SharedPreferences.getInstance()).setInt(_tutPref, step);
  }

  void _tutorialEvent(GameEvent e) {
    if (_tut == 2 && e is MergedEvent) _setTutorial(3);
    if (_tut == 3 && e is OrderDeliveredEvent) _setTutorial(4);
  }

  Rect? _rectOf(GlobalKey k) {
    final box = k.currentContext?.findRenderObject() as RenderBox?;
    final stack = _kStack.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stack == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
  }

  Widget? get _tutorial {
    if (_tut == _tutDone) return null;
    // 1단계: 판에 아이템이 3개 이상이면 다음으로
    if (_tut == 1 && game.board.whereType<Item>().length >= 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tut == 1) _setTutorial(2);
      });
    }
    void next() {
      sfx(Sfx.tap);
      _setTutorial(_tut >= 5 ? _tutDone : _tut + 1);
    }

    final skip = _tut == 0 ? () => _setTutorial(_tutDone) : null;
    return switch (_tut) {
      0 => CoachOverlay(
        text: tr('tut.hello'),
        buttonLabel: tr('tut.next'),
        onNext: next,
        onSkip: skip,
        skipLabel: tr('tut.skip'),
      ),
      1 => CoachOverlay(
        text: tr('tut.spawner', {'n': GameConfig.energyPerTap}),
        hole: _rectOf(_kSpawner),
        action: true,
      ),
      2 => CoachOverlay(
        text: tr('tut.merge'),
        hole: _rectOf(_kBoard),
        action: true,
      ),
      3 => CoachOverlay(
        text: tr('tut.orders'),
        hole: _rectOf(_kOrders),
        action: true,
        buttonLabel: tr('tut.next'),
        onNext: next,
      ),
      4 => CoachOverlay(
        text: tr('tut.decor'),
        hole: _rectOf(_kDecor),
        buttonLabel: tr('tut.next'),
        onNext: next,
      ),
      _ => CoachOverlay(
        text: tr('tut.garden'),
        hole: _rectOf(_kGarden),
        buttonLabel: tr('tut.done'),
        onNext: next,
      ),
    };
  }

  // 고정 높이 (dp). 남는 높이는 모두 정원 창이 가진다.
  static const double _hudH = 56;
  static const double _toolbarH = 54;
  static const double _ordersH = 70;
  static const double _infoH = 42;
  static const double _controlsH = 78;
  static const double _gardenMinH = 150;

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
              return LayoutBuilder(
                builder: (context, c) {
                  // 보드는 폭에 맞추되, 정원 창이 최소 높이를 갖도록 필요하면 줄인다.
                  const fixed =
                      _hudH + _toolbarH + _ordersH + _infoH + _controlsH + 16;
                  final maxBoardH = max(
                    220.0,
                    c.maxHeight - fixed - _gardenMinH,
                  );
                  final boardW = min(c.maxWidth - 20, maxBoardH * 6 / 5);
                  return Stack(
                    key: _kStack,
                    children: [
                      Column(
                        children: [
                          SizedBox(height: _hudH, child: _topBar()),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: _gardenWindow(),
                            ),
                          ),
                          SizedBox(height: _toolbarH, child: _gardenToolbar()),
                          SizedBox(
                            key: _kOrders,
                            height: _ordersH,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: OrdersBar(
                                game: game,
                                onRefresh: _refreshOrder,
                                adFree: adFree,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            key: _kBoard,
                            width: boardW,
                            child: BoardView(
                              game: game,
                              selected: _selected,
                              onSelect: (c) => setState(() => _selected = c),
                              onLockedTap: _onLockedCell,
                              onBubbleTap: _onBubble,
                            ),
                          ),
                          SizedBox(height: _infoH, child: _infoBar()),
                          SizedBox(height: _controlsH, child: _controls()),
                        ],
                      ),
                      // 알림: 모든 것 위 (HUD 바로 아래). 터치는 통과.
                      Positioned(
                        left: 16,
                        right: 16,
                        top: _hudH + 6,
                        child: IgnorePointer(
                          child: Column(
                            children: [
                              for (final t in _toasts)
                                _ToastView(key: ValueKey(t.id), text: t.text),
                            ],
                          ),
                        ),
                      ),
                      ?_tutorial,
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// 상단 HUD: 레벨 · 코인 · 별 · 에너지 (각각 캡슐) + 광고 제거 · 설정.
  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      child: Row(
        children: [
          _LevelBadge(level: game.level, progress: game.xp / game.xpToNext),
          const SizedBox(width: 6),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  _Pill(
                    icon: Art.coin,
                    text: fmt(game.coins),
                    sub: tr('hud.perHour', {'v': fmt(game.incomePerHour)}),
                  ),
                  const SizedBox(width: 6),
                  _Pill(icon: Art.star, text: '${game.stars}'),
                  const SizedBox(width: 6),
                  _Pill(
                    icon: Art.icon('energy'),
                    text: '${game.energy}/${GameConfig.energyCap}',
                    warn: game.energy == 0,
                    plus: true,
                    sub: game.energy >= GameConfig.energyCap
                        ? null
                        : fmtDuration(game.energyNextIn),
                    onTap: _energyDialog,
                  ),
                  if (game.boostActive) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Palette.ad,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconText(
                        tr('hud.boost', {
                          'time': fmtDuration(game.boostRemaining),
                        }),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (!adFree) ...[
            _IconButton(
              icon: 'no_ads',
              onTap: () {
                sfx(Sfx.open);
                showShopSheet(context, widget.billing);
              },
            ),
            const SizedBox(width: 6),
          ],
          _IconButton(
            icon: 'settings',
            onTap: () {
              sfx(Sfx.open);
              widget.openSettings(context);
            },
          ),
        ],
      ),
    );
  }

  /// 정원 창: 씬만 담는다 (메뉴 버튼은 아래 도구줄로 옮겨 장식 · 친구를 가리지 않는다).
  Widget _gardenWindow() {
    return Container(
      key: _kGarden,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF7A5230), width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: GardenScene(
        game: game,
        area: _viewArea,
        radius: 19,
        focusY: 1.0, // 넘치는 높이는 하늘에서 자른다 (땅 위 장식 자리가 잘리지 않게)
        markerScale: 0.95,
        onSlotTap: _onSlotTap,
        onVisitorTap: _onVisitorTap,
        overlay: [
          // 구역 이동 (이전 구역 보기)
          if (_viewArea > 0)
            Positioned(
              left: 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: _RoundButton(
                  label: 'arrow_left',
                  onTap: () => setState(() => _viewArea--),
                ),
              ),
            ),
          if (_viewArea < game.currentArea)
            Positioned(
              right: 6,
              top: 0,
              bottom: 0,
              child: Center(
                child: _RoundButton(
                  label: 'arrow_right',
                  onTap: () => setState(() => _viewArea++),
                ),
              ),
            ),
          // 크게 보기
          Positioned(
            right: 8,
            top: 8,
            child: _RoundButton(
              label: 'expand',
              icon: Icons.open_in_full_rounded,
              onTap: _openGarden,
            ),
          ),
        ],
      ),
    );
  }

  /// 정원 아래 도구줄: 구역 진행도 + 꾸미기 · 강화 · 도감 · 보관함.
  Widget _gardenToolbar() {
    final canDecorate = List.generate(
      Garden.slotsPerArea,
      game.canPlace,
    ).any((x) => x);
    final a = Garden.areaAt(_viewArea);
    final done = _viewArea < game.currentArea
        ? Garden.slotsPerArea
        : game.placed.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _openGarden,
              child: FrameBox(
                frame: 'capsule',
                fallback: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                corner: 14,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                child: Row(
                  children: [
                    ArtImage(Art.areaIcon(a), size: 26),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: IconText(
                              game.areaLocked && _viewArea == game.currentArea
                                  ? '${areaName(a)}  ${tr('common.lockedLevel', {'n': game.areaRequiredLevel})}'
                                  : '${areaName(a)}  $done/${Garden.slotsPerArea}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          const SizedBox(height: 3),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: done / Garden.slotsPerArea,
                              minHeight: 5,
                              backgroundColor: const Color(0xFFE8E0CC),
                              color: Palette.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _MenuButton(
            key: _kDecor,
            icon: 'decorate',
            label: tr('menu.decorate'),
            badge: canDecorate,
            onTap: () {
              sfx(Sfx.open);
              setState(() => _viewArea = game.currentArea);
              showDecorSheet(context, game);
            },
          ),
          const SizedBox(width: 5),
          _MenuButton(
            icon: game.isUnlocked(Feature.upgrades) ? 'upgrade' : 'lock',
            label: tr('menu.upgrade'),
            badge: Upgrades.all.any((u) => game.canBuyUpgrade(u.type)),
            onTap: () {
              if (_gate(Feature.upgrades)) {
                sfx(Sfx.open);
                showUpgradesSheet(context, game);
              }
            },
          ),
          const SizedBox(width: 5),
          _MenuButton(
            icon: 'book',
            label: tr('menu.book'),
            onTap: () {
              sfx(Sfx.open);
              showCollectionSheet(context, game);
            },
          ),
          const SizedBox(width: 5),
          _MenuButton(
            icon: game.storageOpen ? 'storage' : 'lock',
            label: tr('menu.storage'),
            onTap: () {
              if (_gate(Feature.storage)) _openStorage();
            },
          ),
        ],
      ),
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
                  'v': fmt(GameConfig.incomeOf(sel.level) * 3600),
                }),
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ),
          if (game.storageOpen) ...[
            FilledButton(
              style: plainButton(
                FilledButton.styleFrom(
                  backgroundColor: Palette.primary,
                  minimumSize: const Size(40, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
              onPressed: () {
                if (game.store(idx)) {
                  setState(() => _selected = null);
                } else {
                  _toast(tr('storage.full'));
                  _openStorage();
                }
              },
              child: IconText(
                tr('board.store'),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 6),
          ],
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
    } else {
      final Widget message;
      if (game.canUndoSell) {
        message = Center(
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
        message = Center(
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
      child = !game.storageOpen
          ? message
          : Row(
              children: [
                FilledButton(
                  style: framedButton(
                    FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Palette.text,
                      minimumSize: const Size(40, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    'button_white',
                  ),
                  onPressed: _openStorage,
                  child: IconText(
                    tr('board.storeOpen', {
                      'used': game.storageUsed,
                      'max': game.storage.length,
                    }),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(child: message),
              ],
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

  void _openGarden() {
    sfx(Sfx.open);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GardenScreen(
          game: game,
          area: _viewArea,
          onVisitorTap: _onVisitorTap,
        ),
      ),
    );
  }

  void _openStorage() => showStorageSheet(context, game, onMessage: _toast);

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
          _Spawner(key: _kSpawner, game: game, onTap: _onSpawnerTap),
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
  const _Spawner({super.key, required this.game, required this.onTap});
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
                // 에너지 회복 진행 (가득이면 꽉 찬 고리)
                value: full || game.energy >= GameConfig.energyCap
                    ? 1
                    : (game.energyProgress / game.energyRegenSeconds).clamp(
                        0,
                        1,
                      ),
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
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = false,
  });
  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    const w = 52.0;
    const h = 46.0;
    return GestureDetector(
      onTap: () {
        sfx(Sfx.tap);
        onTap();
      },
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
                ArtImage(Art.icon(icon), size: 22),
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
  const _RoundButton({required this.label, required this.onTap, this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      sfx(Sfx.tap);
      onTap();
    },
    child: Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF7A5230), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: icon != null
          ? Icon(icon, size: 20, color: const Color(0xFF7A5230))
          : ArtImage(Art.icon(label), size: 20),
    ),
  );
}

/// HUD 자원 캡슐: 아이콘 + 값 (+ 작은 보조 줄, + 버튼).
class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.text,
    this.sub,
    this.plus = false,
    this.warn = false,
    this.onTap,
  });
  final ArtRef icon;
  final String text;
  final String? sub;
  final bool plus;
  final bool warn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF7A5230), width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArtImage(icon, size: 28),
            const SizedBox(width: 3),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: sub == null ? 19 : 17,
                    height: 1.05,
                    color: warn ? const Color(0xFFB0640A) : Palette.text,
                  ),
                ),
                if (sub != null)
                  IconText(
                    sub!,
                    style: const TextStyle(
                      fontSize: 10.5,
                      height: 1.0,
                      color: Colors.black54,
                    ),
                  ),
              ],
            ),
            if (plus) ...[
              const SizedBox(width: 4),
              Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Palette.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// HUD 오른쪽 둥근 아이콘 버튼.
class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});
  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: FrameBox.decorationFor(
        'tile',
        BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF7A5230), width: 2),
        ),
        corner: 14,
      ),
      child: ArtImage(Art.icon(icon), size: 26),
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
