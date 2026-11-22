import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'config.dart';
import 'tuning.dart';
import 'meta.dart';

export 'meta.dart';

class Item {
  final int id;
  final Chain chain;
  int level;

  /// 비눗방울 아이템이면 터지는 시각. 광고를 보면 꺼낼 수 있다. null 이면 보통 아이템.
  DateTime? bubbleUntil;

  Item(this.id, this.chain, this.level, {this.bubbleUntil});

  bool get isBubble => bubbleUntil != null;
  ItemDef get def => Chains.item(chain, level);

  Map<String, dynamic> toJson() => {
    'i': id,
    'c': chain.index,
    'l': level,
    if (bubbleUntil != null) 'b': bubbleUntil!.millisecondsSinceEpoch,
  };

  static Item fromJson(Map<String, dynamic> j) => Item(
    j['i'] as int,
    Chain.values[j['c'] as int],
    j['l'] as int,
    bubbleUntil: j['b'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(j['b'] as int),
  );
}

class Order {
  final int id;
  final String friendId;
  final Chain chain;
  final int level;
  final int stars;
  const Order(this.id, this.friendId, this.chain, this.level, this.stars);

  ItemDef get item => Chains.item(chain, level);

  Map<String, dynamic> toJson() => {
    'i': id,
    'f': friendId,
    'c': chain.index,
    'l': level,
    's': stars,
  };
  static Order fromJson(Map<String, dynamic> j) => Order(
    j['i'] as int,
    j['f'] as String,
    Chain.values[j['c'] as int],
    j['l'] as int,
    j['s'] as int,
  );
}

/// 오늘의 시장 한 칸.
class ShopOffer {
  final Chain chain;
  final int level;
  final int price;
  bool sold;

  /// 0 보통 · 1 오늘의 무료 선물 · 2 부탁 도우미(지금 부탁의 한 단계 아래) · 3 다이아로 사는 고단계 · 4 광고 보고 받는 고단계.
  final int kind;
  ShopOffer(
    this.chain,
    this.level,
    this.price, {
    this.sold = false,
    this.kind = 0,
  });

  Map<String, dynamic> toJson() => {
    'c': chain.index,
    'l': level,
    'p': price,
    if (sold) 's': true,
    if (kind != 0) 'k': kind,
  };
  static ShopOffer fromJson(Map<String, dynamic> j) => ShopOffer(
    Chain.values[(j['c'] as num).toInt()],
    (j['l'] as num).toInt(),
    (j['p'] as num).toInt(),
    sold: j['s'] == true,
    kind: (j['k'] as num?)?.toInt() ?? 0,
  );
}

enum BuyResult { ok, noCoins, noGems, noSpace, sold, needAd }

enum StyleResult { ok, noCoins, noGems, notPlaced }

class _Sale {
  final int cell;
  final Item item;
  final double price;
  final DateTime at;
  _Sale(this.cell, this.item, this.price, this.at);
}

enum TapResult { spawned, noEnergy, boardFull, basketEmpty }

enum MoveResult { none, moved, swapped, merged, maxMerged }

sealed class GameEvent {}

class DiscoveryEvent extends GameEvent {
  final Chain chain;
  final int level;
  final double bonus;
  DiscoveryEvent(this.chain, this.level, this.bonus);
}

class MaxMergeEvent extends GameEvent {
  final double payout;
  MaxMergeEvent(this.payout);
}

class OrderDeliveredEvent extends GameEvent {
  final String friendId;
  final int stars;
  final double coins;
  final bool affectionUp;
  final int xp;
  OrderDeliveredEvent(
    this.friendId,
    this.stars,
    this.coins,
    this.affectionUp, [
    this.xp = 0,
  ]);
}

class DecorPlacedEvent extends GameEvent {
  final int area;
  final int slot;
  DecorPlacedEvent(this.area, this.slot);
}

class FriendJoinedEvent extends GameEvent {
  final String friendId;
  FriendJoinedEvent(this.friendId);
}

class AreaCompletedEvent extends GameEvent {
  final int area;
  AreaCompletedEvent(this.area);
}

class LevelUpEvent extends GameEvent {
  final int level;
  final List<Feature> unlocked;
  final double coins;
  final int stars;
  final int energy;
  LevelUpEvent(this.level, this.unlocked, this.coins, this.stars, this.energy);
}

/// 합치기 연출용 (UI 이펙트 레이어가 사용).
class MergedEvent extends GameEvent {
  final int cell;
  final int level;
  MergedEvent(this.cell, this.level);
}

class BubbleEvent extends GameEvent {
  final int cell;
  BubbleEvent(this.cell);
}

/// 에너지가 바닥나 바구니를 못 눌렀다 (바닥날 때마다 한 번).
class EnergyEmptyEvent extends GameEvent {}

/// 계절 세트(한 구역 8종)를 다 모았다.
class MaxGiftEvent extends GameEvent {
  final String friendId;
  final double coins;
  final int stars;
  final Chain chain;
  final int level;
  MaxGiftEvent(this.friendId, this.coins, this.stars, this.chain, this.level);
}

class OrderMilestoneEvent extends GameEvent {
  final int count;
  final int gems;
  OrderMilestoneEvent(this.count, this.gems);
}

class RenewEvent extends GameEvent {
  final int round;
  final int seeds;
  RenewEvent(this.round, this.seeds);
}

class SeasonSetEvent extends GameEvent {
  final int area;
  final int style;
  SeasonSetEvent(this.area, this.style);
}

/// 보상형 광고를 끝까지 봤다.
/// 다이아를 썼다 (어디에 · 얼마나) — 분석용.
/// 랜드마크를 세웠거나 그림 단계가 올랐다 (D-048).
class LandmarkEvent extends GameEvent {
  final int area;
  final int level;
  final bool newStage;
  LandmarkEvent(this.area, this.level, {required this.newStage});
}

/// 생산력 강화가 25단계 고비를 넘어 ×2 가 됐다 (D-048).
class UpgradeMilestoneEvent extends GameEvent {
  final UpgradeType type;
  final int level;
  UpgradeMilestoneEvent(this.type, this.level);
}

class GemsSpentEvent extends GameEvent {
  final int amount;
  final String what;
  GemsSpentEvent(this.amount, this.what);
}

class AdRewardEvent extends GameEvent {
  final String kind;
  AdRewardEvent(this.kind);
}

class SoldEvent extends GameEvent {
  final Item item;
  final double price;
  SoldEvent(this.item, this.price);
}

class OfflineReward {
  final Duration away;
  final double coins;
  const OfflineReward(this.away, this.coins);
}

/// 게임의 모든 규칙과 상태. UI·광고·저장소와 분리되어 있어 단위 테스트할 수 있다.
class GameState extends ChangeNotifier {
  GameState({Random? random, DateTime Function()? clock})
    : _rng = random ?? Random(),
      _clock = clock ?? DateTime.now {
    lastSeen = _clock();
    nextVisitorAt = _clock().add(GameConfig.visitorMinGap);
    _fillOrders();
    _sendWelcome();
  }

  final Random _rng;
  final DateTime Function() _clock;
  final _events = StreamController<GameEvent>.broadcast();
  Stream<GameEvent> get events => _events.stream;

  double coins = 0;
  int stars = 0;
  double lifetimeCoins = 0;

  // ---- 튜토리얼 · 기능 안내 (계정 저장, 기기 설정이 아니라): -1 = 예전 저장(기기 값 사용)
  int tutorial = 0;
  final Set<String> tipsSeen = {};
  bool tipsKnown = true;
  void setTutorial(int step) {
    tutorial = step;
    notifyListeners();
  }

  // ---- 정원 재단장 (D-031)
  /// 몇 번째 회차인가 (1부터).
  int renewCount = 1;

  /// 지금까지 받은 황금 씨앗 (영구 수입 배율) · 쓸 수 있는 씨앗.
  int seedsTotal = 0;
  int seeds = 0;

  /// 공식으로 받은 씨앗 (광고 보너스 제외). 받을 씨앗 = 누적 코인으로 정해지는 몫 − 이 값 (D-038).
  int seedsClaimed = 0;

  /// 이번 회차가 시작될 때의 누적 코인 (이번 회차에 번 코인 = lifetimeCoins − 이 값).
  double runStartCoins = 0;
  final Map<SeedPerk, int> seedPerks = {};
  int perkLv(SeedPerk p) => seedPerks[p] ?? 0;

  double get runCoins => max(0, lifetimeCoins - runStartCoins);
  double get seedMultiplier => 1 + Renewal.seedIncome * seedsTotal;

  /// 지금까지 번 모든 코인으로 정해지는 씨앗 몫 (쿠키 클리커 · 애드캡 방식: 같은 지점에서 다시 해도 0).
  int get seedsEntitled => Renewal.seedsFor(lifetimeCoins);
  bool get canRenew =>
      lv(UpgradeType.basketTier) >= Renewal.needBasketTier &&
      renewSeedsPreview > 0;
  int get renewSeedsPreview => max(0, seedsEntitled - seedsClaimed);

  /// 다음 씨앗 1개까지 더 벌어야 하는 코인.
  double get coinsToNextSeed => max(
    0,
    Renewal.coinsForSeeds(max(seedsEntitled, seedsClaimed) + 1) - lifetimeCoins,
  );

  /// 재단장 추천: 받을 씨앗이 가진 씨앗의 절반(최소 3) 이상이거나, 살 수 있는 강화가 30분 넘게 없을 때.
  double _noBuySecs = 0;
  bool get renewRecommended =>
      canRenew &&
      (renewSeedsPreview >= max(3, seedsTotal ~/ 2) || _noBuySecs >= 1800);

  /// 재단장하면 바뀌는 영구 수입 배율.
  double get seedMultiplierAfterRenew =>
      1 + Renewal.seedIncome * (seedsTotal + renewSeedsPreview);

  // ---- 하루 부탁 단계 보상 (D-032)
  String _ordersDay = '';
  int _ordersToday = 0;
  int get ordersToday {
    _rollOrdersDay();
    return _ordersToday;
  }

  void _rollOrdersDay() {
    final k = _dayKey(now);
    if (k == _ordersDay) return;
    _ordersDay = k;
    _ordersToday = 0;
  }

  /// 다음 단계 보상 (없으면 null): (목표 수, 다이아).
  (int, int)? get nextOrderMilestone {
    final n = ordersToday;
    for (var i = 0; i < GameConfig.orderMilestones.length; i++) {
      if (n < GameConfig.orderMilestones[i]) {
        return (
          GameConfig.orderMilestones[i],
          GameConfig.orderMilestoneGems[i],
        );
      }
    }
    return null;
  }

  /// 광고 보고 다이아 (하루 5번).
  bool get gemAdAvailable => canWatchAd(AdKind.gems);
  void grantGemAd() {
    gems += GameConfig.adGems;
    notifyListeners();
  }

  /// 최대 에너지 (씨앗 강화 '에너지 통'으로 +10씩).
  int get energyCap =>
      GameConfig.energyCap +
      10 * perkLv(SeedPerk.energyJar) +
      setBonus(SetEffect.energyCap).round();

  bool canBuyPerk(SeedPerk p) {
    final d = Renewal.of(p);
    return perkLv(p) < d.maxLevel && seeds >= d.costAt(perkLv(p));
  }

  bool buyPerk(SeedPerk p) {
    if (!canBuyPerk(p)) return false;
    seeds -= Renewal.of(p).costAt(perkLv(p));
    seedPerks[p] = perkLv(p) + 1;
    notifyListeners();
    return true;
  }

  /// 정원 재단장: 판 · 코인 · 바구니 등급 · 생산력/수익 강화를 처음부터, 씨앗을 받는다.
  /// 정원 · 구역 · 친구 · 하트 · 레벨 · 도감 · 업적 · 다이아 · 의상 · 에너지/오프라인/품질 강화는 그대로.
  int renew({bool withAd = false}) {
    if (!canRenew) return 0;
    final base = renewSeedsPreview;
    final got = withAd ? (base * Renewal.adBonus).round() : base;
    final lastRun = runCoins;
    seedsClaimed += base;
    seedsTotal += got;
    seeds += got;
    renewCount += 1;
    for (var i = 0; i < board.length; i++) {
      // 다이아로 산 보관 칸의 아이템은 남긴다
      if (GameConfig.isVault(i)) continue;
      board[i] = null;
    }
    for (final t in [
      UpgradeType.flowerPower,
      UpgradeType.snackPower,
      UpgradeType.teaPower,
      UpgradeType.stardustPower,
      UpgradeType.income,
    ]) {
      upgrades.remove(t);
    }
    upgrades[UpgradeType.basketTier] = perkLv(SeedPerk.startBasket);
    if (perkLv(SeedPerk.autoMemory) == 0)
      upgrades.remove(UpgradeType.autoMerge);
    coins = lastRun * 0.01 * perkLv(SeedPerk.startCoins);
    runStartCoins = lifetimeCoins;
    _featured = null;
    orders.clear();
    energy = max(energy, energyCap);
    _fillOrders();
    _trace('renew', '$renewCount,$got,${lastRun.round()}');
    _events.add(RenewEvent(renewCount, got));
    notifyListeners();
    return got;
  }

  int level = 1;
  int xp = 0;
  int energy = GameConfig.energyStart;
  double energyProgress = 0;

  /// 오늘 본 보상형 광고 수 (종류별). 날짜가 바뀌면 초기화.
  final Map<AdKind, int> adsToday = {};
  String _adsDay = '';
  List<Item?> board = List<Item?>.filled(GameConfig.cellCount, null);
  Set<int> unlockedCells = {...GameConfig.startCells};

  /// 보관함 (길이 = 열린 칸 수, 빈 칸은 null).
  List<Item?> storage = List<Item?>.filled(Storage.startSlots, null);
  int _nextId = 1;
  final Map<UpgradeType, int> upgrades = {
    for (final u in UpgradeType.values) u: 0,
  };
  double autoMergeProgress = 0;
  final Map<Chain, int> highest = {for (final c in Chain.values) c: 1};

  int currentArea = 0; // 지금 꾸미는 구역 (이전 구역은 모두 완성)
  Set<int> placed = {}; // 현재 구역에 설치한 장식 슬롯

  /// 친구 의상: 친구 id → 입은 의상 id, 산 의상 'friend:outfit'.
  Map<String, String> outfits = {};
  Set<String> ownedOutfits = {};

  /// 장식 디자인: 'area:slot' → 고른 디자인(0 기본 · 1 고급 · 2 특별), 산 디자인 'area:slot:v'.
  Map<String, int> decorStyle = {};
  Set<String> ownedStyles = {};
  Set<String> friends = {Friends.starter};
  final Map<String, int> deliveries = {};
  List<Order> orders = [];

  /// 시간제 부스트가 끝나는 시각.
  final Map<BoostKind, DateTime> boosts = {};

  /// 친구 부탁 하루 한도 (친구 id → 오늘 별 받은 횟수 / 광고로 늘린 횟수), 오늘 부탁 바꾸기 횟수.
  final Map<String, int> starOrdersUsed = {};
  final Map<String, int> starOrdersBonus = {};
  String _quotaDay = '';
  int rerollsToday = 0;

  /// 다이아로 영구 해금한 보관 칸 (맨 아랫줄).
  Set<int> vaultOwned = {};

  /// 기간제 정원 패스 (새싹 정원 패키지 등). 구독(adFree)과 같은 혜택.
  DateTime? passUntil;

  /// 새싹 정원 패키지: 샀는지 · 한정 타이머 끝 · 몇 번 보여 줬는지.
  bool starterBought = false;

  /// 친구 초대 (D-045): 나를 초대한 사람 · 그때, 보상을 받은 초대 친구, 마지막으로 공유 보상을 받은 날.
  String? invitedBy;
  DateTime? invitedAt;
  final Set<String> inviteRewarded = {};
  String shareDay = '';

  /// 초대 환영 선물을 받을 수 있는 새 계정인지.
  bool get canBeInvited =>
      invitedBy == null && level <= Invite.newPlayerMaxLevel;

  /// 초대 코드로 시작: 환영 선물을 쪽지로 (계정당 한 번).
  bool acceptInvite(String inviterUid, String inviterName) {
    if (!canBeInvited || inviterUid.isEmpty) return false;
    invitedBy = inviterUid;
    invitedAt = now;
    addMail(
      Mail(
        id: 'invite-welcome',
        kind: MailKind.social,
        from: inviterName,
        titleKey: 'mail.inviteWelcome',
        args: {'name': inviterName},
        reward: const Reward(gems: Invite.welcomeGems),
        at: now,
      ),
    );
    _trace('invite', 'accepted');
    notifyListeners();
    return true;
  }

  /// 초대한 친구가 조건을 채웠다: 초대 보상 (친구마다 한 번, 최대 [Invite.maxRewards]명).
  bool grantInviteReward(String friendUid, String friendName) {
    if (inviteRewarded.contains(friendUid) ||
        inviteRewarded.length >= Invite.maxRewards) {
      return false;
    }
    inviteRewarded.add(friendUid);
    addMail(
      Mail(
        id: 'invite-$friendUid',
        kind: MailKind.social,
        from: friendName,
        titleKey: 'mail.inviteReward',
        args: {'name': friendName},
        reward: const Reward(gems: Invite.rewardGems),
        at: now,
      ),
    );
    _trace('invite', 'reward');
    notifyListeners();
    return true;
  }

  /// 오늘 공유 보상을 아직 받지 않았는지.
  bool get shareRewardReady => shareDay != _dayKey(now);

  /// 자랑하기: 하루 한 번 에너지. 받았으면 그 양.
  int claimShareReward() {
    if (!shareRewardReady) return 0;
    shareDay = _dayKey(now);
    energy += Invite.shareEnergy;
    _trace('share', '+${Invite.shareEnergy}');
    notifyListeners();
    return Invite.shareEnergy;
  }

  /// 한 번이라도 산 다이아 팩 (팩마다 첫 구매는 다이아 2배, D-042).
  final Set<String> boughtPacks = {};
  bool firstPackBonus(GemPack p) => !boughtPacks.contains(p.id);
  DateTime? starterOfferUntil;
  int starterShows = 0;

  /// 아직 켜지 않은 부스트 (패키지로 받은 것, 분 단위).
  final Map<BoostKind, int> boostTokens = {};

  /// 가진 정원 효과 · 켜 둔 효과.
  Set<String> effects = {};
  String? effectOn;

  /// 지금 활성 게임 (광고 서비스가 기간제 패스를 확인할 때).
  static GameState? active;
  String _passDay = '';
  DateTime? coinBagReadyAt;
  late DateTime lastSeen;
  late DateTime nextVisitorAt;
  DateTime? visitorUntil;
  int totalMerges = 0;

  /// 마지막 저장 시각 (클라우드 동기화 시 최신 판단용).
  DateTime? savedAt;

  final Map<String, DateTime> _friendTapReady = {};
  _Sale? _lastSale;

  // ---- 업적 · 쪽지
  final Map<Stat, int> stats = {};

  /// 업적별 받은 단계 수.
  final Map<String, int> achClaimed = {};
  List<Mail> mail = [];
  DateTime? nextFriendGiftAt;

  /// 7일 출석: 이번 주기에서 받은 날 수(0~6) · 마지막으로 받은 날.
  int checkInCount = 0;
  String _checkInDay = '';

  /// 오늘의 시장 (날이 바뀌면 새로 차린다).
  List<ShopOffer> _offers = [];
  String _offersDay = '';

  /// 다이아 (하드 통화) · 오늘 다이아로 에너지를 산 횟수.
  int gems = 0;
  int _gemRefillsToday = 0;
  String _playDay = '';
  bool _welcomeSent = false;

  /// 도감에서 이미 본 최고 단계 (새 발견 빨간 점용).
  final Map<Chain, int> seenHighest = {for (final c in Chain.values) c: 1};

  /// 최근 전달한 부탁 (종류-단계), 최대 3개. 새 부탁이 같은 것을 바로 다시 원하지 않게.
  final List<String> _recentOrders = [];

  /// 결제 서비스가 넣어준다 (저장하지 않음).
  bool adFree = false;

  // ---------------------------------------------------------------- 파생 값

  DateTime get now => _clock();

  bool isUnlocked(Feature f) => level >= (Leveling.unlockLevel[f] ?? 1);
  int get xpToNext => Leveling.xpToNext(level);

  List<Chain> get availableChains => [
    Chain.flower,
    if (isUnlocked(Feature.snack)) Chain.snack,
    for (var b = 1; b < Chains.baskets.length; b++)
      if (basketOpen(b)) ...Chains.baskets[b],
  ];

  /// 바구니(생성기) — 하단 바구니를 좌우로 넘겨 고른다 (바이블 D-013).
  int basket = 0;

  /// 구역 바구니 남은 횟수 (충전식).
  late final List<double> basketCharge = [
    for (final c in Chains.basketCharges) c.toDouble(),
  ];
  bool basketReady(int b) =>
      Chains.basketCharges[b] <= 0 || basketCharge[b] >= 1;
  int basketChargesLeft(int b) => basketCharge[b].floor();

  /// 다음 1회가 차기까지 남은 시간.
  Duration basketNextIn(int b) {
    final r = Chains.basketRechargeSec[b];
    if (r <= 0 || basketCharge[b] >= Chains.basketCharges[b]) {
      return Duration.zero;
    }
    final frac = basketCharge[b] - basketCharge[b].floor();
    return Duration(seconds: ((1 - frac) * r).ceil());
  }

  void _rechargeBaskets(double dt) {
    for (var b = 0; b < basketCharge.length; b++) {
      final r = Chains.basketRechargeSec[b];
      if (r <= 0) continue;
      basketCharge[b] = min(
        Chains.basketCharges[b].toDouble(),
        basketCharge[b] + dt / r,
      );
    }
  }

  bool basketOpen(int b) =>
      b == 0 ||
      (b < Chains.baskets.length &&
          currentArea >= Chains.basketArea[b] &&
          level >= Leveling.areaLevel(Chains.basketArea[b]) &&
          Chains.baskets[b].every(Chains.ready));

  List<int> get openBaskets => [
    for (var b = 0; b < Chains.baskets.length; b++)
      if (basketOpen(b)) b,
  ];

  void selectBasket(int b) {
    if (!basketOpen(b) || b == basket) return;
    basket = b;
    notifyListeners();
  }

  int lv(UpgradeType t) => upgrades[t] ?? 0;

  int affection(String friendId) => min(
    Friends.maxAffection,
    (deliveries[friendId] ?? 0) ~/ Friends.deliveriesPerAffection,
  );

  /// 친구 레벨 (강화로 올림). 하트(호감도)보다 높을 수 없다.
  final Map<String, int> friendLevels = {};
  int friendLevel(String id) => friendLevels[id] ?? 0;
  bool canLevelFriend(String id) =>
      friends.contains(id) &&
      friendLevel(id) < Friends.maxAffection &&
      friendLevel(id) < affection(id) &&
      coins >= friendLevelCost(id);

  /// 고정 가격 소모처(친구 레벨 · 칸 · 고급 장식)는 바구니 등급만큼 물가가 오른다 (수입 인플레이션을 따라감).
  double get inflation =>
      pow(GameConfig.valueGrowth, spawnLevel - 1).toDouble();
  double friendLevelCost(String id) =>
      Friends.levelCost(friendLevel(id)) * inflation;
  double styleCost(int area, int slot) =>
      Garden.styleCoins(area, slot) * inflation;

  bool levelFriend(String id) {
    if (!canLevelFriend(id)) return false;
    coins -= friendLevelCost(id);
    friendLevels[id] = friendLevel(id) + 1;
    _bump(Stat.upgradesBought);
    notifyListeners();
    return true;
  }

  double buff(FriendBuff b) {
    double sum = 0;
    for (final f in Friends.all) {
      if (f.buff == b && friends.contains(f.id))
        sum += f.perLevel * Friends.effectiveLevel(friendLevel(f.id));
    }
    return sum;
  }

  /// 에너지 1 회복에 걸리는 시간(초): 강화 + 친구 버프.
  double get energyRegenSeconds =>
      Upgrades.energyRegenSeconds(lv(UpgradeType.energyRegen)) /
      (1 + buff(FriendBuff.energyRegen) + setBonus(SetEffect.energyRegen));

  double? get autoMergeInterval {
    final i = Upgrades.autoMergeInterval(lv(UpgradeType.autoMerge));
    return i == null ? null : i / (1 + buff(FriendBuff.autoMerge));
  }

  /// 바구니 기본 단계 = 1 + 바구니 등급 (D-029).
  int get spawnLevel => 1 + lv(UpgradeType.basketTier);

  /// 바구니 기준 상대 단계 (부탁 별 · 경험치는 이 값으로: 등급이 올라도 별 · 레벨 속도는 그대로).
  int relLevel(int level) => max(1, level - spawnLevel + 1);

  /// 바구니에서 2단계가 나올 확률 (기본 + 품질 강화 + 친구 버프).
  double get luckyChance =>
      GameConfig.luckySpawnChance +
      Upgrades.qualityChance(lv(UpgradeType.spawnLevel)) +
      buff(FriendBuff.lucky) +
      setBonus(SetEffect.lucky) +
      (boosted(BoostKind.lucky) ? Boosts.luckyBonus : 0);
  Duration get offlineCap =>
      Upgrades.offlineCap(lv(UpgradeType.offlineCap)) +
      Duration(minutes: setBonus(SetEffect.offline).round());

  bool isPlaced(int area, int slot) =>
      area < currentArea || (area == currentArea && placed.contains(slot));
  int get decorCount => currentArea * Garden.slotsPerArea + placed.length;

  /// 지금 구역을 꾸미는 데 필요한 레벨. 모자라면 별이 있어도 설치할 수 없다.
  int get areaRequiredLevel => Leveling.areaLevel(currentArea);
  bool get areaLocked => level < areaRequiredLevel;

  /// 정원 매력도 = 수익 배율.
  double get gardenMultiplier =>
      1 +
      decorCount * GameConfig.decorIncomeBonus +
      currentArea * GameConfig.areaIncomeBonus +
      completedSeasonSets * Garden.seasonSetBonus +
      decorScore * DecorSets.incomePerPoint +
      landmarkCharm;

  // ---------------------------------------------------------------- 랜드마크 (D-048)

  /// 구역 → 랜드마크 레벨 (0 = 아직 안 세움). 재단장해도 남는다.
  final Map<int, int> landmarks = {};
  int landmarkLevel(int area) => landmarks[area] ?? 0;

  /// 세울 수 있는 구역: 들어온 구역 (처음 6구역). 지금 꾸미는 구역에서도 세워 늘 보이게.
  /// 강화가 열린 뒤부터 (튜토리얼 첫 몇 분에는 안 보이게).
  bool landmarkOpen(int area) =>
      isUnlocked(Feature.upgrades) &&
      area < Landmarks.ids.length &&
      area <= currentArea;

  /// 다음 레벨 가격: 지금 시간당 수입 × 시간 (부스트 제외 기본 수입).
  double landmarkCost(int area) =>
      hourlyIncome * Landmarks.hoursAt(landmarkLevel(area));

  /// 랜드마크 레벨 상한: 플레이어 레벨 − 5 (초반 싼 수입으로 몰아 올리지 못하게), 최대 [Landmarks.maxLevel].
  int get landmarkCap => min(Landmarks.maxLevel, max(1, level - 5));
  bool landmarkCapped(int area) => landmarkLevel(area) >= landmarkCap;

  /// 세우기(Lv0 → 1)는 다른 장식처럼 별로: 그 구역 가장 비싼 장식만큼.
  int landmarkBuildStars(int area) =>
      Garden.decorCost(area, Garden.slotsPerArea - 1);

  bool canBuildLandmark(int area) =>
      landmarkOpen(area) &&
      landmarkLevel(area) == 0 &&
      stars >= landmarkBuildStars(area);

  bool buildLandmark(int area) {
    if (!canBuildLandmark(area)) return false;
    stars -= landmarkBuildStars(area);
    landmarks[area] = 1;
    _events.add(LandmarkEvent(area, 1, newStage: true));
    _trace('landmark', '$area,1,build');
    notifyListeners();
    return true;
  }

  /// 레벨업(Lv1 부터)은 코인.
  bool canUpgradeLandmark(int area) =>
      landmarkOpen(area) &&
      landmarkLevel(area) >= 1 &&
      landmarkLevel(area) < landmarkCap &&
      coins >= landmarkCost(area);

  bool upgradeLandmark(int area) {
    if (!canUpgradeLandmark(area)) return false;
    coins -= landmarkCost(area);
    final before = Landmarks.stageOf(landmarkLevel(area));
    final lv = landmarkLevel(area) + 1;
    landmarks[area] = lv;
    final newStage = lv == 1 || Landmarks.stageOf(lv) != before;
    _events.add(LandmarkEvent(area, lv, newStage: newStage));
    _bump(Stat.upgradesBought);
    _trace('landmark', '$area,$lv');
    notifyListeners();
    return true;
  }

  /// 일괄: 살 수 있는 만큼. 올린 레벨 수.
  int upgradeLandmarkMax(int area) {
    var n = 0;
    while (n < Landmarks.maxLevel && upgradeLandmark(area)) {
      n++;
    }
    return n;
  }

  /// 모든 랜드마크의 정원 매력 합.
  double get landmarkCharm =>
      landmarks.values.fold(0.0, (a, lv) => a + Landmarks.charm(lv));

  // ---------------------------------------------------------------- 꾸밈 점수 · 세트 (D-046)

  /// 구역 세트 단계: 2 = 8자리 모두 특별, 1 = 8자리 모두 고급 이상, 0 = 아직.
  int setTier(int area) {
    if (area >= DecorSets.areas || area > currentArea) return 0;
    var tier = 2;
    for (var i = 0; i < Garden.slotsPerArea; i++) {
      if (ownedStyles.contains('$area:$i:2')) continue;
      if (ownedStyles.contains('$area:$i:1')) {
        tier = 1;
        continue;
      }
      return 0;
    }
    return tier;
  }

  /// 이 구역에서 특별 디자인을 가진 자리 수 · 고급 이상을 가진 자리 수.
  ({int special, int premium}) setProgress(int area) {
    var sp = 0, pr = 0;
    for (var i = 0; i < Garden.slotsPerArea; i++) {
      if (ownedStyles.contains('$area:$i:2')) {
        sp++;
        pr++;
      } else if (ownedStyles.contains('$area:$i:1')) {
        pr++;
      }
    }
    return (special: sp, premium: pr);
  }

  /// 이 구역 세트로 받는 효과 크기 (특별 1 · 고급 0.4 · 없음 0) × 그 효과의 최대치.
  double setBonus(SetEffect e) {
    final i = DecorSets.effects.indexOf(e);
    final t = setTier(i);
    final k = t == 2 ? 1.0 : (t == 1 ? DecorSets.premiumRatio : 0.0);
    return k * DecorSets.full[e]!;
  }

  /// 꾸밈 점수: 특별 디자인 1점 · 고급 0.4점 (6구역까지).
  double get decorScore {
    var n = 0.0;
    for (var a = 0; a < DecorSets.areas && a <= currentArea; a++) {
      for (var i = 0; i < Garden.slotsPerArea; i++) {
        if (ownedStyles.contains('$a:$i:2')) {
          n += DecorSets.specialPoint;
        } else if (ownedStyles.contains('$a:$i:1')) {
          n += DecorSets.premiumPoint;
        }
      }
    }
    return n;
  }

  /// 이 구역의 이 시즌 장식 8종을 모두 가졌는지 (계절 세트 완성).
  bool seasonSetComplete(int area, int style) =>
      [for (var i = 0; i < Garden.slotsPerArea; i++) i]
          .every((i) => ownedStyles.contains('$area:$i:$style'));

  int seasonSetOwned(int area, int style) => [
    for (var i = 0; i < Garden.slotsPerArea; i++)
      if (ownedStyles.contains('$area:$i:$style')) i,
  ].length;

  int get completedSeasonSets {
    var n = 0;
    for (var a = 0; a < Garden.areas.length; a++) {
      for (final st in Garden.seasonStyles.keys) {
        if (seasonSetComplete(a, st)) n++;
      }
    }
    return n;
  }

  /// 구역에 켜진 계절 풍경: 완성한 세트를 8자리 모두 입혀 두었을 때 그 시즌 (아니면 null).
  int? landscapeOf(int area) {
    if (area > currentArea) return null;
    for (final st in Garden.seasonStyles.keys) {
      if (!seasonSetComplete(area, st)) continue;
      final all = [for (var i = 0; i < Garden.slotsPerArea; i++) i]
          .every((i) => isPlaced(area, i) && styleOf(area, i) == st);
      if (all) return st;
    }
    return null;
  }

  /// 방치 수익 배율 (수익 강화 · 친구 버프). 정원 매력은 부탁 코인에만.
  double get _incomeMult =>
      Upgrades.incomeMultiplier(lv(UpgradeType.income)) *
      (1 + buff(FriendBuff.income)) *
      seedMultiplier;

  bool boosted(BoostKind k) => boosts[k]?.isAfter(now) ?? false;
  Duration boostLeft(BoostKind k) =>
      boosted(k) ? boosts[k]!.difference(now) : Duration.zero;
  bool canAddBoostOf(BoostKind k) =>
      boostLeft(k) < Boosts.max - const Duration(minutes: 1);

  /// 코인 2배 부스트 (예전 이름 유지).
  bool get boostActive => boosted(BoostKind.coins);
  Duration get boostRemaining => boostLeft(BoostKind.coins);
  bool get anyBoost => BoostKind.values.any(boosted);

  bool get coinBagReady =>
      coinBagReadyAt == null || !coinBagReadyAt!.isAfter(now);
  Duration get coinBagCooldownLeft =>
      coinBagReady ? Duration.zero : coinBagReadyAt!.difference(now);

  bool get visitorVisible => visitorUntil != null && visitorUntil!.isAfter(now);

  /// 아이템 1개의 초당 방치 수익 (단계 × 종류별 생산력 × 수익 강화 · 버프).
  double itemIncomePerSec(Item it) => it.isBubble
      ? 0
      : GameConfig.incomeOf(it.chain, it.level) *
            Upgrades.chainPower(lv(Upgrades.powerOf(it.chain))) *
            _incomeMult;

  /// 칸에 표시하는 시간당 값 (2배 부스트 포함).
  double itemIncomePerHour(Item it) =>
      itemIncomePerSec(it) * 3600 * (boostActive ? 2 : 1);

  double get baseIncomePerSec {
    double sum = 0;
    for (final it in board) {
      if (it != null) sum += itemIncomePerSec(it);
    }
    return sum;
  }

  double get incomePerSec => baseIncomePerSec * (boostActive ? 2 : 1);

  /// 시간당 방치 수익 (화면 표시용).
  double get incomePerHour => incomePerSec * 3600;

  /// 코인 보상 배율 (정원 매력 · 친구 버프 · 2배 부스트). 수익 강화는 방치 수익에만 걸린다
  /// (부탁 코인에까지 곱하면 코인이 눈덩이처럼 불어난다).
  double get _coinMult =>
      gardenMultiplier * (1 + buff(FriendBuff.income)) * (boostActive ? 2 : 1);

  /// 에너지 광고: 해금 · 하루 횟수 · 에너지가 적을 때만.
  bool get energyAdAvailable =>
      isUnlocked(Feature.energyAd) &&
      canWatchAd(AdKind.energy) &&
      energy < GameConfig.energyAdBelow;

  /// 정원 패스 혜택 중 (구독 또는 기간제).
  /// 패키지로 받은 기간제 패스 끝 알림 단계: 0 없음 · 1 사흘 전 · 2 하루 전 · 3 끝남 (본 단계까지 저장).
  int passNoticeSeen = 0;

  /// 지금 보여 줄 패스 끝 알림 단계 (구독 중이면 없음).
  int? get passNoticeDue {
    if (adFree || passUntil == null) return null;
    final left = passUntil!.difference(now);
    final stage = left.isNegative
        ? 3
        : left <= const Duration(days: 1)
        ? 2
        : left <= const Duration(days: 3)
        ? 1
        : 0;
    return stage > passNoticeSeen ? stage : null;
  }

  void markPassNotice(int stage) {
    passNoticeSeen = max(passNoticeSeen, stage);
    notifyListeners();
  }

  bool get passActive => adFree || (passUntil?.isAfter(now) ?? false);
  Duration get passLeft => passUntil == null || !passUntil!.isAfter(now)
      ? Duration.zero
      : passUntil!.difference(now);

  bool isCellOpen(int i) =>
      unlockedCells.contains(i) ||
      (GameConfig.isVault(i) &&
          (vaultOwned.contains(i) ||
              (passActive && GameConfig.passVault.contains(i))));

  /// 집어 들 수 있는 칸: 열린 칸 + 패스가 끝나 잠긴 보관 칸에 남은 아이템 (꺼내기만 가능).
  bool canTake(int i) =>
      isCellOpen(i) || (GameConfig.isVault(i) && board[i] != null);

  /// 패스가 끝나 잠겼지만 아이템이 남아 있는 보관 칸.
  bool vaultHeld(int i) => !isCellOpen(i) && canTake(i);

  int get vaultCostNext => GameConfig.vaultCost(vaultOwned.length);

  /// 보관 칸 다이아로 영구 해금.
  bool buyVault(int i) {
    if (!GameConfig.isVault(i) || vaultOwned.contains(i)) return false;
    final cost = vaultCostNext;
    if (!_spendGems(cost, 'vault')) return false;
    vaultOwned.add(i);
    _trace('vault', '$i,$cost');
    notifyListeners();
    return true;
  }

  int? get _emptyCell {
    for (var i = 0; i < board.length; i++) {
      if (board[i] == null && isCellOpen(i)) return i;
    }
    return null;
  }

  bool get boardFull => _emptyCell == null;

  /// 꽉 찼고 합칠 수 있는 쌍도 없으면 true (판매를 안내할 때 사용).
  bool get boardStuck => boardFull && !_hasMergeablePair();

  bool _hasMergeablePair() {
    final seen = <String>{};
    for (final it in board) {
      if (it == null || it.isBubble || it.level >= Chains.maxLevel(it.chain))
        continue;
      if (!seen.add('${it.chain.index}-${it.level}')) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------- 경험치

  void _gainXp(int amount) {
    xp += amount;
    while (xp >= xpToNext) {
      xp -= xpToNext;
      level++;
      final c = Leveling.levelUpCoins(level);
      _earn(c);
      stars += Leveling.levelUpStars;
      gems += Gems.levelUp;
      final gotEnergy = Leveling.levelUpEnergy(level, energy);
      energy += gotEnergy;
      final opened = Leveling.unlockedAt(level);
      _events.add(
        LevelUpEvent(level, opened, c, Leveling.levelUpStars, gotEnergy),
      );
      // 간식이 열리면 첫 부탁을 간식으로 바꿔 바로 체감되게 한다
      if (opened.contains(Feature.snack) && orders.isNotEmpty) {
        orders[0] = _placeholder;
        orders[0] = _newOrder(preferChain: Chain.snack);
      }
    }
  }

  // ---------------------------------------------------------------- 진행

  /// 오늘 별 부탁이 남은 친구를 먼저 고른다 (다 썼으면 아무나).
  /// 방금 부탁을 들어준 친구가 다시 부탁하기까지 쉬는 시간 (같은 친구가 연달아 부탁하지 않게).
  static const Duration orderRest = Duration(seconds: 45);
  final Map<String, DateTime> _restUntil = {};

  /// 쉬는 중인 친구 (친구가 셋 이상일 때만: 초반 한두 명일 때는 부탁이 끊기지 않게).
  bool _resting(String f) {
    if (friends.length < 3) return false;
    final t = _restUntil[f];
    return t != null && now.isBefore(t);
  }

  String _pickFriend(List<String> pool) {
    // 지금 다른 부탁을 들고 있지 않은 친구 먼저 (정원에서 한 친구 머리 위에 말풍선이 겹치지 않게),
    // 그중에서도 방금 부탁을 들어준 친구는 빼고
    final busy = {for (final o in orders) o.friendId};
    final rested = [
      for (final f in pool)
        if (!busy.contains(f) && !_resting(f)) f,
    ];
    final free = rested.isNotEmpty
        ? rested
        : [
            for (final f in pool)
              if (!busy.contains(f)) f,
          ];
    final base = free.isEmpty ? pool : free;
    final left = [
      for (final f in base)
        if (starOrdersLeft(f) > 0) f,
    ];
    final from = left.isEmpty ? base : left;
    return from[_rng.nextInt(from.length)];
  }

  /// 보관함 창은 없어지고 판 맨 아랫줄 보관 칸으로 합쳐졌다 (D-017).
  /// 보관함에 있던 아이템은 판 빈칸으로 꺼내고, 코인으로 산 보관함 칸 수만큼 보관 칸을 무료로 연다.
  void _migrateStorage() {
    final bought = storage.length - Storage.startSlots;
    if (bought > 0) {
      var n = bought;
      for (final c in [32, 33, 34, 35, 30, 31]) {
        if (n <= 0) break;
        if (vaultOwned.add(c)) n--;
      }
    }
    final keep = <Item?>[];
    for (final it in storage) {
      if (it == null) continue;
      final cell = _emptyCell;
      if (cell == null) {
        keep.add(it); // 판이 가득하면 다음에 다시
      } else {
        board[cell] = it;
      }
    }
    storage = [
      ...keep,
      ...List<Item?>.filled(max(0, Storage.startSlots - keep.length), null),
    ];
  }

  // ---------------------------------------------------------------- 부탁 하루 한도

  void _rollQuotaDay() {
    final k = _dayKey(now);
    if (k == _quotaDay) return;
    _quotaDay = k;
    starOrdersUsed.clear();
    starOrdersBonus.clear();
    rerollsToday = 0;
  }

  /// 하루 별 부탁 한도: 첫 구역을 끝냈거나, 첫 구역에서도 부탁을 [OrderQuota.freeOrders]번 들어준 뒤부터.
  /// (첫 구역에서 별을 쓰지 않고 머물며 한도 없이 별을 모으던 구멍을 막는다. 튜토리얼 흐름은 그대로)
  bool get quotaActive =>
      currentArea >= 1 || (stats[Stat.orders] ?? 0) >= OrderQuota.freeOrders;
  int starOrderLimit(String friendId) {
    _rollQuotaDay();
    return OrderQuota.perFriend +
        (friendLevel(friendId) >= Friends.starMilestone ? 1 : 0) +
        (starOrdersBonus[friendId] ?? 0) +
        (passActive ? OrderQuota.pass : 0);
  }

  int starOrdersLeft(String friendId) => quotaActive
      ? max(0, starOrderLimit(friendId) - (starOrdersUsed[friendId] ?? 0))
      : 99;
  bool orderGivesStars(Order o) => starOrdersLeft(o.friendId) > 0;

  /// 광고를 보고 그 친구의 오늘 별 부탁 +2.
  void grantQuotaAd(String friendId) {
    _rollQuotaDay();
    starOrdersBonus[friendId] =
        (starOrdersBonus[friendId] ?? 0) + OrderQuota.perAd;
    _trace('quota', '$friendId,+${OrderQuota.perAd}');
    _fillOrders();
    notifyListeners();
  }

  int get freeRerollsLeft {
    _rollQuotaDay();
    return max(0, OrderQuota.freeRerolls - rerollsToday);
  }

  /// 정원 패스: 하루 한 번 다이아 쪽지.
  void _passDaily() {
    if (!passActive) return;
    final k = _dayKey(now);
    if (k == _passDay) return;
    _passDay = k;
    addMail(
      Mail(
        id: 'pass-$k',
        kind: MailKind.notice,
        from: 'team',
        titleKey: 'mail.passDaily',
        reward: const Reward(gems: OrderQuota.passDailyGems),
        at: now,
      ),
    );
  }

  void tick(double dt) {
    if (dt <= 0) return;
    final day0 = _playDay;
    _rollPlayDay();
    if (_playDay != day0) _expireMail();
    _passDaily();
    // 날이 바뀌어 한도가 다시 차거나 친구가 새로 오면 부탁을 채운다
    _fillOrders();
    _maybeFriendGift();
    _earn(incomePerSec * dt);
    _sampleEarn(dt);
    _regenEnergy(dt);
    _rechargeBaskets(dt);
    _noBuySecs = UpgradeType.values.any(canBuyUpgrade) ? 0 : _noBuySecs + dt;

    final ami = autoMergeInterval;
    if (ami != null) {
      autoMergeProgress += dt;
      if (autoMergeProgress >= ami) {
        autoMergeProgress = 0;
        autoMergeOnce();
      }
    }

    // 시간이 다 된 비눗방울은 터진다
    for (var i = 0; i < board.length; i++) {
      final it = board[i];
      if (it != null && it.isBubble && !it.bubbleUntil!.isAfter(now))
        board[i] = null;
    }

    if (isUnlocked(Feature.visitor) &&
        !visitorVisible &&
        !now.isBefore(nextVisitorAt)) {
      visitorUntil = now.add(GameConfig.visitorStay);
      nextVisitorAt = visitorUntil!.add(_randomVisitorGap());
    }

    lastSeen = now;
    notifyListeners();
  }

  Duration _randomVisitorGap() {
    final a = GameConfig.visitorMinGap.inSeconds;
    final b = GameConfig.visitorMaxGap.inSeconds;
    return Duration(seconds: a + _rng.nextInt(b - a + 1));
  }

  void _earn(double v, {bool live = true}) {
    coins += v;
    lifetimeCoins += v;
    _bump(Stat.coinsEarned, v.round());
    if (live) _winCoins += v;
  }

  /// 플레이하는 동안 실제로 버는 코인 속도 (시간당, 5분 창의 지수 평균. 오프라인 보상은 빼고).
  /// 랜드마크처럼 '지금 수입 × 시간' 으로 값이 정해지는 것의 기준 (D-048).
  double earnRate = 0;
  double _winCoins = 0, _winSec = 0;

  void _sampleEarn(double dt) {
    _winSec += dt;
    if (_winSec < 300) return;
    final rate = _winCoins / _winSec * 3600;
    earnRate = earnRate <= 0 ? rate : earnRate * 0.7 + rate * 0.3;
    _winCoins = 0;
    _winSec = 0;
  }

  /// 지금 시간당 수입 (재 본 값이 없으면 기본 수입의 10배로 어림).
  double get hourlyIncome =>
      max(100.0, earnRate > 0 ? earnRate : baseIncomePerSec * 3600 * 10);

  // ---------------------------------------------------------------- 에너지

  void _regenEnergy(double dt) {
    if (energy >= energyCap) {
      energyProgress = 0;
      return;
    }
    energyProgress += dt;
    while (energyProgress >= energyRegenSeconds && energy < energyCap) {
      energyProgress -= energyRegenSeconds;
      energy++;
    }
  }

  /// 다음 에너지 1이 차기까지 남은 시간.
  Duration get energyNextIn => energy >= energyCap
      ? Duration.zero
      : Duration(seconds: (energyRegenSeconds - energyProgress).ceil());

  /// 바구니 탭: 에너지 1로 즉시 하나 생성. 결과를 돌려준다.
  TapResult tapSpawner() {
    if (boardFull) return TapResult.boardFull;
    if (!basketOpen(basket)) basket = 0;
    if (!basketReady(basket)) return TapResult.basketEmpty;
    // 에너지 절약 부스트: 에너지가 있을 때만, 바구니 한 번에 [Boosts.energySaveChance] 확률로 에너지가 들지 않는다
    final free =
        energy >= GameConfig.energyPerTap &&
        boosted(BoostKind.energy) &&
        _rng.nextDouble() < Boosts.energySaveChance;
    if (!free && energy < GameConfig.energyPerTap) {
      if (!_emptyReported) {
        _emptyReported = true;
        _events.add(EnergyEmptyEvent());
      }
      return TapResult.noEnergy;
    }
    _emptyReported = false;
    _bump(Stat.spawns);
    if (!free) {
      energy -= GameConfig.energyPerTap;
      _bump(Stat.energySpent, GameConfig.energyPerTap);
    }
    if (Chains.basketCharges[basket] > 0) basketCharge[basket] -= 1;
    _spawnOne();
    notifyListeners();
    return TapResult.spawned;
  }

  void grantEnergyAd() {
    energy += Tuning.energyAdAmount; // 상한을 넘어도 된다 (Travel Town 방식)
    notifyListeners();
  }

  // ---------------------------------------------------------------- 광고 하루 상한

  String _dayKey(DateTime t) => '${t.year}-${t.month}-${t.day}';

  void _rollAdDay() {
    final k = _dayKey(now);
    if (k != _adsDay) {
      _adsDay = k;
      adsToday.clear();
      _gemRefillsToday = 0;
    }
  }

  int adsLeft(AdKind kind) {
    _rollAdDay();
    return max(0, (GameConfig.adDailyCap[kind] ?? 999) - (adsToday[kind] ?? 0));
  }

  bool canWatchAd(AdKind kind) => adsLeft(kind) > 0;

  bool _emptyReported = false;

  void recordAd(AdKind kind) {
    _events.add(AdRewardEvent(kind.name));
    _rollAdDay();
    adsToday[kind] = (adsToday[kind] ?? 0) + 1;
    _bump(Stat.adsWatched);
    notifyListeners();
  }

  int? _spawnOne() {
    final cell = _emptyCell;
    if (cell == null) return null;
    if (!basketOpen(basket)) basket = 0;
    final chains = [
      for (final c in Chains.baskets[basket])
        if (availableChains.contains(c)) c,
    ];
    final chain = chains[_rng.nextInt(chains.length)];
    var lvl = spawnLevel;
    if (_rng.nextDouble() < luckyChance) lvl += 1;
    lvl = min(lvl, Chains.maxLevel(chain));
    board[cell] = Item(_nextId++, chain, lvl);
    _trace('spawn', '${chain.name},$lvl,$basket');
    _checkDiscovery(chain, lvl);
    return cell;
  }

  void _checkDiscovery(Chain chain, int lvl) {
    if (lvl > (highest[chain] ?? 1)) {
      highest[chain] = lvl;
      final bonus = GameConfig.discoveryBonusOf(chain, lvl) * _coinMult;
      _earn(bonus);
      _events.add(DiscoveryEvent(chain, lvl, bonus));
      _gainXp(Leveling.xpForDiscovery);
    }
  }

  /// 드래그 앤 드롭. 잠긴 칸, 비눗방울은 움직일 수 없다.
  MoveResult move(int from, int to) {
    if (from == to ||
        from < 0 ||
        to < 0 ||
        from >= board.length ||
        to >= board.length) {
      return MoveResult.none;
    }
    if (!canTake(from) || !isCellOpen(to)) return MoveResult.none;
    final a = board[from];
    final b = board[to];
    if (a == null || a.isBubble || (b != null && b.isBubble))
      return MoveResult.none;
    MoveResult r;
    if (b == null) {
      board[to] = a;
      board[from] = null;
      r = MoveResult.moved;
    } else if (a.chain == b.chain && a.level == b.level) {
      r = _merge(from, to);
    } else {
      board[to] = a;
      board[from] = b;
      r = MoveResult.swapped;
    }
    notifyListeners();
    return r;
  }

  MoveResult _merge(int from, int to) {
    final b = board[to]!;
    totalMerges++;
    _bump(Stat.merges);
    board[from] = null;
    if (b.level >= Chains.maxLevel(b.chain)) {
      final payout = GameConfig.maxMergePayoutOf(b.chain, b.level) * _coinMult;
      board[to] = null;
      _earn(payout);
      _bump(Stat.maxMerges);
      _trace('merge', '${b.chain.name},${b.level},max,${payout.round()}');
      _events.add(MaxMergeEvent(payout));
      _gainXp(Leveling.xpForMerge(b.level));
      return MoveResult.maxMerged;
    }
    b.level += 1;
    _trace('merge', '${b.chain.name},${b.level - 1},${b.level}');
    _events.add(MergedEvent(to, b.level));
    _checkDiscovery(b.chain, b.level);
    _gainXp(Leveling.xpForMerge(b.level));
    if (relLevel(b.level) >= GameConfig.bubbleMinLevel &&
        !board.any((it) => it != null && it.isBubble) &&
        board.indexed.where((e) => e.$2 == null && isCellOpen(e.$1)).length >=
            GameConfig.bubbleMinFree &&
        (_lastBubble == null ||
            now.difference(_lastBubble!) >= GameConfig.bubbleGap) &&
        _rng.nextDouble() < GameConfig.bubbleChance) {
      _lastBubble = now;
      final cell = _emptyCell;
      if (cell != null) {
        board[cell] = Item(
          _nextId++,
          b.chain,
          b.level,
          bubbleUntil: now.add(GameConfig.bubbleLife),
        );
        _trace('bubble', '${b.chain.name},${b.level}');
        _events.add(BubbleEvent(cell));
      }
    }
    return MoveResult.merged;
  }

  /// 비눗방울 꺼내기 (보상형 광고를 본 뒤 호출).
  DateTime? _lastBubble;

  bool popBubble(int cell) {
    final it = board[cell];
    if (it == null || !it.isBubble) return false;
    it.bubbleUntil = null;
    _bump(Stat.bubblesPopped);
    notifyListeners();
    return true;
  }

  bool _isOrderTarget(Item it) =>
      orders.any((o) => o.chain == it.chain && o.level == it.level);

  /// 가장 낮은 레벨의 같은 아이템 한 쌍을 합친다. 부탁에 필요한 아이템은 건드리지 않는다.
  bool autoMergeOnce() {
    final groups = <String, List<int>>{};
    for (var i = 0; i < board.length; i++) {
      final it = board[i];
      if (it == null ||
          it.isBubble ||
          it.level >= Chains.maxLevel(it.chain) ||
          it.level >=
              Upgrades.autoMergeMaxLevel(
                lv(UpgradeType.autoMerge),
                spawnLevel,
              ) ||
          _isOrderTarget(it))
        continue;
      groups
          .putIfAbsent(
            '${it.level.toString().padLeft(2, '0')}-${it.chain.index}',
            () => [],
          )
          .add(i);
    }
    final keys = groups.keys.toList()..sort();
    for (final k in keys) {
      final cells = groups[k]!;
      if (cells.length >= 2) {
        _merge(cells[1], cells[0]);
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------- 칸 해금, 판매

  int get cellsPurchased => unlockedCells.length - GameConfig.startCells.length;
  int get lockedCellCount =>
      GameConfig.coinCells -
      unlockedCells.where((c) => c < GameConfig.coinCells).length;
  double get nextCellCost => cellCost(cellsPurchased) * inflation;
  int get nextCellLevel => Leveling.cellLevel(cellsPurchased);

  bool canBuyCell(int cell) =>
      cell >= 0 &&
      cell < GameConfig.coinCells &&
      !isCellOpen(cell) &&
      level >= nextCellLevel &&
      coins >= nextCellCost;

  bool buyCell(int cell) {
    if (!canBuyCell(cell)) return false;
    coins -= nextCellCost;
    unlockedCells.add(cell);
    _bump(Stat.cellsBought);
    notifyListeners();
    return true;
  }

  double sellPrice(Item it) => GameConfig.sellValueOf(it.chain, it.level);

  /// 최고 단계 아이템인가 (친구에게 선물할 수 있다).
  bool isMaxItem(Item it) =>
      !it.isBubble && it.level >= Chains.maxLevel(it.chain);

  /// 선물하면 받는 코인 (안내 창 표시용, 실제 지급과 같은 값).
  double giftCoins(Item it) =>
      GameConfig.maxGiftCoinsOf(it.chain, it.level) * _coinMult;

  /// 하트가 아직 다 차지 않은 친구 (선물 받을 수 있는 친구).
  List<String> get giftableFriends => [
    for (final f in Friends.all)
      if (friends.contains(f.id) && affection(f.id) < Friends.maxAffection)
        f.id,
  ];

  /// 최고 단계 아이템을 친구에게 선물: 하트 +1 · 코인. 하트가 모두 찼으면 별로 바꿔 준다.
  bool giftMaxItem(int cell, String friendId) {
    final it = board[cell];
    if (it == null || !isMaxItem(it) || !friends.contains(friendId)) {
      return false;
    }
    board[cell] = null;
    final full = affection(friendId) >= Friends.maxAffection;
    deliveries[friendId] =
        (deliveries[friendId] ?? 0) + Friends.deliveriesPerAffection;
    final coins = giftCoins(it);
    _earn(coins);
    final s = full ? GameConfig.maxGiftStars : 0;
    stars += s;
    _trace('gift', '${it.chain.name},${it.level},$friendId');
    _events.add(MaxGiftEvent(friendId, coins, s, it.chain, it.level));
    notifyListeners();
    return true;
  }

  /// 아이템 판매. 판매 금액을 돌려준다.
  double? sell(int cell) {
    final it = board[cell];
    if (it == null || it.isBubble) return null;
    final price = sellPrice(it);
    board[cell] = null;
    _earn(price);
    _lastSale = _Sale(cell, it, price, now);
    _bump(Stat.sells);
    _events.add(SoldEvent(it, price));
    notifyListeners();
    return price;
  }

  bool get canUndoSell {
    final s = _lastSale;
    return s != null &&
        now.difference(s.at) < GameConfig.sellUndoWindow &&
        board[s.cell] == null &&
        coins >= s.price;
  }

  bool undoSell() {
    if (!canUndoSell) return false;
    final s = _lastSale!;
    coins -= s.price;
    lifetimeCoins -= s.price;
    board[s.cell] = s.item;
    _lastSale = null;
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------- 보관함

  bool get storageOpen => isUnlocked(Feature.storage);
  int get storageUsed => storage.where((it) => it != null).length;
  bool get storageFull => storageUsed >= storage.length;
  bool get storageMaxed => storage.length >= Storage.maxSlots;
  double get nextStorageCost =>
      Storage.slotCost(storage.length - Storage.startSlots);

  bool canStore(int cell) {
    if (!storageOpen || storageFull) return false;
    if (cell < 0 || cell >= board.length) return false;
    final it = board[cell];
    return it != null && !it.isBubble;
  }

  /// 판의 아이템을 보관함 빈 칸으로 옮긴다.
  bool store(int cell) {
    if (!canStore(cell)) return false;
    final slot = storage.indexOf(null);
    storage[slot] = board[cell];
    board[cell] = null;
    _bump(Stat.stored);
    notifyListeners();
    return true;
  }

  /// 보관함 아이템을 판으로 꺼낸다 (cell 이 없으면 첫 빈 칸). 꺼낸 칸 번호, 실패면 null.
  int? retrieve(int slot, {int? cell}) {
    if (slot < 0 || slot >= storage.length || storage[slot] == null) {
      return null;
    }
    final target = cell ?? _emptyCell;
    if (target == null || !isCellOpen(target) || board[target] != null) {
      return null;
    }
    board[target] = storage[slot];
    storage[slot] = null;
    notifyListeners();
    return target;
  }

  bool get canBuyStorageSlot =>
      storageOpen && !storageMaxed && coins >= nextStorageCost;

  bool buyStorageSlot() {
    if (!canBuyStorageSlot) return false;
    coins -= nextStorageCost;
    storage = [...storage, null];
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------- 부탁

  /// 오늘 부탁할 수 있는 친구: 첫 구역 뒤에는 오늘 별 부탁이 남은 친구만
  /// (이미 들고 있는 부탁 수만큼 빼고). 별 부탁을 다 쓴 친구는 내일까지 부탁하지 않는다.
  List<String> get _askers {
    final pool = friends.toList()..sort();
    if (!quotaActive) return pool;
    return [
      for (final f in pool)
        if (starOrdersLeft(f) - orders.where((o) => o.friendId == f).length > 0)
          f,
    ];
  }

  /// 부탁을 채운다. 한도를 다 쓴 친구의 부탁은 거둬들이고, 부탁할 친구가 없으면 빈 채로 둔다.
  void _fillOrders() {
    if (quotaActive) {
      orders.removeWhere(
        (o) => !canDeliverOrder(o) && starOrdersLeft(o.friendId) <= 0,
      );
    }
    // 친구 한 명당 부탁 하나 (정원에서 친구 머리 위 말풍선 하나)
    final slots = min(GameConfig.orderSlots, friends.length);
    bool freeAsker() {
      final busy = {for (final o in orders) o.friendId};
      return _askers.any((f) => !busy.contains(f) && !_resting(f));
    }

    while (orders.length < slots && freeAsker()) {
      orders.add(_newOrder());
    }
  }

  bool canDeliverOrder(Order o) => _findItem(o.chain, o.level) >= 0;

  /// 바구니 등급이 바뀐 뒤: 바구니가 더는 만들 수 없는 낮은 부탁(판에도 없음)은 같은 친구의 새 부탁으로,
  /// 남는 부탁은 별을 지금 등급 기준으로 다시 매긴다 (재단장 뒤 낮은 부탁이 판을 영영 막던 버그).
  void _refreshOrdersForTier() {
    for (var i = 0; i < orders.length; i++) {
      final o = orders[i];
      final inStorage = storage.any(
        (it) => it != null && it.chain == o.chain && it.level == o.level,
      );
      if (o.level < spawnLevel && !canDeliverOrder(o) && !inStorage) {
        final n = _newOrder();
        orders[i] = Order(n.id, o.friendId, n.chain, n.level, n.stars);
      } else {
        final st = Garden.orderStars(relLevel(o.level));
        if (st != o.stars) {
          orders[i] = Order(o.id, o.friendId, o.chain, o.level, st);
        }
      }
    }
  }

  /// 오늘 별 부탁이 모두 끝나 부탁이 하나도 없다 (정원에 '내일 또 와요' 표시).
  bool get ordersDoneToday => quotaActive && orders.isEmpty;

  DateTime? _lastRescue;

  /// 판에서 부탁 범위보다 높아 쓸 데 없이 칸을 막는 아이템 (가장 높은 것).
  Item? get stuckItem {
    final top = orderCenter + 2;
    final chains = availableChains;
    Item? best;
    for (final it in board) {
      if (it == null || it.isBubble || !chains.contains(it.chain)) continue;
      if (it.level <= top || it.level >= Chains.maxLevel(it.chain)) continue;
      if (orders.any((o) => o.chain == it.chain && o.level == it.level)) {
        continue;
      }
      if (best == null || it.level > best.level) best = it;
    }
    return best;
  }

  /// 부탁 단계의 중심: 바구니 기본 단계 + 레벨에 따른 폭 (Lv1 ≈ +1.5, Lv20 이상 +6.5).
  double get orderCenter => spawnLevel - 1 + Leveling.orderLevelCenter(level);

  Order _newOrder({Chain? preferChain}) {
    final askers = _askers;
    final pool = askers.isEmpty ? (friends.toList()..sort()) : askers;
    final chains = availableChains;
    final center = orderCenter;
    // 구조 부탁: 막힌 고단계 아이템을 가끔(1/4, 10분에 한 번까지) 원한다. 별 · 코인은 에너지 비례라 공정하다.
    final stuck = preferChain == null ? stuckItem : null;
    if (stuck != null &&
        (_lastRescue == null ||
            now.difference(_lastRescue!) >= GameConfig.rescueOrderGap) &&
        _rng.nextDouble() < Tuning.rescueChance) {
      _lastRescue = now;
      return Order(
        _nextId++,
        _pickFriend(pool),
        stuck.chain,
        stuck.level,
        Garden.orderStars(relLevel(stuck.level)),
      );
    }
    for (var attempt = 0; ; attempt++) {
      final friendId = _pickFriend(pool);
      final chain = preferChain ?? chains[_rng.nextInt(chains.length)];
      // 피할 것이 많아 고를 게 없으면 단계 폭을 조금씩 넓힌다 (±1 → ±2 → ±3)
      final spread = 1.0 + min(1, attempt ~/ 15);
      // 3번에 1번은 낮은 단계(바구니 +1~2) 부탁: 판에 남는 낮은 아이템을 쓸 데가 생기게
      final easy = attempt < 20 && _rng.nextDouble() < Tuning.easyOrderChance;
      final lvl =
          (easy
                  ? spawnLevel + 1 + _rng.nextInt(2)
                  : (center + (_rng.nextDouble() * 2 - 1) * spread).round())
              .clamp(spawnLevel + 1, Chains.maxLevel(chain));
      final dup = orders.any((o) => o.chain == chain && o.level == lvl);
      // 같은 부탁을 연달아 받아 별을 쉽게 모으지 못하게: 최근 전달한 것 · 판에 이미 있는 것은 피한다
      // (부탁은 합쳐서 만들어야 하는 아이템이 기본 · 장르 표준)
      final recent = _recentOrders.contains('${chain.index}-$lvl');
      final onBoard = _findItem(chain, lvl) >= 0;
      final justGiven =
          _recentOrders.isNotEmpty &&
          _recentOrders.last == '${chain.index}-$lvl';
      // 30번 안에 못 찾으면 '방금 전달한 것'만 피하고, 60번 넘으면 아무거나
      // 낮은 단계 부탁은 판에 있는 것도 원한다 (별 1개짜리라 공짜 별 걱정이 작고, 칸을 비워 준다)
      if ((!dup && !recent && (!onBoard || easy)) ||
          (attempt > 30 && !justGiven && !onBoard) ||
          attempt > 60) {
        return Order(
          _nextId++,
          friendId,
          chain,
          lvl,
          Garden.orderStars(relLevel(lvl)),
        );
      }
    }
  }

  int _findItem(Chain chain, int lvl) => board.indexWhere(
    (it) => it != null && !it.isBubble && it.chain == chain && it.level == lvl,
  );

  bool canDeliver(int orderIndex) {
    if (orderIndex < 0 || orderIndex >= orders.length) return false;
    final o = orders[orderIndex];
    return _findItem(o.chain, o.level) >= 0;
  }

  /// 부탁 코인도 생산력 · 수익 강화를 따라 커진다 (부탁이 수입에서 밀려나지 않게).
  double orderCoins(Order o) =>
      GameConfig.orderCoinsOf(o.chain, o.level) *
      Upgrades.chainPower(lv(Upgrades.powerOf(o.chain))) *
      _incomeMult *
      _coinMult *
      (1 + buff(FriendBuff.orderCoins));

  bool deliver(int orderIndex) {
    if (!canDeliver(orderIndex)) return false;
    final o = orders[orderIndex];
    board[_findItem(o.chain, o.level)] = null;
    final withStars = orderGivesStars(o);
    var gained = withStars ? o.stars : 0;
    // 단풍(별 보너스): 가끔 별을 반만큼 더
    if (withStars &&
        _rng.nextDouble() <
            buff(FriendBuff.starBonus) + 0.05 * perkLv(SeedPerk.starWish)) {
      gained += max(1, o.stars ~/ 2);
    }
    // 2회차부터 회차 별 보너스
    if (withStars && renewCount > 1) {
      gained = (gained * (1 + GameConfig.roundStarBonus(renewCount))).round();
    }
    // 온실 세트: 부탁 별 +% (소수 부분은 확률로 한 개 더)
    final sb = setBonus(SetEffect.orderStars);
    if (withStars && sb > 0) {
      final x = gained * (1 + sb);
      gained = x.floor() + (_rng.nextDouble() < x - x.floor() ? 1 : 0);
    }
    // 하루 부탁 단계 보상: 하루 한도가 걸리는 별 부탁만 센다 (첫 구역의 한도 없는 부탁으로 쉽게 채우지 않게)
    _rollOrdersDay();
    final counts = withStars && quotaActive;
    if (counts) _ordersToday += 1;
    final mi = counts ? GameConfig.orderMilestones.indexOf(_ordersToday) : -1;
    if (mi >= 0) {
      final g = GameConfig.orderMilestoneGems[mi];
      gems += g;
      _events.add(OrderMilestoneEvent(_ordersToday, g));
    }
    if (withStars && quotaActive) {
      starOrdersUsed[o.friendId] = (starOrdersUsed[o.friendId] ?? 0) + 1;
    }
    stars += gained;
    _bump(Stat.orders);
    _bump(Stat.orderStars, gained);
    final c = orderCoins(o);
    _earn(c);
    final before = affection(o.friendId);
    deliveries[o.friendId] = (deliveries[o.friendId] ?? 0) + 1;
    final up = affection(o.friendId) > before;
    _recentOrders.add('${o.chain.index}-${o.level}');
    if (_recentOrders.length > 3) _recentOrders.removeAt(0);
    orders.removeAt(orderIndex);
    _restUntil[o.friendId] = now.add(orderRest);
    _fillOrders();
    _trace(
      'order',
      '${o.friendId},${o.chain.name},${o.level},$gained,${c.round()}',
    );
    final gx = Leveling.xpForOrder(relLevel(o.level));
    _events.add(OrderDeliveredEvent(o.friendId, gained, c, up, gx));
    _gainXp(gx);
    notifyListeners();
    return true;
  }

  static const _placeholder = Order(-1, '', Chain.flower, 0, 0);

  /// 부탁 교체 (보상형 광고).
  void refreshOrder(int orderIndex) {
    if (orderIndex < 0 || orderIndex >= orders.length) return;
    _rollQuotaDay();
    rerollsToday++;
    final old = orders.removeAt(orderIndex);
    _fillOrders();
    final o = orders.isEmpty ? old : orders.last;
    _trace(
      'reroll',
      '${old.chain.name},${old.level}>${o.chain.name},${o.level}',
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------- 꾸미기

  int decorCost(int slot) => Garden.decorCost(currentArea, slot);

  bool canPlace(int slot) =>
      slot >= 0 &&
      slot < Garden.slotsPerArea &&
      !placed.contains(slot) &&
      !areaLocked &&
      stars >= decorCost(slot);

  bool placeDecor(int slot) {
    if (!canPlace(slot)) return false;
    final cost = decorCost(slot);
    stars -= cost;
    placed.add(slot);
    _bump(Stat.decor);
    final area = currentArea;
    final def = Garden.areaAt(area).decor[slot];
    _events.add(DecorPlacedEvent(area, slot));
    final f = def.bringsFriend;
    if (f != null && !friends.contains(f)) {
      friends.add(f);
      _events.add(FriendJoinedEvent(f));
    }
    if (placed.length >= Garden.slotsPerArea) {
      currentArea++;
      placed = {};
      _bump(Stat.areas);
      _events.add(AreaCompletedEvent(area));
    }
    _gainXp(Leveling.xpForDecor(area, slot));
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------- 장식 디자인

  int styleOf(int area, int slot) => decorStyle['$area:$slot'] ?? 0;

  bool ownsStyle(int area, int slot, int style) => style == 0
      ? isPlaced(area, slot)
      : ownedStyles.contains('$area:$slot:$style');

  /// 디자인 바꾸기: 이미 산 것은 무료, 아니면 고급은 코인 · 특별은 다이아로 사서 바로 놓는다.
  StyleResult setStyle(int area, int slot, int style) {
    if (!isPlaced(area, slot) || style < 0 || style >= Garden.styles) {
      return StyleResult.notPlaced;
    }
    if (!ownsStyle(area, slot, style)) {
      if (Garden.isSeasonStyle(style)) {
        // 시즌 디자인은 그 시즌에만 판다
        if (style != seasonStyleNow) return StyleResult.notPlaced;
        if (!_spendGems(Garden.seasonGems, 'season_decor'))
          return StyleResult.noGems;
      } else if (style == 1) {
        final c = styleCost(area, slot);
        if (coins < c) return StyleResult.noCoins;
        coins -= c;
      } else {
        if (!_spendGems(Garden.styleGems(area), 'style'))
          return StyleResult.noGems;
      }
      ownedStyles.add('$area:$slot:$style');
      _bump(Stat.stylesBought);
      if (Garden.isSeasonStyle(style) && seasonSetComplete(area, style)) {
        _events.add(SeasonSetEvent(area, style));
      }
    }
    if (style == 0) {
      decorStyle.remove('$area:$slot');
    } else {
      decorStyle['$area:$slot'] = style;
    }
    notifyListeners();
    return StyleResult.ok;
  }

  int get seasonStyleNow => Garden.seasonStyleFor(now.month);

  /// 이 구역 시즌 세트를 다 가졌는지 ([slots] = 그림이 있는 자리들).
  bool ownsSeasonSet(int area, Iterable<int> slots) =>
      slots.every((i) => ownedStyles.contains('$area:$i:$seasonStyleNow'));

  /// 구역 시즌 세트 (8종 한 번에, 할인). 놓은 장식에는 바로 입히고, 아직 안 놓은 자리는 놓은 뒤 무료로 고른다.
  StyleResult buySeasonSet(int area, Iterable<int> slots) {
    final s = seasonStyleNow;
    if (ownsSeasonSet(area, slots)) return StyleResult.ok;
    if (!_spendGems(Garden.seasonSetGems, 'season_set'))
      return StyleResult.noGems;
    for (final i in slots) {
      ownedStyles.add('$area:$i:$s');
      if (isPlaced(area, i)) decorStyle['$area:$i'] = s;
    }
    _bump(Stat.stylesBought);
    _trace('seasonSet', '$area,$s');
    _events.add(SeasonSetEvent(area, s));
    notifyListeners();
    return StyleResult.ok;
  }

  // ---------------------------------------------------------------- 친구 의상

  String? outfitOf(String friendId) => outfits[friendId];
  bool ownsOutfit(String friendId, String outfit) =>
      ownedOutfits.contains('$friendId:$outfit');

  /// 의상 입히기 (null = 기본 옷). 안 산 의상은 다이아로 사서 바로 입힌다.
  StyleResult wearOutfit(String friendId, String? outfit) {
    if (!friends.contains(friendId)) return StyleResult.notPlaced;
    if (outfit != null) {
      final o = Outfits.byId(outfit);
      if (o == null) return StyleResult.notPlaced;
      if (!ownsOutfit(friendId, outfit)) {
        if (o.limited) return StyleResult.notPlaced; // 한정 의상은 패키지로만
        if (!o.onSaleIn(now.month))
          return StyleResult.notPlaced; // 계절 의상은 그 계절에만
        if (!_spendGems(o.gems, 'outfit')) return StyleResult.noGems;
        ownedOutfits.add('$friendId:$outfit');
        _bump(Stat.stylesBought);
      }
      outfits[friendId] = outfit;
    } else {
      outfits.remove(friendId);
    }
    notifyListeners();
    return StyleResult.ok;
  }

  // ---------------------------------------------------------------- 친구, 손님

  bool friendTapReady(String id) {
    final t = _friendTapReady[id];
    return t == null || !t.isAfter(now);
  }

  /// 친구 탭. 쿨다운이 아니면 코인을 주고 금액을 돌려준다.
  double? tapFriend(String id) {
    if (!friends.contains(id) || !friendTapReady(id)) return null;
    _friendTapReady[id] = now.add(GameConfig.friendTapCooldown);
    final v = GameConfig.friendTapCoins;
    _earn(v);
    _bump(Stat.friendTaps);
    notifyListeners();
    return v;
  }

  double visitorCoins({required bool withAd}) =>
      GameConfig.visitorCoinsOf(level, baseIncomePerSec) *
      _coinMult *
      (1 + setBonus(SetEffect.visitorCoins)) *
      (withAd ? GameConfig.visitorAdMultiplier : 1);

  /// 깜짝 손님 선물 받기. 광고를 봤으면 더 크게.
  ({double coins, int stars})? claimVisitor({required bool withAd}) {
    if (!visitorVisible) return null;
    final c = visitorCoins(withAd: withAd);
    final s = withAd ? GameConfig.visitorAdStars : 0;
    _earn(c);
    stars += s;
    visitorUntil = null;
    _bump(Stat.visitors);
    notifyListeners();
    return (coins: c, stars: s);
  }

  // ---------------------------------------------------------------- 누적 기록 · 업적

  int stat(Stat s) => stats[s] ?? 0;
  void _bump(Stat s, [int n = 1]) {
    stats[s] = stat(s) + n;
    if (!_detailed.contains(s)) _trace('act', '${s.name},$n');
  }

  /// 개발자 성장 로그로 보내는 행동 기록 (꺼져 있으면 아무것도 안 함).
  /// [type] 이 행 종류, [data] 는 쉼표로 구분한 값.
  static void Function(String type, String data)? tracer;
  void _trace(String type, String data) => tracer?.call(type, data);

  /// 따로 자세히 남기거나(합치기 · 생성 · 부탁) 너무 잦은(코인 생산) 기록은 'act' 에서 뺀다.
  static const _detailed = {
    Stat.merges,
    Stat.maxMerges,
    Stat.spawns,
    Stat.energySpent,
    Stat.orders,
    Stat.orderStars,
    Stat.coinsEarned,
    Stat.shopBuys,
    Stat.gemsSpent,
  };

  /// 판 상태 한 줄: 칸마다 사슬 글자(f 꽃 · s 간식 · t 차 · d 별가루)+단계, 빈칸 '.', 잠긴 칸 '#', 비눗방울은 뒤에 '*'.
  String boardCode() => [
    for (var i = 0; i < board.length; i++)
      if (!isCellOpen(i))
        '#'
      else if (board[i] == null)
        '.'
      else
        '${const ['f', 's', 't', 'd'][board[i]!.chain.index]}${board[i]!.level}${board[i]!.isBubble ? '*' : ''}',
  ].join(' ');

  /// 소셜 친구에게 선물을 보냈다 (업적 '선물 보내기'용).
  void recordGiftSent() {
    _bump(Stat.giftsSent);
    notifyListeners();
  }

  /// 업적이 세는 현재 값.
  int achievementValue(AchievementDef d) => switch (d.kind) {
    AchKind.stat => stat(d.stat!),
    AchKind.level => level,
    AchKind.flowerLevel => highest[Chain.flower] ?? 1,
    AchKind.snackLevel => highest[Chain.snack] ?? 1,
    AchKind.friends => friends.length,
    AchKind.maxAffection => [
      for (final f in friends)
        if (affection(f) >= Friends.maxAffection) f,
    ].length,
  };

  /// 도달한 단계 수 (0 ~ tiers.length).
  int achievementReached(AchievementDef d) {
    final v = achievementValue(d);
    return d.tiers.where((t) => v >= t).length;
  }

  int achievementClaimedTiers(AchievementDef d) => achClaimed[d.id] ?? 0;
  bool achievementClaimable(AchievementDef d) =>
      achievementClaimedTiers(d) < achievementReached(d);
  int get claimableAchievements =>
      Achievements.all.where(achievementClaimable).length;

  /// 다음 단계 보상을 받는다.
  Reward? claimAchievement(AchievementDef d) {
    if (!achievementClaimable(d)) return null;
    final tier = achievementClaimedTiers(d);
    final r = d.rewardFor(tier);
    achClaimed[d.id] = tier + 1;
    _applyReward(r);
    notifyListeners();
    return r;
  }

  /// 받을 수 있는 업적 보상을 모두 받는다 (단계가 여럿 쌓였으면 전부).
  Reward claimAllAchievements() {
    var c = 0, e = 0, st = 0, gm = 0;
    for (final d in Achievements.all) {
      for (Reward? r; (r = claimAchievement(d)) != null;) {
        c += r!.coins;
        e += r.energy;
        st += r.stars;
        gm += r.gems;
      }
    }
    return Reward(coins: c, energy: e, stars: st, gems: gm);
  }

  void _applyReward(Reward r) {
    _trace('reward', '${r.coins},${r.energy},${r.stars},${r.gems}');
    if (r.coins > 0) _earn(r.coins.toDouble());
    energy += r.energy; // 상한을 넘어도 된다
    stars += r.stars;
    gems += r.gems;
  }

  // ---------------------------------------------------------------- 출석

  bool get checkInReady => _checkInDay != _dayKey(now);
  int get checkInToday => checkInCount % CheckIn.days;
  Reward checkInReward(int day) => CheckIn.reward(day, level);

  Reward? claimCheckIn() {
    if (!checkInReady) return null;
    final r = checkInReward(checkInToday);
    _checkInDay = _dayKey(now);
    checkInCount = (checkInCount + 1) % CheckIn.days;
    _applyReward(r);
    notifyListeners();
    return r;
  }

  // ---------------------------------------------------------------- 오늘의 시장

  bool get dailyShopOpen => level >= DailyShop.unlockLevel;

  /// 오늘의 시장: ① 무료 선물 하나 ② 부탁 도우미(지금 부탁 아이템의 한 단계 아래) ③④ 부탁 단계 근처 아이템.
  /// 낮은 단계만 팔던 때는 바구니 탭보다 나을 게 없어서, 진행에 실제로 도움이 되는 것을 판다.
  List<ShopOffer> get offers {
    final k = _dayKey(now);
    // 예전 저장(다이아 · 광고 칸이 없던 목록)도 한 번 새로 만든다
    if (k != _offersDay || !_offers.any((o) => o.kind >= 3)) {
      // 같은 날 다시 만들 때(예전 저장 옮기기) 이미 받은 무료 선물은 그대로 받은 것으로
      final freeTaken =
          k == _offersDay && _offers.any((o) => o.kind == 1 && o.sold);
      _offersDay = k;
      final chains = availableChains;
      Chain pick() => chains[_rng.nextInt(chains.length)];
      final center = orderCenter.round();
      final list = <ShopOffer>[
        ShopOffer(pick(), spawnLevel + min(3, 1 + level ~/ 6), 0, kind: 1),
      ];
      final pending = [
        for (final o in orders)
          if (!canDeliver(orders.indexOf(o)) && relLevel(o.level) >= 3) o,
      ];
      if (pending.isNotEmpty) {
        final o = pending[_rng.nextInt(pending.length)];
        list.add(
          ShopOffer(
            o.chain,
            o.level - 1,
            DailyShop.price(o.chain, o.level - 1, level),
            kind: 2,
          ),
        );
      }
      while (list.length < DailyShop.slots) {
        final c = pick();
        final l = max(
          spawnLevel + 1,
          center - 2 + _rng.nextInt(2),
        ).clamp(1, Chains.maxLevel(c));
        list.add(ShopOffer(c, l, DailyShop.price(c, l, level)));
      }
      // 고단계 두 칸: 다이아로 사기 · 광고 보고 받기
      list.add(
        ShopOffer(
          pick(),
          min(
            Chains.maxLevel(Chain.flower),
            spawnLevel + Gems.marketGemLevelUp,
          ),
          Gems.marketGemPrice,
          kind: 3,
        ),
      );
      list.add(
        ShopOffer(
          pick(),
          min(Chains.maxLevel(Chain.flower), spawnLevel + Gems.marketAdLevelUp),
          0,
          kind: 4,
        ),
      );
      if (freeTaken) list.first.sold = true;
      _offers = list;
    }
    return _offers;
  }

  /// 오늘의 무료 선물을 아직 안 받았다 (상점 빨간 점).
  bool get freeOfferReady =>
      dailyShopOpen && offers.any((o) => o.kind == 1 && !o.sold);

  BuyResult buyOffer(int i, {bool adWatched = false}) {
    final o = offers[i];
    if (o.sold) return BuyResult.sold;
    if (o.kind == 4 && !adWatched) return BuyResult.needAd;
    if (o.kind == 3 ? gems < o.price : (o.kind != 4 && coins < o.price)) {
      return o.kind == 3 ? BuyResult.noGems : BuyResult.noCoins;
    }
    final cell = _emptyCell;
    if (cell == null) return BuyResult.noSpace;
    if (o.kind == 3) {
      _spendGems(o.price, 'market');
    } else if (o.kind != 4) {
      coins -= o.price;
    }
    o.sold = true;
    board[cell] = Item(_nextId++, o.chain, o.level);
    _bump(Stat.shopBuys);
    _trace('buy', '${o.chain.name},${o.level},${o.price.round()},${o.kind}');
    notifyListeners();
    return BuyResult.ok;
  }

  // ---------------------------------------------------------------- 다이아

  /// 결제 · 보상으로 받은 다이아.
  /// 다이아 팩 결제 완료: 그 팩을 처음 사면 2배. 받은 다이아 수를 돌려준다.
  int grantGemPack(GemPack p) {
    final n = p.gems * (firstPackBonus(p) ? Gems.firstBuyMultiplier : 1);
    boughtPacks.add(p.id);
    _trace('gemPack', '${p.id} +$n');
    grantGems(n);
    return n;
  }

  void grantGems(int n) {
    if (n <= 0) return;
    gems += n;
    _trace('gems', '+$n');
    notifyListeners();
  }

  bool _spendGems(int n, [String what = 'other']) {
    if (gems < n) return false;
    gems -= n;
    _bump(Stat.gemsSpent, n);
    _trace('gems', '-$n $what');
    _events.add(GemsSpentEvent(n, what));
    return true;
  }

  int get refillCost => Gems.refillCost(_gemRefillsToday);

  /// 다이아로 에너지 100 충전 (상한을 넘어도 된다).
  bool buyEnergyRefill() {
    _rollAdDay();
    if (!_spendGems(refillCost, 'energy_refill')) return false;
    _gemRefillsToday++;
    energy += Gems.refillEnergy;
    notifyListeners();
    return true;
  }

  int bubbleGemCost(int cell) {
    final it = board[cell];
    final until = it?.bubbleUntil;
    if (until == null) return 0;
    final left = until.difference(now);
    return Gems.bubbleCost(left.isNegative ? Duration.zero : left);
  }

  bool popBubbleWithGems(int cell) {
    final cost = bubbleGemCost(cell);
    if (cost <= 0 || !_spendGems(cost, 'bubble')) return false;
    return popBubble(cell);
  }

  // ---------------------------------------------------------------- 쪽지

  int get unreadMail => mail.where((m) => !m.claimed).length;

  void addMail(Mail m) {
    if (mail.any((x) => x.id == m.id)) return;
    mail.insert(0, m);
    // 오래된 받은 쪽지부터 정리
    while (mail.length > MailConfig.keep) {
      final i = mail.lastIndexWhere((x) => x.claimed);
      if (i < 0) break;
      mail.removeAt(i);
    }
    notifyListeners();
  }

  /// 쪽지 열기 · 보상 받기. 받은 보상을 돌려준다.
  /// 보상 없는 쪽지를 열어 봤다 (읽음).
  void readMail(String id) {
    final m = mail.where((x) => x.id == id).firstOrNull;
    if (m == null || m.claimed || m.hasReward) return;
    m.claimed = true;
    m.readAt = now;
    notifyListeners();
  }

  /// 읽은 쪽지 지우기 (안 받은 보상이 있는 쪽지는 지우지 않는다). 지운 수.
  int deleteMail(Iterable<String> ids) {
    final set = ids.toSet();
    final before = mail.length;
    mail.removeWhere((m) => set.contains(m.id) && m.claimed);
    final n = before - mail.length;
    if (n > 0) notifyListeners();
    return n;
  }

  /// 읽은 지 [MailConfig.keepRead] 지난 쪽지를 지운다 (오래된 것부터).
  void _expireMail() {
    final cut = now.subtract(MailConfig.keepRead);
    mail.removeWhere((m) => m.claimed && (m.readAt ?? m.at).isBefore(cut));
  }

  /// 새 버전으로 처음 열었을 때 업데이트 안내 쪽지 (그 버전의 바뀐 점 + 작은 선물). 한 번만.
  bool addUpdateMail(int versionCode, String versionName) {
    final id = 'update-$versionCode';
    if (versionCode <= 0 ||
        mail.any((m) => m.id == id) ||
        _updateSeen >= versionCode) {
      return false;
    }
    // 처음 설치한 사람(진행이 거의 없음)에게는 '업데이트' 안내를 보내지 않는다
    final fresh = _updateSeen == 0 && level <= 1;
    _updateSeen = versionCode;
    if (fresh) return false;
    addMail(
      Mail(
        id: id,
        kind: MailKind.notice,
        from: 'team',
        titleKey: 'mail.updateTitle',
        args: {'version': versionName},
        bodyKey: 'patch.$versionName',
        reward: const Reward(energy: MailConfig.updateGiftEnergy),
        at: now,
      ),
    );
    return true;
  }

  /// 마지막으로 업데이트 안내를 확인한 버전 코드.
  int _updateSeen = 0;

  Reward? claimMail(String id) {
    final m = mail.where((x) => x.id == id).firstOrNull;
    if (m == null || m.claimed) return null;
    m.claimed = true;
    m.readAt = now;
    _applyReward(m.reward);
    _bump(Stat.mailClaimed);
    notifyListeners();
    return m.reward;
  }

  Reward claimAllMail() {
    var c = 0, e = 0, s = 0, g = 0;
    for (final m in mail.where((x) => !x.claimed).toList()) {
      final r = claimMail(m.id)!;
      c += r.coins;
      e += r.energy;
      s += r.stars;
      g += r.gems;
    }
    return Reward(coins: c, energy: e, stars: s, gems: g);
  }

  void _sendWelcome() {
    if (_welcomeSent) return;
    _welcomeSent = true;
    mail.insert(
      0,
      Mail(
        id: 'welcome',
        kind: MailKind.notice,
        from: 'team',
        titleKey: 'mail.welcome',
        reward: const Reward(energy: 20, coins: 50),
        at: now,
      ),
    );
  }

  /// 동물 친구가 가끔 보내는 깜짝 선물 (3~6시간마다, 안 받은 선물은 최대 3통).
  void _maybeFriendGift() {
    final t = now;
    nextFriendGiftAt ??= t.add(MailConfig.friendGiftMinGap);
    if (t.isBefore(nextFriendGiftAt!) || friends.length < 2) return;
    final unread = mail
        .where((m) => m.kind == MailKind.friendGift && !m.claimed)
        .length;
    final gap =
        MailConfig.friendGiftMinGap.inMinutes +
        _rng.nextInt(
          MailConfig.friendGiftMaxGap.inMinutes -
              MailConfig.friendGiftMinGap.inMinutes +
              1,
        );
    nextFriendGiftAt = t.add(Duration(minutes: gap));
    if (unread >= MailConfig.friendGiftMaxUnread) return;
    final pool = friends.toList()..sort();
    final from = pool[_rng.nextInt(pool.length)];
    // 에너지 · 코인 · 드물게 별
    final roll = _rng.nextDouble();
    final reward = roll < 0.5
        ? Reward(energy: 5 + _rng.nextInt(3) * 5)
        : roll < 0.9
        ? Reward(coins: (20 + level * 5) * (1 + _rng.nextInt(2)))
        : Reward(stars: 4 + level);
    addMail(
      Mail(
        id: 'fg-${t.millisecondsSinceEpoch}',
        kind: MailKind.friendGift,
        from: from,
        titleKey: 'mail.friendGift.${_rng.nextInt(4)}',
        reward: reward,
        at: t,
      ),
    );
  }

  void _rollPlayDay() {
    final d = now;
    final k = '${d.year}-${d.month}-${d.day}';
    if (k == _playDay) return;
    _playDay = k;
    _bump(Stat.daysPlayed);
  }

  /// 도감에 새로 발견한 게 있는지 (빨간 점).
  bool get hasNewDiscovery =>
      Chain.values.any((c) => (highest[c] ?? 1) > (seenHighest[c] ?? 1));
  void markBookSeen() {
    for (final c in Chain.values) {
      seenHighest[c] = highest[c] ?? 1;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- 강화

  /// 끝없는 강화(생산력 · 수익)는 바구니 등급 물가를 따라간다 (D-038):
  /// 등급을 올렸다고 다른 강화가 상대적으로 싸지지 않게 (눈덩이 방지).
  double upgradeCost(UpgradeType t) {
    final d = Upgrades.of(t);
    return d.costAt(lv(t)) * (d.maxLevel == Upgrades.endless ? inflation : 1);
  }

  bool upgradeMaxed(UpgradeType t) => lv(t) >= Upgrades.of(t).maxLevel;

  bool upgradeFeatureLocked(UpgradeType t) {
    final f = Upgrades.of(t).feature;
    return !isUnlocked(Feature.upgrades) || (f != null && !isUnlocked(f));
  }

  /// 플레이어 레벨 상한에 걸렸는지.
  bool upgradeCapped(UpgradeType t) => level < upgradeLevelNeeded(t);
  int upgradeLevelNeeded(UpgradeType t) => Upgrades.of(t).levelFor(lv(t));

  bool canBuyUpgrade(UpgradeType t) =>
      !upgradeFeatureLocked(t) &&
      !upgradeMaxed(t) &&
      !upgradeCapped(t) &&
      coins >= upgradeCost(t);

  bool buyUpgrade(UpgradeType t) {
    if (!_buyUpgradeOnce(t)) return false;
    notifyListeners();
    return true;
  }

  bool _buyUpgradeOnce(UpgradeType t) {
    if (!canBuyUpgrade(t)) return false;
    coins -= upgradeCost(t);
    upgrades[t] = lv(t) + 1;
    if (t == UpgradeType.basketTier) _refreshOrdersForTier();
    _bump(Stat.upgradesBought);
    final every = Upgrades.milestoneEvery(t);
    if (every != null && lv(t) % every == 0) {
      _events.add(UpgradeMilestoneEvent(t, lv(t)));
    }
    return true;
  }

  /// '최대' 강화를 쓸 수 있는 강화 (바구니 등급은 한 단계씩: 부탁 단계가 함께 오른다).
  bool bulkUpgradable(UpgradeType t) => t != UpgradeType.basketTier;

  /// 지금 코인으로 한 번에 살 수 있는 단계 수 (최대 [cap]).
  int affordableUpgrades(UpgradeType t, {int cap = 999}) {
    if (!bulkUpgradable(t) || !canBuyUpgrade(t))
      return canBuyUpgrade(t) ? 1 : 0;
    final d = Upgrades.of(t);
    final mul = d.maxLevel == Upgrades.endless ? inflation : 1.0;
    var c = coins, l = lv(t), n = 0;
    while (n < cap && l < d.maxLevel && level >= d.levelFor(l)) {
      final cost = d.costAt(l) * mul;
      if (c < cost) break;
      c -= cost;
      l++;
      n++;
    }
    return n;
  }

  /// 일괄 강화 (D-048): 살 수 있는 만큼 한 번에. 산 단계 수.
  int buyUpgradeMax(UpgradeType t) {
    if (!bulkUpgradable(t)) return buyUpgrade(t) ? 1 : 0;
    var n = 0;
    while (n < 999 && _buyUpgradeOnce(t)) {
      n++;
    }
    if (n > 0) {
      _trace('upgradeMax', '${t.name},$n');
      notifyListeners();
    }
    return n;
  }

  // ---------------------------------------------------------------- 광고 보상

  void _addBoost(BoostKind k, Duration d) {
    final start = boosted(k) ? boosts[k]! : now;
    var until = start.add(d);
    final cap = now.add(Boosts.max);
    if (until.isAfter(cap)) until = cap;
    boosts[k] = until;
    notifyListeners();
  }

  /// 광고 보상 부스트.
  void grantBoostAd(BoostKind k) {
    _addBoost(k, Boosts.perAd[k]!);
    _trace('boost', '${k.name},ad');
  }

  /// 다이아로 부스트.
  bool buyBoost(BoostKind k) {
    if (!canAddBoostOf(k)) return false;
    if (!_spendGems(Boosts.gemCost[k]!, 'boost_${k.name}')) return false;
    _addBoost(k, Boosts.perGems[k]!);
    _trace('boost', '${k.name},gems');
    return true;
  }

  void grantBoost() => grantBoostAd(BoostKind.coins);

  /// 보관 부스트 한 묶음 크기(분)와 개수.
  int boostTokenPack(BoostKind k) => Starter.boostUse.inMinutes;
  int boostTokenCount(BoostKind k) =>
      ((boostTokens[k] ?? 0) / boostTokenPack(k)).ceil();

  /// 보관한 부스트 하나 켜기 (최대 60분까지만 쌓이고 남는 건 보관에 남긴다).
  bool useBoostToken(BoostKind k) {
    final have = boostTokens[k] ?? 0;
    if (have <= 0 || !canAddBoostOf(k)) return false;
    final room = (Boosts.max - boostLeft(k)).inMinutes;
    final use = min(min(have, boostTokenPack(k)), room);
    _addBoost(k, Duration(minutes: use));
    if (have - use > 0) {
      boostTokens[k] = have - use;
    } else {
      boostTokens.remove(k);
    }
    _trace('boost', '${k.name},token,$use');
    return true;
  }

  // ---------------------------------------------------------------- 새싹 정원 패키지

  /// 상점에 패키지를 보여 줄지: 안 샀고, 아직 처음 보여 주기 전이거나 7일 안.
  bool get starterVisible =>
      !starterBought && (starterOfferUntil == null || starterOfferActive);

  bool get starterOfferActive =>
      !starterBought &&
      starterOfferUntil != null &&
      starterOfferUntil!.isAfter(now);
  Duration get starterOfferLeft =>
      starterOfferActive ? starterOfferUntil!.difference(now) : Duration.zero;

  /// 팝업으로 보여 줄 때 (처음이면 48시간 타이머 시작). 보여 줄 차례가 아니면 false.
  bool showStarterOffer() {
    if (starterBought || starterShows >= 2) return false;
    if (starterShows == 1 && !starterOfferActive) return false;
    starterShows++;
    starterOfferUntil ??= now.add(Starter.offerWindow);
    notifyListeners();
    return true;
  }

  /// 결제 완료 → 지급 (한 번만).
  bool grantStarter() {
    if (starterBought) return false;
    starterBought = true;
    gems += Starter.gems;
    energy += Starter.energy;
    final from = passActive && passUntil != null && passUntil!.isAfter(now)
        ? passUntil!
        : now;
    passUntil = from.add(Starter.pass);
    for (final e in Starter.boosts.entries) {
      boostTokens[e.key] = (boostTokens[e.key] ?? 0) + e.value.inMinutes;
    }
    effects.add(Starter.effect);
    effectOn = Starter.effect;
    ownedOutfits.add('${Starter.outfitFriend}:${Starter.outfit}');
    _trace('starter', '${Starter.krw}');
    notifyListeners();
    return true;
  }

  /// 코인 꾸러미 (다이아).
  double coinPackAmount(int i) {
    final (_, hours, floor) = Gems.coinPacks[i];
    return max(
      floor * inflation * Tuning.coinScale,
      incomePerSec * 3600 * hours,
    ).roundToDouble();
  }

  bool buyCoinPack(int i) {
    if (!_spendGems(Gems.coinPacks[i].$1, 'coin_pack_$i')) return false;
    _earn(coinPackAmount(i));
    _trace('coinPack', '$i');
    notifyListeners();
    return true;
  }

  /// 지금 판 · 보관함에 있는 가장 높은 단계 (비눗방울 제외).
  int get _fieldTop {
    var top = spawnLevel;
    for (final it in [...board, ...storage]) {
      if (it != null && !it.isBubble && it.level > top) top = it.level;
    }
    return top;
  }

  /// 추천 아이템 단계 범위: 판 최고 단계 -2 ~ -1 (최소 바구니 +1).
  int get surpriseMax => max(spawnLevel + 1, _fieldTop - 1);
  int get surpriseMin => max(spawnLevel + 1, _fieldTop - 2);

  /// 추천 아이템 (다이아): 무엇을 받는지 사기 전에 정확히 보여 주고 그대로 준다 (무작위 상품이 아님, D-039).
  /// 정해진 상품은 사거나, 날이 바뀌거나, 바구니가 더 높아져 쓸모없어질 때만 새로 정한다 (다시 뽑기 없음).
  (Chain, int)? _featured;
  String _featuredDay = '';
  (Chain, int) get featuredItem {
    final f = _featured;
    if (f == null ||
        _featuredDay != _dayKey(now) ||
        f.$2 <= spawnLevel ||
        f.$2 > spawnLevel + Gems.featuredMaxAbove) {
      final chains = availableChains;
      final c = chains[_rng.nextInt(chains.length)];
      final hi = min(surpriseMax, spawnLevel + Gems.featuredMaxAbove);
      final lo = min(surpriseMin, hi);
      final l = (lo + _rng.nextInt(hi - lo + 1)).clamp(1, Chains.maxLevel(c));
      _featured = (c, l);
      _featuredDay = _dayKey(now);
      // 화면을 그리는 중에 정해질 수 있으니, 저장은 다음 틈에 (껐다 켜도 같은 상품)
      scheduleMicrotask(notifyListeners);
    }
    return _featured!;
  }

  /// 추천 아이템 값: 그 아이템을 바구니로 만드는 에너지 × 0.7.
  int get surpriseGems {
    final l = featuredItem.$2;
    return (pow(2, l - spawnLevel) * Gems.surpriseGemPerEnergy).round().clamp(
      Gems.surpriseMinGems,
      Gems.surpriseMaxGems,
    );
  }

  /// 추천 아이템 사기: 보여 준 그 아이템을 빈 칸에.
  /// [shown] = 화면에 보여 준 상품. 그사이 날이 바뀌어 상품이 달라졌으면 사지 않는다 (본 적 없는 값을 받지 않게).
  bool buySurprise({(Chain, int)? shown}) {
    final cell = _emptyCell;
    if (cell == null) return false;
    final (c, l) = featuredItem;
    if (shown != null && shown != (c, l)) {
      notifyListeners();
      return false;
    }
    if (!_spendGems(surpriseGems, 'featured')) return false;
    board[cell] = Item(_nextId++, c, l);
    _trace('featured', '${c.name}$l');
    _featured = null;
    notifyListeners();
    return true;
  }

  /// 계절 정원 효과 따로 사기.
  bool buyEffect(String id) {
    if (effects.contains(id) || !_spendGems(Gems.effectGems, 'season_effect'))
      return false;
    effects.add(id);
    effectOn = id;
    notifyListeners();
    return true;
  }

  void setEffect(String? id) {
    if (id != null && !effects.contains(id)) return;
    effectOn = id;
    notifyListeners();
  }

  bool get canAddBoost => canAddBoostOf(BoostKind.coins);

  double get coinBagAmount =>
      GameConfig.coinBagOf(level, baseIncomePerSec) * _coinMult;

  double grantCoinBag() {
    final amount = coinBagAmount;
    _earn(amount);
    coinBagReadyAt = now.add(GameConfig.coinBagCooldown);
    notifyListeners();
    return amount;
  }

  // ---------------------------------------------------------------- 오프라인

  OfflineReward? computeOffline() {
    final t = now;
    var away = t.difference(lastSeen);
    if (away < const Duration(minutes: 1)) return null;
    _rechargeBaskets(away.inMilliseconds / 1000);
    _regenEnergy(away.inMilliseconds / 1000); // 에너지는 오프라인 상한 없이 찬다 (최대치까지)
    lastSeen = t;
    // 잠깐 나갔다 온 것은 보상 없음 (최소 시간), 길수록 효율이 줄어든다 (감쇄)
    if (away < GameConfig.offlineMinAway) return null;
    if (away > offlineCap) away = offlineCap;
    final c =
        GameConfig.offlineEarnings(
          baseIncomePerSec,
          away.inSeconds.toDouble(),
        ) *
        (1 + buff(FriendBuff.offline)) *
        (1 + 0.1 * perkLv(SeedPerk.moonRest));
    if (c <= 0) return null;
    return OfflineReward(away, c);
  }

  void grantOffline(OfflineReward r, {bool doubled = false}) {
    _earn(r.coins * (doubled ? 2 : 1), live: false);
    notifyListeners();
  }

  // ---------------------------------------------------------------- 저장

  static const int saveVersion = 3;

  /// 경제 규칙 판. 2 = 부탁 별이 에너지에 비례.
  static const int econVersion = 3;

  /// 경제 v3: 옛 버전(조 단위 방치형 시절)에서 넘어온 코인이 수백만이면 코인이 의미가 없어진다.
  /// 레벨에 맞는 상한까지 줄인다 (Lv9 ≈ 2.4만).
  static double coinCapFor(int level) => 300.0 * level * level + 2000;

  /// 진행도 비교용 점수 (클라우드와 로컬 중 어느 쪽이 더 진행됐는지).
  double get progressScore =>
      level * 1e6 + decorCount * 1e3 + log(lifetimeCoins + 1);

  Map<String, dynamic> toJson() {
    savedAt = now;
    return {
      'v': saveVersion,
      'coins': coins,
      'stars': stars,
      'gems': gems,
      'checkIn': checkInCount,
      'checkInDay': _checkInDay,
      'offers': [for (final o in _offers) o.toJson()],
      'offersDay': _offersDay,
      'gemRefills': _gemRefillsToday,
      'econ': econVersion,
      'life': lifetimeCoins,
      'renew': renewCount,
      'tut': tutorial,
      'tips': tipsSeen.toList(),
      'ordDay': _ordersDay,
      'ordToday': _ordersToday,
      'seedsT': seedsTotal,
      'seedsC': seedsClaimed,
      if (_featured != null)
        'featured': [_featured!.$1.index, _featured!.$2, _featuredDay],
      'seeds': seeds,
      'runStart': runStartCoins,
      'perks': {for (final e in seedPerks.entries) e.key.name: e.value},
      'level': level,
      'xp': xp,
      'board': [for (final it in board) it?.toJson()],
      'cells': unlockedCells.toList()..sort(),
      'store': [for (final it in storage) it?.toJson()],
      'nextId': _nextId,
      'up': {for (final e in upgrades.entries) e.key.name: e.value},
      'energy': energy,
      'ep': energyProgress,
      'adsDay': _adsDay,
      'ads': {for (final e in adsToday.entries) e.key.name: e.value},
      'hi': {for (final e in highest.entries) e.key.name: e.value},
      'area': currentArea,
      'placed': placed.toList(),
      'basket': basket,
      if (decorStyle.isNotEmpty) 'styles': decorStyle,
      if (outfits.isNotEmpty) 'outfits': outfits,
      if (ownedOutfits.isNotEmpty) 'ownedOutfits': ownedOutfits.toList(),
      if (ownedStyles.isNotEmpty) 'ownedStyles': ownedStyles.toList(),
      'friends': friends.toList(),
      'deliv': deliveries,
      'orders': [for (final o in orders) o.toJson()],
      'boost': boosts[BoostKind.coins]?.millisecondsSinceEpoch,
      'boostE': boosts[BoostKind.energy]?.millisecondsSinceEpoch,
      'bCharge': basketCharge,
      'boostL': boosts[BoostKind.lucky]?.millisecondsSinceEpoch,
      'quotaDay': _quotaDay,
      'quotaUsed': starOrdersUsed,
      'quotaBonus': starOrdersBonus,
      'rerolls': rerollsToday,
      'vault': vaultOwned.toList()..sort(),
      'passDay': _passDay,
      'friendLv': friendLevels,
      'passUntil': passUntil?.millisecondsSinceEpoch,
      'starter': starterBought,
      'packs': boughtPacks.toList(),
      if (invitedBy != null) 'invitedBy': invitedBy,
      if (invitedAt != null) 'invitedAt': invitedAt!.millisecondsSinceEpoch,
      if (inviteRewarded.isNotEmpty) 'inviteRewarded': inviteRewarded.toList(),
      if (shareDay.isNotEmpty) 'shareDay': shareDay,
      if (earnRate > 0) 'earnRate': earnRate,
      if (landmarks.isNotEmpty)
        'landmarks': {for (final e in landmarks.entries) '${e.key}': e.value},
      'starterUntil': starterOfferUntil?.millisecondsSinceEpoch,
      'starterShows': starterShows,
      'passNoticeSeen': passNoticeSeen,
      'boostTokens': {for (final e in boostTokens.entries) e.key.name: e.value},
      'effects': effects.toList(),
      'effectOn': effectOn,
      'bag': coinBagReadyAt?.millisecondsSinceEpoch,
      'seen': lastSeen.millisecondsSinceEpoch,
      'visitorNext': nextVisitorAt.millisecondsSinceEpoch,
      'merges': totalMerges,
      'stats': {for (final e in stats.entries) e.key.name: e.value},
      'ach': achClaimed,
      'mail': [for (final m in mail) m.toJson()],
      if (_updateSeen > 0) 'updateSeen': _updateSeen,
      'fgNext': nextFriendGiftAt?.millisecondsSinceEpoch,
      'playDay': _playDay,
      'welcome': _welcomeSent,
      'seenHi': {for (final e in seenHighest.entries) e.key.name: e.value},
      'savedAt': savedAt!.millisecondsSinceEpoch,
    };
  }

  String encode() => jsonEncode(toJson());

  /// 저장 데이터를 불러온다. 버전이 다르면 false (새로 시작).
  bool load(String raw) {
    final Object? j;
    try {
      j = jsonDecode(raw);
    } catch (_) {
      return false;
    }
    return j is Map<String, dynamic> && loadJson(j);
  }

  /// 저장 불러오기. 전부 되거나 전혀 안 되거나: 망가진 저장이면 원래 상태로 되돌리고 false.
  bool loadJson(Map<String, dynamic> j) {
    final backup = toJson();
    try {
      return _loadJson(j);
    } catch (e) {
      debugPrint('save load failed: $e');
      _loadJson(backup);
      return false;
    }
  }

  bool _loadJson(Map<String, dynamic> j) {
    if (j['v'] != saveVersion) return false;
    // 경제 2판(별이 에너지에 비례)으로 옮기기: 남은 별은 4배, 부탁의 별은 다시 계산
    final econ = (j['econ'] as num?)?.toInt() ?? 1;
    DateTime? ts(String k) => j[k] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((j[k] as num).toInt());

    coins = (j['coins'] as num).toDouble();
    stars = (j['stars'] as num?)?.toInt() ?? 0;
    if (econ < 2) stars *= 4;
    gems = (j['gems'] as num?)?.toInt() ?? 0;
    checkInCount = (j['checkIn'] as num?)?.toInt() ?? 0;
    _checkInDay = j['checkInDay'] as String? ?? '';
    _offers = [
      for (final o in (j['offers'] as List? ?? []))
        ShopOffer.fromJson((o as Map).cast<String, dynamic>()),
    ];
    _offersDay = j['offersDay'] as String? ?? '';
    _gemRefillsToday = (j['gemRefills'] as num?)?.toInt() ?? 0;
    lifetimeCoins = (j['life'] as num?)?.toDouble() ?? coins;
    renewCount = (j['renew'] as num?)?.toInt() ?? 1;
    tutorial = (j['tut'] as num?)?.toInt() ?? -1;
    tipsSeen
      ..clear()
      ..addAll([for (final t in (j['tips'] as List?) ?? const []) '$t']);
    tipsKnown = j['tips'] != null;
    _ordersDay = j['ordDay'] as String? ?? '';
    _ordersToday = (j['ordToday'] as num?)?.toInt() ?? 0;
    seedsTotal = (j['seedsT'] as num?)?.toInt() ?? 0;
    // 예전 저장(회차 코인 공식)은 '이번 회차 시작 때까지 번 코인'의 몫을 받은 것으로 본다 (광고 덤 · 옛 공식의 차이로 재단장이 오래 막히지 않게)
    seedsClaimed =
        (j['seedsC'] as num?)?.toInt() ??
        min(
          seedsTotal,
          Renewal.seedsFor((j['runStart'] as num?)?.toDouble() ?? 0),
        );
    final fe = j['featured'];
    if (fe is List && fe.length == 3) {
      final fc = Chain
          .values[(fe[0] as num).toInt().clamp(0, Chain.values.length - 1)];
      _featured = (fc, (fe[1] as num).toInt().clamp(1, Chains.maxLevel(fc)));
      _featuredDay = fe[2] as String? ?? '';
    } else {
      _featured = null;
    }
    seeds = (j['seeds'] as num?)?.toInt() ?? 0;
    // 예전 저장(재단장 전)은 지금까지 번 코인을 이번 회차로 치지 않는다 (씨앗 과지급 방지)
    runStartCoins = (j['runStart'] as num?)?.toDouble() ?? lifetimeCoins;
    seedPerks.clear();
    for (final e in ((j['perks'] as Map?) ?? const {}).entries) {
      final k = SeedPerk.values.where((p) => p.name == e.key).firstOrNull;
      if (k != null) seedPerks[k] = (e.value as num).toInt();
    }
    level = (j['level'] as num?)?.toInt() ?? 1;
    xp = (j['xp'] as num?)?.toInt() ?? 0;
    final b = j['board'] as List;
    board = List<Item?>.filled(GameConfig.cellCount, null);
    for (var i = 0; i < b.length && i < board.length; i++) {
      if (b[i] != null)
        board[i] = Item.fromJson((b[i] as Map).cast<String, dynamic>());
    }
    unlockedCells = {
      ...GameConfig.startCells,
      for (final c in (j['cells'] as List? ?? [])) (c as num).toInt(),
    };
    final st = j['store'] as List? ?? const [];
    storage = List<Item?>.filled(
      st.length.clamp(Storage.startSlots, Storage.maxSlots),
      null,
    );
    for (var i = 0; i < st.length && i < storage.length; i++) {
      if (st[i] != null) {
        storage[i] = Item.fromJson((st[i] as Map).cast<String, dynamic>());
      }
    }
    _nextId = (j['nextId'] as num?)?.toInt() ?? 1;
    final up = (j['up'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final t in UpgradeType.values) {
      // 예전 저장의 바구니 속도(spawnSpeed) 단계는 에너지 회복 속도로 옮긴다.
      final v =
          up[t.name] ??
          (t == UpgradeType.energyRegen ? up['spawnSpeed'] : null);
      upgrades[t] = (v as num?)?.toInt() ?? 0;
    }
    energy = (j['energy'] as num?)?.toInt() ?? GameConfig.energyStart;
    energyProgress = (j['ep'] as num?)?.toDouble() ?? 0;
    _adsDay = j['adsDay'] as String? ?? '';
    adsToday.clear();
    final ads = (j['ads'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final k in AdKind.values) {
      final v = (ads[k.name] as num?)?.toInt();
      if (v != null) adsToday[k] = v;
    }
    final hi = (j['hi'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final c in Chain.values) {
      highest[c] = (hi[c.name] as num?)?.toInt() ?? 1;
    }
    currentArea = (j['area'] as num?)?.toInt() ?? 0;
    placed = {for (final s in (j['placed'] as List? ?? [])) (s as num).toInt()};
    basket = (j['basket'] as num?)?.toInt() ?? 0;
    outfits = ((j['outfits'] as Map?) ?? {}).map(
      (k, v) => MapEntry('$k', '$v'),
    );
    ownedOutfits = {for (final s in (j['ownedOutfits'] as List? ?? [])) '$s'};
    decorStyle = ((j['styles'] as Map?) ?? {}).map(
      (k, v) => MapEntry('$k', (v as num).toInt()),
    );
    ownedStyles = {for (final s in (j['ownedStyles'] as List? ?? [])) '$s'};
    friends = {
      Friends.starter,
      for (final f in (j['friends'] as List? ?? [])) f as String,
    };
    deliveries
      ..clear()
      ..addAll(
        ((j['deliv'] as Map?) ?? {}).map(
          (k, v) => MapEntry(k as String, (v as num).toInt()),
        ),
      );
    orders = [
      for (final o in (j['orders'] as List? ?? []))
        Order.fromJson((o as Map).cast<String, dynamic>()),
    ];
    if (econ < 2) {
      orders = [
        for (final o in orders)
          Order(
            o.id,
            o.friendId,
            o.chain,
            o.level,
            Garden.orderStars(relLevel(o.level)),
          ),
      ];
    }
    boosts.clear();
    for (final (k, key) in [
      (BoostKind.coins, 'boost'),
      (BoostKind.energy, 'boostE'),
      (BoostKind.lucky, 'boostL'),
    ]) {
      final t = ts(key);
      if (t != null) boosts[k] = t;
    }
    final bc = j['bCharge'] as List?;
    for (var b = 0; b < basketCharge.length; b++) {
      basketCharge[b] = bc != null && b < bc.length
          ? (bc[b] as num)
                .toDouble()
                .clamp(0, Chains.basketCharges[b])
                .toDouble()
          : Chains.basketCharges[b].toDouble();
    }
    _quotaDay = j['quotaDay'] as String? ?? '';
    Map<String, int> ints(Object? m) => {
      for (final e in ((m as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toInt(),
    };
    starOrdersUsed
      ..clear()
      ..addAll(ints(j['quotaUsed']));
    starOrdersBonus
      ..clear()
      ..addAll(ints(j['quotaBonus']));
    rerollsToday = (j['rerolls'] as num?)?.toInt() ?? 0;
    vaultOwned = {
      for (final c in (j['vault'] as List? ?? [])) (c as num).toInt(),
    };
    _passDay = j['passDay'] as String? ?? '';
    friendLevels.clear();
    if (j['friendLv'] is Map) {
      for (final e in (j['friendLv'] as Map).entries) {
        friendLevels['${e.key}'] = (e.value as num).toInt();
      }
    } else {
      // 예전 저장: 호감도가 곧 효과였다 → 친구 레벨 2까지는 그대로 이어 준다
      for (final f in friends) {
        final a = min(affection(f), 2);
        if (a > 0) friendLevels[f] = a;
      }
    }
    if (econ < 3) coins = min(coins, coinCapFor(level));
    passUntil = ts('passUntil');
    starterBought = j['starter'] as bool? ?? false;
    boughtPacks
      ..clear()
      ..addAll([for (final x in (j['packs'] as List? ?? const [])) '$x']);
    invitedBy = j['invitedBy'] as String?;
    invitedAt = ts('invitedAt');
    inviteRewarded
      ..clear()
      ..addAll([
        for (final x in (j['inviteRewarded'] as List? ?? const [])) '$x',
      ]);
    shareDay = j['shareDay'] as String? ?? '';
    earnRate = (j['earnRate'] as num?)?.toDouble() ?? 0;
    landmarks
      ..clear()
      ..addAll({
        for (final e in ((j['landmarks'] as Map?) ?? const {}).entries)
          if (int.tryParse('${e.key}') != null && e.value is num)
            int.parse('${e.key}'): (e.value as num).toInt().clamp(
              0,
              Landmarks.maxLevel,
            ),
      });
    starterOfferUntil = ts('starterUntil');
    starterShows = (j['starterShows'] as num?)?.toInt() ?? 0;
    // 예전 저장: 이미 끝난 패스는 '끝났어요' 창을 새로 띄우지 않는다
    passNoticeSeen =
        (j['passNoticeSeen'] as num?)?.toInt() ??
        (passUntil != null && !passUntil!.isAfter(now) ? 3 : 0);
    boostTokens.clear();
    for (final e in ((j['boostTokens'] as Map?) ?? const {}).entries) {
      final k = BoostKind.values.where((b) => b.name == e.key).firstOrNull;
      if (k != null) boostTokens[k] = (e.value as num).toInt();
    }
    effects = {for (final x in (j['effects'] as List? ?? [])) '$x'};
    effectOn = j['effectOn'] as String?;
    _migrateStorage();
    coinBagReadyAt = ts('bag');
    lastSeen = ts('seen') ?? now;
    nextVisitorAt = ts('visitorNext') ?? now.add(GameConfig.visitorMinGap);
    totalMerges = (j['merges'] as num?)?.toInt() ?? 0;
    stats.clear();
    final savedStats = (j['stats'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final k in Stat.values) {
      final v = (savedStats[k.name] as num?)?.toInt();
      if (v != null) stats[k] = v;
    }
    if (savedStats.isEmpty) stats[Stat.merges] = totalMerges; // 예전 저장
    achClaimed
      ..clear()
      ..addAll(
        ((j['ach'] as Map?) ?? {}).map(
          (k, v) => MapEntry(k as String, (v as num).toInt()),
        ),
      );
    mail = [
      for (final m in (j['mail'] as List? ?? []))
        Mail.fromJson((m as Map).cast<String, dynamic>()),
    ];
    nextFriendGiftAt = ts('fgNext');
    _playDay = j['playDay'] as String? ?? '';
    _welcomeSent = j['welcome'] as bool? ?? mail.isNotEmpty;
    _sendWelcome();
    _updateSeen = (j['updateSeen'] as num?)?.toInt() ?? 0;
    _expireMail();
    final sh = (j['seenHi'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final c in Chain.values) {
      seenHighest[c] = (sh[c.name] as num?)?.toInt() ?? (highest[c] ?? 1);
    }
    savedAt = ts('savedAt');
    notifyListeners();
    // 한도 · 친구 레벨 · 패스를 다 읽은 뒤에 부탁을 채운다 (예전 저장의 막힌 낮은 부탁도 바꾼다)
    _refreshOrdersForTier();
    _fillOrders();
    return true;
  }

  @override
  void dispose() {
    _events.close();
    super.dispose();
  }
}
