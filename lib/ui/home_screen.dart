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
import 'sheets.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.game, required this.ads, required this.billing});
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

  GameState get game => widget.game;

  @override
  void initState() {
    super.initState();
    _sub = game.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(GameEvent e) {
    switch (e) {
      case DiscoveryEvent(:final level, :final bonus):
        final d = GameConfig.item(level);
        _toast('${d.emoji} 새 꽃 발견! ${d.name}  +🪙${fmt(bonus)}');
      case MaxMergeEvent(:final payout):
        _toast('✨ 황금 수확! +🪙${fmt(payout)}');
      case GardenTaskEvent(:final areaCompleted, :final areaIndex):
        if (areaCompleted) {
          _toast('🎉 ${Garden.areaAt(areaIndex).name} 완성! 수익 보너스 UP');
        }
        widget.ads.maybeShowInterstitial();
      case MergeEvent():
        break;
    }
  }

  void _toast(String msg) {
    final t = _Toast(_toastId++, msg);
    setState(() => _toasts.add(t));
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _toasts.remove(t));
    });
  }

  Future<void> _watchBoost() async {
    if (await widget.ads.showRewarded()) {
      game.grantBoost();
      _toast('⚡ 수익 2배! (${fmtDuration(game.boostRemaining)})');
    } else {
      _toast('광고를 불러오는 중이에요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> _watchCoinBag() async {
    if (await widget.ads.showRewarded()) {
      final v = game.grantCoinBag();
      _toast('💰 +🪙${fmt(v)}');
    } else {
      _toast('광고를 불러오는 중이에요. 잠시 후 다시 시도해 주세요.');
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
            builder: (context, _) => Stack(
              children: [
                Column(
                  children: [
                    _topBar(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Center(child: BoardView(game: game)),
                      ),
                    ),
                    _controls(),
                    if (!widget.billing.adFree) const BannerSlot(),
                  ],
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 90,
                  child: IgnorePointer(
                    child: Column(children: [for (final t in _toasts) _ToastView(key: ValueKey(t.id), text: t.text)]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🪙 ${fmt(game.coins)}',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Palette.text)),
                Row(
                  children: [
                    Text('초당 ${fmt(game.incomePerSec)}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    if (game.boostActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Palette.ad, borderRadius: BorderRadius.circular(10)),
                        child: Text('⚡x2 ${fmtDuration(game.boostRemaining)}',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (!widget.billing.adFree)
            IconButton(
              tooltip: '광고 제거',
              onPressed: () => showShopSheet(context, widget.billing),
              icon: const Text('🚫📺', style: TextStyle(fontSize: 22)),
            ),
        ],
      ),
    );
  }

  Widget _controls() {
    final adLabel = widget.billing.adFree ? '' : '📺 ';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _AdButton(
                  label: '$adLabel수익 2배',
                  sub: game.boostActive ? '+10분 연장' : '10분',
                  onTap: game.canAddBoost && widget.ads.rewardedReady ? _watchBoost : null,
                ),
              ),
              const SizedBox(width: 10),
              _Spawner(game: game),
              const SizedBox(width: 10),
              Expanded(
                child: _AdButton(
                  label: '$adLabel코인 주머니',
                  sub: game.coinBagReady ? '🪙${fmt(game.coinBagAmount)}' : fmtDuration(game.coinBagCooldownLeft),
                  onTap: game.coinBagReady && widget.ads.rewardedReady ? _watchCoinBag : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _BigButton(
                  label: '🌳 정원 꾸미기',
                  badge: game.canBuyGardenTask,
                  onTap: () => showGardenSheet(context, game),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BigButton(
                  label: '⬆️ 강화',
                  badge: Upgrades.all.any((u) => game.canBuyUpgrade(u.type)),
                  onTap: () => showUpgradesSheet(context, game),
                ),
              ),
            ],
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
        width: 84,
        height: 84,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 84,
              height: 84,
              child: CircularProgressIndicator(
                value: full ? 1 : (game.spawnProgress / game.spawnInterval).clamp(0, 1),
                strokeWidth: 7,
                backgroundColor: Colors.white70,
                color: full ? Colors.redAccent : Palette.primary,
              ),
            ),
            Container(
              width: 66,
              height: 66,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🧺', style: TextStyle(fontSize: 28)),
                  Text(full ? '가득!' : '톡톡', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
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
  const _AdButton({required this.label, required this.sub, required this.onTap});
  final String label;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.ad,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      ),
      onPressed: onTap,
      child: Column(
        children: [
          FittedBox(child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          FittedBox(child: Text(sub, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.label, required this.onTap, this.badge = false});
  final String label;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.primary),
            onPressed: onTap,
            child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
        ),
        if (badge)
          const Positioned(
            right: -2,
            top: -4,
            child: CircleAvatar(radius: 9, backgroundColor: Colors.redAccent),
          ),
      ],
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
      builder: (_, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * -12), child: child)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xEE2F3B2F), borderRadius: BorderRadius.circular(14)),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ad == null) _load();
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
        onAdLoaded: (_) => setState(() => _loaded = true),
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
    return SizedBox(width: ad.size.width.toDouble(), height: ad.size.height.toDouble(), child: AdWidget(ad: ad));
  }
}
