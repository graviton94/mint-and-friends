// 밸런스 시뮬레이션 (14일, 플레이어 3유형). 실행: cp 후 flutter test, 또는 BALANCE_OUT=경로 BALANCE_DAYS=21
// ignore_for_file: avoid_print
// 밸런스 감사용 임시 시뮬레이션 (감사 후 삭제).
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mint_and_friends/game/config.dart';
import 'package:mint_and_friends/game/game_state.dart';
import 'package:mint_and_friends/game/tuning.dart';

class Profile {
  final String name;
  final List<double> sessionHours; // 하루 접속 시각
  final int sessionMin;
  final double tapsPerMin;
  final int starterGems;
  final bool spendGems;
  final bool buyStyles;
  final int seed;
  final bool focusZone; // 가장 새 바구니만 쓴다 (디자이너처럼)
  final bool boostAds;
  const Profile(
    this.name,
    this.sessionHours, {
    this.sessionMin = 12,
    this.tapsPerMin = 27,
    this.starterGems = 0,
    this.spendGems = false,
    this.buyStyles = true,
    this.seed = 1,
    this.focusZone = false,
    this.boostAds = true,
  });
  Profile withSeed(int s) => Profile(
    name,
    sessionHours,
    sessionMin: sessionMin,
    tapsPerMin: tapsPerMin,
    starterGems: starterGems,
    spendGems: spendGems,
    buyStyles: buyStyles,
    seed: s,
    focusZone: focusZone,
    boostAds: boostAds,
  );
}

class Acc {
  final Map<String, double> m = {};
  void add(String k, num v) => m[k] = (m[k] ?? 0) + v;
  double operator [](String k) => m[k] ?? 0;
}

class Sim {
  final Profile p;
  late GameState g;
  late DateTime now;
  final DateTime start = DateTime(2026, 3, 2); // 월요일
  final energyIn = Acc(); // 에너지 공급원
  final coinsIn = Acc(); // 코인 수입원
  final coinsOut = Acc(); // 코인 소비처
  final starsIn = Acc();
  int freeSpawns = 0, paidSpawns = 0;
  final Map<Chain, int> maxDay = {};
  final Map<Chain, int> spawnsBy = {for (final c in Chain.values) c: 0};
  final List<String> rows = [];
  final List<String> areaDay = []; // 구역 i+2 에 들어간 날.세션
  int gifts = 0, sells = 0, maxMerges = 0, delivered = 0;
  int adsBoost = 0, adsOther = 0;
  final rng = Random(99);

  Sim(this.p) {
    now = start.add(Duration(hours: p.sessionHours.first.floor()));
    g = GameState(random: Random(p.seed), clock: () => now);
    if (p.starterGems > 0) g.grantGems(p.starterGems);
  }

  /// 호출 전후 차이로 에너지 · 코인 · 별 출처를 기록한다.
  T track<T>(String src, T Function() fn) {
    final e0 = g.energy, l0 = g.level, c0 = g.lifetimeCoins, s0 = g.stars;
    final sp0 = g.stat(Stat.energySpent);
    final r = fn();
    var lvE = 0;
    for (var l = l0 + 1; l <= g.level; l++) {
      lvE += Leveling.levelUpEnergy(l, 0);
    }
    final dE = g.energy - e0 + (g.stat(Stat.energySpent) - sp0) - lvE;
    if (dE != 0) energyIn.add(src, dE);
    if (lvE > 0) energyIn.add('levelUp', lvE);
    final dC = g.lifetimeCoins - c0;
    if (dC > 0) coinsIn.add(src, dC);
    final dS = g.stars - s0;
    if (dS > 0) starsIn.add(src, dS);
    return r;
  }

  void spend(String cat, double before) {
    final d = before - g.coins;
    if (d > 0) coinsOut.add(cat, d);
  }

  bool _ad(AdKind k) {
    if (!g.canWatchAd(k)) return false;
    g.recordAd(k);
    if (k == AdKind.boost) {
      adsBoost++;
    } else {
      adsOther++;
    }
    return true;
  }

  bool isOrderTarget(Item it) =>
      g.orders.any((o) => o.chain == it.chain && o.level == it.level);

  /// 같은 아이템 한 쌍씩 모두 합친다 (부탁에 걸린 단계는 하나 남긴다).
  void mergeAll() {
    for (var guard = 0; guard < 60; guard++) {
      final groups = <String, List<int>>{};
      for (var i = 0; i < g.board.length; i++) {
        final it = g.board[i];
        if (it == null || it.isBubble || !g.isCellOpen(i)) continue;
        if (it.level >= Chains.maxLevel(it.chain)) continue;
        groups.putIfAbsent('${it.chain.index}-${it.level}', () => []).add(i);
      }
      var did = false;
      final keys = groups.keys.toList()..sort();
      for (final k in keys) {
        final c = groups[k]!;
        final it = g.board[c.first]!;
        // 부탁 대상이면 1개는 남긴다 (3개 이상일 때만 합침)
        final need = isOrderTarget(it) ? 3 : 2;
        if (c.length >= need) {
          track('merge', () => g.move(c[1], c[0]));
          did = true;
          break;
        }
      }
      if (!did) return;
    }
  }

  void deliverAll() {
    for (var again = true; again;) {
      again = false;
      for (var i = 0; i < g.orders.length; i++) {
        if (track('order', () => g.deliver(i))) {
          delivered++;
          again = true;
          break;
        }
      }
    }
  }

  /// 최고 단계: 하트가 덜 찬 친구에게 선물 (코인 · 하트), 모두 찼으면 별 30.
  void handleMax() {
    for (var i = 0; i < g.board.length; i++) {
      final it = g.board[i];
      if (it == null || !g.isMaxItem(it)) continue;
      final gf = g.giftableFriends;
      final to = gf.isNotEmpty ? gf.first : g.friends.first;
      if (track('gift', () => g.giftMaxItem(i, to))) gifts++;
    }
  }

  void freeSpace() {
    // 판이 꽉 차면 부탁과 상관없는 가장 낮은 아이템을 판다
    if (!g.boardFull) return;
    var low = -1;
    for (var i = 0; i < g.board.length; i++) {
      final it = g.board[i];
      if (it == null || it.isBubble || !g.isCellOpen(i) || isOrderTarget(it)) {
        continue;
      }
      if (low < 0 || it.level < g.board[low]!.level) low = i;
    }
    if (low >= 0 && track('sell', () => g.sell(low)) != null) sells++;
  }

  void buyStuff() {
    for (var guard = 0; guard < 50; guard++) {
      final cands = <(double, String, void Function())>[];
      for (final t in UpgradeType.values) {
        if (g.canBuyUpgrade(t)) {
          cands.add((g.upgradeCost(t), 'up:${t.name}', () => g.buyUpgrade(t)));
        }
      }
      if (g.level >= g.nextCellLevel && g.coins >= g.nextCellCost) {
        for (var c = 0; c < GameConfig.coinCells; c++) {
          if (!g.isCellOpen(c)) {
            cands.add((g.nextCellCost, 'cell', () => g.buyCell(c)));
            break;
          }
        }
      }
      for (final f in g.friends) {
        if (g.canLevelFriend(f)) {
          cands.add((g.friendLevelCost(f), 'friend', () => g.levelFriend(f)));
        }
      }
      if (p.buyStyles) {
        for (var a = 0; a <= g.currentArea; a++) {
          for (var s = 0; s < Garden.slotsPerArea; s++) {
            if (g.isPlaced(a, s) && !g.ownsStyle(a, s, 1)) {
              final c = g.styleCost(a, s);
              if (g.coins >= c) {
                cands.add((c, 'style', () => g.setStyle(a, s, 1)));
              }
            }
          }
        }
      }
      if (cands.isEmpty) return;
      cands.sort((a, b) => a.$1.compareTo(b.$1));
      final (cost, cat, fn) = cands.first;
      final before = g.coins;
      buys++;
      final grp = cat.startsWith('up:') ? 'upgrade' : cat;
      buysBy[grp] = (buysBy[grp] ?? 0) + 1;
      audit(cat, cost);
      if (cat == 'up:basketTier') {
        tierLog.add(
          'R${g.renewCount}:T${g.lv(UpgradeType.basketTier) + 1}@D${curDay + 1} ${(earnPerHour).toStringAsExponential(1)}/h cost ${cost.toStringAsExponential(1)}',
        );
      }
      fn();
      spend(grp, before);
    }
  }

  void market() {
    if (!g.dailyShopOpen) return;
    final offs = g.offers;
    for (var i = 0; i < offs.length; i++) {
      final o = offs[i];
      if (o.sold) continue;
      if (o.kind == 1 || o.kind == 2) {
        final before = g.coins;
        if (g.buyOffer(i) == BuyResult.ok) spend('market', before);
      }
    }
  }

  void placeDecor() {
    for (var s = 0; s < Garden.slotsPerArea; s++) {
      if (g.canPlace(s)) {
        track('decor', () => g.placeDecor(s));
        return placeDecor();
      }
    }
  }

  void housekeeping() {
    track('checkIn', () => g.claimCheckIn());
    track('mail', () => g.claimAllMail());
    track('achievement', () => g.claimAllAchievements());
  }

  /// 매 초 · 수시로 하는 광고 · 보너스.
  void ads(double sessionLeftSec) {
    // 에너지 광고 (에너지 < 20)
    if (g.energyAdAvailable && _ad(AdKind.energy)) {
      track('energyAd', () => g.grantEnergyAd());
    }
    // 부스트 광고: 에너지 절약을 세션 끝까지 덮게 쌓는다
    if (p.boostAds && g.isUnlocked(Feature.boost)) {
      while (g.boostLeft(BoostKind.energy).inSeconds < sessionLeftSec &&
          g.canAddBoostOf(BoostKind.energy) &&
          _ad(AdKind.boost)) {
        g.grantBoostAd(BoostKind.energy);
      }
    }
    if (g.isUnlocked(Feature.coinBag) &&
        g.coinBagReady &&
        _ad(AdKind.coinBag)) {
      track('coinBag', () => g.grantCoinBag());
    }
    if (g.visitorVisible) track('visitor', () => g.claimVisitor(withAd: true));
    for (var c = 0; c < g.board.length; c++) {
      final it = g.board[c];
      if (it != null && it.isBubble) g.popBubble(c);
    }
    // 부탁 한도 광고: 별 부탁이 끝난 친구에게
    if (g.quotaActive && g.orders.length < GameConfig.orderSlots) {
      for (final f in g.friends.toList()..sort()) {
        if (g.starOrdersLeft(f) <= 0 && _ad(AdKind.quota)) {
          g.grantQuotaAd(f);
          break;
        }
      }
    }
  }

  void heavyGems(double sessionLeftSec) {
    if (!p.spendGems) return;
    if (g.isUnlocked(Feature.boost) &&
        !g.boosted(BoostKind.energy) &&
        sessionLeftSec > 300 &&
        g.gems >= Boosts.gemCost[BoostKind.energy]!) {
      g.buyBoost(BoostKind.energy);
    }
    if (g.energy <= 0 &&
        !g.energyAdAvailable &&
        sessionLeftSec > 240 &&
        g.gems >= g.refillCost) {
      track('refill', () => g.buyEnergyRefill());
    }
  }

  int basketIdx = 0;
  bool basketReady(int b) {
    try {
      return (g as dynamic).basketReady(b) as bool;
    } on NoSuchMethodError {
      return true;
    }
  }

  void tap() {
    final open = g.openBaskets.where(basketReady).toList();
    if (open.isEmpty) open.add(0);
    if (p.focusZone) {
      g.selectBasket(open.last);
    } else {
      g.selectBasket(open[basketIdx % open.length]);
    }
    final sp0 = g.stat(Stat.energySpent);
    final r = track('tap', () => g.tapSpawner());
    if (r == TapResult.spawned) {
      if (g.stat(Stat.energySpent) == sp0) {
        freeSpawns++;
      } else {
        paidSpawns++;
      }
    }
    mergeAll();
    deliverAll();
    handleMax();
    if (r == TapResult.boardFull) freeSpace();
  }

  /// 세션 하나. 반환: 세션 동안 생성 수.
  int session(int day, double hour) {
    now = start.add(Duration(days: day, minutes: (hour * 60).round()));
    curDay = day;
    final off = track('offline', () => g.computeOffline());
    if (off != null) track('offline', () => g.grantOffline(off, doubled: true));
    housekeeping();
    final sp0 = freeSpawns + paidSpawns;
    final secs = p.sessionMin * 60;
    var acc = 0.0;
    for (var s = 0; s < secs; s++) {
      now = now.add(const Duration(seconds: 1));
      track('regen', () => g.tick(1));
      final left = (secs - s).toDouble();
      ads(left);
      heavyGems(left);
      if (s % 60 == 0) basketIdx++;
      acc += p.tapsPerMin / 60;
      while (acc >= 1) {
        acc -= 1;
        tap();
      }
      if (s % 60 == 0) _earnLog.add((now, g.lifetimeCoins));
      if (s % 5 == 0) {
        mergeAll();
        deliverAll();
        handleMax();
        placeDecor();
        maybeRenew(day);
        buyStuff();
        if (s % 60 == 0) market();
        housekeeping();
      }
    }
    while (areaDay.length < g.currentArea) {
      areaDay.add('${day + 1}.${p.sessionHours.indexOf(hour) + 1}');
    }
    for (final c in Chain.values) {
      if (!maxDay.containsKey(c) && g.highest[c]! >= Chains.maxLevel(c)) {
        maxDay[c] = day + 1;
      }
    }
    return freeSpawns + paidSpawns - sp0;
  }

  void runDays(int days, {void Function(int day)? afterDay}) {
    for (var d = 0; d < days; d++) {
      for (final h in p.sessionHours) {
        session(d, h);
      }
      rows.add(dayRow(d + 1));
      afterDay?.call(d + 1);
    }
  }

  final List<String> renews = [];

  /// 재단장: 지금 받을 씨앗이 가진 씨앗의 절반(최소 3) 이상이면 한다 (흔한 환생 기준). 씨앗 강화는 싼 것부터.
  void maybeRenew(int day) {
    if (!g.canRenew) return;
    final n = g.renewSeedsPreview;
    if (n < max(3, g.seedsTotal ~/ 2)) return;
    final got = g.renew(withAd: true);
    renews.add('D${day + 1}:+$got');
    for (var guard = 0; guard < 50; guard++) {
      final c =
          [
            for (final d in Renewal.perks)
              if (g.canBuyPerk(d.perk)) d,
          ]..sort(
            (a, b) => a
                .costAt(g.perkLv(a.perk))
                .compareTo(b.costAt(g.perkLv(b.perk))),
          );
      if (c.isEmpty) break;
      g.buyPerk(c.first.perk);
    }
  }

  // ---- 경제 감사: 살 때 값이 '최근 24시간 실제 수입'의 몇 시간치인가
  final List<(DateTime, double)> _earnLog = [];

  /// 최근 24시간(게임 시각) 동안 번 코인 ÷ 24 = 시간당 실수입.
  double get earnPerHour {
    final cut = now.subtract(const Duration(hours: 24));
    final old = _earnLog.lastWhere(
      (e) => !e.$1.isAfter(cut),
      orElse: () => _earnLog.isEmpty ? (now, g.lifetimeCoins) : _earnLog.first,
    );
    final hrs = max(1.0, now.difference(old.$1).inMinutes / 60);
    return max(1.0, (g.lifetimeCoins - old.$2) / hrs);
  }

  static String bucket(int day) => day <= 7
      ? 'W1'
      : day <= 30
      ? 'M1'
      : day <= 90
      ? 'M3'
      : 'Y1';
  final Map<String, Map<String, List<double>>> auditH = {};
  int curDay = 0;
  void audit(String cat, double cost) {
    final h = cost / earnPerHour;
    auditH
        .putIfAbsent(cat, () => {})
        .putIfAbsent(bucket(curDay + 1), () => [])
        .add(h);
  }

  String auditReport() {
    String f(double h) => h < 1 / 60
        ? '${(h * 3600).toStringAsFixed(0)}s'
        : h < 1
        ? '${(h * 60).toStringAsFixed(1)}m'
        : '${h.toStringAsFixed(1)}h';
    final b = StringBuffer(
      'audit (cost in hours of real income; median [p10..p90] n):\n',
    );
    final keys = auditH.keys.toList()..sort();
    for (final k in keys) {
      final row = StringBuffer('  ${k.padRight(18)}');
      for (final bk in ['W1', 'M1', 'M3', 'Y1']) {
        final l = auditH[k]![bk];
        if (l == null || l.isEmpty) {
          row.write(' | $bk -');
          continue;
        }
        l.sort();
        double q(double p) => l[((l.length - 1) * p).round()];
        row.write(' | $bk ${f(q(.5))} [${f(q(.1))}..${f(q(.9))}] ${l.length}');
      }
      b.writeln(row);
    }
    return b.toString();
  }

  final List<String> tierLog = [];
  int buys = 0;
  final Map<String, int> buysBy = {};
  double _lastRate = 0;

  String dayRow(int day) {
    final rate = g.incomePerSec * 3600;
    final rateGrowth = _lastRate > 0 ? rate / _lastRate : 0;
    _lastRate = rate;
    final buyStr =
        'buys $buys ${buysBy.entries.map((e) => '${e.key}:${e.value}').join(',')} '
        'rate/h ${rate.toStringAsExponential(2)} x${rateGrowth.toStringAsFixed(2)} ';
    buys = 0;
    buysBy.clear();
    final earned = g.lifetimeCoins;
    final spent = coinsOut.m.values.fold(0.0, (a, b) => a + b);
    final funcSpent = spent - coinsOut['style'];
    final shares = coinsIn.m.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    final totalIn = shares.fold(0.0, (a, e) => a + e.value);
    final shareStr = shares
        .take(5)
        .map((e) => '${e.key}${(100 * e.value / max(1, totalIn)).round()}%')
        .join(' ');
    final h = g.highest;
    final up = UpgradeType.values.map((t) => g.lv(t)).join('/');
    final fl = [for (final f in g.friends.toList()..sort()) g.friendLevel(f)];
    return 'D$day R${g.renewCount} seeds${g.seedsTotal} Lv${g.level} area${g.currentArea + 1}(${g.placed.length}/8) '
        'items f${h[Chain.flower]} s${h[Chain.snack]} t${h[Chain.tea]} d${h[Chain.stardust]} '
        'coins earned ${earned.toStringAsExponential(2)} spent ${spent.toStringAsExponential(2)} '
        '(sink ${(100 * spent / max(1, earned)).round()}% func ${(100 * funcSpent / max(1, earned)).round()}%) '
        'bal ${g.coins.toStringAsExponential(2)} stars ${g.stars} gems ${g.gems} '
        'spawns paid $paidSpawns free $freeSpawns '
        'upg[$up] cells ${g.cellsPurchased} friends ${fl.join(',')} '
        'gifts $gifts sells $sells orders ${g.stat(Stat.orders)} | $buyStr| in: $shareStr';
  }

  String summary() {
    String fmt(Acc a) =>
        (a.m.entries.toList()..sort((x, y) => y.value.compareTo(x.value)))
            .map((e) => '${e.key}=${e.value.round()}')
            .join(' ');
    return [
      '== ${p.name} ==',
      ...rows,
      'areaEnter(2..): $areaDay',
      'maxDay: ${maxDay.map((k, v) => MapEntry(k.name, v))}',
      'renews(${renews.length}): ${renews.join(' ')}',
      'energyIn: ${fmt(energyIn)} | freeSpawns=$freeSpawns',
      'coinsIn: ${fmt(coinsIn)}',
      'coinsOut: ${fmt(coinsOut)}',
      'starsIn: ${fmt(starsIn)}',
      'ads: boost=$adsBoost other=$adsOther delivered=$delivered',
      auditReport(),
      'tiers: ${tierLog.take(40).join(' | ')}',
    ].join('\n');
  }
}

const profA = Profile('A engaged free', [8, 12.5, 18, 22]);
const profC = Profile('C focus-zone (designer-like, 4x12min)', [
  8,
  12.5,
  18,
  22,
], focusZone: true);
const profN = Profile('A-noBoostAds', [8, 12.5, 18, 22], boostAds: false);
const profS = Profile('A-noStyles (coins only on functional sinks)', [
  8,
  12.5,
  18,
  22,
], buyStyles: false);
const profB = Profile(
  'B heavy',
  [7, 9, 11, 13, 15, 17, 19, 22],
  starterGems: 500,
  spendGems: true,
);

void main() {
  final out = Platform.environment['BALANCE_OUT'] ?? 'build/balance.txt';
  final days = int.tryParse(Platform.environment['BALANCE_DAYS'] ?? '') ?? 14;
  final buf = StringBuffer();

  setUp(() {
    Chains.ready = (_) => true; // 찻잎 · 별가루 그림은 assets 에 모두 있다
    Garden.ready = (_) => true;
    final a = double.tryParse(Platform.environment['AREA_STAR_SCALE'] ?? '');
    if (a != null) Tuning.areaStarScale = a;
  });

  test('profiles', () {
    final only = Platform.environment['BALANCE_PROFILES'];
    final seeds = only == null ? [1, 2, 3] : [1];
    for (final p in [profA, profB, profC, profN, profS]) {
      if (only != null && !only.split(',').contains(p.name.split(' ').first))
        continue;
      for (final seed in seeds) {
        final s = Sim(p.withSeed(seed));
        s.runDays(days);
        buf.writeln('seed $seed');
        buf.writeln(s.summary());
      }
    }
    File(out).writeAsStringSync(buf.toString());
  }, timeout: const Timeout(Duration(minutes: 30)));

  test('boost per-session multiplier', () {
    // 7일차 A 상태에서 같은 세션을 부스트 조건만 바꿔 돌린다
    final base = Sim(profA)..runDays(6);
    final saved = base.g.encode();
    final lines = StringBuffer(
      '\n== boost session test (day7 08:00, A state Lv${base.g.level}) ==\n',
    );
    for (final mode in ['none', 'cover(3 ads)', 'none30', 'stack6']) {
      var tot = 0, totFree = 0;
      for (var seed = 1; seed <= 10; seed++) {
        final s = Sim(
          Profile(
            'x',
            [8],
            buyStyles: true,
            seed: 7,
            sessionMin: mode == 'none30' || mode == 'stack6' ? 30 : 12,
          ),
        );
        s.now = s.start.add(const Duration(days: 6, hours: 7, minutes: 59));
        s.g = GameState(random: Random(seed), clock: () => s.now);
        s.g.load(saved);
        // 광고 자동 부스트는 끈다: 모드별로 직접 준다
        s.now = s.start.add(const Duration(days: 6, hours: 8));
        final off = s.g.computeOffline();
        if (off != null) s.g.grantOffline(off);
        if (mode == 'cover(3 ads)' || mode == 'stack6') {
          final n = mode == 'stack6' ? 6 : 3;
          for (var i = 0; i < n; i++) {
            s.g.grantBoostAd(BoostKind.energy);
            s.g.recordAd(AdKind.boost);
          }
        }
        for (var i = 0; i < 5; i++) {
          s.g.recordAd(AdKind.energy);
        }
        s.g.claimAllAchievements();
        s.g.claimAllMail();
        s.g.energy = 100;
        if (mode == 'none' || mode == 'none30') {
          for (var i = 0; i < 6; i++) {
            s.g.recordAd(AdKind.boost); // 광고 부스트 소진 처리
          }
        }
        if (mode == 'gems15') {
          s.g.grantGems(40);
          s.g.buyBoost(BoostKind.energy);
        }
        final e0 = s.g.energy;
        final n = s.session(6, 8.0 + 1 / 60);
        tot += n;
        totFree += s.freeSpawns;
        if (seed == 1) lines.writeln('$mode seed1 startE=$e0 spawns=$n');
      }
      lines.writeln('$mode: mean spawns ${tot / 10} free ${totFree / 10}');
    }
    File(out).writeAsStringSync(lines.toString(), mode: FileMode.append);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
