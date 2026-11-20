import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
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
  static const header =
      '''# mint&friends growth log v2
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

  /// 파일 저장이 안 될 때의 이유 (개발자 창에 그대로 보여 준다).
  String? problem;

  /// 파일에 못 쓰는 동안 줄을 메모리에 모아 둔다 (내보낼 때 쓴다).
  final List<String> _mem = [];
  static const int _memMax = 50000;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    on = _p!.getBool(_kOn) ?? false;
    _session = _p!.getInt(_kSession) ?? 0;
    _p!.remove(_kOldLines);
    // 앱 지원 폴더 → 문서 폴더 → 임시 폴더 순으로, 실제로 써지는 곳을 쓴다
    final errors = <String>[];
    for (final get in [
      getApplicationSupportDirectory,
      getApplicationDocumentsDirectory,
      getTemporaryDirectory,
    ]) {
      try {
        final dir = await get();
        await dir.create(recursive: true);
        final f = File('${dir.path}/growth_log.csv');
        await f.writeAsString('', mode: FileMode.append, flush: true);
        _file = f;
        bytes = await f.length();
        lineCount = (bytes / 70).round(); // 대략치 (내보낼 때 정확히 셈)
        break;
      } catch (e) {
        errors.add('$e');
      }
    }
    problem = _file == null ? 'no file: ${errors.join(' / ')}' : null;
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
    if (_file == null) {
      _mem.add(line);
      if (_mem.length > _memMax) _mem.removeRange(0, _mem.length - _memMax);
    }
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
    if (_file == null) _buf.clear();
    if (_file == null || _buf.isEmpty) return _flushing ?? Future.value();
    final chunk = '${_buf.join('\n')}\n';
    _buf.clear();
    final prev = _flushing ?? Future.value();
    final f = _file!;
    return _flushing = prev.then((_) async {
      try {
        await f.writeAsString(chunk, mode: FileMode.append, flush: true);
        bytes = await f.length();
        problem = null;
        if (bytes > rotateBytes) {
          final old = File('${f.path}.1');
          if (await old.exists()) await old.delete();
          await f.rename(old.path);
          bytes = 0;
        }
      } catch (e) {
        problem = 'write: $e';
        _mem.addAll(chunk.trimRight().split('\n'));
      }
      notifyListeners();
    });
  }

  /// 전체 기록 글 (설명 머리말 + 지난 파일 + 지금 파일 + 메모리에만 있는 줄).
  Future<String> _allText() async {
    final b = StringBuffer()..writeln(header);
    final f = _file;
    if (f != null) {
      for (final x in [File('${f.path}.1'), f]) {
        try {
          if (await x.exists()) b.write(await x.readAsString());
        } catch (e) {
          b.writeln('# read failed: $e');
        }
      }
    }
    for (final l in _mem) {
      b.writeln(l);
    }
    return b.toString();
  }

  /// 공유 창으로 CSV 파일을 보낸다 (드라이브 · 카톡 · 메일 등).
  /// 공유가 안 되면 전체 글을 클립보드에 복사한다. 결과 문구를 돌려준다 (화면에 그대로 보여 준다).
  Future<String> exportFile() async {
    if (_game != null) record(_game!, 'manual');
    await flush();
    await (_flushing ?? Future.value());
    final text = await _allText();
    final lines = '\n'.allMatches(text).length - header.split('\n').length;
    lineCount = max(0, lines);
    notifyListeners();
    final name =
        'mintfriends_log_${_now().replaceAll(':', '').replaceAll('-', '').replaceAll('T', '_')}.csv';
    String? shareError;
    try {
      final out = File('${(await getTemporaryDirectory()).path}/$name');
      await out.writeAsString(text, flush: true);
      final r = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(out.path, mimeType: 'text/csv', name: name)],
          subject: name,
        ),
      );
      if (r.status != ShareResultStatus.unavailable) {
        return 'ok:$lineCount';
      }
      shareError = 'share unavailable';
    } catch (e) {
      shareError = '$e';
    }
    await Clipboard.setData(ClipboardData(text: text));
    return 'clip:$lineCount:$shareError';
  }

  Future<void> clear() async {
    _buf.clear();
    recent.clear();
    lineCount = 0;
    bytes = 0;
    _mem.clear();
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
