import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';

/// 게임 효과음 종류. 파일은 assets/audio/*.ogg (tool/make_audio.py 로 생성).
///
/// 자주 나는 소리(spawn/merge)는 변주 파일 여러 개 중 하나를 무작위로 골라 덜 질리게 한다.
enum Sfx {
  tap(['tap'], throttleMs: 60),
  spawn(['spawn_1', 'spawn_2', 'spawn_3'], throttleMs: 60),
  merge(['merge_1', 'merge_2', 'merge_3'], throttleMs: 60),
  // 합치기 소리 6계층 (D-076): 2~5 · 6~10 · 11~15 · 16~20 · 21~25 · 26~. 차분하게 (낮은 음 · 작은 소리).
  // merge_big 은 최고 단계 합치기(코인)에만
  merge2(['merge_t2'], throttleMs: 60),
  merge3(['merge_t3'], throttleMs: 60),
  merge4(['merge_t4'], throttleMs: 60),
  merge5(['merge_t5'], throttleMs: 60),
  merge6(['merge_t6'], throttleMs: 60),
  mergeBig(['merge_big']),
  coin(['coin']),
  spend(['spend']), // 재화를 쓸 때 (coin 을 낮고 부드럽게, D-080)
  deliver(['deliver']),
  levelup(['levelup']),
  unlock(['unlock']),
  sell(['sell']),
  error(['error']),
  place(['place']),
  splash(['splash']),
  bubble(['bubble']),
  open(['open']);

  const Sfx(this.files, {this.throttleMs = 40});

  /// 파일 이름(확장자 제외) 목록. 여러 개면 재생할 때 하나를 무작위로 고른다.
  final List<String> files;

  /// 같은 효과음을 다시 재생하기까지의 최소 간격.
  final int throttleMs;

  List<String> get assets => [for (final f in files) 'audio/$f.ogg'];

  /// 첫 번째(대표) 파일 경로.
  String get asset => assets.first;
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
  static const String _hapticKey = 'haptic_on';
  static const String _bgmAsset = 'audio/bgm_garden.ogg';
  static const double musicVolume = 0.45;
  static const double sfxVolume = 0.9;
  static const int _poolSize = 6;

  bool _musicOn = true;
  bool _sfxOn = true;
  bool get musicOn => _musicOn;
  bool get sfxOn => _sfxOn;

  /// 진동 (D-114): 손으로 합칠 때 아주 약하게, 큰 순간에만 조금 세게. 설정에서 끌 수 있다.
  bool _hapticOn = true;
  bool get hapticOn => _hapticOn;

  bool _ready = false;
  Future<void>? _initFuture;
  AudioPlayer? _music;
  bool _musicStarted = false; // startMusic 이 불렸고 아직 끄지 않음
  bool _lifecyclePaused = false;
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  final Stopwatch _clock = Stopwatch()..start();
  final Map<Sfx, int> _lastPlayed = {};
  final Random _random = Random();

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
      _hapticOn = prefs.getBool(_hapticKey) ?? true;
      notifyListeners();
    } catch (_) {}
    // 단계마다 따로 감싼다: 한 단계(저지연 모드 · 오디오 컨텍스트 · 미리 풀기)가 실패해도
    // 나머지는 살아 있게 (예전엔 첫 실패에서 BGM 플레이어까지 만들지 못해 소리가 하나도 안 났다)
    final errors = <String>[];
    Future<void> step(String name, Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        errors.add('$name:$e');
      }
    }

    AudioContext? sfxCtx;
    try {
      // 효과음 · 배경 음악 모두 다른 앱(유튜브 · 음악)의 소리를 끊지 않고 겹쳐 난다 (오디오 포커스를 뺏지 않음).
      sfxCtx = AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
          .build();
    } catch (e) {
      errors.add('ctx:$e');
    }
    for (var i = 0; i < _poolSize; i++) {
      final p = AudioPlayer(playerId: 'sfx_$i');
      await step('mode', () => p.setPlayerMode(PlayerMode.lowLatency));
      await step('release', () => p.setReleaseMode(ReleaseMode.stop));
      if (sfxCtx != null) {
        await step('context', () => p.setAudioContext(sfxCtx!));
      }
      await step('volume', () => p.setVolume(sfxVolume));
      _pool.add(p);
    }
    final m = AudioPlayer(playerId: 'bgm');
    await step('bgmLoop', () => m.setReleaseMode(ReleaseMode.loop));
    await step('bgmVolume', () => m.setVolume(musicVolume));
    if (sfxCtx != null) {
      await step('bgmContext', () => m.setAudioContext(sfxCtx!));
    }
    _music = m;
    _ready = _pool.isNotEmpty;
    // 에셋을 임시 파일로 미리 풀어 둬서 첫 재생 지연을 줄인다 (실패해도 재생은 된다).
    await step(
      'preload',
      () => Future.wait([
        AudioCache.instance.load(_bgmAsset),
        for (final s in Sfx.values)
          for (final a in s.assets) AudioCache.instance.load(a),
      ]),
    );
    status =
        'ready=$_ready pool=${_pool.length} music=$_musicOn sfx=$_sfxOn'
        '${errors.isEmpty ? '' : ' errors=${errors.take(3).join(' | ')}'}';
    notifyListeners();
  }

  /// 마지막 초기화 결과 (성장 로그에 남긴다).
  String status = 'not-init';

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

  Future<void> setHaptic(bool on) async {
    if (_hapticOn == on) return;
    _hapticOn = on;
    notifyListeners();
    await _save(_hapticKey, on);
  }

  Future<void> _save(String key, bool value) async {
    if (!enabled) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  /// 효과음 재생. 같은 효과음은 [Sfx.throttleMs] 안에 한 번만, 여러 효과음은 겹쳐 난다.
  void play(Sfx s) {
    if (!enabled || !_sfxOn || !_ready || _pool.isEmpty) return;
    final now = _clock.elapsedMilliseconds;
    final last = _lastPlayed[s];
    if (last != null && now - last < s.throttleMs) return;
    _lastPlayed[s] = now;
    final p = _pool[_next];
    _next = (_next + 1) % _pool.length;
    final assets = s.assets;
    final asset = assets.length == 1
        ? assets.first
        : assets[_random.nextInt(assets.length)];
    unawaited(_playOn(p, asset));
  }

  Future<void> _playOn(AudioPlayer p, String asset) async {
    try {
      await p.stop();
      await p.play(
        AssetSource(asset),
        volume: sfxVolume,
        mode: PlayerMode.lowLatency,
      );
    } catch (e) {
      // 저지연 모드가 안 되는 기기: 일반 모드로 다시
      try {
        await p.play(
          AssetSource(asset),
          volume: sfxVolume,
          mode: PlayerMode.mediaPlayer,
        );
      } catch (e2) {
        lastError = 'sfx:$e2';
      }
    }
  }

  String? lastError;

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
    } catch (e) {
      lastError = 'bgm:$e';
    }
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

/// 합친 결과 단계에 맞는 합치기 소리 (5단계마다 한 계층).
Sfx mergeSfx(int level) => switch (level) {
  <= 5 => Sfx.merge,
  <= 10 => Sfx.merge2,
  <= 15 => Sfx.merge3,
  <= 20 => Sfx.merge4,
  <= 25 => Sfx.merge5,
  _ => Sfx.merge6,
};

/// 짧게 쓰는 효과음 호출: `sfx(Sfx.merge)`.
void sfx(Sfx s) => AudioService.instance.play(s);

/// 진동 세기: 톡(손으로 합치기) · 쿵(최고 단계 · 행운 · 레벨업 · 새 구역).
enum Haptic { tap, big }

void haptic(Haptic h) {
  if (!AudioService.instance.hapticOn) return;
  switch (h) {
    case Haptic.tap:
      HapticFeedback.lightImpact();
    case Haptic.big:
      HapticFeedback.mediumImpact();
  }
}
