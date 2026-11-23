import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/game_state.dart';
import 'crash_service.dart';

/// 저장 데이터 요약 (충돌 시 사용자에게 보여줌).
class SaveSummary {
  final int level;
  final int area;
  final double progress;
  final DateTime? savedAt;
  const SaveSummary(this.level, this.area, this.progress, this.savedAt);

  static SaveSummary of(Map<String, dynamic> j) {
    final level = (j['level'] as num?)?.toInt() ?? 1;
    final area = (j['area'] as num?)?.toInt() ?? 0;
    final placed = (j['placed'] as List?)?.length ?? 0;
    final saved = (j['savedAt'] as num?)?.toInt();
    return SaveSummary(
      level,
      area,
      level * 1e6 + (area * 8 + placed) * 1e3,
      saved == null ? null : DateTime.fromMillisecondsSinceEpoch(saved),
    );
  }

  /// 막 시작한 게임인지 (덮어써도 아깝지 않은지).
  bool get isFresh => level <= 1 && area == 0 && progress < 1e6 + 1e3;
}

enum SyncDecision { uploadLocal, useCloud, ask }

/// 로그인 직후 기기 데이터와 클라우드 데이터 중 무엇을 쓸지 정한다 (순수 함수, 테스트 대상).
SyncDecision decideSync({
  required SaveSummary? local,
  required String? localOwner,
  required SaveSummary? cloud,
  required String uid,
}) {
  if (cloud == null) return SyncDecision.uploadLocal;
  if (local == null || local.isFresh) return SyncDecision.useCloud;
  if (localOwner == uid) {
    final l = local.savedAt, c = cloud.savedAt;
    if (l == null || c == null)
      return local.progress >= cloud.progress
          ? SyncDecision.uploadLocal
          : SyncDecision.useCloud;
    return l.isBefore(c) ? SyncDecision.useCloud : SyncDecision.uploadLocal;
  }
  // 다른 계정(또는 게스트)으로 쌓은 기기 데이터 + 클라우드에도 진행도 → 사용자에게 묻는다
  return SyncDecision.ask;
}

enum SyncStatus { local, syncing, synced, error }

/// 클라우드 읽기 (테스트에서 바꿔 끼운다).
typedef CloudFetch = Future<Map<String, dynamic>?> Function(String uid);

/// 클라우드 쓰기 (테스트에서 바꿔 끼운다).
typedef CloudWrite = Future<void> Function(
  String uid,
  String json,
  GameState game,
);

/// 기기 저장(SharedPreferences, Google 백업 대상) + 클라우드 저장(Firestore users/{uid}).
class SaveService extends ChangeNotifier {
  static const _key = 'save_v3';
  static const _ownerKey = 'save_owner';
  static const Duration cloudInterval = Duration(seconds: 60);

  SaveService(this._prefs, {CloudFetch? fetch, CloudWrite? write})
    : _fetchOverride = fetch,
      _writeOverride = write;
  final SharedPreferences _prefs;
  SharedPreferences get prefs => _prefs;
  final CloudFetch? _fetchOverride;
  final CloudWrite? _writeOverride;

  String? uid; // 클라우드 저장 대상 (null 이면 기기에만 저장)
  SyncStatus status = SyncStatus.local;
  DateTime? lastCloudSave;
  Timer? _timer;
  Future<bool>? _inflight;

  /// 연결 중인 계정 (결정이 끝나기 전에는 uid 로 붙이지 않는다).
  String? _pendingUid;
  bool get attaching => _pendingUid != null;

  String? get localOwner => _prefs.getString(_ownerKey);

  /// 마지막으로 기기에 저장된 시각 (저장된 값 그대로. toJson 은 지금 시각을 찍으므로 쓰지 않는다).
  DateTime? get localSavedAt {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw);
      final t = j is Map ? (j['savedAt'] as num?)?.toInt() : null;
      return t == null ? null : DateTime.fromMillisecondsSinceEpoch(t);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- 기기

  /// 기기 저장을 불러온다. 없거나 버전이 다르면 false.
  bool loadLocal(GameState game) {
    final raw = _prefs.getString(_key);
    if (raw == null) return false;
    try {
      return game.load(raw);
    } catch (_) {
      return false;
    }
  }

  void saveLocal(GameState game) {
    _prefs.setString(_key, game.encode());
    // 계정 연결 중에는 주인을 바꾸지 않는다 (충돌 질문을 건너뛰지 않게)
    if (uid != null && _pendingUid == null) _prefs.setString(_ownerKey, uid!);
  }

  Future<void> clearLocal() async {
    await _prefs.remove(_key);
    await _prefs.remove(_ownerKey);
  }

  // ---------------------------------------------------------------- 클라우드

  DocumentReference<Map<String, dynamic>> _doc(String id) =>
      FirebaseFirestore.instance.collection('users').doc(id);

  Future<Map<String, dynamic>?> _fetchCloud(String id) async {
    final f = _fetchOverride;
    if (f != null) return f(id);
    // 연결이 막히면 Firestore 는 오래 기다린다: 제한 시간 뒤에는 실패로 보고 나중에 다시.
    final snap = await _doc(id).get().timeout(const Duration(seconds: 12));
    final data = snap.data();
    final raw = data?['data'] as String?;
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _writeCloud(String id, String json, GameState game) async {
    final w = _writeOverride;
    if (w != null) return w(id, json, game);
    await _doc(id)
        .set({
          'data': json,
          'level': game.level,
          'area': game.currentArea,
          'progress': game.progressScore,
          'updatedAt': FieldValue.serverTimestamp(),
          'schema': GameState.saveVersion,
        })
        .timeout(
          const Duration(seconds: 20),
        ); // 오프라인이면 끝나지 않는다 (쓰기는 Firestore 가 대기열에 둔다)
  }

  /// 로그인 직후 호출. 충돌이면 [askUser] 로 물어본다 (true = 클라우드 사용).
  /// 클라우드를 읽지 못하면 false (uid 를 붙이지 않는다: 읽지 못한 클라우드를 기기 진행으로 덮어쓰지 않게).
  Future<bool> attach(
    String newUid,
    GameState game, {
    required Future<bool> Function(SaveSummary local, SaveSummary cloud)
    askUser,
  }) async {
    // 무엇보다 먼저: 기기 저장의 주인과 저장 시각을 잡아 두고, 주기 업로드를 멈춘다.
    // (가져오는 동안 자동 저장이 주인 · 시각을 바꾸면 충돌 질문 없이 덮어쓴다)
    final owner = localOwner;
    final savedAt = localSavedAt;
    _timer?.cancel();
    _timer = null;
    _pendingUid = newUid;
    uid = null; // 결정 전에는 어디에도 올리지 않는다
    status = SyncStatus.syncing;
    notifyListeners();
    try {
      final cloudJson = await _fetchCloud(newUid);
      final l = SaveSummary.of(game.toJson());
      final local = SaveSummary(l.level, l.area, l.progress, savedAt);
      final cloud = cloudJson == null ? null : SaveSummary.of(cloudJson);
      var decision = decideSync(
        local: local,
        localOwner: owner,
        cloud: cloud,
        uid: newUid,
      );
      if (decision == SyncDecision.ask) {
        decision = await askUser(local, cloud!)
            ? SyncDecision.useCloud
            : SyncDecision.uploadLocal;
      }
      if (decision == SyncDecision.useCloud && cloudJson != null) {
        // 불러오지 못한 클라우드 저장(버전 · 손상)은 오류: 올리지도, 동기화됐다고 하지도 않는다
        if (!game.loadJson(cloudJson)) {
          throw StateError('cloud save could not be loaded');
        }
        _pendingUid = null;
        uid = newUid;
        saveLocal(game);
        status = SyncStatus.synced;
        lastCloudSave = DateTime.now();
      } else {
        _pendingUid = null;
        uid = newUid;
        saveLocal(game);
        await upload(game);
      }
    } catch (e) {
      debugPrint('cloud attach failed: $e');
      _pendingUid = null;
      uid = null;
      status = SyncStatus.error;
      notifyListeners();
      return false;
    }
    _timer?.cancel();
    _timer = Timer.periodic(cloudInterval, (_) => upload(game));
    notifyListeners();
    return true;
  }

  void detach() {
    _timer?.cancel();
    _timer = null;
    _pendingUid = null;
    uid = null;
    status = SyncStatus.local;
    notifyListeners();
  }

  /// 클라우드에 올린다. 실제로 올라갔으면 true.
  /// 이미 올리는 중이면 그 업로드가 끝난 뒤 지금 상태로 한 번 더 올린다.
  Future<bool> upload(GameState game) async {
    while (_inflight != null) {
      await _inflight;
    }
    final id = uid;
    if (id == null) return false;
    final f = _upload(id, game);
    _inflight = f;
    try {
      return await f;
    } finally {
      if (identical(_inflight, f)) _inflight = null;
    }
  }

  Future<bool> _upload(String id, GameState game) async {
    status = SyncStatus.syncing;
    notifyListeners();
    try {
      final json = game.encode();
      _prefs.setString(_key, json);
      _prefs.setString(_ownerKey, id);
      await _writeCloud(id, json, game);
      lastCloudSave = DateTime.now();
      status = SyncStatus.synced;
      return true;
    } catch (e) {
      debugPrint('cloud upload failed: $e');
      CrashService.log('cloud upload failed: $e');
      status = SyncStatus.error;
      return false;
    } finally {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// 테스트에서 저장 요약을 쉽게 만들기 위한 헬퍼.
@visibleForTesting
SaveSummary summaryOf(GameState g) => SaveSummary.of(g.toJson());
