import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../art/art.dart';
import '../game/config.dart';
import '../game/event_pass.dart';
import '../game/format.dart';
import '../game/game_state.dart';
import '../game/reward_hold.dart';
import '../i18n/l10n.dart';
import '../i18n/names.dart';
import '../services/ads_service.dart';
import '../services/audio_service.dart';
import '../services/billing_service.dart';
import 'board/board_view.dart';
import 'garden/garden_scene.dart';
import 'garden/garden_screen.dart';
import 'meta_ui.dart';
import 'offers_ui.dart';
import 'event_ui.dart';
import 'renew_ui.dart';
import 'share_card.dart';
import 'share_flow.dart';
import 'sheets.dart';
import 'theme.dart';
import 'tutorial.dart';
import '../game/tuning.dart';
import '../services/analytics_service.dart';
import 'widgets/icon_text.dart';
import 'widgets/frame_box.dart';
import 'widgets/top_toast.dart';
import 'widgets/reward_popup.dart';

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

/// 점검용 (D-108): 홈 화면의 창을 이름으로 열어 본다 (줄바꿈 · 작은 화면 테스트).
abstract interface class HomeDebug {
  Map<String, VoidCallback> debugDialogs();
}

class _HomeScreenState extends State<HomeScreen> implements HomeDebug {
  StreamSubscription<GameEvent>? _sub;
  final List<_Toast> _toasts = [];
  int _toastId = 0;
  late int _viewArea;
  int? _selected;
  final List<LevelUpEvent> _levelUps = [];
  bool _levelDialogOpen = false;

  GameState get game => widget.game;

  @override
  Map<String, VoidCallback> debugDialogs() {
    final itemCell = game.board.indexWhere((it) => it != null && !it.isBubble);
    return {
      'levelUp': () {
        _levelUps.add(
          LevelUpEvent(game.level, [Feature.values.last], 123456, 12, 30),
        );
        _showLevelUps();
      },
      'unlock': () => _showUnlock(Feature.values.last),
      'energy': _energyDialog,
      'energyLow': () {
        game.energy = 0;
        _energyDialog();
      },
      'event': () {
        EventPass.debugEvent ??= EventPass.events.first;
        game.currentEvent;
        game.eventStep = 6;
        game.claimEventStep(0, premium: false);
        showEventSheet(context, widget.billing, game, watchAd: _rewardedCapped);
      },
      'msOffer': () {
        game.milestoneKey = 'lv:20';
        game.milestoneUntil = game.now.add(const Duration(hours: 5));
        showMilestoneOffer(context, widget.billing, game);
      },
      'gift': () => _giftDialog(itemCell),
      'xp': _xpInfo,
      'income': _incomeInfo,
      'seasonSet': () => _seasonSetDialog(2, 0),
      'quota': () => _quotaDialog(game.friends.first),
      'allDone': _allDoneDialog,
      'vault': () => _vaultDialog(GameConfig.coinCells),
      'bubble': () => _bubbleFlow(itemCell, 50, () {}),
      'visitor': _visitorFlow,
      'order': () => _orderInfo(0),
      'newArea': () => showNewAreaDialog(context, game, game.currentArea),
      'newBasket': () => showNewBasketDialog(context, [1]),
      'renewConfirm': () => showRenewConfirm(context, game, adFree: false),
      'renewDone': () => showRenewDone(context, game, 3),
      'seed': () => showSeedSheet(context, game),
      'share': () => showShareDialog(context, game, ShareKind.garden),
      for (final m in game.mail.take(3))
        'mail:${m.id}': () => showMailDetail(context, game, m),
    };
  }

  /// 광고 없이 보상: 구독 또는 기간제 정원 패스 (새싹 정원 패키지).
  bool get adFree => widget.billing.adFree || game.passActive;

  @override
  void initState() {
    unawaited(Analytics.instance.funnel('home_view'));
    super.initState();
    _viewArea = game.currentArea;
    _sub = game.events.listen(_onEvent);
    game.addListener(_checkNewTips);
    game.addListener(_syncTutorial);
    _loadTutorial();
  }

  @override
  void dispose() {
    game.removeListener(_checkNewTips);
    game.removeListener(_syncTutorial);
    _sub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- 이벤트

  // 새 쪽지 알림: 잠깐 모아서 한 번에 ('~의 편지가 도착했어요' / '새 쪽지가 n통 왔어요')
  final List<Mail> _newMail = [];
  void _mailArrived(Mail m) {
    _newMail.add(m);
    if (_newMail.length > 1) return;
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final list = [..._newMail];
      _newMail.clear();
      if (list.isEmpty) return;
      sfx(Sfx.unlock);
      if (list.length > 1) {
        _toast(tr('toast.mailMany', {'n': list.length}));
        return;
      }
      final m = list.single;
      final friend = Friends.all.any((f) => f.id == m.from);
      _toast(
        m.id.startsWith('update-')
            ? tr('toast.mailUpdate')
            : m.kind == MailKind.notice && m.from == 'team'
            ? tr('toast.mailNotice')
            : tr('toast.mailFrom', {
                'name': friend ? friendName(m.from) : m.from,
              }),
      );
    });
  }

  void _onEvent(GameEvent e) {
    switch (e) {
      case DiscoveryEvent(:final chain, :final level, :final bonus):
        sfx(Sfx.coin);
        final d = Chains.item(chain, level);
        TopToast.celebrate(
          context,
          art: ArtImage(Art.item(d.chain, d.level), size: 58),
          title: tr('discover.title'),
          sub: '${itemName(d)}  [[coin]]+${fmt(bonus)}',
        );
        // 체인의 마지막 단계(전설 아이템)를 처음 만들었다: 자랑 카드
        if (level >= Chains.maxLevel(chain)) {
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (mounted) {
              showShareDialog(context, game, ShareKind.legendary, chain: chain);
            }
          });
        }
      case MaxMergeEvent(:final payout):
        sfx(Sfx.mergeBig);
        _toast(tr('toast.maxMerge', {'coins': fmt(payout)}));
      case OrderDeliveredEvent(
        :final friendId,
        :final stars,
        :final affectionUp,
        :final xp,
      ):
        sfx(Sfx.deliver);
        _tutorialEvent(e);
        final done = game.quotaActive && game.starOrdersLeft(friendId) == 0;
        final thanks = stars > 0
            ? tr('toast.thanks', {
                'emoji': friendToken(friendId),
                'stars': stars,
              })
            : tr('toast.thanksCoins', {'emoji': friendToken(friendId)});
        final heart = affectionUp ? tr('toast.affectionUp') : '';
        final quota = done && stars > 0
            ? tr('toast.quotaDone', {'name': friendName(friendId)})
            : '';
        _toast('$thanks  [[xp]]+$xp$heart$quota');
        // 오늘 부탁이 모두 끝나면 한 번만 알려 준다 (이후엔 정원의 작은 아이콘)
        if (!game.ordersDoneToday) _allDoneShown = false;
        if (game.ordersDoneToday && !_allDoneShown) {
          _allDoneShown = true;
          Future.delayed(const Duration(milliseconds: 900), () {
            if (mounted) _allDoneDialog();
          });
        }
      case DecorPlacedEvent(:final area, :final slot):
        sfx(Sfx.place);
        _tutorialEvent(e);
        final d = Garden.areaAt(area).decor[slot];
        // 장식 설치 축하 창: 장식 그림 + 이름 + 정원 매력 (구역 완성은 따로 축하)
        RewardPopup.show(
          context,
          const Reward(),
          title: tr('decorDone.title'),
          art: Art.decor(d, style: game.styleOf(area, slot)),
          sub: tr('decorDone.sub', {
            'name': decorName(d),
            'n': (GameConfig.decorIncomeBonus * 100).round(),
          }),
          stay: const Duration(milliseconds: 2200),
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
      case MaxGiftEvent(:final friendId, :final coins, :final stars):
        sfx(Sfx.deliver);
        _toast(
          stars > 0
              ? tr('toast.giftMaxStars', {
                  'emoji': friendToken(friendId),
                  'stars': stars,
                  'coins': fmt(coins),
                })
              : tr('toast.gift2', {
                  'emoji': friendToken(friendId),
                  'coins': fmt(coins),
                }),
        );
      case OrderMilestoneEvent(:final count, :final gems):
        sfx(Sfx.unlock);
        TopToast.celebrate(
          context,
          art: ArtImage(Art.icon('diamond'), size: 52),
          title: tr('milestone.title', {'n': count}),
          sub: '[[diamond]] +$gems',
        );
      case PiggyEvent(:final full):
        sfx(Sfx.unlock);
        TopToast.celebrate(
          context,
          art: ArtImage(
            Art.icon('piggy').available
                ? Art.icon('piggy')
                : Art.icon('dia_basket'),
            size: 52,
          ),
          title: tr(full ? 'piggy.fullToast' : 'piggy.readyToast'),
          sub: '[[diamond]] ${fmtInt(game.piggyGems)}',
        );
      case EventStepEvent(:final step):
        sfx(Sfx.unlock);
        TopToast.celebrate(
          context,
          art: ArtImage(
            Art.icon('event_flag').available
                ? Art.icon('event_flag')
                : Art.icon('calendar'),
            size: 52,
          ),
          title: tr('event.stepUp', {'n': step}),
          sub: tr('event.stepSub'),
        );
      case MilestoneOfferEvent():
        // 레벨업 · 새 구역 창이 다 닫힌 뒤에 (창이 겹치지 않게)
        _whenIdle(() => showMilestoneOffer(context, widget.billing, game));
      case RenewEvent():
        sfx(Sfx.levelup);
      case SeasonSetEvent(:final area, :final style):
        sfx(Sfx.levelup);
        setState(() => _viewArea = area);
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) _seasonSetDialog(area, style);
        });
      case AreaCompletedEvent(:final area):
        _areaFlow = true;
        haptic(Haptic.big);
        _toast(tr('toast.areaDone', {'name': areaName(Garden.areaAt(area))}));
        // 완성한 구역 자랑 카드 (장식 · 친구가 모두 있는 정원) → 첫 구역이면 새싹 정원 패키지 (한 번만)
        Future.delayed(const Duration(milliseconds: 1500), () async {
          if (!mounted) return;
          await showShareDialog(context, game, ShareKind.area, area: area);
          if (!mounted) return;
          setState(() => _viewArea = game.currentArea);
          // 새 구역 열림 축하 (D-083)
          if (game.currentArea < Garden.areas.length) {
            await showNewAreaDialog(context, game, game.currentArea);
            if (!mounted) return;
          }
          _areaFlow = false;
          if (area == 0 && game.showStarterOffer()) {
            await Future.delayed(const Duration(milliseconds: 600));
            if (mounted) showStarterSheet(context, widget.billing, game);
          }
        });
      case LevelUpEvent():
        sfx(Sfx.levelup);
        haptic(Haptic.big);
        _levelUps.add(e);
        _showLevelUps();
      case LuckySpawnEvent():
        sfx(Sfx.merge2);
        haptic(Haptic.big); // 행운 바구니: 종소리 하나 (D-080)
      case BubbleEvent():
        sfx(Sfx.bubble);
        _toast(tr('toast.bubble'));
      case SoldEvent(:final price):
        sfx(Sfx.sell);
        _toast(tr('toast.sold', {'coins': fmt(price)}));
      case MergedEvent(:final level):
        sfx(mergeSfx(level));
        _tutorialEvent(e);
      case MailEvent(:final mail):
        _mailArrived(mail);
      case LandmarkEvent(:final area, :final level, :final newStage):
        if (newStage) {
          sfx(Sfx.levelup);
          TopToast.celebrate(
            context,
            art: ArtImage(Art.landmark(area, level), size: 64),
            title: tr(level == 1 ? 'landmark.built' : 'landmark.grew', {
              'name': tr(
                'landmark.${Landmarks.ids[area % Landmarks.ids.length]}',
              ),
            }),
            sub: tr('landmark.charmMax', {
              'pct': (Landmarks.charm(level) * 100).round(),
            }),
          );
        }
      case UpgradeMilestoneEvent(:final type, :final level):
        sfx(Sfx.levelup);
        TopToast.celebrate(
          context,
          art: ArtImage(IconText.resolve(Upgrades.of(type).icon), size: 56),
          title: tr('upgrade.milestoneHit', {'name': upgradeTitle(type)}),
          sub: tr('upgrade.milestoneSub', {'lv': level}),
        );
      case EnergyEmptyEvent() ||
          AdRewardEvent() ||
          GemsSpentEvent() ||
          OrdersDoneEvent() ||
          TrackEvent() ||
          TutorialStepEvent():
        break; // 지표용 (Analytics)
    }
  }

  /// 다른 창(레벨업 · 새 구역 흐름)이 없을 때 한 번 실행 (최대 1분 기다림).
  void _whenIdle(VoidCallback f, [int tries = 0]) {
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      final busy =
          _areaFlow ||
          _levelDialogOpen ||
          _levelUps.isNotEmpty ||
          (ModalRoute.of(context)?.isCurrent == false);
      if (busy && tries < 24) return _whenIdle(f, tries + 1);
      if (!busy) f();
    });
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

  /// 구역 완성 → 자랑 → 새 구역 창이 진행 중 (바구니 알림은 새 구역 창이 맡는다).
  bool _areaFlow = false;

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
              const SizedBox(height: 12),
              IconText(
                tr('levelUp.unlocked'),
                style: const TextStyle(fontSize: 15, color: Colors.black54),
              ),
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
    // 새로 열린 기능마다 '잠금 해제!' 창 → 확인을 누르면 바로 그 기능 안내로 (D-060)
    for (final f in e.unlocked.where((f) => f != Feature.storage)) {
      if (!mounted) break;
      await _showUnlock(f);
    }
    // 레벨로 바구니가 새로 열렸으면 (구역 완성 흐름 중이면 그쪽 새 구역 창이 보여 준다, D-085)
    if (mounted && !_areaFlow) {
      final fresh = game.takeNewBaskets();
      if (fresh.isNotEmpty) await showNewBasketDialog(context, fresh);
    }
    _levelDialogOpen = false;
    _startOnboarding(e.unlocked);
    _showLevelUps();
  }

  /// 기능 하나의 '잠금 해제!' 창: 실제 화면의 그 버튼 모양 + 이름 + 설명.
  Future<void> _showUnlock(Feature f) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => GameDialog(
      banner: 'gold',
      title: IconText(tr('unlock.title'), textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlowHalo(size: 150, child: IgnorePointer(child: _featurePreview(f))),
          // 미리보기가 이름 칩이면 이름을 또 쓰지 않는다
          if (!_chipPreview.contains(f)) ...[
            const SizedBox(height: 8),
            IconText(
              featureName(f),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20),
            ),
          ],
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
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () {
            sfx(Sfx.tap);
            Navigator.pop(ctx);
          },
          child: IconText(tr('unlock.ok')),
        ),
      ],
    ),
  );

  static const _chipPreview = {
    Feature.autoMerge,
    Feature.autoSpawn,
    Feature.offlineCap,
    Feature.spawnLevel,
  };

  /// 방금 연 기능들의 안내를 줄 맨 앞에 두고, 기다리지 않고 바로 띄운다.
  Future<void> _startOnboarding(List<Feature> fs) async {
    final ids = [
      for (final f in fs)
        if (f != Feature.storage) f.name,
    ];
    if (ids.isEmpty) return;
    final seen = await _seenTips();
    if (!mounted) return;
    setState(() {
      _tips.removeWhere(ids.contains);
      _tips.insertAll(0, [
        for (final id in ids)
          if (!seen.contains(id)) id,
      ]);
      _onboardNow = true;
    });
  }

  /// 잠금 해제 창 바로 뒤: 안내를 기다리지 않고 띄운다 (한 번).
  bool _onboardNow = false;

  /// 강화 화면에서 쓰는 기능: 안내 뒤 강화 화면을 바로 연다.
  static const _upgradeTips = {
    'upgrades',
    'autoMerge',
    'autoSpawn',
    'offlineCap',
    'spawnLevel',
  };

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
      Feature.boost => chip('boost', tr('ctrl.boost')),
      // 실제 정원 오른쪽 위의 코인 주머니 버튼 그대로 + 받는 양
      Feature.coinBag => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GardenTool(icon: 'coinbag', ad: true, onTap: () {}),
          const SizedBox(width: 8),
          IconText(
            '[[coin]]${fmt(game.coinBagAmount)}',
            style: const TextStyle(fontSize: 20),
          ),
        ],
      ),
      Feature.energyAd => _Pill(
        icon: Art.icon('energy'),
        text: '${game.energy}/${game.energyCap}',
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
      Feature.autoSpawn => chip('basket', upgradeTitle(UpgradeType.autoSpawn)),
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
    'autoSpawn',
    'design',
    'spawnLevel',
    'basket',
    'wardrobe',
  ];

  /// 본 안내는 계정 저장(game.tipsSeen)에 둔다. 예전 저장이면 기기 값을 옮겨 온다.
  Future<Set<String>> _seenTips() async {
    if (_tipsSeen != null) return _tipsSeen!;
    if (!game.tipsKnown) {
      game.tipsSeen.addAll(
        (await SharedPreferences.getInstance()).getStringList(_tipsPref) ??
            const [],
      );
      game.tipsKnown = true;
    }
    return _tipsSeen = game.tipsSeen;
  }

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
    (await _seenTips()).add(id);
    p.setStringList(_tipsPref, _tipsSeen!.toList());
  }

  GlobalKey _tipTarget(String id) => switch (id) {
    'energyAd' => _kSpawner,
    'boost' => _kMenu,
    'snack' || 'basket' => _kSpawner,
    'visitor' => _kGarden,
    'gems' => _kGems,
    'market' => _kShop,
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
    if (current && _onboardNow) {
      _onboardNow = false;
      _quietUntil = DateTime.now().add(const Duration(milliseconds: 350));
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) setState(() {});
      });
    } else if (current && !_wasCurrent) {
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
      buttonLabel: tr(_upgradeTips.contains(id) ? 'tip.go' : 'tip.ok'),
      onNext: () {
        sfx(Sfx.tap);
        _doneTip();
        // 강화로 여는 기능은 강화 화면까지 바로 데려간다
        if (_upgradeTips.contains(id) && game.isUnlocked(Feature.upgrades)) {
          game.markUpgradesSeen();
          showUpgradesSheet(
            context,
            game,
            onRenew: _renew,
            focus: switch (id) {
              'autoMerge' => UpgradeType.autoMerge,
              'autoSpawn' => UpgradeType.autoSpawn,
              'offlineCap' => UpgradeType.offlineCap,
              'spawnLevel' => UpgradeType.spawnLevel,
              _ => null,
            },
          );
        }
      },
    );
  }

  // ---------------------------------------------------------------- 행동

  Future<bool> _rewarded() async {
    final ok = await widget.ads.showRewarded();
    if (!ok) {
      _toast(tr('toast.adLoading'));
      Analytics.instance.adUnavailable();
    }
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
      case TapResult.basketEmpty:
        sfx(Sfx.error);
        _toast(
          tr('toast.basketEmpty', {
            'time': fmtDuration(game.basketNextIn(game.basket)),
          }),
        );
      default:
        sfx(Sfx.spawn);
        unawaited(Analytics.instance.funnel('first_spawn'));
    }
  }

  Future<void> _energyDialog() async {
    final canAd = game.energyAdAvailable;
    if (game.energyBundleAvailable &&
        game.energy < GameConfig.energyPerTap * 10) {
      Analytics.instance.offerView(Offers.energy, 'energy_dialog');
    }
    final watch = await showDialog<Object>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: game,
        builder: (ctx, _) {
          final full = game.energy >= game.energyCap;
          // 에너지가 거의 없을 때 하루 한 번 묶음 (D-110)
          final bundle =
              game.energyBundleAvailable &&
              game.energy < GameConfig.energyPerTap * 10;
          final hero = PopupHero(
            art: ArtImage(
              Art.icon('energy_jar').available
                  ? Art.icon('energy_jar')
                  : Art.icon('energy'),
              size: 84,
            ),
            big: '${game.energy} / ${game.energyCap}',
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
          );
          return GameDialog(
            title: IconText(tr('energy.title'), textAlign: TextAlign.center),
            content: bundle
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      hero,
                      const SizedBox(height: 10),
                      ListenableBuilder(
                        listenable: widget.billing,
                        builder: (_, _) => energyBundleCard(widget.billing),
                      ),
                    ],
                  )
                : hero,
            actionsAlignment: MainAxisAlignment.center,
            onClose: () => Navigator.pop(ctx, false),
            actions: [
              if (canAd)
                DialogAdButton(
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
      if (!mounted) return;
      if (game.buyEnergyRefill()) {
        RewardPopup.show(
          context,
          const Reward(energy: Gems.refillEnergy),
          title: tr('reward.bought'),
        );
      } else {
        _toast(tr('shop.notEnough'));
        _openShop();
      }
      return;
    }
    if (watch == true && await _rewardedCapped(AdKind.energy)) {
      game.grantEnergyAd();
      if (mounted) {
        RewardPopup.show(
          context,
          Reward(energy: Tuning.energyAdAmount),
          title: tr('reward.ad'),
        );
      }
    }
  }

  void _openShop() {
    sfx(Sfx.open);
    game.markShopSeen(); // 코인 물건 점은 그날 한 번 보면 꺼진다
    showShopSheet(
      context,
      widget.billing,
      game,
      watchAd: _rewardedCapped,
      adFree: adFree,
    );
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

  bool _allDoneShown = false;

  /// 정원 재단장: 확인 → (광고) → 재단장 → 완료 창.
  Future<void> _renew() async {
    final pick = await showRenewConfirm(context, game, adFree: adFree);
    if (pick == null || !mounted) return;
    // 광고를 골랐는데 못 봤으면(로드 실패 · 취소) 재단장을 진행하지 않는다 (되돌릴 수 없는 동작)
    if (pick && !await _rewarded()) return;
    final got = game.renew(withAd: pick);
    if (got <= 0 || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() {
      _selected = null;
      _viewArea = game.currentArea;
    });
    await showRenewDone(context, game, got);
  }

  /// 최고 단계 아이템 선물: 친구를 고른다 (하트가 덜 찬 친구가 앞).
  Future<void> _giftDialog(int cell) async {
    final it = game.board[cell];
    if (it == null) return;
    final list = game.friends.toList()
      ..sort((a, b) => game.affection(a).compareTo(game.affection(b)));
    final pick = await showDialog<String>(
      context: context,
      builder: (ctx) => GameDialog(
        banner: 'gold',
        title: IconText(tr('gift.title'), textAlign: TextAlign.center),
        onClose: () => Navigator.pop(ctx),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArtImage(Art.item(it.chain, it.level), size: 64),
            const SizedBox(height: 4),
            IconText(
              tr('gift.note', {'coins': fmt(game.giftCoins(it))}),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF6B5A44)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final id in list)
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, id),
                    child: Container(
                      width: 74,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFE2D3B5),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          ArtImage(
                            Art.friend(
                              Friends.byId(id),
                              outfit: game.outfitOf(id),
                            ),
                            size: 44,
                          ),
                          Text(
                            friendName(id),
                            style: const TextStyle(fontSize: 12),
                          ),
                          IconText(
                            '[[heart]]${game.affection(id)}/${Friends.maxAffection}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (pick == null) return;
    if (game.giftMaxItem(cell, pick)) setState(() => _selected = null);
  }

  /// 레벨 배지를 누르면: 경험치를 어떻게 얻는지.
  Future<void> _xpInfo() => showDialog<void>(
    context: context,
    builder: (ctx) => GameDialog(
      title: IconText(tr('xp.title'), textAlign: TextAlign.center),
      onClose: () => Navigator.pop(ctx),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconText(
            tr('xp.progress', {
              'lv': game.level,
              'xp': game.xp,
              'need': game.xpToNext,
            }),
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (game.xp / game.xpToNext).clamp(0.0, 1.0),
              minHeight: 10,
              color: Palette.primary,
              backgroundColor: const Color(0xFFE8E0CC),
            ),
          ),
          const SizedBox(height: 10),
          // 다음 레벨에 받는 것 · 열리는 것 (D-080)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6E0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2C48E), width: 1.5),
            ),
            child: Column(
              children: [
                IconText(
                  tr('xp.next', {'lv': game.level + 1}),
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 4),
                IconText(
                  '[[coin]]${fmt(Leveling.levelUpCoins(game.level + 1))}  [[energy]]+${Leveling.levelUpEnergy(game.level + 1, 0)}  [[diamond]]+${Gems.levelUp}',
                  style: const TextStyle(fontSize: 17),
                ),
                for (final f in Feature.values)
                  if (Leveling.unlockLevel[f] == game.level + 1)
                    IconText(
                      tr('xp.unlock', {'name': featureName(f)}),
                      style: const TextStyle(
                        fontSize: 15,
                        color: Palette.primary,
                      ),
                    ),
                if (Leveling.areaLevel(game.currentArea + 1) == game.level + 1)
                  IconText(
                    tr('xp.area'),
                    style: const TextStyle(
                      fontSize: 15,
                      color: Palette.primary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 레벨업 방법 (D-082): 수치 없이 세 줄만
          IconText(tr('xp.how'), style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          for (final k in ['order', 'decor', 'discover'])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: IconText(
                tr('xp.$k'),
                style: const TextStyle(fontSize: 15, color: Color(0xFF5E4B36)),
              ),
            ),
        ],
      ),
    ),
  );

  /// 코인 캡슐을 누르면: 수입이 어떻게 정해지는지 (수입 요약, D-080).
  final _kHudRow = GlobalKey();
  double _hudScale = 1;

  /// 위쪽 재화 줄 (코인 · 별 · 다이아). 폭이 모자라면 통째로 줄어든다.
  Widget _hudPills() => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      key: _kHudRow,
      children: [
        _Pill(
          onTap: _incomeInfo,
          icon: Art.coin,
          text: fmt(game.coins),
          sub: game.autoIdle
              ? tr('hud.perHourAuto', {
                  'v': fmt(game.incomePerHour * game.idleMult),
                  'p': (game.autoIdleBonus * 100).round(),
                })
              : tr('hud.perHour', {'v': fmt(game.incomePerHour)}),
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
            if (game.shopDot)
              Positioned(
                right: -3,
                top: -3,
                child: Transform.scale(
                  scale: 1 / _hudScale,
                  alignment: Alignment.topRight,
                  child: const RedDot(),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Future<void> _incomeInfo() {
    // 계산서처럼 (D-082): 아이템별 기본 수입 → 소계 → 곱해지는 효과 → 곱 합계 → 총합
    final byChain = <Chain, double>{};
    for (final it in game.board) {
      if (it == null || it.isBubble) continue;
      byChain[it.chain] =
          (byChain[it.chain] ?? 0) +
          GameConfig.incomeOf(it.chain, it.level) *
              Upgrades.chainPower(game.lv(Upgrades.powerOf(it.chain))) *
              3600;
    }
    // 줄마다 반올림한 값으로 더해야 계산서가 딱 맞는다
    if (byChain.values.every((v) => v < 1000)) {
      byChain.updateAll((_, v) => v.roundToDouble());
    }
    final items = byChain.values.fold<double>(0, (a, b) => a + b);
    final mults = <(String, double)>[
      (
        tr('income.upgrade'),
        Upgrades.incomeMultiplier(game.lv(UpgradeType.income)),
      ),
      (tr('income.friends'), 1 + game.buff(FriendBuff.income)),
      (tr('income.seeds'), game.seedMultiplier),
      if (game.boostActive) (tr('income.boost'), 2.0),
      if (game.autoIdle) (tr('income.auto'), game.idleMult),
    ].where((e) => e.$2 > 1.0005).toList();
    final mult = mults.fold<double>(1, (a, e) => a * e.$2);
    String pct(double m) => '${(m * 100).toStringAsFixed(m < 1.1 ? 1 : 0)}%';
    const ink = Color(0xFF5E4B36);
    Widget line(String a, String b, {bool sub = false, bool total = false}) =>
        Padding(
          padding: EdgeInsets.symmetric(vertical: total ? 6 : 3),
          child: Row(
            children: [
              Expanded(
                child: IconText(
                  a,
                  style: TextStyle(
                    fontSize: total ? 18 : 15,
                    color: sub || total ? Palette.primary : ink,
                  ),
                ),
              ),
              IconText(
                b,
                style: TextStyle(
                  fontSize: total ? 20 : 15,
                  color: sub || total ? Palette.primary : ink,
                ),
              ),
            ],
          ),
        );
    const rule = Divider(height: 10, thickness: 1.2, color: Color(0xFFE2D3B5));
    return showDialog<void>(
      context: context,
      builder: (ctx) => GameDialog(
        title: IconText(tr('income.title'), textAlign: TextAlign.center),
        onClose: () => Navigator.pop(ctx),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IconText(
              tr('income.board'),
              style: const TextStyle(fontSize: 13, color: Colors.black45),
            ),
            for (final c in Chain.values)
              if ((byChain[c] ?? 0) > 0)
                line(
                  '[[item:${c.name}:3]] ${chainName(c)}',
                  '[[coin]]${fmt(byChain[c]!)}',
                ),
            rule,
            line(tr('income.items'), '[[coin]]${fmt(items)}', sub: true),
            if (mults.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final (a, m) in mults)
                line(
                  a,
                  '+${((m - 1) * 100).toStringAsFixed(m < 1.1 ? 1 : 0)}%',
                ),
              rule,
              line(tr('income.multTotal'), '×${pct(mult)}', sub: true),
            ],
            const Divider(height: 14, thickness: 2, color: Color(0xFFB89A6E)),
            line(
              tr('income.total'),
              '[[coin]]${fmt(items * mult)}',
              total: true,
            ),
            const SizedBox(height: 8),
            line(
              tr('income.offline'),
              tr('unit.hour', {'n': game.offlineCap.inHours}),
            ),
          ],
        ),
      ),
    );
  }

  /// 계절 세트 완성: 레벨 업처럼 화면 가운데 축하 창.
  Future<void> _seasonSetDialog(int area, int style) => showDialog<void>(
    context: context,
    builder: (ctx) => GameDialog(
      banner: 'gold',
      title: IconText(tr('season.title'), textAlign: TextAlign.center),
      onClose: () => Navigator.pop(ctx),
      content: PopupHero(
        art: GlowHalo(
          size: 170,
          child: ArtImage(
            Art.decor(Garden.areaAt(area).decor.first, style: style),
            size: 110,
          ),
        ),
        big: tr('style.$style'),
        note: tr('season.note', {
          'area': areaName(Garden.areaAt(area)),
          'n': (Garden.seasonSetBonus * 100).round(),
        }),
      ),
      actions: [
        FilledButton(
          style: framedButton(
            FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
            ),
            'button_gold',
          ),
          onPressed: () => Navigator.pop(ctx),
          child: IconText(
            tr('season.ok'),
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ],
    ),
  );

  Future<void> _quotaDialog(String friendId, {bool allDone = false}) async {
    final f = Friends.byId(friendId);
    final watch = await showDialog<bool>(
      context: context,
      builder: (ctx) => GameDialog(
        banner: 'gold',
        title: IconText(
          allDone ? tr('quota.allTitle') : tr('quota.title'),
          textAlign: TextAlign.center,
        ),
        content: PopupHero(
          art: GlowHalo(
            child: ArtImage(
              Art.friend(f, outfit: game.outfitOf(friendId)),
              size: 92,
            ),
          ),
          big:
              '[[star]]${game.starOrderLimit(friendId)} / ${game.starOrderLimit(friendId)}',
          note: allDone
              ? tr('quota.allNote', {
                  'name': friendName(friendId),
                  'n': OrderQuota.perAd,
                })
              : tr('quota.note', {
                  'name': friendName(friendId),
                  'n': OrderQuota.perAd,
                }),
        ),
        actionsAlignment: MainAxisAlignment.center,
        onClose: () => Navigator.pop(ctx, false),
        actions: [
          DialogAdButton(
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
      if (mounted) {
        RewardPopup.show(
          context,
          const Reward(),
          title: tr('reward.ad'),
          art: Art.friend(Friends.byId(friendId), happy: true),
          sub: tr('reward.quotaAd', {
            'name': friendName(friendId),
            'n': OrderQuota.perAd,
          }),
        );
      }
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
      final c = game.grantCoinBag();
      if (mounted) {
        RewardPopup.show(
          context,
          Reward(coins: c.round()),
          title: tr('reward.ad'),
        );
      }
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
      sfx(Sfx.open);
      _toast(tr('toast.rerollAd'));
    }
  }

  void _onSlotTap(int slot) {
    // 놓은 장식: 디자인 화면으로 (D-063)
    if (game.isPlaced(game.currentArea, slot)) {
      final d = Garden.areaAt(game.currentArea).decor[slot];
      if (Art.decorStyles(d).length > 1) {
        sfx(Sfx.open);
        showStyleSheet(context, game, game.currentArea, slot);
      }
      return;
    }
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
    // 창 · 광고가 떠 있는 동안 비눗방울이 터지지 않게 (터지면 아무것도 못 받는다)
    final release = RewardHold.bubble(game, cell);
    try {
      await _bubbleFlow(cell, cost, release);
    } finally {
      release();
    }
  }

  Future<void> _bubbleFlow(int cell, int cost, void Function() release) async {
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
          DialogAdButton(
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
      // 붙잡은 채로 꺼낸다 (원래 시간이 지났어도 받는다)
      if (await _rewarded() && game.popBubble(cell)) {
        sfx(Sfx.unlock);
        _showFreed(cell, tr('reward.ad'));
      }
    } else if (pick == 'gems') {
      release(); // 비용은 원래 남은 시간으로 (판에서는 아직 안 터졌다)
      final it = game.board[cell];
      if (it == null || !it.isBubble) return; // 사라졌으면 상점을 열 일이 아니다
      final need = game.bubbleGemCost(cell);
      if (game.popBubbleWithGems(cell)) {
        sfx(Sfx.unlock);
        _showFreed(cell, tr('reward.bought'));
      } else if (game.gems < need) {
        _toast(tr('shop.notEnough'));
        _openShop();
      }
    }
  }

  /// 비눗방울에서 꺼낸 아이템을 그림 · 이름으로 알려 준다.
  void _showFreed(int cell, String title) {
    final it = game.board[cell];
    if (it == null || !mounted) return;
    RewardPopup.show(
      context,
      const Reward(),
      title: title,
      art: Art.item(it.chain, it.level),
      sub: tr('reward.bubble', {
        'name': itemName(Chains.item(it.chain, it.level)),
      }),
    );
  }

  Future<void> _onVisitorTap() async {
    // 창 · 광고가 떠 있는 동안 손님이 떠나지 않게 (떠나면 아무것도 못 받는다)
    final release = RewardHold.visitor(game);
    try {
      await _visitorFlow();
    } finally {
      release();
    }
  }

  Future<void> _visitorFlow() async {
    final base = game.visitorCoins(withAd: false);
    final withAd = await showDialog<bool>(
      context: context,
      builder: (ctx) => GameDialog(
        banner: 'gold',
        title: IconText(tr('visitor.title'), textAlign: TextAlign.center),
        onClose: () => Navigator.pop(ctx),
        content: PopupHero(
          art: GlowHalo(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ArtImage(Art.visitor('wave'), size: 92),
                ArtImage(Art.gift, size: 56),
              ],
            ),
          ),
          big: '[[coin]]${fmt(base)}',
          note: tr('visitor.body'),
        ),
        actions: [
          DialogAdButton(
            label: tr('reward.times', {
              'n': GameConfig.visitorAdMultiplier.toInt(),
            }),
            sub:
                '[[coin]]${fmt(game.visitorCoins(withAd: true))}  [[star]]${GameConfig.visitorAdStars}',
            adFree: adFree,
            onTap: () => Navigator.pop(ctx, true),
          ),
          DialogPlainButton(
            label: '${tr('visitor.take')}  [[coin]]${fmt(base)}',
            onTap: () => Navigator.pop(ctx, false),
          ),
        ],
      ),
    );
    if (withAd == null) return;
    final ok = withAd ? await widget.ads.showRewarded() : false;
    if (withAd && !ok) {
      // 광고가 없으면 손님을 그대로 두고 알린다 (기본 보상으로 몰래 넘기지 않는다)
      _toast(tr('toast.adLoading'));
      Analytics.instance.adUnavailable();
      return;
    }
    final r = game.claimVisitor(withAd: ok); // 붙잡은 채로 받는다
    if (r != null && mounted) {
      RewardPopup.show(
        context,
        Reward(coins: r.coins.round(), stars: r.stars),
        title: tr('reward.visitor'),
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
  final _kShop = GlobalKey();
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
    // 진행은 계정 저장에 둔다 (새 계정은 같은 기기에서도 처음부터). 예전 저장만 기기 값
    var step = game.tutorial >= 0 ? game.tutorial : (p.getInt(_tutPref) ?? 0);
    // 이미 한참 진행한 플레이어에게는 다시 보여 주지 않는다
    if (step == 0 && (game.level >= 3 || game.totalMerges > 20))
      step = _tutDone;
    game.tutorial = step; // 판단한 단계를 저장에도 (리스너가 되돌리지 않게)
    if (mounted) setState(() => _tut = step);
    _tutLoaded = true;
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
    // 패키지로 받은 기간제 패스: 사흘 전 · 하루 전 · 끝난 날 한 번씩 (출석판과 겹치지 않게 다음 접속으로)
    else if (step == _tutDone && game.passNoticeDue != null) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _passNotice();
      });
    }
    // 레이아웃이 끝난 뒤 위치를 다시 잰다
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// 정원 패스 끝 알림: 구독으로 이어 가게.
  Future<void> _passNotice() async {
    final stage = game.passNoticeDue;
    if (stage == null) return;
    game.markPassNotice(stage);
    final days = (game.passLeft.inHours + 23) ~/ 24;
    final b = widget.billing;
    await showDialog<void>(
      context: context,
      builder: (ctx) => GameDialog(
        banner: 'gold',
        title: IconText(tr('pass.notice.title'), textAlign: TextAlign.center),
        onClose: () => Navigator.pop(ctx),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArtImage(Art.icon('garden_pass'), size: 96),
            const SizedBox(height: 8),
            IconText(
              tr('pass.notice.$stage', {'d': days}),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 6),
            IconText(
              tr('pass.notice.body', {
                'gems': OrderQuota.passDailyGems,
                'energy': OrderQuota.passEnergyCap,
                'quota': OrderQuota.pass,
                'cells': GameConfig.passVault.length,
              }),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF6B5A44)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: IconText(tr('pass.notice.later')),
          ),
          FilledButton(
            style: framedButton(FilledButton.styleFrom(), 'button_green'),
            onPressed: b.product == null
                ? null
                : () {
                    Navigator.pop(ctx);
                    b.buyRemoveAds();
                  },
            child: IconText(
              b.product == null
                  ? tr('shop.connecting')
                  : tr('pass.notice.keep', {'price': b.product!.price}),
            ),
          ),
        ],
      ),
    );
  }

  bool _tutLoaded = false;

  /// 로그인 뒤 클라우드 저장을 불러오면 튜토리얼 단계도 그 계정 것으로 (재설치한 기존 유저에게 다시 보이지 않게).
  void _syncTutorial() {
    if (!_tutLoaded || !mounted) return;
    final t = game.tutorial;
    if (t >= 0 && t != _tut) {
      setState(() => _tut = t);
    } else if (_tut != _tutDone &&
        _tut <= 1 &&
        (game.level >= 3 || game.totalMerges > 20)) {
      _setTutorial(_tutDone);
    }
  }

  Future<void> _setTutorial(int step) async {
    if (step == 1) Analytics.instance.tutorialBegin();
    if (step == _tutDone && _tut != _tutDone) {
      Analytics.instance.tutorialComplete();
    }
    setState(() => _tut = step);
    game.setTutorial(step);
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
    // 1단계: 판에 아이템이 3개 이상이고 합칠 짝이 있으면 다음으로
    // 2단계인데 합칠 짝이 없으면 (팔았거나 예전 저장) 바구니 단계로 돌아가 하나 더 꺼내게 (D-101)
    final hasPair = _mergePair() != null;
    if (_tut == 1 && game.board.whereType<Item>().length >= 3 && hasPair) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tut == 1) _setTutorial(2);
      });
    }
    if (_tut == 2 && !hasPair) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tut == 2 && _mergePair() == null) _setTutorial(1);
      });
    }
    void next() {
      sfx(Sfx.tap);
      _setTutorial(_tut >= 5 ? _tutDone : _tut + 1);
    }

    // 건너뛰기는 첫 합치기를 해 본 뒤부터 (첫 화면에서 건너뛰고 바로 나가는 사람이 많았다, 1.0.9)
    final skip = _tut >= 3 ? () => _setTutorial(_tutDone) : null;
    return switch (_tut) {
      0 => CoachOverlay(
        text: tr('tut.hello'),
        buttonLabel: tr('tut.next'),
        onNext: next,
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
        onSkip: skip,
        skipLabel: tr('tut.skip'),
      ),
      4 => CoachOverlay(
        text: tr('tut.decor'),
        hole: _rectOf(_kDecor),
        pointAt: _rectOf(_kDecor)?.center,
        buttonLabel: tr('tut.next'),
        onNext: next,
        onSkip: skip,
        skipLabel: tr('tut.skip'),
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
          GestureDetector(
            onTap: _xpInfo,
            child: _LevelBadge(
              level: game.level,
              progress: game.xp / game.xpToNext,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (_, box) {
                // 재화 줄은 폭에 맞춰 줄어든다: 그 안의 빨간 점만 원래 크기로 되돌린다 (D-086)
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final w = _kHudRow.currentContext?.size?.width;
                  if (w == null || w <= 0) return;
                  final s = min(1.0, box.maxWidth / w);
                  if (mounted && (s - _hudScale).abs() > 0.01) {
                    setState(() => _hudScale = s);
                  }
                });
                return _hudPills();
              },
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
                game.upgradeDot || game.hasNewDiscovery || widget.socialBadge()
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
        onLandmarkTap: (a) => showLandmarkSheet(context, game, a),
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
          // 오늘 부탁이 모두 끝: 작은 별 아이콘 (누르면 광고로 별 부탁 더 받기)
          if (game.ordersDoneToday && _viewArea == game.currentArea)
            Positioned(
              left: 8,
              bottom: 10,
              child: GestureDetector(
                onTap: _allDoneDialog,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                  decoration: BoxDecoration(
                    color: const Color(0xF2FFFBF0),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF7A5230),
                      width: 2,
                    ),
                  ),
                  child: IconText(
                    '${adFree ? '' : '[[ad]]'}[[star]]+${OrderQuota.perAd}',
                    iconScale: 1.1,
                    style: const TextStyle(fontSize: 14),
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
          // 안내 문구 대신 그 아이템의 도감 한 줄 (도감 팝업과 같은 모양, 한 줄로, D-087)
          extra: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '“${tr('lore.${o.chain.name}.${o.level}')}”',
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF8A6E4E),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              IconText(
                tr('order.reward', {
                  'stars': game.orderGivesStars(o) ? o.stars : 0,
                  'xp': Leveling.xpForOrder(game.relLevel(o.chain, o.level)),
                }),
                style: const TextStyle(fontSize: 16, color: Color(0xFF7A5230)),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        onClose: () => Navigator.pop(ctx, false),
        actions: [
          // 다른 부탁: 새로고침 그림 + 다른 버튼과 같은 초록 버튼 · 글자 (D-087)
          FilledButton(
            style: framedButton(
              FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
              'button_green',
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: IconText(
              game.freeRerollsLeft > 0
                  ? '[[refresh]] ${tr('order.changeFree', {'n': game.freeRerollsLeft})}'
                  : '${adFree ? '' : '[[ad]] '}[[refresh]] ${tr('order.change')}',
              style: const TextStyle(fontSize: 18),
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
                    'v': fmt(game.itemIncomePerHour(sel)),
                  }),
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ),

            if (game.isMaxItem(sel) && game.friends.isNotEmpty) ...[
              FilledButton(
                style: plainButton(
                  FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE8739A),
                    minimumSize: const Size(40, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                onPressed: () => _giftDialog(idx),
                child: IconText(
                  tr('board.gift'),
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
    final cheap = game.cheapestSellCell;
    if (cheap != null) {
      // 꽉 막혔을 때만: 가장 덜 아까운 아이템 하나를 골라 준다 (누르면 그 아이템이 선택되고, 팔지는 직접)
      return card(
        GestureDetector(
          onTap: () => setState(() => _selected = cheap),
          child: IconText(
            tr('board.stuckPick'),
            style: const TextStyle(fontSize: 14, color: Color(0xFFB0640A)),
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
      game.eventClaimable +
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
        // 이달의 이벤트 (D-112): 그림이 들어온 달만
        if (game.currentEvent != null)
          MenuEntry(
            Art.icon('event_calendar').available ? 'event_calendar' : 'party',
            tr('menu.event'),
            () => showEventSheet(
              context,
              widget.billing,
              game,
              watchAd: _rewardedCapped,
            ),
            badge: game.eventClaimable,
          ),
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
            if (_gate(Feature.upgrades)) {
              game.markUpgradesSeen();
              showUpgradesSheet(context, game, onRenew: _renew);
            }
          },
          badge: game.upgradeDot ? -1 : 0,
        ),
        if (game.friends.any(
          (id) => Art.outfitsFor(Friends.byId(id)).isNotEmpty,
        ))
          MenuEntry(
            'outfit',
            tr('menu.wardrobe'),
            () => showWardrobePicker(context, game),
          ),
        MenuEntry('book', tr('menu.book'), () {
          // 열기 전에 본 단계를 기억해 두고 '새로 발견'을 보여 준다 (D-095)
          final before = Map<Chain, int>.of(game.seenHighest);
          game.markBookSeen();
          showCollectionSheet(context, game, seenBefore: before);
        }, badge: game.hasNewDiscovery ? -1 : 0),
        if (widget.openFriends != null)
          MenuEntry(
            'friends',
            tr('menu.friends'),
            () => widget.openFriends!(context),
            badge: widget.socialBadge() ? -1 : 0,
            fallback: Icons.people_alt_rounded,
          ),
        // 정원 패스 이용 중: 혜택 보기 (D-074)
        if (game.passActive)
          MenuEntry(
            'garden_pass',
            tr('menu.removeAds'),
            () =>
                showPassSheet(context, game, subscribed: widget.billing.adFree),
          ),
        // 부스트: 가진 것 쓰기 · 광고 · 다이아로 바로 켜기 (상점은 오른쪽 아래로, D-075)
        MenuEntry(
          game.isUnlocked(Feature.boost) ? 'boost' : 'lock',
          tr('ctrl.boost'),
          _watchBoost,
          badge:
              game.isUnlocked(Feature.boost) &&
                  BoostKind.values.any((k) => game.boostTokenCount(k) > 0) &&
                  BoostKind.values.every((k) => !game.boosted(k))
              ? -1
              : 0,
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
              badge: canDecorate || game.designDotAny,
              onTap: () {
                sfx(Sfx.open);
                setState(() => _viewArea = game.currentArea);
                game.markDesignSeen();
                showDecorSheet(context, game);
              },
            ),
          ),
          SizedBox(width: game.openBaskets.length > 1 ? 4 : 10),
          _Spawner(
            key: _kSpawner,
            game: game,
            onTap: _onSpawnerTap,
            onLongPress: _energyDialog,
          ),
          SizedBox(width: game.openBaskets.length > 1 ? 4 : 10),
          // 오른쪽 아래 = 상점 (D-075). 켜진 부스트가 있으면 남은 시간을 작게 보여 준다
          Expanded(
            child: _BarTile(
              key: _kShop,
              icon: 'shop',
              label: tr('menu.shop'),
              sub: activeBoosts.isNotEmpty ? boostLine() : tr('ctrl.shop.sub'),
              badge: game.shopDot,
              onTap: _openShop,
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
    final multi = open.length > 1;
    // 지금 바구니로는 못 만드는 부탁이 다른 바구니에 있으면 그쪽 화살표를 반짝인다
    int? wantDir;
    if (multi) {
      final cur = open.indexOf(game.basket);
      for (var i = 0; i < game.orders.length; i++) {
        final o = game.orders[i];
        if (game.canDeliver(i) || !game.orderGivesStars(o)) continue;
        final b = open.indexWhere((b) => Chains.baskets[b].contains(o.chain));
        if (b < 0 || b == cur) continue;
        final fwd = (b - cur + open.length) % open.length;
        wantDir = fwd <= open.length - fwd ? 1 : -1;
        break;
      }
    }
    Widget arrow(int dir) {
      final target = multi
          ? open[(open.indexOf(game.basket) + dir + open.length) % open.length]
          : 0;
      return _BasketArrow(
        dir: dir,
        icon: target == 0 ? Art.basket : Art.icon(Chains.basketIcon[target]),
        hot: wantDir == dir,
        onTap: () => swipe(dir),
      );
    }

    final ring = GestureDetector(
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
                value: full || game.energy >= game.energyCap
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
            // 충전식 바구니: 남은 횟수 (0이면 다음 충전까지 시간)
            if (Chains.basketCharges[game.basket] > 0)
              Positioned(
                top: -6,
                right: -10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: game.basketReady(game.basket)
                        ? const Color(0xFF5FA05A)
                        : const Color(0xFFB0A48C),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    game.basketReady(game.basket)
                        ? tr('spawner.charges', {
                            'n': game.basketChargesLeft(game.basket),
                          })
                        : _shortLeft(game.basketNextIn(game.basket)),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      height: 1.2,
                    ),
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
    if (!multi) return ring;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [arrow(-1), ring, arrow(1)],
    );
  }
}

/// 바구니 옆 작은 화살표: 누르면 옆 바구니로. 다음 바구니 그림이 살짝 보이고,
/// 그 바구니가 필요한 부탁이 있으면 노랗게 통통 튄다.
class _BasketArrow extends StatefulWidget {
  const _BasketArrow({
    required this.dir,
    required this.icon,
    required this.hot,
    required this.onTap,
  });
  final int dir;
  final ArtRef icon;
  final bool hot;
  final VoidCallback onTap;

  @override
  State<_BasketArrow> createState() => _BasketArrowState();
}

class _BasketArrowState extends State<_BasketArrow>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void initState() {
    super.initState();
    if (widget.hot) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_BasketArrow old) {
    super.didUpdateWidget(old);
    if (widget.hot && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.hot && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hot = widget.hot;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.translate(
          offset: Offset(
            widget.dir * 4 * Curves.easeOut.transform(_c.value),
            0,
          ),
          child: child,
        ),
        child: SizedBox(
          width: 24,
          height: 70,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: hot ? 1 : 0.75,
                child: ArtImage(widget.icon, size: 18),
              ),
              if (Art.icon('chevron').available)
                Transform.flip(
                  flipX: widget.dir < 0,
                  child: ArtImage(Art.icon('chevron'), size: 24),
                )
              else
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hot ? const Color(0xFFFFD45C) : Colors.white,
                    border: Border.all(
                      color: hot
                          ? const Color(0xFFB57A12)
                          : const Color(0x55000000),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    widget.dir < 0
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    size: 20,
                    color: hot
                        ? const Color(0xFF6B4300)
                        : const Color(0xFF5E5242),
                  ),
                ),
            ],
          ),
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
    this.badge = false,
  });
  final String icon;
  final String label;
  final String? sub;
  final VoidCallback? onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    const colors = [Color(0xFFFFFBF0), Color(0xFFF3E6C8)];
    const ink = Color(0xFF4A3A22);
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
                ArtImage(Art.icon(icon), size: 36),
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
          if (badge) const Positioned(right: -4, top: -4, child: RedDot()),
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

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.label, required this.onTap, this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (label == 'expand' && Art.icon('expand').available) {
      return GestureDetector(
        onTap: () {
          sfx(Sfx.tap);
          onTap();
        },
        child: ArtImage(Art.icon('expand'), size: 38),
      );
    }
    return _plain();
  }

  Widget _plain() => GestureDetector(
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
              if (Art.icon('plus').available)
                ArtImage(Art.icon('plus'), size: 22)
              else
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
      // 크림색 말풍선 카드 (게임 창과 같은 갈색 테두리), 한 줄로 줄여 맞춤
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: const Color(0xF7FFF8EA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF7A5230), width: 2.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        // 알림은 한 줄 (문구를 짧게 쓴다: 한국어 약 20자 안). 넘치면 조금만 줄인다
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: IconText(
            text,
            maxLines: 1,
            textAlign: TextAlign.center,
            iconScale: 1.15,
            style: const TextStyle(color: Color(0xFF3A2E22), fontSize: 16),
          ),
        ),
      ),
    );
  }
}

/// 새 구역이 열렸을 때 (D-085): 여러 장으로. ① 구역 · 장식 ② 새 친구 ③ 새 바구니 (있을 때만).
Future<void> showNewAreaDialog(BuildContext context, GameState game, int area) {
  sfx(Sfx.levelup);
  final def = Garden.areaAt(area);
  final newFriends = [
    for (final d in def.decor)
      if (d.bringsFriend != null && !game.friends.contains(d.bringsFriend))
        d.bringsFriend!,
  ];
  final baskets = game.takeNewBaskets();
  return _showPages(context, tr('area.newTitle'), [
    _areaPage(def),
    if (newFriends.isNotEmpty) _friendsPage(newFriends),
    for (final b in baskets) _basketPage(b),
  ]);
}

/// 레벨이 올라 바구니만 새로 열렸을 때 (구역은 이미 열려 있던 경우).
Future<void> showNewBasketDialog(BuildContext context, List<int> baskets) {
  sfx(Sfx.levelup);
  return _showPages(context, tr('basket.newTitle'), [
    for (final b in baskets) _basketPage(b),
  ]);
}

Future<void> _showPages(
  BuildContext context,
  String title,
  List<Widget> pages,
) => showDialog<void>(
  context: context,
  builder: (ctx) => _PagedDialog(title: title, pages: pages),
);

class _PagedDialog extends StatefulWidget {
  const _PagedDialog({required this.title, required this.pages});
  final String title;
  final List<Widget> pages;

  @override
  State<_PagedDialog> createState() => _PagedDialogState();
}

class _PagedDialogState extends State<_PagedDialog> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final last = _i == widget.pages.length - 1;
    return GameDialog(
      banner: 'gold',
      title: IconText(widget.title, textAlign: TextAlign.center),
      onClose: () => Navigator.pop(context),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0.15, 0),
                  end: Offset.zero,
                ).animate(a),
                child: child,
              ),
            ),
            child: KeyedSubtree(key: ValueKey(_i), child: widget.pages[_i]),
          ),
          if (widget.pages.length > 1) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var k = 0; k < widget.pages.length; k++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: k == _i ? 18 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: k == _i
                          ? Palette.primary
                          : const Color(0xFFD9CBB0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          style: framedButton(
            FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
            ),
            last ? 'button_gold' : 'button_green',
          ),
          onPressed: () {
            sfx(Sfx.tap);
            if (last) {
              Navigator.pop(context);
            } else {
              setState(() => _i++);
            }
          },
          child: IconText(
            tr(last ? 'area.newGo' : 'area.next'),
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ],
    );
  }
}

const _ink = Color(0xFF5E4B36);

Widget _pageTitle(String s) => Padding(
  padding: const EdgeInsets.only(top: 10, bottom: 8),
  child: IconText(
    s,
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 24, color: Color(0xFF5C402C)),
  ),
);

/// ① 새 구역 배경 + 장식 8종.
Widget _areaPage(AreaDef def) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.elasticOut,
      builder: (_, v, child) =>
          Transform.scale(scale: 0.6 + 0.4 * v, child: child),
      child: Container(
        height: 150,
        // 테두리는 그림 위에 (foregroundDecoration)
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF7A5230), width: 3),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(Art.areaBackground(def).path, fit: BoxFit.cover),
            Align(
              alignment: const Alignment(-0.88, -0.78),
              child: ArtImage(Art.areaIcon(def), size: 44),
            ),
          ],
        ),
      ),
    ),
    _pageTitle(areaName(def)),
    for (var row = 0; row < def.decor.length; row += 4)
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final d in def.decor.skip(row).take(4))
            Padding(
              padding: const EdgeInsets.all(3),
              child: ArtImage(Art.decor(d), size: 46),
            ),
        ],
      ),
    const SizedBox(height: 8),
    IconText(
      tr('area.newNote', {'n': def.decor.length}),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 15, color: _ink),
    ),
  ],
);

/// ② 새로 올 친구들.
Widget _friendsPage(List<String> ids) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    const SizedBox(height: 6),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final f in ids)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GlowHalo(
              size: 130,
              child: ArtImage(
                Art.friend(Friends.byId(f), happy: true),
                size: 96,
              ),
            ),
          ),
      ],
    ),
    _pageTitle(tr('area.friendsTitle')),
    IconText(
      ids.map(friendName).join(', '),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 18, color: Palette.primary),
    ),
    const SizedBox(height: 6),
    IconText(
      tr('area.friendsNote'),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 15, color: _ink),
    ),
  ],
);

/// ③ 새 바구니: 바구니 그림 + 나오는 아이템 1~4단계.
Widget _basketPage(int b) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    GlowHalo(
      size: 150,
      child: ArtImage(Art.icon(Chains.basketIcon[b]), size: 100),
    ),
    _pageTitle(tr('basket.newName', {'name': tr('basket.$b')})),
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final c in Chains.baskets[b])
          for (var lv = 1; lv <= 4; lv++) ...[
            ArtImage(Art.item(c, lv), size: 40),
            if (lv < 4)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 1),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Color(0xFFB89A6E),
                ),
              ),
          ],
      ],
    ),
    const SizedBox(height: 8),
    IconText(
      tr('basket.newNote', {
        'chain': Chains.baskets[b].map(chainName).join(' · '),
      }),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 15, color: _ink),
    ),
  ],
);
