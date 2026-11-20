import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/game_state.dart';

/// 개발자 전용 성장 로그. 설정의 버전 글자를 7번 누르면 켜진다 (일반 플레이어에게는 보이지 않음).
/// 켜져 있으면 세션 시작 · 5분마다 · 레벨업 · 구역 완성 · 앱을 내릴 때 한 줄씩 기록하고,
/// 설정의 '성장 로그'에서 복사해 Claude 에게 붙여 넣으면 밸런스 분석에 쓴다.
class DevLog extends ChangeNotifier {
  DevLog._();
  static final DevLog instance = DevLog._();

  static const _kOn = 'dev_mode';
  static const _kLines = 'dev_growth_log';
  static const int maxLines = 600;
  static const Duration every = Duration(minutes: 5);

  SharedPreferences? _p;
  bool on = false;
  List<String> lines = [];
  DateTime? _sessionStart;
  DateTime _lastAuto = DateTime(2000);
  int _session = 0;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    on = _p!.getBool(_kOn) ?? false;
    lines = _p!.getStringList(_kLines) ?? [];
    _session = _p!.getInt('dev_session') ?? 0;
  }

  Future<void> toggle() async {
    on = !on;
    await _p?.setBool(_kOn, on);
    notifyListeners();
  }

  static const header =
      'time,session,event,min,level,xp,area,placed,coins,stars,gems,energy,cells,friends,orders,merges,spawns,energySpent,ads,upgrades,gemsSpent,achTiers,daysPlayed';

  /// 한 줄 기록. [event]: start · tick · level · area · pause.
  void record(GameState g, String event) {
    if (!on) return;
    final now = DateTime.now();
    if (event == 'start') {
      _session++;
      _p?.setInt('dev_session', _session);
      _sessionStart = now;
    }
    _sessionStart ??= now;
    final mins = now.difference(_sessionStart!).inMinutes;
    final upgrades = g.upgrades.values.fold(0, (a, b) => a + b);
    final achTiers = g.achClaimed.values.fold(0, (a, b) => a + b);
    final row = [
      now.toIso8601String().substring(0, 19),
      _session,
      event,
      mins,
      g.level,
      g.xp,
      g.currentArea,
      g.placed.length,
      g.coins.round(),
      g.stars,
      g.gems,
      g.energy,
      g.unlockedCells.length,
      g.friends.length,
      g.stat(Stat.orders),
      g.stat(Stat.merges),
      g.stat(Stat.spawns),
      g.stat(Stat.energySpent),
      g.stat(Stat.adsWatched),
      upgrades,
      g.stat(Stat.gemsSpent),
      achTiers,
      g.stat(Stat.daysPlayed),
    ].join(',');
    lines.add(row);
    if (lines.length > maxLines) lines.removeRange(0, lines.length - maxLines);
    _p?.setStringList(_kLines, lines);
    notifyListeners();
  }

  /// 주기 기록 (게임 루프에서 자주 불러도 5분에 한 번만 남는다).
  void maybeTick(GameState g) {
    if (!on) return;
    final now = DateTime.now();
    if (now.difference(_lastAuto) < every) return;
    _lastAuto = now;
    record(g, 'tick');
  }

  String export() => [header, ...lines].join('\n');

  Future<void> clear() async {
    lines = [];
    await _p?.setStringList(_kLines, lines);
    notifyListeners();
  }
}
