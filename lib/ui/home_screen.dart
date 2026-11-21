import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart' show SystemUiOverlayStyle;
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
import 'meta_ui.dart';
import 'sheets.dart';
import 'theme.dart';
import 'tutorial.dart';
import '../game/tuning.dart';
import '../services/analytics_service.dart';
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
    this.openFriends,
    this.socialBadge = _noBadge,
  });

  static bool _noBadge() => false;

  /// 친구(소셜) 화면 열기. 소셜 기능이 없으면 null (메뉴에서 숨김).
  final void Function(BuildContext context)? openFriends;

  /// 친구 쪽에 확인할 것이 있는지 (받을 선물 등) → 메뉴 빨간 점.
  final bool Function() socialBadge;
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

  /// 광고 없이 보상: 구독 또는 기간제 정원 패스 (새싹 정원 패키지).
  bool get adFree => widget.billing.adFree || game.passActive;

  @override
  void initState() {
    super.initState();
    _viewArea = game.currentArea;
    _sub = game.events.listen(_onEvent);
    game.addListener(_checkNewTips);
    _loadTutorial();
  }

  @override
  void dispose() {
    game.removeListener(_checkNewTips);
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
        final done = game.quotaActive && game.starOrdersLeft(friendId) == 0;
        _toast(
          (stars > 0
                  ? tr('toast.thanks', {
                      'emoji': friendToken(friendId),
                      'stars': stars,
                    })
                  : tr('toast.thanksCoins', {'emoji': friendToken(friendId)})) +
              (affectionUp ? tr('toast.affectionUp') : '') +
              (done && stars > 0
                  ? tr('toast.quotaDone', {'name': friendName(friendId)})
                  : ''),
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
      case SeasonSetEvent(:final area, :final style):
        sfx(Sfx.levelup);
        _toast(
          tr('toast.seasonSet', {
            'area': areaName(Garden.areaAt(area)),
            'season': tr('style.$style'),
            'n': (Garden.seasonSetBonus * 100).round(),
          }),
        );
        setState(() => _viewArea = area);
      case AreaCompletedEvent(:final area):
        _toast(tr('toast.areaDone', {'name': areaName(Garden.areaAt(area))}));
        // 첫 구역 완성 직후: 새싹 정원 패키지 (한 번만)
        if (area == 0) {
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && game.showStarterOffer()) {
              showStarterSheet(context, widget.billing, game);
            }
          });
        }
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
      case EnergyEmptyEvent() || AdRewardEvent():
        break; // 지표용 (Analytics)
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
            if (e.unlocked.any((f) => f != Feature.storage)) ...[
              const SizedBox(height: 14),
              IconText(
                tr('levelUp.unlocked'),
                style: const TextStyle(fontSize: 15, color: Colors.black54),
              ),
              const SizedBox(height: 6),
              for (final f in e.unlocked.where(
                (f) => f != Feature.storage,
              )) ...[
                // 실제 화면의 그 버튼 모양 그대로 보여 준다
                IgnorePointer(child: _featurePreview(f)),
                const SizedBox(height: 6),
                IconText(
                  tr('feature.${f.name}.desc'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF5A4A36),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
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
    // 새로 열린 기능은 실제 위치를 손으로 가리켜 안내한다
    _queueFeatureTips(e.unlocked);
    _showLevelUps();
  }

  /// 레벨업 팝업 안에 보여 줄 기능 미리보기: 실제 화면의 버튼 · 칩과 같은 위젯.
  Widget _featurePreview(Feature f) {
    Widget chip(String icon, String label) => Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7A5230), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ArtImage(Art.icon(icon), size: 30),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
    final w = switch (f) {
      Feature.boost => SizedBox(
        width: 84,
        child: _BarTile(
          icon: Art.icon('boost').available ? 'boost' : 'coinbag',
          label: tr('ctrl.boost'),
          ad: true,
          onTap: () {},
        ),
      ),
      Feature.coinBag => SizedBox(
        width: 84,
        child: _BarTile(
          icon: 'coinbag',
          label: '[[coin]]${fmt(game.coinBagAmount)}',
          ad: true,
          onTap: () {},
        ),
      ),
      Feature.energyAd => _Pill(
        icon: Art.icon('energy'),
        text: '${game.energy}/${GameConfig.energyCap}',
        plus: true,
      ),
      Feature.upgrades => SizedBox(
        width: 84,
        child: _BarTile(
          icon: 'upgrade',
          label: tr('menu.upgrade'),
          onTap: () {},
        ),
      ),
      Feature.storage => const SizedBox.shrink(),
      Feature.snack => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ArtImage(Art.basket, size: 44),
          const Icon(Icons.arrow_forward_rounded, color: Color(0xFF7A5230)),
          ArtImage(Art.item(Chain.snack, 1), size: 44),
        ],
      ),
      Feature.visitor => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ArtImage(Art.visitor(), size: 60),
          ArtImage(Art.gift, size: 36),
        ],
      ),
      Feature.autoMerge => chip('auto', upgradeTitle(UpgradeType.autoMerge)),
      Feature.offlineCap => chip('moon', upgradeTitle(UpgradeType.offlineCap)),
      Feature.spawnLevel => chip(
        'quality',
        upgradeTitle(UpgradeType.spawnLevel),
      ),
    };
    return w;
  }

  // ---------------------------------------------------------------- 새 기능 안내 (처음 한 번)
  // 레벨로 열리는 기능(Feature) + 조건으로 열리는 기능(다이아 · 출석 · 시장 · 디자인 · 바구니 · 옷장 · 친구).
  static const _tipsPref = 'feature_tips_seen';
  final List<String> _tips = [];
  Set<String>? _tipsSeen;

  // 보관함은 판 맨 아랫줄 보관 칸으로 합쳐져 안내하지 않는다 (D-017)
  Future<void> _queueFeatureTips(List<Feature> fs) => _queueTips([
    for (final f in fs)
      if (f != Feature.storage) f.name,
  ]);

  /// 안내 순서 (게임 진행 순서): 줄은 늘 이 순서로 정렬한다.
  static const List<String> _tipOrder = [
    'energyAd',
    'upgrades',
    'gems',
    'boost',
    'snack',
    'checkIn',
    'coinBag',
    'market',
    'friends',
    'autoMerge',
    'visitor',
    'offlineCap',
    'design',
    'spawnLevel',
    'basket',
    'wardrobe',
  ];

  Future<Set<String>> _seenTips() async => _tipsSeen ??= {
    ...?(await SharedPreferences.getInstance()).getStringList(_tipsPref),
  };

  Future<void> _queueTips(List<String> ids) async {
    final seen = await _seenTips();
    final add = [
      for (final id in ids)
        if (!seen.contains(id) && !_tips.contains(id)) id,
    ];
    if (add.isEmpty || !mounted) return;
    setState(() {
      _tips.addAll(add);
      int rank(String id) {
        final i = _tipOrder.indexOf(id);
        return i < 0 ? 999 : i;
      }

      _tips.sort((x, y) => rank(x).compareTo(rank(y)));
    });
  }

  /// 지금 조건이 맞는 안내들.
  List<String> get _tipsNow => [
    for (final f in Feature.values)
      if (game.isUnlocked(f)) f.name,
    if (game.level >= 2) 'gems',
    if (game.level >= 3) 'checkIn',
    if (game.dailyShopOpen) 'market',
    if (game.openBaskets.length > 1) 'basket',
    if (_hasDesignChoice) 'design',
    if (_hasWardrobe) 'wardrobe',
    if (widget.openFriends != null && game.level >= 5) 'friends',
  ];

  /// 처음 한 번: 이미 쓸 수 있던 기능은 '본 것'으로 친다.
  /// 안내는 기능이 **새로 열리는 순간**에만 나온다 (껐다 켤 때마다 예전 기능을 하나씩 소개하지 않게).
  Future<void> _baselineTips() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('feature_tips_base_v2') ?? false) return;
    final seen = await _seenTips();
    if (_tut == _tutDone) seen.addAll(_tipsNow);
    await p.setStringList(_tipsPref, seen.toList());
    await p.setBool('feature_tips_base_v2', true);
  }

  bool _tipsReady = false;

  /// 게임이 바뀔 때마다: 방금 조건이 맞은 새 기능 안내를 줄에 넣는다 (한 번 본 것은 다시 안 나온다).
  void _checkNewTips() {
    if (_tut != _tutDone || !_tipsReady) return;
    final want = _tipsNow;
    final seen = _tipsSeen;
    if (seen != null &&
        want.every((w) => seen.contains(w) || _tips.contains(w))) {
      return;
    }
    _queueTips(want);
  }

  bool get _hasDesignChoice {
    for (var a = 0; a <= game.currentArea; a++) {
      final area = Garden.areaAt(a);
      for (var i = 0; i < area.decor.length; i++) {
        if (game.isPlaced(a, i) && Art.decorStyles(area.decor[i]).length > 1) {
          return true;
        }
      }
    }
    return false;
  }

  bool get _hasWardrobe => [
    for (final f in Friends.all)
      if (game.friends.contains(f.id)) f,
  ].any((f) => Art.outfitsFor(f).isNotEmpty);

  /// 화면이 막 돌아온 직후(다른 화면 · 창을 닫은 뒤)에는 잠깐 기다렸다가 안내한다.
  DateTime _quietUntil = DateTime(2000);
  bool _wasCurrent = true;

  Future<void> _doneTip() async {
    if (_tips.isEmpty) return;
    final id = _tips.removeAt(0);
    // 다음 안내는 조금 쉬었다가 (연달아 뜨지 않게)
    _quietUntil = DateTime.now().add(const Duration(seconds: 4));
    Future.delayed(const Duration(seconds: 4, milliseconds: 100), () {
      if (mounted) setState(() {});
    });
    setState(() {});
    final p = await SharedPreferences.getInstance();
    (_tipsSeen ??= {...?p.getStringList(_tipsPref)}).add(id);
    p.setStringList(_tipsPref, _tipsSeen!.toList());
  }

  GlobalKey _tipTarget(String id) => switch (id) {
    'energyAd' => _kSpawner,
    'boost' => _kBoost,
    'snack' || 'basket' => _kSpawner,
    'visitor' => _kGarden,
    'gems' || 'market' => _kGems,
    'checkIn' || 'friends' => _kMenu,
    'design' => _kDecor,
    'coinBag' when game.coinBagReady => _kCoinBag,
    _ => _kMenu,
  };

  String _tipTitle(String id) {
    for (final f in Feature.values) {
      if (f.name == id) return featureName(f);
    }
    return tr('tipTitle.$id');
  }

  Widget? get _featureTip {
    if (_tut != _tutDone || _tips.isEmpty || _levelDialogOpen) return null;
    // 홈 화면이 맨 앞일 때만 (정원 · 시트 · 창이 열려 있으면 기다린다)
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current && !_wasCurrent) {
      _quietUntil = DateTime.now().add(const Duration(milliseconds: 1500));
      Future.delayed(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() {});
      });
    }
    _wasCurrent = current;
    if (!current || DateTime.now().isBefore(_quietUntil)) return null;
    final id = _tips.first;
    final r = _rectOf(_tipTarget(id));
    // 바구니 넘기기는 손장갑이 옆으로 밀어 보인다
    final swipe = id == 'basket' && r != null;
    return CoachOverlay(
      title: _tipTitle(id),
      text: tr('tip.$id'),
      hole: r,
      pointAt: swipe ? r.center + const Offset(24, 0) : r?.center,
      dragTo: swipe ? r.center - const Offset(24, 0) : null,
      buttonLabel: tr('tip.ok'),
      onNext: () {
        sfx(Sfx.tap);
        _doneTip();
      },
    );
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
        // 패키지를 한 번 본 뒤 타이머 안에 에너지가 떨어지면 한 번 더 (그 뒤로는 상점에만)
        if (game.starterShows == 1 && game.showStarterOffer()) {
          await showStarterSheet(context, widget.billing, game);
        } else {
          await _energyDialog();
        }
      case TapResult.boardFull:
        sfx(Sfx.error);
        _toast(tr('toast.boardFull'));
      default:
        sfx(Sfx.spawn);
    }
  }

  Future<void> _energyDialog() async {
    final canAd = game.energyAdAvailable;
    final watch = await showDialog<Object>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: game,
        builder: (ctx, _) {
          final full = game.energy >= GameConfig.energyCap;
          return GameDialog(
            title: IconText(tr('energy.title'), textAlign: TextAlign.center),
            content: PopupHero(
              art: ArtImage(
                Art.icon('energy_jar').available
                    ? Art.icon('energy_jar')
                    : Art.icon('energy'),
                size: 84,
              ),
              big: '${game.energy} / ${GameConfig.energyCap}',
              note: full
                  ? tr('energy.fullNow')
                  : tr('energy.next', {'time': fmtDuration(game.energyNextIn)}),
              extra: full
                  ? null
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (game.energyProgress / game.energyRegenSeconds)
                            .clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor: const Color(0xFFEDE3CC),
                        color: const Color(0xFFF2B33D),
                      ),
                    ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            onClose: () => Navigator.pop(ctx, false),
            actions: [
              if (canAd)
                _DialogAdButton(
                  label: tr('energy.watch', {'n': Tuning.energyAdAmount}),
                  sub: tr('energy.left', {'n': game.adsLeft(AdKind.energy)}),
                  adFree: adFree,
                  onTap: () => Navigator.pop(ctx, true),
                ),
              if (!full)
                FilledButton(
                  style: framedButton(
                    FilledButton.styleFrom(minimumSize: const Size(120, 48)),
                    'button_green',
                  ),
                  onPressed: () => Navigator.pop(ctx, 'gems'),
                  child: IconText(
                    tr('energy.gems', {
                      'n': Gems.refillEnergy,
                      'cost': game.refillCost,
                    }),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
            ],
          );
        },
      ),
    );
    if (watch == 'gems') {
      if (game.buyEnergyRefill()) {
        sfx(Sfx.coin);
      } else {
        _toast(tr('shop.notEnough'));
        _openShop();
      }
      return;
    }
    if (watch == true && await _rewardedCapped(AdKind.energy)) {
      game.grantEnergyAd();
    }
  }

  void _openShop() {
    sfx(Sfx.open);
    showShopSheet(context, widget.billing, game);
  }

  Future<void> _watchBoost() async {
    if (!_gate(Feature.boost)) return;
    sfx(Sfx.open);
    await showBoostSheet(
      context,
      game,
      watchAd: _rewardedCapped,
      adFree: adFree,
    );
  }

  /// 친구의 오늘 별 부탁이 끝났을 때: 광고로 +2.
  /// 오늘 부탁이 모두 끝났을 때: 가장 친한 친구가 광고를 보면 별 부탁 +2.
  Future<void> _allDoneDialog() {
    final pool = game.friends.toList()
      ..sort(
        (a, b) => (game.deliveries[b] ?? 0).compareTo(game.deliveries[a] ?? 0),
      );
    return _quotaDialog(pool.first, allDone: true);
  }

  Future<void> _quotaDialog(String friendId, {bool allDone = false}) async {
    final f = Friends.byId(friendId);
    final watch = await showDialog<bool>(
      context: context,
      builder: (ctx) => GameDialog(
        title: IconText(
          allDone
              ? tr('quota.allTitle')
              : tr('quota.title', {'name': friendName(friendId)}),
          textAlign: TextAlign.center,
        ),
        content: PopupHero(
          art: ArtImage(Art.friend(f), size: 84),
          big: '[[star]]0 / ${game.starOrderLimit(friendId)}',
          note: allDone
              ? tr('quota.allNote', {
                  'name': friendName(friendId),
                  'n': OrderQuota.perAd,
                })
              : tr('quota.note', {'n': OrderQuota.perAd}),
        ),
        actionsAlignment: MainAxisAlignment.center,
        onClose: () => Navigator.pop(ctx, false),
        actions: [
          _DialogAdButton(
            label: tr('quota.watch', {'n': OrderQuota.perAd}),
            sub: tr('energy.left', {'n': game.adsLeft(AdKind.quota)}),
            adFree: adFree,
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (watch == true && await _rewardedCapped(AdKind.quota)) {
      game.grantQuotaAd(friendId);
      sfx(Sfx.coin);
    }
  }

  /// 맨 아랫줄 보관 칸: 다이아로 영구 해금 (정원 패스는 2칸 바로).
  Future<void> _vaultDialog(int cell) async {
    final cost = game.vaultCostNext;
    final enough = game.gems >= cost;
    final passCell = GameConfig.passVault.contains(cell);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => GameDialog(
        title: IconText(tr('vault.title'), textAlign: TextAlign.center),
        content: PopupHero(
          art: ArtImage(Art.icon('storage'), size: 76),
          big: '[[diamond]]$cost',
          note: tr(passCell ? 'vault.notePass' : 'vault.note'),
        ),
        actionsAlignment: MainAxisAlignment.center,
        onClose: () => Navigator.pop(ctx, false),
        actions: [
          FilledButton(
            style: framedButton(
              FilledButton.styleFrom(minimumSize: const Size(120, 48)),
              'button_green',
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: IconText(
              enough ? tr('cell.open') : tr('vault.needGems'),
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (game.buyVault(cell)) {
      sfx(Sfx.unlock);
    } else {
      _openShop();
    }
  }

  Future<void> _watchCoinBag() async {
    if (!_gate(Feature.coinBag)) return;
    if (await _rewardedCapped(AdKind.coinBag)) {
      sfx(Sfx.coin);
      _toast(tr('toast.coins', {'coins': fmt(game.grantCoinBag())}));
    }
  }

  /// 부탁 바꾸기: 하루 3번 무료, 그다음은 광고.
  Future<void> _refreshOrder(int i) async {
    if (game.freeRerollsLeft > 0) {
      game.refreshOrder(i);
      sfx(Sfx.open);
      _toast(tr('toast.rerollFree', {'n': game.freeRerollsLeft}));
    } else if (await _rewardedCapped(AdKind.refresh)) {
      game.refreshOrder(i);
    }
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
    if (GameConfig.isVault(cell)) return _vaultDialog(cell);
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
        content: PopupHero(
          art: ArtImage(Art.lock, size: 76),
          big: '[[coin]]${fmt(cost)}',
          note: tr('cell.note'),
        ),
        actionsAlignment: MainAxisAlignment.center,
        onClose: () => Navigator.pop(ctx, false),
        actions: [
          FilledButton(
            style: framedButton(
              FilledButton.styleFrom(minimumSize: const Size(120, 48)),
              'button_green',
            ),
            onPressed: enough ? () => Navigator.pop(ctx, true) : null,
            child: IconText(
              enough ? tr('cell.open') : tr('cell.needCoins'),
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
    if (ok == true && game.buyCell(cell)) sfx(Sfx.unlock);
  }

  Future<void> _onBubble(int cell) async {
    final cost = game.bubbleGemCost(cell);
    final pick = await showDialog<String>(
      context: context,
      builder: (ctx) => GameDialog(
        title: IconText(tr('bubble.title'), textAlign: TextAlign.center),
        content: PopupHero(
          art: ArtImage(Art.bubble, size: 84),
          big: game.board[cell] == null
              ? ''
              : itemName(
                  Chains.item(game.board[cell]!.chain, game.board[cell]!.level),
                ),
          note: tr('bubble.note'),
        ),
        actionsAlignment: MainAxisAlignment.center,
        onClose: () => Navigator.pop(ctx),
        actions: [
          _DialogAdButton(
            label: tr('bubble.ad'),
            adFree: adFree,
            onTap: () => Navigator.pop(ctx, 'ad'),
          ),
          FilledButton(
            style: framedButton(
              FilledButton.styleFrom(minimumSize: const Size(110, 48)),
              'button_green',
            ),
            onPressed: () => Navigator.pop(ctx, 'gems'),
            child: IconText(
              '[[diamond]] $cost',
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ],
      ),
    );
    if (pick == 'ad') {
      if (await _rewarded()) game.popBubble(cell);
    } else if (pick == 'gems') {
      if (game.popBubbleWithGems(cell)) {
        sfx(Sfx.unlock);
      } else {
        _toast(tr('shop.notEnough'));
        _openShop();
      }
    }
  }

  Future<void> _onVisitorTap() async {
    final withAd = await showDialog<bool>(
      context: context,
      builder: (ctx) => GameDialog(
        banner: 'gold',
        title: IconText(tr('visitor.title'), textAlign: TextAlign.center),
        content: PopupHero(
          art: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ArtImage(Art.visitor(), size: 86),
              ArtImage(Art.gift, size: 52),
            ],
          ),
          big: '[[coin]]${fmt(game.visitorCoins(withAd: false))}',
          note: tr('visitor.body'),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: IconText(
              tr('visitor.take'),
              style: const TextStyle(fontSize: 17),
            ),
          ),
          _DialogAdButton(
            label: tr('visitor.takeBig', {
              'coins': fmt(game.visitorCoins(withAd: true)),
              'stars': GameConfig.visitorAdStars,
            }),
            adFree: adFree,
            onTap: () => Navigator.pop(ctx, true),
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

  // ---------------------------------------------------------------- 화면

  // 튜토리얼이 가리키는 위치
  final _kSpawner = GlobalKey();
  final _kBoard = GlobalKey();
  final _kOrders = GlobalKey();
  final _kDecor = GlobalKey();
  final _kGarden = GlobalKey();
  final _kBoost = GlobalKey();
  final _kCoinBag = GlobalKey();
  final _kStack = GlobalKey();
  final _kGems = GlobalKey();
  final _kMenu = GlobalKey();
  final _kGifts = GlobalKey();

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
    await _baselineTips();
    _tipsReady = true;
    _quietUntil = DateTime.now().add(const Duration(seconds: 3));
    _checkNewTips();
    // 하루 첫 접속: 튜토리얼이 끝난 플레이어에게 출석판을 띄운다
    if (step == _tutDone && game.level >= 2 && game.checkInReady) {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && game.checkInReady) showCheckInSheet(context, game);
      });
    }
    // 레이아웃이 끝난 뒤 위치를 다시 잰다
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _setTutorial(int step) async {
    if (step == 1) Analytics.instance.tutorialBegin();
    if (step == _tutDone && _tut != _tutDone) {
      Analytics.instance.tutorialComplete();
    }
    setState(() => _tut = step);
    (await SharedPreferences.getInstance()).setInt(_tutPref, step);
  }

  void _tutorialEvent(GameEvent e) {
    if (_tut == 2 && e is MergedEvent) _setTutorial(3);
    if (_tut == 3 && e is OrderDeliveredEvent) _setTutorial(4);
  }

  /// 합칠 수 있는 같은 아이템 두 칸의 화면 위치 (튜토리얼 손장갑이 끌어 보이는 곳).
  (Offset, Offset)? _mergePair() {
    final board = _rectOf(_kBoard);
    if (board == null) return null;
    const pad = 5.0;
    final cell = (board.width - pad * 2) / GameConfig.cols;
    Offset center(int i) =>
        board.topLeft +
        Offset(
          pad + (i % GameConfig.cols + 0.5) * cell,
          pad + (i ~/ GameConfig.cols + 0.5) * cell,
        );
    for (var a = 0; a < game.board.length; a++) {
      final x = game.board[a];
      if (x == null || x.isBubble) continue;
      for (var b = a + 1; b < game.board.length; b++) {
        final y = game.board[b];
        if (y != null &&
            !y.isBubble &&
            y.chain == x.chain &&
            y.level == x.level) {
          return (center(a), center(b));
        }
      }
    }
    return null;
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
        pointAt: _rectOf(_kSpawner)?.center,
        action: true,
      ),
      2 => () {
        final pair = _mergePair();
        return CoachOverlay(
          text: tr('tut.merge'),
          hole: _rectOf(_kBoard),
          pointAt: pair?.$1,
          dragTo: pair?.$2,
          action: true,
        );
      }(),
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
        pointAt: _rectOf(_kDecor)?.center,
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
  static const double _controlsH = 76;

  @override
  Widget build(BuildContext context) {
    final extra = widget.extraListenable;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
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
                    // 정원 창은 배경 비율(1.5:1) 그대로가 목표, 판은 폭에 맞춘다 (칸 최대 58dp).
                    // 높이가 모자라면 정원 → 판 순서로 줄인다.
                    final w = c.maxWidth;
                    final h = c.maxHeight;
                    const gap = 8.0;
                    const fixed = _hudH + _controlsH + gap * 3;
                    final boardIdeal = min(w - 20, 58.0 * GameConfig.cols + 10);
                    final natural = (w - 20) / GardenScene.aspect;
                    final gardenH = (h - fixed - boardIdeal)
                        .clamp(min(120.0, natural), natural)
                        .toDouble();
                    final boardW = min(
                      boardIdeal,
                      (h - fixed - gardenH) * GameConfig.cols / GameConfig.rows,
                    );
                    return Stack(
                      key: _kStack,
                      children: [
                        Column(
                          children: [
                            SizedBox(height: _hudH, child: _topBar()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: SizedBox(
                                key: _kOrders,
                                height: gardenH,
                                child: _gardenWindow(),
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: SizedBox(
                                  key: _kBoard,
                                  width: boardW,
                                  child: BoardView(
                                    game: game,
                                    selected: _selected,
                                    onSelect: (c) =>
                                        setState(() => _selected = c),
                                    onLockedTap: _onLockedCell,
                                    onBubbleTap: _onBubble,
                                    floating: _floatingInfo(),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: _controlsH, child: _controls()),
                            const SizedBox(height: gap),
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
                        ?_featureTip,
                      ],
                    );
                  },
                );
              },
            ),
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
                  _Pill(icon: Art.star, text: fmt(game.stars.toDouble())),
                  const SizedBox(width: 6),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _Pill(
                        key: _kGems,
                        icon: Art.icon('diamond'),
                        text: fmt(game.gems.toDouble()),
                        plus: true,
                        onTap: _openShop,
                      ),
                      // 상점에 오늘의 무료 선물이 있으면
                      if (game.freeOfferReady)
                        const Positioned(right: -3, top: -3, child: RedDot()),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 선물함 (쪽지 · 출석 · 업적: 받을 것 수) · 메뉴 (강화 · 도감 · 친구 · 상점 · 설정)
          _IconButton(
            key: _kGifts,
            icon: 'gift',
            badge: _giftCount,
            onTap: _openGifts,
          ),
          const SizedBox(width: 6),
          _IconButton(
            key: _kMenu,
            icon: 'menu',
            fallback: Icons.menu_rounded,
            badge:
                Upgrades.all.any((u) => game.canBuyUpgrade(u.type)) ||
                    game.hasNewDiscovery ||
                    game.freeOfferReady ||
                    widget.socialBadge()
                ? -1
                : 0,
            onTap: _openMenu,
          ),
        ],
      ),
    );
  }

  /// 정원 창: 씬만 담는다 (메뉴 버튼은 아래 도구줄로 옮겨 장식 · 친구를 가리지 않는다).
  /// 정원 창: 배경 비율 그대로, 친구 머리 위에 부탁 말풍선. 구역 이름 · 크게 보기 · 코인 주머니가 겹쳐 있다.
  Widget _gardenWindow() {
    final bagOpen = game.isUnlocked(Feature.coinBag);
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
        focusY: 1.0,
        markerScale: 1.1,
        onSlotTap: _onSlotTap,
        onVisitorTap: _onVisitorTap,
        onOrderTap: _viewArea == game.currentArea ? _onOrderTap : null,
        orderTopInset: 50,
        overlay: [
          Positioned(left: 8, top: 8, child: _areaPill()),
          // 오늘 부탁이 모두 끝: 내일 또 와요 (광고로 별 부탁 더 받기)
          if (game.ordersDoneToday && _viewArea == game.currentArea)
            Positioned(
              left: 0,
              right: 0,
              bottom: 10,
              child: Center(
                child: GestureDetector(
                  onTap: _allDoneDialog,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 8, 16, 8),
                    decoration: BoxDecoration(
                      color: const Color(0xF2FFFBF0),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF7A5230),
                        width: 2,
                      ),
                    ),
                    child: IconText(
                      '${tr('quota.allDone')}  ${adFree ? '' : '[[ad]]'}[[star]]+${OrderQuota.perAd}',
                      iconScale: 1.1,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 8,
            top: 8,
            child: _RoundButton(
              label: 'expand',
              icon: Icons.open_in_full_rounded,
              onTap: _openGarden,
            ),
          ),
          // 코인 주머니: 받을 수 있을 때만 크게 보기 옆에 떨어져 있다
          if (bagOpen && game.coinBagReady)
            Positioned(
              right: 52,
              top: 6,
              child: _GardenTool(
                key: _kCoinBag,
                icon: 'coinbag',
                ad: !adFree,
                onTap: _watchCoinBag,
              ),
            ),
        ],
      ),
    );
  }

  /// 아직 준비 안 된 부탁: 무엇이 필요한지 + 다른 부탁으로 바꾸기 (하루 3번 무료, 그다음 광고).
  Future<void> _orderInfo(int i) async {
    final o = game.orders[i];
    final change = await showDialog<bool>(
      context: context,
      builder: (ctx) => GameDialog(
        title: IconText(
          tr('order.wants', {'name': friendName(o.friendId)}),
          textAlign: TextAlign.center,
        ),
        content: PopupHero(
          art: ArtImage(Art.item(o.chain, o.level), size: 76),
          big: '${itemName(Chains.item(o.chain, o.level))} Lv${o.level}',
          note: tr('order.wantsNote', {'stars': o.stars}),
        ),
        actionsAlignment: MainAxisAlignment.center,
        onClose: () => Navigator.pop(ctx, false),
        actions: [
          FilledButton(
            style: framedButton(
              FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Palette.text,
              ),
              'button_white',
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: IconText(
              game.freeRerollsLeft > 0
                  ? tr('order.changeFree', {'n': game.freeRerollsLeft})
                  : '${adFree ? '' : '[[ad]] '}${tr('order.change')}',
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ],
      ),
    );
    if (change == true) await _refreshOrder(i);
  }

  /// 정원의 부탁 말풍선을 눌렀을 때: 전달 · 별 부탁 더 받기 · 무엇이 필요한지 안내.
  void _onOrderTap(int i) {
    if (i >= game.orders.length) return;
    final o = game.orders[i];
    if (game.canDeliver(i)) {
      game.deliver(i);
    } else if (!game.orderGivesStars(o)) {
      _quotaDialog(o.friendId);
    } else {
      sfx(Sfx.tap);
      _orderInfo(i);
    }
  }

  /// 정원 창 왼쪽 위: 구역 이름 · 장식 수 · 진행 막대.
  Widget _areaPill() {
    final a = Garden.areaAt(_viewArea);
    final done = _viewArea < game.currentArea
        ? Garden.slotsPerArea
        : game.placed.length;
    final locked = game.areaLocked && _viewArea == game.currentArea;
    return GestureDetector(
      onTap: _openGarden,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 14, 7),
        decoration: BoxDecoration(
          color: const Color(0xEEFFF8E8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF7A5230), width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 지난 구역 보기 (말풍선을 가리지 않게 이름표 안에)
            if (game.currentArea > 0) ...[
              _PillArrow(
                left: true,
                enabled: _viewArea > 0,
                onTap: () => setState(() => _viewArea--),
              ),
              const SizedBox(width: 4),
            ],
            ArtImage(Art.areaIcon(a), size: 24),
            const SizedBox(width: 5),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconText(
                  locked
                      ? '${areaName(a)}  ${tr('common.lockedLevel', {'n': game.areaRequiredLevel})}'
                      : '${areaName(a)}  $done/${Garden.slotsPerArea}',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: 90,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: done / Garden.slotsPerArea,
                      minHeight: 4,
                      backgroundColor: const Color(0xFFE8E0CC),
                      color: Palette.primary,
                    ),
                  ),
                ),
              ],
            ),
            if (game.currentArea > 0) ...[
              const SizedBox(width: 6),
              _PillArrow(
                left: false,
                enabled: _viewArea < game.currentArea,
                onTap: () => setState(() => _viewArea++),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 판 위에 뜨는 정보: 선택한 아이템(팔기 · 보관), 판매 되돌리기, 판이 막혔을 때 안내. 없으면 null.
  Widget? _floatingInfo() {
    final idx = _selected;
    final sel = idx == null ? null : game.board[idx];
    Widget card(Widget child) => Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF7A5230), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
    if (idx != null && sel != null) {
      return card(
        Row(
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
        ),
      );
    }
    if (game.canUndoSell) {
      return card(
        GestureDetector(
          onTap: game.undoSell,
          child: IconText(
            tr('board.undo'),
            style: const TextStyle(fontSize: 16),
          ),
        ),
      );
    }
    if (game.boardStuck) {
      return card(
        IconText(
          tr('board.stuck'),
          style: const TextStyle(fontSize: 14, color: Color(0xFFB0640A)),
        ),
      );
    }
    return null;
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

  int get _giftCount =>
      game.unreadMail +
      game.claimableAchievements +
      (game.checkInReady ? 1 : 0);

  /// 선물함: 매일 받는 보상 (쪽지 · 출석 · 업적).
  void _openGifts() {
    sfx(Sfx.open);
    showMenuSheet(
      context,
      game,
      title: tr('menu.gifts'),
      () => [
        MenuEntry(
          'letter',
          tr('menu.mail'),
          () => showMailSheet(context, game),
          badge: game.unreadMail,
        ),
        MenuEntry(
          'calendar',
          tr('menu.checkIn'),
          () => showCheckInSheet(context, game),
          badge: game.checkInReady ? -1 : 0,
          fallback: Icons.event_available_rounded,
        ),
        MenuEntry(
          'trophy',
          tr('menu.achievements'),
          () => showAchievementsSheet(context, game),
          badge: game.claimableAchievements,
        ),
      ],
    );
  }

  void _openMenu() {
    sfx(Sfx.open);
    showMenuSheet(
      context,
      Listenable.merge([game, widget.billing, ?widget.extraListenable]),
      () => [
        MenuEntry(
          game.isUnlocked(Feature.upgrades) ? 'upgrade' : 'lock',
          tr('menu.upgrade'),
          () {
            if (_gate(Feature.upgrades)) showUpgradesSheet(context, game);
          },
          badge: Upgrades.all.any((u) => game.canBuyUpgrade(u.type)) ? -1 : 0,
        ),
        MenuEntry('book', tr('menu.book'), () {
          game.markBookSeen();
          showCollectionSheet(context, game);
        }, badge: game.hasNewDiscovery ? -1 : 0),
        if (widget.openFriends != null)
          MenuEntry(
            'friends',
            tr('menu.friends'),
            () => widget.openFriends!(context),
            badge: widget.socialBadge() ? -1 : 0,
            fallback: Icons.people_alt_rounded,
          ),
        MenuEntry(
          'shop',
          tr('menu.shop'),
          _openShop,
          badge: game.freeOfferReady ? -1 : 0,
          fallback: Icons.storefront,
        ),
        MenuEntry(
          'settings',
          tr('menu.settings'),
          () => widget.openSettings(context),
        ),
      ],
    );
  }

  /// 아래 줄: 꾸미기 · [바구니] · 부스트 (엄지로 누르는 세 가지).
  Widget _controls() {
    final boostOpen = game.isUnlocked(Feature.boost);
    final canDecorate = List.generate(
      Garden.slotsPerArea,
      game.canPlace,
    ).any((x) => x);
    final nextCost = [
      for (var i = 0; i < Garden.slotsPerArea; i++)
        if (!game.placed.contains(i)) game.decorCost(i),
    ].fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    final activeBoosts = BoostKind.values.where(game.boosted).toList();
    String boostLine() {
      if (!boostOpen)
        return tr('common.lockedLevel', {
          'n': Leveling.unlockLevel[Feature.boost],
        });
      if (activeBoosts.isEmpty) return tr('ctrl.boost.idle');
      final k = activeBoosts.reduce(
        (a, b) => game.boostLeft(a) >= game.boostLeft(b) ? a : b,
      );
      final more = activeBoosts.length > 1
          ? ' +${activeBoosts.length - 1}'
          : '';
      return '${tr('boost.${k.name}')} ${_shortLeft(game.boostLeft(k))}$more';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Expanded(
            child: _BarTile(
              key: _kDecor,
              icon: 'decorate',
              label: tr('menu.decorate'),
              sub: nextCost == null
                  ? '[[check]]'
                  : '[[star]]${game.stars} / $nextCost',
              badge: canDecorate,
              onTap: () {
                sfx(Sfx.open);
                setState(() => _viewArea = game.currentArea);
                showDecorSheet(context, game);
              },
            ),
          ),
          const SizedBox(width: 10),
          _Spawner(
            key: _kSpawner,
            game: game,
            onTap: _onSpawnerTap,
            onLongPress: _energyDialog,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _BarTile(
              key: _kBoost,
              icon: Art.icon('boost').available ? 'boost' : 'coinbag',
              label: tr('ctrl.boost'),
              sub: boostLine(),
              ad: true,
              active: activeBoosts.isNotEmpty,
              locked: !boostOpen,
              onTap: _watchBoost,
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

  static const double size = 46;

  @override
  Widget build(BuildContext context) {
    // 정사각형 고정 (HUD 높이에 눌려 타원이 되지 않게)
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _XpRingPainter(progress.clamp(0.0, 1.0)),
        child: Center(
          child: Container(
            width: size - 14,
            height: size - 14,
            decoration: const BoxDecoration(
              color: Palette.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: FittedBox(
                child: Text(
                  '$level',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 경험치 고리: 크림색 바탕 + 갈색 테두리 + 금색 진행 (둥근 끝).
class _XpRingPainter extends CustomPainter {
  _XpRingPainter(this.v);
  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r - 1, Paint()..color = const Color(0xFF5A3A1E));
    canvas.drawCircle(c, r - 3, Paint()..color = const Color(0xFFFFF4DA));
    final rect = Rect.fromCircle(center: c, radius: r - 6.5);
    canvas.drawArc(
      rect,
      -pi / 2,
      2 * pi * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFF2B33D),
    );
  }

  @override
  bool shouldRepaint(_XpRingPainter o) => o.v != v;
}

class _Spawner extends StatelessWidget {
  const _Spawner({
    super.key,
    required this.game,
    required this.onTap,
    this.onLongPress,
  });
  final GameState game;
  final VoidCallback onTap;

  /// 길게 누르면 에너지 창 (상단 에너지 칸을 없애고 바구니로 옮김).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final full = game.boardFull;
    final open = game.openBaskets;
    // 바구니가 여러 개면 좌우로 넘겨 바꾼다 (찻잎 바구니 · 별가루 병)
    void swipe(int dir) {
      if (open.length < 2) return;
      final i = open.indexOf(game.basket);
      game.selectBasket(open[(i + dir + open.length) % open.length]);
      sfx(Sfx.tap);
    }

    final icon = game.basket == 0
        ? Art.basket
        : Art.icon(Chains.basketIcon[game.basket]);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() > 120) swipe(v < 0 ? 1 : -1);
      },
      child: SizedBox(
        width: 70,
        height: 70,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
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
              padding: const EdgeInsets.all(5),
              // 글꼴 · 숫자 길이와 상관없이 원 안에 들어가게 줄여 맞춤
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ArtImage(icon, size: 26),
                    IconText(
                      full ? tr('spawner.full') : '[[energy]]${game.energy}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            if (open.length > 1)
              Positioned(
                bottom: -8,
                child: Row(
                  children: [
                    for (final b in open)
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: b == game.basket
                              ? Palette.primary
                              : Colors.black26,
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

/// 위쪽 줄용 짧은 남은 시간: 1분 이상은 '12분', 그 밑은 '40초'.
String _shortLeft(Duration d) => d.inMinutes >= 1
    ? tr('boost.minutes', {'n': d.inMinutes + (d.inSeconds % 60 > 0 ? 1 : 0)})
    : tr('boost.seconds', {'n': d.inSeconds});

/// 아래 줄 넓은 버튼: 아이콘 + 이름 + 한 줄 정보 (광고 · 부스트는 보라, 도구는 크림색).
class _BarTile extends StatelessWidget {
  const _BarTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.sub,
    this.ad = false,
    this.active = false,
    this.badge = false,
    this.locked = false,
  });
  final String icon;
  final String label;
  final String? sub;
  final VoidCallback? onTap;
  final bool ad;
  final bool active;
  final bool badge;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final colors = locked
        ? const [Color(0xFFE2DBCB), Color(0xFFCFC6B3)]
        : active
        ? const [Color(0xFFFFE38A), Color(0xFFF2B33D)]
        : ad
        ? const [Color(0xFFC9A5F2), Color(0xFF9C6ADE)]
        : const [Color(0xFFFFFBF0), Color(0xFFF3E6C8)];
    final light = ad && !locked && !active;
    final ink = light ? Colors.white : const Color(0xFF4A3A22);
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              sfx(Sfx.tap);
              onTap!();
            },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 62,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF5A3A1E), width: 2.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 4,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
            child: Row(
              children: [
                Opacity(
                  opacity: locked ? 0.55 : 1,
                  child: ArtImage(Art.icon(icon), size: 36),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.15,
                            color: ink,
                          ),
                        ),
                      ),
                      if (sub != null)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: IconText(
                            sub!,
                            iconScale: 1.0,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.15,
                              color: ink.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (badge && !locked)
            const Positioned(right: -4, top: -4, child: RedDot()),
        ],
      ),
    );
  }
}

/// 정원 위 작은 둥근 버튼 (코인 주머니 등). [ad] 면 광고 표시.
/// 구역 이름표 안의 작은 화살표.
class _PillArrow extends StatelessWidget {
  const _PillArrow({
    required this.left,
    required this.enabled,
    required this.onTap,
  });
  final bool left;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: enabled
        ? () {
            sfx(Sfx.tap);
            onTap();
          }
        : null,
    child: Opacity(
      opacity: enabled ? 1 : 0.3,
      child: ArtImage(Art.icon(left ? 'arrow_left' : 'arrow_right'), size: 22),
    ),
  );
}

class _GardenTool extends StatelessWidget {
  const _GardenTool({
    super.key,
    required this.icon,
    required this.onTap,
    this.ad = false,
  });
  final String icon;
  final VoidCallback onTap;
  final bool ad;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      sfx(Sfx.tap);
      onTap();
    },
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
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
          child: ArtImage(Art.icon(icon), size: 26),
        ),
        if (ad)
          Positioned(
            right: -4,
            top: -4,
            child: ArtImage(Art.icon('ad'), size: 18),
          ),
      ],
    ),
  );
}

class _DialogAdButton extends StatelessWidget {
  const _DialogAdButton({
    required this.label,
    required this.onTap,
    required this.adFree,
    this.sub,
  });
  final String label;
  final String? sub;
  final bool adFree;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: framedButton(
        FilledButton.styleFrom(
          backgroundColor: Palette.ad,
          minimumSize: const Size(double.infinity, 56),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        ),
        'button_purple',
      ),
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconText(
            adFree ? label : '[[ad]] $label',
            style: const TextStyle(fontSize: 19, color: Colors.white),
          ),
          if (sub != null)
            IconText(
              sub!,
              style: const TextStyle(fontSize: 11.5, color: Color(0xE6FFFFFF)),
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
    super.key,
    required this.icon,
    required this.text,
    this.sub,
    this.plus = false,
    this.onTap,
  });
  final ArtRef icon;
  final String text;
  final String? sub;
  final bool plus;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.fromLTRB(5, 3, 12, 3),
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
                    color: Palette.text,
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
  const _IconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badge = 0,
    this.fallback,
  });
  final String icon;
  final IconData? fallback;
  final VoidCallback onTap;

  /// 0 = 없음, -1 = 점만, 양수 = 숫자.
  final int badge;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
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
          child: Art.icon(icon).available || fallback == null
              ? ArtImage(Art.icon(icon), size: 26)
              : Icon(fallback, size: 26, color: const Color(0xFF7A5230)),
        ),
        if (badge != 0)
          Positioned(
            right: -5,
            top: -5,
            child: RedDot(count: badge > 0 ? badge : null),
          ),
      ],
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
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
