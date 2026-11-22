import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/game_state.dart';

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

/// 기기 저장(SharedPreferences, Google 백업 대상) + 클라우드 저장(Firestore users/{uid}).
class SaveService extends ChangeNotifier {
  static const _key = 'save_v3';
  static const _ownerKey = 'save_owner';
  static const Duration cloudInterval = Duration(seconds: 60);

  SaveService(this._prefs);
  final SharedPreferences _prefs;

  String? uid; // 클라우드 저장 대상 (null 이면 기기에만 저장)
  SyncStatus status = SyncStatus.local;
  DateTime? lastCloudSave;
  Timer? _timer;
  bool _uploading = false;

  String? get localOwner => _prefs.getString(_ownerKey);

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
    if (uid != null) _prefs.setString(_ownerKey, uid!);
  }

  Future<void> clearLocal() async {
    await _prefs.remove(_key);
    await _prefs.remove(_ownerKey);
  }

  // ---------------------------------------------------------------- 클라우드

  DocumentReference<Map<String, dynamic>> _doc(String id) =>
      FirebaseFirestore.instance.collection('users').doc(id);

  Future<Map<String, dynamic>?> _fetchCloud(String id) async {
    // 연결이 막히면 Firestore 는 오래 기다린다: 제한 시간 뒤에는 실패로 보고 나중에 다시.
    final snap = await _doc(id).get().timeout(const Duration(seconds: 12));
    final data = snap.data();
    final raw = data?['data'] as String?;
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  /// 로그인 직후 호출. 충돌이면 [askUser] 로 물어본다 (true = 클라우드 사용).
  /// 클라우드를 읽지 못하면 false (uid 를 붙이지 않는다: 읽지 못한 클라우드를 기기 진행으로 덮어쓰지 않게).
  Future<bool> attach(
    String newUid,
    GameState game, {
    required Future<bool> Function(SaveSummary local, SaveSummary cloud)
    askUser,
  }) async {
    uid = newUid;
    status = SyncStatus.syncing;
    notifyListeners();
    try {
      final cloudJson = await _fetchCloud(newUid);
      final localJson = game.toJson();
      final local = SaveSummary.of(localJson);
      final cloud = cloudJson == null ? null : SaveSummary.of(cloudJson);
      var decision = decideSync(
        local: local,
        localOwner: localOwner,
        cloud: cloud,
        uid: newUid,
      );
      if (decision == SyncDecision.ask) {
        decision = await askUser(local, cloud!)
            ? SyncDecision.useCloud
            : SyncDecision.uploadLocal;
      }
      if (decision == SyncDecision.useCloud && cloudJson != null) {
        game.loadJson(cloudJson);
        saveLocal(game);
        status = SyncStatus.synced;
        lastCloudSave = DateTime.now();
      } else {
        saveLocal(game);
        await upload(game);
      }
    } catch (e) {
      debugPrint('cloud attach failed: $e');
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
    uid = null;
    status = SyncStatus.local;
    notifyListeners();
  }

  Future<void> upload(GameState game) async {
    final id = uid;
    if (id == null || _uploading) return;
    _uploading = true;
    status = SyncStatus.syncing;
    notifyListeners();
    try {
      final json = game.encode();
      _prefs.setString(_key, json);
      _prefs.setString(_ownerKey, id);
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
      lastCloudSave = DateTime.now();
      status = SyncStatus.synced;
    } catch (e) {
      debugPrint('cloud upload failed: $e');
      status = SyncStatus.error;
    } finally {
      _uploading = false;
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
