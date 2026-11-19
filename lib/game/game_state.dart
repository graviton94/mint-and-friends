import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'config.dart';

class Item {
  final int id;
  final Chain chain;
  int level;
  Item(this.id, this.chain, this.level);

  ItemDef get def => Chains.item(chain, level);

  Map<String, dynamic> toJson() => {'i': id, 'c': chain.index, 'l': level};
  static Item fromJson(Map<String, dynamic> j) =>
      Item(j['i'] as int, Chain.values[j['c'] as int], j['l'] as int);
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
  OrderDeliveredEvent(this.friendId, this.stars, this.coins, this.affectionUp);
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
  }

  final Random _rng;
  final DateTime Function() _clock;
  final _events = StreamController<GameEvent>.broadcast();
  Stream<GameEvent> get events => _events.stream;

  double coins = 0;
  int stars = 0;
  double lifetimeCoins = 0;
  List<Item?> board = List<Item?>.filled(GameConfig.cellCount, null);
  int _nextId = 1;
  final Map<UpgradeType, int> upgrades = {
    for (final u in UpgradeType.values) u: 0,
  };
  double spawnProgress = 0;
  double autoMergeProgress = 0;
  final Map<Chain, int> highest = {for (final c in Chain.values) c: 1};

  int currentArea = 0; // 지금 꾸미는 구역 (이전 구역은 모두 완성)
  Set<int> placed = {}; // 현재 구역에 설치한 장식 슬롯
  Set<String> friends = {Friends.starter};
  final Map<String, int> deliveries = {};
  List<Order> orders = [];

  DateTime? boostUntil;
  DateTime? coinBagReadyAt;
  late DateTime lastSeen;
  late DateTime nextVisitorAt;
  DateTime? visitorUntil;
  int totalMerges = 0;

  final Map<String, DateTime> _friendTapReady = {};

  /// 결제 서비스가 넣어준다 (저장하지 않음).
  bool adFree = false;

  // ---------------------------------------------------------------- 파생 값

  DateTime get now => _clock();

  int lv(UpgradeType t) => upgrades[t] ?? 0;

  int affection(String friendId) => min(
    Friends.maxAffection,
    (deliveries[friendId] ?? 0) ~/ Friends.deliveriesPerAffection,
  );

  double buff(FriendBuff b) {
    double sum = 0;
    for (final f in Friends.all) {
      if (f.buff == b && friends.contains(f.id)) {
        sum += f.perLevel * affection(f.id);
      }
    }
    return sum;
  }

  double get spawnInterval =>
      Upgrades.spawnInterval(lv(UpgradeType.spawnSpeed)) /
      (1 + buff(FriendBuff.spawnSpeed));

  double? get autoMergeInterval {
    final i = Upgrades.autoMergeInterval(lv(UpgradeType.autoMerge));
    return i == null ? null : i / (1 + buff(FriendBuff.autoMerge));
  }

  int get spawnLevel => Upgrades.spawnLevel(lv(UpgradeType.spawnLevel));
  Duration get offlineCap => Upgrades.offlineCap(lv(UpgradeType.offlineCap));

  bool isPlaced(int area, int slot) =>
      area < currentArea || (area == currentArea && placed.contains(slot));
  int get decorCount => currentArea * Garden.slotsPerArea + placed.length;

  /// 정원 매력도 = 수익 배율.
  double get gardenMultiplier =>
      1 +
      decorCount * GameConfig.decorIncomeBonus +
      currentArea * GameConfig.areaIncomeBonus;

  double get _incomeMult =>
      Upgrades.incomeMultiplier(lv(UpgradeType.income)) *
      gardenMultiplier *
      (1 + buff(FriendBuff.income));

  bool get boostActive => boostUntil != null && boostUntil!.isAfter(now);
  Duration get boostRemaining =>
      boostActive ? boostUntil!.difference(now) : Duration.zero;

  bool get coinBagReady =>
      coinBagReadyAt == null || !coinBagReadyAt!.isAfter(now);
  Duration get coinBagCooldownLeft =>
      coinBagReady ? Duration.zero : coinBagReadyAt!.difference(now);

  bool get visitorVisible => visitorUntil != null && visitorUntil!.isAfter(now);

  double get baseIncomePerSec {
    double sum = 0;
    for (final it in board) {
      if (it != null) sum += GameConfig.incomeOf(it.level);
    }
    return sum * _incomeMult;
  }

  double get incomePerSec => baseIncomePerSec * (boostActive ? 2 : 1);

  bool get boardFull => !board.contains(null);

  // ---------------------------------------------------------------- 진행

  void tick(double dt) {
    if (dt <= 0) return;
    _earn(incomePerSec * dt);

    if (boardFull) {
      spawnProgress = spawnInterval;
    } else {
      spawnProgress += dt;
      while (spawnProgress >= spawnInterval && !boardFull) {
        spawnProgress -= spawnInterval;
        _spawnOne();
      }
    }

    final ami = autoMergeInterval;
    if (ami != null) {
      autoMergeProgress += dt;
      if (autoMergeProgress >= ami) {
        autoMergeProgress = 0;
        autoMergeOnce();
      }
    }

    if (!visitorVisible && !now.isBefore(nextVisitorAt)) {
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

  void _earn(double v) {
    coins += v;
    lifetimeCoins += v;
  }

  /// 바구니 탭: 생성 게이지를 크게 채운다.
  void tapSpawner() {
    if (boardFull) return;
    spawnProgress += max(spawnInterval * 0.5, 0.4);
    if (spawnProgress >= spawnInterval) {
      spawnProgress = 0;
      _spawnOne();
    }
    notifyListeners();
  }

  int? _spawnOne() {
    final cell = board.indexOf(null);
    if (cell < 0) return null;
    final chain = Chain.values[_rng.nextInt(Chain.values.length)];
    var level = spawnLevel;
    if (_rng.nextDouble() <
        GameConfig.luckySpawnChance + buff(FriendBuff.lucky)) {
      level += 1;
    }
    level = min(level, GameConfig.maxLevel);
    board[cell] = Item(_nextId++, chain, level);
    _checkDiscovery(chain, level);
    return cell;
  }

  void _checkDiscovery(Chain chain, int level) {
    if (level > (highest[chain] ?? 1)) {
      highest[chain] = level;
      final bonus =
          GameConfig.incomeOf(level) *
          _incomeMult *
          GameConfig.discoveryBonusSeconds;
      _earn(bonus);
      _events.add(DiscoveryEvent(chain, level, bonus));
    }
  }

  /// 드래그 앤 드롭.
  MoveResult move(int from, int to) {
    if (from == to ||
        from < 0 ||
        to < 0 ||
        from >= board.length ||
        to >= board.length) {
      return MoveResult.none;
    }
    final a = board[from];
    final b = board[to];
    if (a == null) return MoveResult.none;
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
    board[from] = null;
    if (b.level >= GameConfig.maxLevel) {
      final payout =
          GameConfig.incomeOf(b.level) *
          _incomeMult *
          GameConfig.maxMergePayoutSeconds;
      board[to] = null;
      _earn(payout);
      _events.add(MaxMergeEvent(payout));
      return MoveResult.maxMerged;
    }
    b.level += 1;
    _checkDiscovery(b.chain, b.level);
    return MoveResult.merged;
  }

  bool _isOrderTarget(Item it) =>
      orders.any((o) => o.chain == it.chain && o.level == it.level);

  /// 가장 낮은 레벨의 같은 아이템 한 쌍을 합친다. 부탁에 필요한 아이템은 건드리지 않는다.
  bool autoMergeOnce() {
    final groups = <String, List<int>>{};
    for (var i = 0; i < board.length; i++) {
      final it = board[i];
      if (it == null || it.level >= GameConfig.maxLevel || _isOrderTarget(it)) {
        continue;
      }
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

  // ---------------------------------------------------------------- 부탁

  void _fillOrders() {
    while (orders.length < GameConfig.orderSlots) {
      orders.add(_newOrder());
    }
  }

  Order _newOrder() {
    final pool = friends.toList()..sort();
    final center = Garden.orderLevelCenter(currentArea, placed.length);
    for (var attempt = 0; ; attempt++) {
      final friendId = pool[_rng.nextInt(pool.length)];
      final chain = Chain.values[_rng.nextInt(Chain.values.length)];
      final level = (center + _rng.nextDouble() * 2 - 1).round().clamp(
        2,
        GameConfig.maxLevel,
      );
      final dup = orders.any((o) => o.chain == chain && o.level == level);
      if (!dup || attempt > 10) {
        return Order(
          _nextId++,
          friendId,
          chain,
          level,
          Garden.orderStars(level),
        );
      }
    }
  }

  int _findItem(Chain chain, int level) => board.indexWhere(
    (it) => it != null && it.chain == chain && it.level == level,
  );

  bool canDeliver(int orderIndex) {
    if (orderIndex < 0 || orderIndex >= orders.length) return false;
    final o = orders[orderIndex];
    return _findItem(o.chain, o.level) >= 0;
  }

  double orderCoins(Order o) =>
      GameConfig.incomeOf(o.level) *
      _incomeMult *
      GameConfig.orderCoinSeconds *
      (1 + buff(FriendBuff.orderCoins));

  bool deliver(int orderIndex) {
    if (!canDeliver(orderIndex)) return false;
    final o = orders[orderIndex];
    board[_findItem(o.chain, o.level)] = null;
    var gained = o.stars;
    if (_rng.nextDouble() < buff(FriendBuff.starBonus)) gained += 1;
    stars += gained;
    final c = orderCoins(o);
    _earn(c);
    final before = affection(o.friendId);
    deliveries[o.friendId] = (deliveries[o.friendId] ?? 0) + 1;
    final up = affection(o.friendId) > before;
    orders[orderIndex] = _placeholder;
    orders[orderIndex] = _newOrder();
    _events.add(OrderDeliveredEvent(o.friendId, gained, c, up));
    notifyListeners();
    return true;
  }

  static const _placeholder = Order(-1, '', Chain.flower, 0, 0);

  /// 부탁 교체 (보상형 광고).
  void refreshOrder(int orderIndex) {
    if (orderIndex < 0 || orderIndex >= orders.length) return;
    orders[orderIndex] = _placeholder;
    orders[orderIndex] = _newOrder();
    notifyListeners();
  }

  // ---------------------------------------------------------------- 꾸미기

  int decorCost(int slot) => Garden.decorCost(currentArea, slot);

  bool canPlace(int slot) =>
      slot >= 0 &&
      slot < Garden.slotsPerArea &&
      !placed.contains(slot) &&
      stars >= decorCost(slot);

  bool placeDecor(int slot) {
    if (!canPlace(slot)) return false;
    stars -= decorCost(slot);
    placed.add(slot);
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
      _events.add(AreaCompletedEvent(area));
    }
    notifyListeners();
    return true;
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
    final v = max(1.0, baseIncomePerSec * GameConfig.friendTapSeconds);
    _earn(v);
    notifyListeners();
    return v;
  }

  double visitorCoins({required bool withAd}) => max(
    30,
    baseIncomePerSec *
        (withAd
            ? GameConfig.visitorAdCoinSeconds
            : GameConfig.visitorCoinSeconds),
  );

  /// 깜짝 손님 선물 받기. 광고를 봤으면 더 크게.
  ({double coins, int stars})? claimVisitor({required bool withAd}) {
    if (!visitorVisible) return null;
    final c = visitorCoins(withAd: withAd);
    final s = withAd ? GameConfig.visitorAdStars : 0;
    _earn(c);
    stars += s;
    visitorUntil = null;
    notifyListeners();
    return (coins: c, stars: s);
  }

  // ---------------------------------------------------------------- 구매

  double upgradeCost(UpgradeType t) => Upgrades.of(t).costAt(lv(t));
  bool upgradeMaxed(UpgradeType t) => lv(t) >= Upgrades.of(t).maxLevel;
  bool canBuyUpgrade(UpgradeType t) =>
      !upgradeMaxed(t) && coins >= upgradeCost(t);

  bool buyUpgrade(UpgradeType t) {
    if (!canBuyUpgrade(t)) return false;
    coins -= upgradeCost(t);
    upgrades[t] = lv(t) + 1;
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------- 광고 보상

  void grantBoost() {
    final start = boostActive ? boostUntil! : now;
    var until = start.add(GameConfig.boostPerAd);
    final cap = now.add(GameConfig.boostMax);
    if (until.isAfter(cap)) until = cap;
    boostUntil = until;
    notifyListeners();
  }

  bool get canAddBoost =>
      boostRemaining < GameConfig.boostMax - const Duration(minutes: 1);

  double get coinBagAmount =>
      max(50, baseIncomePerSec * GameConfig.coinBagSeconds);

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
    if (away > offlineCap) away = offlineCap;
    final c =
        baseIncomePerSec *
        away.inSeconds *
        GameConfig.offlineEfficiency *
        (1 + buff(FriendBuff.offline));
    lastSeen = t;
    if (c <= 0) return null;
    return OfflineReward(away, c);
  }

  void grantOffline(OfflineReward r, {bool doubled = false}) {
    _earn(r.coins * (doubled ? 2 : 1));
    notifyListeners();
  }

  // ---------------------------------------------------------------- 저장

  static const int saveVersion = 2;

  Map<String, dynamic> toJson() => {
    'v': saveVersion,
    'coins': coins,
    'stars': stars,
    'life': lifetimeCoins,
    'board': [for (final it in board) it?.toJson()],
    'nextId': _nextId,
    'up': {for (final e in upgrades.entries) e.key.name: e.value},
    'sp': spawnProgress,
    'hi': {for (final e in highest.entries) e.key.name: e.value},
    'area': currentArea,
    'placed': placed.toList(),
    'friends': friends.toList(),
    'deliv': deliveries,
    'orders': [for (final o in orders) o.toJson()],
    'boost': boostUntil?.millisecondsSinceEpoch,
    'bag': coinBagReadyAt?.millisecondsSinceEpoch,
    'seen': lastSeen.millisecondsSinceEpoch,
    'visitorNext': nextVisitorAt.millisecondsSinceEpoch,
    'merges': totalMerges,
  };

  String encode() => jsonEncode(toJson());

  /// 저장 데이터를 불러온다. 버전이 다르면 false (새로 시작).
  bool load(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['v'] != saveVersion) return false;
    DateTime? ts(String k) =>
        j[k] == null ? null : DateTime.fromMillisecondsSinceEpoch(j[k] as int);

    coins = (j['coins'] as num).toDouble();
    stars = j['stars'] as int? ?? 0;
    lifetimeCoins = (j['life'] as num?)?.toDouble() ?? coins;
    final b = j['board'] as List;
    board = List<Item?>.filled(GameConfig.cellCount, null);
    for (var i = 0; i < b.length && i < board.length; i++) {
      if (b[i] != null) {
        board[i] = Item.fromJson((b[i] as Map).cast<String, dynamic>());
      }
    }
    _nextId = j['nextId'] as int? ?? 1;
    final up = (j['up'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final t in UpgradeType.values) {
      upgrades[t] = (up[t.name] as int?) ?? 0;
    }
    spawnProgress = (j['sp'] as num?)?.toDouble() ?? 0;
    final hi = (j['hi'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final c in Chain.values) {
      highest[c] = (hi[c.name] as int?) ?? 1;
    }
    currentArea = j['area'] as int? ?? 0;
    placed = {for (final s in (j['placed'] as List? ?? [])) s as int};
    friends = {
      Friends.starter,
      for (final f in (j['friends'] as List? ?? [])) f as String,
    };
    deliveries
      ..clear()
      ..addAll(
        ((j['deliv'] as Map?) ?? {}).map(
          (k, v) => MapEntry(k as String, v as int),
        ),
      );
    orders = [
      for (final o in (j['orders'] as List? ?? []))
        Order.fromJson((o as Map).cast<String, dynamic>()),
    ];
    _fillOrders();
    boostUntil = ts('boost');
    coinBagReadyAt = ts('bag');
    lastSeen = ts('seen') ?? now;
    nextVisitorAt = ts('visitorNext') ?? now.add(GameConfig.visitorMinGap);
    totalMerges = j['merges'] as int? ?? 0;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _events.close();
    super.dispose();
  }
}
