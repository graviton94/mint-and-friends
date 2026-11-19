import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 게임 효과음 종류. 파일은 assets/audio/<파일명>.ogg (tool/make_audio.py 로 생성).
enum Sfx {
  tap('tap'),
  spawn('spawn'),
  merge('merge'),
  mergeBig('merge_big'),
  coin('coin'),
  deliver('deliver'),
  levelup('levelup'),
  unlock('unlock'),
  sell('sell'),
  error('error'),
  place('place'),
  splash('splash'),
  bubble('bubble'),
  open('open');

  const Sfx(this.file);
  final String file;

  String get asset => 'audio/$file.ogg';
}

/// BGM 과 효과음 재생. 앱 전체에서 하나만 쓴다([AudioService.instance]).
///
/// 소리가 안 나는 환경(테스트, 플러그인 없음 등)에서는 조용히 아무것도 하지 않는다.
class AudioService extends ChangeNotifier {
  AudioService._();
  static final AudioService instance = AudioService._();
  factory AudioService() => instance;

  /// false 면 init/play/음악 재생이 전부 no-op. `flutter test` 에서는 자동으로 false.
  static bool enabled = !_inFlutterTest();

  static bool _inFlutterTest() {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  static const String _musicKey = 'audio_music_on';
  static const String _sfxKey = 'audio_sfx_on';
  static const String _bgmAsset = 'audio/bgm_garden.ogg';
  static const double musicVolume = 0.45;
  static const double sfxVolume = 0.9;
  static const int _poolSize = 6;
  static const int _throttleMs = 40;

  bool _musicOn = true;
  bool _sfxOn = true;
  bool get musicOn => _musicOn;
  bool get sfxOn => _sfxOn;

  bool _ready = false;
  Future<void>? _initFuture;
  AudioPlayer? _music;
  bool _musicStarted = false; // startMusic 이 불렸고 아직 끄지 않음
  bool _lifecyclePaused = false;
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  final Stopwatch _clock = Stopwatch()..start();
  final Map<Sfx, int> _lastPlayed = {};

  /// 설정을 읽고 플레이어를 준비한다. 여러 번 불러도 한 번만 실행된다.
  Future<void> init() {
    if (!enabled) return Future.value();
    return _initFuture ??= _init();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _musicOn = prefs.getBool(_musicKey) ?? true;
      _sfxOn = prefs.getBool(_sfxKey) ?? true;
      notifyListeners();
    } catch (_) {}
    try {
      // 효과음은 다른 소리(BGM·다른 앱)의 오디오 포커스를 뺏지 않게 한다.
      final sfxCtx = AudioContextConfig(
        focus: AudioContextConfigFocus.mixWithOthers,
      ).build();
      for (var i = 0; i < _poolSize; i++) {
        final p = AudioPlayer(playerId: 'sfx_$i');
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setAudioContext(sfxCtx);
        await p.setVolume(sfxVolume);
        _pool.add(p);
      }
      final m = AudioPlayer(playerId: 'bgm');
      await m.setReleaseMode(ReleaseMode.loop);
      await m.setVolume(musicVolume);
      _music = m;
      // 에셋을 임시 파일로 미리 풀어 둬서 첫 재생 지연을 줄인다.
      await Future.wait([
        AudioCache.instance.load(_bgmAsset),
        for (final s in Sfx.values) AudioCache.instance.load(s.asset),
      ]);
      _ready = true;
    } catch (_) {
      _ready = _pool.isNotEmpty;
    }
  }

  Future<void> setMusic(bool on) async {
    if (_musicOn == on) return;
    _musicOn = on;
    notifyListeners();
    await _save(_musicKey, on);
    if (on) {
      await startMusic();
    } else {
      await _stopMusic();
    }
  }

  Future<void> setSfx(bool on) async {
    if (_sfxOn == on) return;
    _sfxOn = on;
    notifyListeners();
    await _save(_sfxKey, on);
  }

  Future<void> _save(String key, bool value) async {
    if (!enabled) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  /// 효과음 재생. 같은 효과음은 40 ms 안에 한 번만, 여러 효과음은 겹쳐 난다.
  void play(Sfx s) {
    if (!enabled || !_sfxOn || !_ready || _pool.isEmpty) return;
    final now = _clock.elapsedMilliseconds;
    final last = _lastPlayed[s];
    if (last != null && now - last < _throttleMs) return;
    _lastPlayed[s] = now;
    final p = _pool[_next];
    _next = (_next + 1) % _pool.length;
    unawaited(_playOn(p, s));
  }

  Future<void> _playOn(AudioPlayer p, Sfx s) async {
    try {
      await p.stop();
      await p.play(
        AssetSource(s.asset),
        volume: sfxVolume,
        mode: PlayerMode.lowLatency,
      );
    } catch (_) {}
  }

  /// BGM 반복 재생 시작(음악이 꺼져 있으면 아무것도 안 함).
  Future<void> startMusic() async {
    if (!enabled) return;
    await init();
    _musicStarted = true;
    final m = _music;
    if (!_musicOn || m == null || _lifecyclePaused) return;
    if (m.state == PlayerState.playing) return;
    try {
      if (m.state == PlayerState.paused) {
        await m.resume();
      } else {
        await m.play(AssetSource(_bgmAsset), volume: musicVolume);
      }
    } catch (_) {}
  }

  Future<void> _stopMusic() async {
    try {
      await _music?.stop();
    } catch (_) {}
  }

  /// 앱이 백그라운드로 갈 때.
  Future<void> pauseMusic() async {
    _lifecyclePaused = true;
    if (!enabled) return;
    try {
      if (_music?.state == PlayerState.playing) await _music?.pause();
    } catch (_) {}
  }

  /// 앱이 다시 앞으로 올 때.
  Future<void> resumeMusic() async {
    _lifecyclePaused = false;
    if (!enabled || !_musicStarted) return;
    await startMusic();
  }
}

/// 짧게 쓰는 효과음 호출: `sfx(Sfx.merge)`.
void sfx(Sfx s) => AudioService.instance.play(s);
