import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';

import '../game/config.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../services/ad_ids.dart';
import '../services/ads_service.dart';
import '../services/billing_service.dart';
import 'board_view.dart';
import 'garden_scene.dart';
import 'orders_bar.dart';
import 'sheets.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.game,
    required this.ads,
    required this.billing,
  });
  final GameState game;
  final AdsService ads;
  final BillingService billing;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<GameEvent>? _sub;
  final List<_Toast> _toasts = [];
  int _toastId = 0;
  late int _viewArea;

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

  void _onEvent(GameEvent e) {
    switch (e) {
      case DiscoveryEvent(:final chain, :final level, :final bonus):
        final d = Chains.item(chain, level);
        _toast('${d.emoji} 새로운 ${d.name} 발견!  +🪙${fmt(bonus)}');
      case MaxMergeEvent(:final payout):
        _toast('✨ 최고 단계 수확! +🪙${fmt(payout)}');
      case OrderDeliveredEvent(
        :final friendId,
        :final stars,
        :final affectionUp,
      ):
        final f = Friends.byId(friendId);
        _toast('${f.emoji} 고마워!  ⭐+$stars${affectionUp ? '  💗호감도 UP' : ''}');
      case DecorPlacedEvent(:final area, :final slot):
        final d = Garden.areaAt(area).decor[slot];
        _toast('${d.emoji} ${d.name} 완성!');
        setState(() => _viewArea = area);
        widget.ads.maybeShowInterstitial();
      case FriendJoinedEvent(:final friendId):
        final f = Friends.byId(friendId);
        _toast('🎉 ${f.emoji} ${f.name}(이)가 놀러 왔어요!');
      case AreaCompletedEvent(:final area):
        _toast('🏆 ${Garden.areaAt(area).name} 완성! 새 구역이 열렸어요');
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _viewArea = game.currentArea);
        });
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

  Future<bool> _rewarded() async {
    final ok = await widget.ads.showRewarded();
    if (!ok) _toast('광고를 불러오는 중이에요. 잠시 후 다시 시도해 주세요.');
    return ok;
  }

  Future<void> _watchBoost() async {
    if (await _rewarded()) {
      game.grantBoost();
      _toast('⚡ 수익 2배! (${fmtDuration(game.boostRemaining)})');
    }
  }

  Future<void> _watchCoinBag() async {
    if (await _rewarded()) _toast('💰 +🪙${fmt(game.grantCoinBag())}');
  }

  Future<void> _refreshOrder(int i) async {
    if (await _rewarded()) game.refreshOrder(i);
  }

  void _onSlotTap(int slot) {
    if (game.canPlace(slot)) {
      game.placeDecor(slot);
    } else {
      final d = Garden.areaAt(game.currentArea).decor[slot];
      _toast(
        '${d.emoji} ${d.name}: ⭐${game.decorCost(slot)} 필요 (부탁을 들어주면 별을 받아요)',
      );
    }
  }

  Future<void> _onVisitorTap() async {
    final withAd = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '${Friends.visitorEmoji} 깜짝 손님!',
          textAlign: TextAlign.center,
        ),
        content: const Text(
          '지나가던 고슴도치가 선물을 두고 갔어요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('받기 🪙${fmt(game.visitorCoins(withAd: false))}'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.ad),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '${adFree ? '' : '📺 '}크게 받기 🪙${fmt(game.visitorCoins(withAd: true))} ⭐${GameConfig.visitorAdStars}',
            ),
          ),
        ],
      ),
    );
    if (withAd == null) return;
    final ok = withAd ? await widget.ads.showRewarded() : false;
    final r = game.claimVisitor(withAd: ok);
    if (r != null) {
      _toast('🎁 +🪙${fmt(r.coins)}${r.stars > 0 ? '  ⭐+${r.stars}' : ''}');
    }
  }

  @override
  Widget build(BuildContext context) {
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
            listenable: Listenable.merge([game, widget.ads, widget.billing]),
            builder: (context, _) => Column(
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
                  child: BoardView(game: game),
                ),
                _controls(),
                if (!adFree) const BannerSlot(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(
                        '🪙 ${fmt(game.coins)}',
                        style: const TextStyle(fontSize: 23),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '⭐ ${game.stars}',
                        style: const TextStyle(fontSize: 23),
                      ),
                    ],
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(
                        '초당 ${fmt(game.incomePerSec)}',
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
                          child: Text(
                            '⚡x2 ${fmtDuration(game.boostRemaining)}',
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
              icon: '🚫',
              label: '광고제거',
              onTap: () => showShopSheet(context, widget.billing),
            ),
            const SizedBox(width: 5),
          ],
          _MenuButton(
            icon: '📖',
            label: '도감',
            onTap: () => showCollectionSheet(context, game),
          ),
          const SizedBox(width: 5),
          _MenuButton(
            icon: '⬆️',
            label: '강화',
            badge: Upgrades.all.any((u) => game.canBuyUpgrade(u.type)),
            onTap: () => showUpgradesSheet(context, game),
          ),
          const SizedBox(width: 5),
          _MenuButton(
            icon: '🔨',
            label: '꾸미기',
            badge: List.generate(
              Garden.slotsPerArea,
              game.canPlace,
            ).any((x) => x),
            onTap: () {
              setState(() => _viewArea = game.currentArea);
              showDecorSheet(context, game);
            },
          ),
        ],
      ),
    );
  }

  Widget _sceneArea() {
    final area = Garden.areaAt(_viewArea);
    return Stack(
      children: [
        Positioned.fill(
          child: GardenScene(
            game: game,
            area: _viewArea,
            onSlotTap: _onSlotTap,
            onVisitorTap: _onVisitorTap,
          ),
        ),
        // 구역 이름, 이동
        Positioned(
          left: 6,
          top: 6,
          child: Row(
            children: [
              if (_viewArea > 0)
                _RoundButton(
                  label: '◀',
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
                child: Text(
                  '${area.emoji} ${area.name}${_viewArea == game.currentArea ? '  ${game.placed.length}/${Garden.slotsPerArea}' : ' ✅'}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              if (_viewArea < game.currentArea)
                _RoundButton(
                  label: '▶',
                  onTap: () => setState(() => _viewArea++),
                ),
            ],
          ),
        ),
        // 알림
        Positioned(
          left: 10,
          right: 10,
          top: 44,
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

  Widget _controls() {
    final adLabel = adFree ? '' : '📺 ';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: _AdButton(
              label: '$adLabel수익 2배',
              sub: game.boostActive ? '+10분 연장' : '10분',
              onTap: game.canAddBoost && widget.ads.rewardedReady
                  ? _watchBoost
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          _Spawner(game: game),
          const SizedBox(width: 10),
          Expanded(
            child: _AdButton(
              label: '$adLabel코인 주머니',
              sub: game.coinBagReady
                  ? '🪙${fmt(game.coinBagAmount)}'
                  : fmtDuration(game.coinBagCooldownLeft),
              onTap: game.coinBagReady && widget.ads.rewardedReady
                  ? _watchCoinBag
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Spawner extends StatelessWidget {
  const _Spawner({required this.game});
  final GameState game;

  @override
  Widget build(BuildContext context) {
    final full = game.boardFull;
    return GestureDetector(
      onTap: game.tapSpawner,
      child: SizedBox(
        width: 72,
        height: 72,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 72,
              height: 72,
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
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🧺', style: TextStyle(fontSize: 24)),
                  Text(
                    full ? '가득!' : '톡톡',
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
      style: FilledButton.styleFrom(
        backgroundColor: Palette.ad,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      ),
      onPressed: onTap,
      child: Column(
        children: [
          FittedBox(child: Text(label, style: const TextStyle(fontSize: 15))),
          FittedBox(child: Text(sub, style: const TextStyle(fontSize: 13))),
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
  });
  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 50,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(icon, style: const TextStyle(fontSize: 19)),
                FittedBox(
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 11, color: Palette.text),
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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          shape: BoxShape.circle,
        ),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
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
        decoration: BoxDecoration(
          color: const Color(0xEE2F3B2F),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
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
