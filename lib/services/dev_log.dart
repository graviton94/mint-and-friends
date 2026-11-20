import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/game_state.dart';

/// 개발자 성장 로그 (장기 누적, 기기 안 파일).
///
/// 기록은 항상 한다. 보기 · 파일로 내보내기는 개발자 모드(설정의 버전 글자 7번)에서만 보인다.
/// 한 줄 = `시각,세션,종류,값...` 이고 종류는:
/// - `start` · `pause` · `level` · `area` · `manual`: 그 순간의 전체 상태 (snap 과 같은 열)
/// - `snap` (1분마다, 플레이 중일 때만): 전체 상태 + 지난 snap 이후 재화 증감
/// - `board` (5분마다 · 세션 시작): 판 30칸 상태
/// - `spawn` · `merge` · `bubble` · `order` · `reroll` · `buy` · `gems` · `reward` · `act`: 행동 하나
///
/// 파일이 [rotateBytes] 를 넘으면 `.1` 로 옮기고 새로 시작한다 (최근 두 파일 = 약 수백 시간).
class DevLog extends ChangeNotifier {
  DevLog._();
  static final DevLog instance = DevLog._();

  static const _kOn = 'dev_mode';
  static const _kSession = 'dev_session';
  static const _kOldLines = 'dev_growth_log'; // 예전 버전 (prefs 600줄): 지운다
  static const Duration snapEvery = Duration(minutes: 1);
  static const Duration boardEvery = Duration(minutes: 5);
  static const int rotateBytes = 20 * 1024 * 1024;

  static const snapCols =
      'level,xp,area,placed,coins,stars,gems,energy,cells,friends,dCoins,dStars,dGems,dEnergy,orders,merges,spawns,energySpent,ads,gemsSpent,daysPlayed';

  /// 파일 맨 앞 설명 (내보낼 때 붙인다).
  static const header = '''# mint&friends growth log v2
# time,session,type,...
# snap/start/pause/level/area/manual: $snapCols
# board: 30 cells row-major (f=flower s=snack t=tea d=stardust + level, '.' empty, '#' locked, '*' bubble)
# spawn: chain,level,basket | merge: chain,from,to (or chain,level,max,coins) | bubble: chain,level
# order: friend,chain,level,stars,coins | reroll: old>new | buy: chain,level,price,kind(0 normal,1 free,2 helper)
# gems: +n/-n | reward: coins,energy,stars,gems | act: stat,n''';

  SharedPreferences? _p;
  bool on = false;
  File? _file;
  final List<String> _buf = [];
  int _session = 0;
  int lineCount = 0;
  int bytes = 0;
  final List<String> recent = [];

  DateTime _lastSnap = DateTime(2000);
  DateTime _lastBoard = DateTime(2000);
  ({int coins, int stars, int gems, int energy})? _prev;
  GameState? _game;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    on = _p!.getBool(_kOn) ?? false;
    _session = _p!.getInt(_kSession) ?? 0;
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/growth_log.csv');
      if (await _file!.exists()) {
        bytes = await _file!.length();
        lineCount = (bytes / 70).round(); // 대략치 (내보낼 때 정확히 셈)
      }
      await _p!.remove(_kOldLines);
    } catch (_) {
      _file = null; // 웹 · 테스트 등 파일이 없는 곳: 메모리에만 (최근 줄)
    }
    GameState.tracer = _onTrace;
  }

  Future<void> toggle() async {
    on = !on;
    await _p?.setBool(_kOn, on);
    notifyListeners();
  }

  String _now() => DateTime.now().toIso8601String().substring(0, 19);

  void _write(String type, String data) {
    final line = '${_now()},$_session,$type,$data';
    _buf.add(line);
    lineCount++;
    recent.add(line);
    if (recent.length > 40) recent.removeAt(0);
    if (_buf.length >= 200) flush();
  }

  void _onTrace(String type, String data) => _write(type, data);

  String _state(GameState g, {bool delta = false}) {
    final cur = (
      coins: g.coins.round(),
      stars: g.stars,
      gems: g.gems,
      energy: g.energy,
    );
    final p = delta ? (_prev ?? cur) : cur;
    if (delta) _prev = cur;
    return [
      g.level,
      g.xp,
      g.currentArea,
      g.placed.length,
      cur.coins,
      cur.stars,
      cur.gems,
      cur.energy,
      g.unlockedCells.length,
      g.friends.length,
      cur.coins - p.coins,
      cur.stars - p.stars,
      cur.gems - p.gems,
      cur.energy - p.energy,
      g.stat(Stat.orders),
      g.stat(Stat.merges),
      g.stat(Stat.spawns),
      g.stat(Stat.energySpent),
      g.stat(Stat.adsWatched),
      g.stat(Stat.gemsSpent),
      g.stat(Stat.daysPlayed),
    ].join(',');
  }

  /// 상태 한 줄. [event]: start · pause · level · area · manual.
  void record(GameState g, String event) {
    _game = g;
    if (event == 'start') {
      _session++;
      _p?.setInt(_kSession, _session);
      _write(event, _state(g, delta: true));
      _lastSnap = DateTime.now();
      _board(g);
      notifyListeners();
      return;
    }
    _write(event, _state(g, delta: true));
    if (event == 'pause') flush();
    notifyListeners();
  }

  void _board(GameState g) {
    _lastBoard = DateTime.now();
    _write('board', g.boardCode());
  }

  /// 게임 루프에서 자주 불러도 된다: 1분마다 snap, 5분마다 board, 그때마다 파일에 씀.
  void maybeTick(GameState g) {
    _game = g;
    final now = DateTime.now();
    if (now.difference(_lastSnap) >= snapEvery) {
      _lastSnap = now;
      _write('snap', _state(g, delta: true));
      if (now.difference(_lastBoard) >= boardEvery) _board(g);
      flush();
    }
  }

  Future<void>? _flushing;

  /// 모아 둔 줄을 파일 끝에 붙인다 (순서 보장).
  Future<void> flush() {
    if (_file == null || _buf.isEmpty) return _flushing ?? Future.value();
    final chunk = '${_buf.join('\n')}\n';
    _buf.clear();
    final prev = _flushing ?? Future.value();
    final f = _file!;
    return _flushing = prev.then((_) async {
      try {
        await f.writeAsString(chunk, mode: FileMode.append, flush: true);
        bytes = await f.length();
        if (bytes > rotateBytes) {
          final old = File('${f.path}.1');
          if (await old.exists()) await old.delete();
          await f.rename(old.path);
          bytes = 0;
        }
      } catch (e) {
        debugPrint('DevLog flush failed: $e');
      }
    });
  }

  /// 지난 파일 + 지금 파일을 한 파일로 묶어 공유 시트로 내보낸다 (드라이브 · 카톡 · 메일 등).
  Future<String?> exportFile() async {
    if (_game != null) record(_game!, 'manual');
    await flush();
    final f = _file;
    if (f == null) return null;
    final out = File(
      '${(await getTemporaryDirectory()).path}/mintfriends_log_${_now().replaceAll(':', '').replaceAll('-', '').replaceAll('T', '_')}.csv',
    );
    final sink = out.openWrite()..writeln(header);
    final old = File('${f.path}.1');
    if (await old.exists()) await sink.addStream(old.openRead());
    if (await f.exists()) await sink.addStream(f.openRead());
    await sink.close();
    lineCount = (await out.readAsLines()).length - header.split('\n').length;
    notifyListeners();
    await SharePlus.instance.share(
      ShareParams(files: [XFile(out.path, mimeType: 'text/csv')], subject: out.uri.pathSegments.last),
    );
    return out.path;
  }

  Future<void> clear() async {
    _buf.clear();
    recent.clear();
    lineCount = 0;
    bytes = 0;
    try {
      if (_file != null) {
        await (_flushing ?? Future.value());
        for (final f in [_file!, File('${_file!.path}.1')]) {
          if (await f.exists()) await f.delete();
        }
      }
    } catch (_) {}
    notifyListeners();
  }
}
