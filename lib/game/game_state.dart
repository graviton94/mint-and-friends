import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'config.dart';

class Item {
  final int id;
  int level;
  Item(this.id, this.level);

  Map<String, dynamic> toJson() => {'i': id, 'l': level};
  static Item fromJson(Map<String, dynamic> j) => Item(j['i'] as int, j['l'] as int);
}

enum MoveResult { none, moved, swapped, merged, maxMerged }

sealed class GameEvent {}

class DiscoveryEvent extends GameEvent {
  final int level;
  final double bonus;
  DiscoveryEvent(this.level, this.bonus);
}

class MaxMergeEvent extends GameEvent {
  final double payout;
  MaxMergeEvent(this.payout);
}

class GardenTaskEvent extends GameEvent {
  final int areaIndex;
  final int taskIndex;
  final bool areaCompleted;
  GardenTaskEvent(this.areaIndex, this.taskIndex, this.areaCompleted);
}

class MergeEvent extends GameEvent {
  final int cell;
  MergeEvent(this.cell);
}

class OfflineReward {
  final Duration away;
  final double coins;
  const OfflineReward(this.away, this.coins);
}

/// 게임의 모든 규칙과 상태. UI/광고/저장소와 분리되어 있어 단위 테스트 가능.
class GameState extends ChangeNotifier {
  GameState({Random? random, DateTime Function()? clock})
      : _rng = random ?? Random(),
        _clock = clock ?? DateTime.now {
    lastSeen = _clock();
  }

  final Random _rng;
  final DateTime Function() _clock;
  final _events = StreamController<GameEvent>.broadcast();
  Stream<GameEvent> get events => _events.stream;

  double coins = 0;
  double lifetimeCoins = 0;
  List<Item?> board = List<Item?>.filled(GameConfig.cellCount, null);
  int _nextId = 1;
  final Map<UpgradeType, int> upgrades = {for (final u in UpgradeType.values) u: 0};
  double spawnProgress = 0;
  double autoMergeProgress = 0;
  int highestLevel = 1;
  int gardenProgress = 0; // 완료한 정원 작업 총 개수
  DateTime? boostUntil;
  DateTime? coinBagReadyAt;
  late DateTime lastSeen;
  int totalMerges = 0;

  /// 결제 서비스에서 주입 (저장하지 않음).
  bool adFree = false;

  // ---------------------------------------------------------------- 파생 값

  int lv(UpgradeType t) => upgrades[t] ?? 0;

  double get spawnInterval => Upgrades.spawnInterval(lv(UpgradeType.spawnSpeed));
  double? get autoMergeInterval => Upgrades.autoMergeInterval(lv(UpgradeType.autoMerge));
  int get spawnLevel => Upgrades.spawnLevel(lv(UpgradeType.spawnLevel));
  Duration get offlineCap => Upgrades.offlineCap(lv(UpgradeType.offlineCap));

  int get currentArea => gardenProgress ~/ Garden.tasksPerArea;
  int get currentTaskInArea => gardenProgress % Garden.tasksPerArea;
  double get nextTaskCost => Garden.taskCost(gardenProgress);

  double get gardenMultiplier =>
      1 + gardenProgress * Garden.taskIncomeBonus + currentArea * Garden.areaIncomeBonus;

  bool get boostActive => boostUntil != null && boostUntil!.isAfter(_clock());
  Duration get boostRemaining => boostActive ? boostUntil!.difference(_clock()) : Duration.zero;

  bool get coinBagReady => coinBagReadyAt == null || !coinBagReadyAt!.isAfter(_clock());
  Duration get coinBagCooldownLeft => coinBagReady ? Duration.zero : coinBagReadyAt!.difference(_clock());

  /// 부스트 제외 초당 수익.
  double get baseIncomePerSec {
    double sum = 0;
    for (final it in board) {
      if (it != null) sum += GameConfig.incomeOf(it.level);
    }
    return sum * Upgrades.incomeMultiplier(lv(UpgradeType.income)) * gardenMultiplier;
  }

  double get incomePerSec => baseIncomePerSec * (boostActive ? 2 : 1);

  bool get boardFull => !board.contains(null);

  // ---------------------------------------------------------------- 진행

  /// 매 프레임(혹은 타이머)마다 호출. dt 초 단위.
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
    lastSeen = _clock();
    notifyListeners();
  }

  void _earn(double v) {
    coins += v;
    lifetimeCoins += v;
  }

  /// 씨앗 상자 탭: 생성 게이지를 크게 채운다.
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
    final empties = [for (var i = 0; i < board.length; i++) if (board[i] == null) i];
    if (empties.isEmpty) return null;
    final cell = empties.first;
    var level = spawnLevel;
    if (_rng.nextDouble() < GameConfig.luckySpawnChance) level += 1;
    level = min(level, GameConfig.maxLevel);
    board[cell] = Item(_nextId++, level);
    _checkDiscovery(level);
    return cell;
  }

  void _checkDiscovery(int level) {
    if (level > highestLevel) {
      highestLevel = level;
      final bonus = GameConfig.incomeOf(level) *
          Upgrades.incomeMultiplier(lv(UpgradeType.income)) *
          gardenMultiplier *
          GameConfig.discoveryBonusSeconds;
      _earn(bonus);
      _events.add(DiscoveryEvent(level, bonus));
    }
  }

  /// 드래그 앤 드롭.
  MoveResult move(int from, int to) {
    if (from == to || from < 0 || to < 0 || from >= board.length || to >= board.length) {
      return MoveResult.none;
    }
    final a = board[from];
    final b = board[to];
    if (a == null) return MoveResult.none;
    if (b == null) {
      board[to] = a;
      board[from] = null;
      notifyListeners();
      return MoveResult.moved;
    }
    if (a.level == b.level) {
      final r = _merge(from, to);
      notifyListeners();
      return r;
    }
    board[to] = a;
    board[from] = b;
    notifyListeners();
    return MoveResult.swapped;
  }

  MoveResult _merge(int from, int to) {
    final b = board[to]!;
    totalMerges++;
    board[from] = null;
    if (b.level >= GameConfig.maxLevel) {
      final payout = GameConfig.incomeOf(b.level) *
          Upgrades.incomeMultiplier(lv(UpgradeType.income)) *
          gardenMultiplier *
          GameConfig.maxMergePayoutSeconds;
      board[to] = null;
      _earn(payout);
      _events.add(MaxMergeEvent(payout));
      return MoveResult.maxMerged;
    }
    b.level += 1;
    _checkDiscovery(b.level);
    _events.add(MergeEvent(to));
    return MoveResult.merged;
  }

  /// 가장 낮은 레벨의 같은 아이템 한 쌍을 합친다.
  bool autoMergeOnce() {
    final byLevel = <int, List<int>>{};
    for (var i = 0; i < board.length; i++) {
      final it = board[i];
      if (it == null) continue;
      byLevel.putIfAbsent(it.level, () => []).add(i);
    }
    final levels = byLevel.keys.toList()..sort();
    for (final l in levels) {
      final cells = byLevel[l]!;
      if (cells.length >= 2) {
        _merge(cells[1], cells[0]);
        return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------- 구매

  double upgradeCost(UpgradeType t) => Upgrades.of(t).costAt(lv(t));
  bool upgradeMaxed(UpgradeType t) => lv(t) >= Upgrades.of(t).maxLevel;
  bool canBuyUpgrade(UpgradeType t) => !upgradeMaxed(t) && coins >= upgradeCost(t);

  bool buyUpgrade(UpgradeType t) {
    if (!canBuyUpgrade(t)) return false;
    coins -= upgradeCost(t);
    upgrades[t] = lv(t) + 1;
    notifyListeners();
    return true;
  }

  bool get canBuyGardenTask => coins >= nextTaskCost;

  bool buyGardenTask() {
    if (!canBuyGardenTask) return false;
    coins -= nextTaskCost;
    final area = currentArea;
    final task = currentTaskInArea;
    gardenProgress++;
    _events.add(GardenTaskEvent(area, task, task == Garden.tasksPerArea - 1));
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------- 광고 보상

  void grantBoost() {
    final now = _clock();
    final start = boostActive ? boostUntil! : now;
    var until = start.add(GameConfig.boostPerAd);
    final cap = now.add(GameConfig.boostMax);
    if (until.isAfter(cap)) until = cap;
    boostUntil = until;
    notifyListeners();
  }

  bool get canAddBoost => boostRemaining < GameConfig.boostMax - const Duration(minutes: 1);

  /// 코인 주머니 금액 (최소 보장값 포함).
  double get coinBagAmount => max(50, baseIncomePerSec * GameConfig.coinBagSeconds);

  double grantCoinBag() {
    final amount = coinBagAmount;
    _earn(amount);
    coinBagReadyAt = _clock().add(GameConfig.coinBagCooldown);
    notifyListeners();
    return amount;
  }

  // ---------------------------------------------------------------- 오프라인

  OfflineReward? computeOffline() {
    final now = _clock();
    var away = now.difference(lastSeen);
    if (away < const Duration(minutes: 1)) return null;
    if (away > offlineCap) away = offlineCap;
    final coins = baseIncomePerSec * away.inSeconds * GameConfig.offlineEfficiency;
    lastSeen = now;
    if (coins <= 0) return null;
    return OfflineReward(away, coins);
  }

  void grantOffline(OfflineReward r, {bool doubled = false}) {
    _earn(r.coins * (doubled ? 2 : 1));
    notifyListeners();
  }

  // ---------------------------------------------------------------- 저장

  Map<String, dynamic> toJson() => {
        'v': 1,
        'coins': coins,
        'life': lifetimeCoins,
        'board': [for (final it in board) it?.toJson()],
        'nextId': _nextId,
        'up': {for (final e in upgrades.entries) e.key.name: e.value},
        'sp': spawnProgress,
        'hl': highestLevel,
        'gp': gardenProgress,
        'boost': boostUntil?.millisecondsSinceEpoch,
        'bag': coinBagReadyAt?.millisecondsSinceEpoch,
        'seen': lastSeen.millisecondsSinceEpoch,
        'merges': totalMerges,
      };

  String encode() => jsonEncode(toJson());

  void load(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    coins = (j['coins'] as num).toDouble();
    lifetimeCoins = (j['life'] as num?)?.toDouble() ?? coins;
    final b = (j['board'] as List);
    board = List<Item?>.filled(GameConfig.cellCount, null);
    for (var i = 0; i < b.length && i < board.length; i++) {
      if (b[i] != null) board[i] = Item.fromJson((b[i] as Map).cast<String, dynamic>());
    }
    _nextId = j['nextId'] as int? ?? 1;
    final up = (j['up'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final t in UpgradeType.values) {
      upgrades[t] = (up[t.name] as int?) ?? 0;
    }
    spawnProgress = (j['sp'] as num?)?.toDouble() ?? 0;
    highestLevel = j['hl'] as int? ?? 1;
    gardenProgress = j['gp'] as int? ?? 0;
    final boost = j['boost'] as int?;
    boostUntil = boost == null ? null : DateTime.fromMillisecondsSinceEpoch(boost);
    final bag = j['bag'] as int?;
    coinBagReadyAt = bag == null ? null : DateTime.fromMillisecondsSinceEpoch(bag);
    final seen = j['seen'] as int?;
    lastSeen = seen == null ? _clock() : DateTime.fromMillisecondsSinceEpoch(seen);
    totalMerges = j['merges'] as int? ?? 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _events.close();
    super.dispose();
  }
}
