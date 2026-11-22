import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/config.dart';
import '../game/game_state.dart';
import '../i18n/l10n.dart';
import '../i18n/names.dart';
import 'analytics_service.dart';
import 'app_config.dart';

/// 친구(소셜): 친구 코드로 추가, 하루 한 번 선물, 친구 정원 구경, 운영 공지.
///
/// Firestore 구조 (규칙: firestore.rules, 서버: functions/main.py sendGift)
///   profiles/{uid}              공개 프로필 {name, code, level, area, placed, friends, avatar, updatedAt}
///   codes/{code}                친구 코드 → {uid, at} (만들기만, 고치기 · 지우기 불가)
///   users/{uid}/friends/{fuid}  내가 추가한 친구 {addedAt, lastGiftSentDay}
///   inbox/{uid}/items/{id}      받은 선물 {kind:'gift', fromUid, fromName, reward, at} (함수만 씀)
///   notices/{id}                운영 공지 (관리자만 씀, tool/post_notice.py)
///   gifts/*, giftCounts/*       하루 한 번 기록 (함수만)
///
/// 네트워크는 [SocialBackend] 뒤에 숨겨 테스트에서는 가짜를 쓴다. 모든 호출에 10초 제한.

// ================================================================ 순수 로직

/// 친구 코드: 헷갈리는 글자(I L O 0 1)를 뺀 8자리.
class FriendCode {
  static const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const length = 8;

  static String generate(Random rng) => String.fromCharCodes([
    for (var i = 0; i < length; i++)
      alphabet.codeUnitAt(rng.nextInt(alphabet.length)),
  ]);

  /// 사용자가 친 코드를 표준형으로 (대문자, 공백 · 하이픈 제거). 올바르지 않으면 null.
  static String? normalize(String input) {
    final s = input.toUpperCase().replaceAll(RegExp(r'[\s\-_.]'), '');
    if (s.length != length) return null;
    for (final c in s.split('')) {
      if (!alphabet.contains(c)) return null;
    }
    return s;
  }

  static bool isValid(String s) => normalize(s) == s;

  /// 보여 줄 때: ABCD-EFGH.
  static String display(String code) => code.length == length
      ? '${code.substring(0, 4)}-${code.substring(4)}'
      : code;
}

/// 기기 시간 기준 날짜 키 (하루 한 번 판정).
String socialDayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

/// 오늘 이 친구에게 아직 선물하지 않았는지.
bool canGiftToday(String? lastSentDay, String today) => lastSentDay != today;

/// 닉네임 정리: 제어 문자 제거, 공백 하나로, 최대 [SocialConfig.nameMax] 글자.
String cleanName(String raw) {
  final s = raw
      .replaceAll(
        RegExp(r'[\u0000-\u001F\u007F\u200B-\u200F\u2028-\u202E]'),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final r = s.runes.toList();
  return r.length <= SocialConfig.nameMax
      ? s
      : String.fromCharCodes(r.take(SocialConfig.nameMax)).trim();
}

/// 동물 친구 id 가 아니면 기본 친구(보리).
String safeAvatar(String? id) =>
    Friends.all.any((f) => f.id == id) ? id! : Friends.starter;

Reward clampReward(
  Reward r, {
  int coins = 5000,
  int energy = 50,
  int stars = 5,
}) => Reward(
  coins: r.coins.clamp(0, coins),
  energy: r.energy.clamp(0, energy),
  stars: r.stars.clamp(0, stars),
);

class SocialConfig {
  static const int maxFriends = 50;
  static const int nameMax = 16;
  static const Duration timeout = Duration(seconds: 10);

  /// 하루 한 번 친구 정원 구경 답례.
  static const Reward visitThanks = Reward(energy: 3);

  /// 프로필은 바뀌었을 때만, 그래도 최소 이 간격으로.
  static const Duration profileMinGap = Duration(minutes: 2);
  static const Duration profileRefresh = Duration(hours: 12);
  static const Duration noticeGap = Duration(minutes: 30);
  static const Duration friendsGap = Duration(minutes: 10);
  static const Duration refreshGap = Duration(minutes: 2);
}

/// 다른 사람에게 보이는 프로필.
class SocialProfile {
  final String uid;
  final String name;
  final String code;
  final int level;
  final int area;
  final Set<int> placed;
  final List<String> friends;
  final String avatar;

  /// 플레이한 날 수 · 나를 초대한 사람 uid · 그때 (초대 보상 조건 확인용, D-045).
  final int days;
  final String invitedBy;
  final int invitedAt;

  const SocialProfile({
    required this.uid,
    required this.name,
    required this.code,
    this.level = 1,
    this.area = 0,
    this.placed = const {},
    this.friends = const [],
    this.avatar = Friends.starter,
    this.days = 0,
    this.invitedBy = '',
    this.invitedAt = 0,
  });

  static SocialProfile fromMap(String uid, Map<String, dynamic> m) {
    final ids = {for (final f in Friends.all) f.id};
    return SocialProfile(
      uid: uid,
      name: cleanName('${m['name'] ?? ''}'),
      code: '${m['code'] ?? ''}',
      level: max(1, (m['level'] as num?)?.toInt() ?? 1),
      area: max(0, (m['area'] as num?)?.toInt() ?? 0),
      placed: {
        for (final s in (m['placed'] as List? ?? const []))
          if (s is num && s >= 0 && s < Garden.slotsPerArea) s.toInt(),
      },
      friends: [
        for (final f in (m['friends'] as List? ?? const []))
          if (ids.contains(f)) f as String,
      ],
      avatar: safeAvatar(m['avatar'] as String?),
      days: max(0, (m['days'] as num?)?.toInt() ?? 0),
      invitedBy: m['invitedBy'] is String ? m['invitedBy'] as String : '',
      invitedAt: max(0, (m['invitedAt'] as num?)?.toInt() ?? 0),
    );
  }

  /// 서버에 쓰는 값 (updatedAt 은 백엔드가 붙인다).
  Map<String, dynamic> toMap() => {
    'name': name,
    'code': code,
    'level': level,
    'area': area,
    'placed': placed.toList()..sort(),
    'friends': friends.toList()..sort(),
    'avatar': avatar,
    'days': days,
    'invitedBy': invitedBy,
    'invitedAt': invitedAt,
  };

  SocialProfile copyWith({String? name, String? avatar}) => SocialProfile(
    uid: uid,
    name: name ?? this.name,
    code: code,
    level: level,
    area: area,
    placed: placed,
    friends: friends,
    avatar: avatar ?? this.avatar,
    days: days,
    invitedBy: invitedBy,
    invitedAt: invitedAt,
  );

  static SocialProfile ofGame(
    String uid,
    GameState g, {
    required String name,
    required String code,
    required String avatar,
  }) => SocialProfile(
    uid: uid,
    name: name,
    code: code,
    level: g.level,
    area: g.currentArea,
    placed: {...g.placed},
    friends: g.friends.toList(),
    avatar: avatar,
    days: g.stat(Stat.daysPlayed),
    invitedBy: g.invitedBy ?? '',
    invitedAt: g.invitedAt?.millisecondsSinceEpoch ?? 0,
  );

  /// 초대 보상 조건을 채웠는지 (초대 뒤 7일 · 서로 다른 5일 · Lv15).
  bool inviteDone(DateTime now) =>
      invitedAt > 0 &&
      level >= Invite.needLevel &&
      days >= Invite.needDays &&
      now.difference(DateTime.fromMillisecondsSinceEpoch(invitedAt)) >=
          Invite.wait;

  /// 친구 정원 구경용 일회용 게임 상태 (저장 · 진행 없음).
  GameState toVisitGame() {
    final g = GameState();
    g.level = level;
    g.currentArea = area;
    g.placed = {...placed};
    g.friends = {Friends.starter, ...friends};
    g.mail.clear();
    return g;
  }

  /// 구경할 때 보여 줄 구역: 지금 구역을 막 시작했으면 완성한 이전 구역.
  int get showcaseArea => placed.isEmpty && area > 0 ? area - 1 : area;
}

/// 내가 추가한 친구 한 명 (프로필은 따로 불러온다).
class FriendLink {
  final String uid;
  final String? lastGiftSentDay;
  const FriendLink(this.uid, {this.lastGiftSentDay});
}

class SocialFriend {
  final String uid;
  final SocialProfile profile;
  String? lastGiftSentDay;
  SocialFriend(this.uid, this.profile, {this.lastGiftSentDay});
}

/// 받은 선물함 한 칸.
class InboxItem {
  final String id;
  final String kind;
  final String fromUid;
  final String fromName;
  final Reward reward;
  final DateTime at;
  const InboxItem({
    required this.id,
    required this.kind,
    required this.fromUid,
    required this.fromName,
    required this.reward,
    required this.at,
  });

  static InboxItem fromMap(String id, Map<String, dynamic> m, DateTime now) {
    final at = m['at'];
    return InboxItem(
      id: id,
      kind: '${m['kind'] ?? ''}',
      fromUid: '${m['fromUid'] ?? ''}',
      fromName: '${m['fromName'] ?? ''}',
      reward: Reward.fromJson((m['reward'] as Map?)?.cast<String, dynamic>()),
      at: at is Timestamp ? at.toDate() : (at is DateTime ? at : now),
    );
  }
}

/// 받은 선물 → 쪽지. 쪽지 id 는 서버 문서 id 에서 만들어 다시 받아도 겹치지 않는다.
Mail? inboxToMail(InboxItem it) {
  if (it.kind != 'gift') return null;
  final name = cleanName(it.fromName);
  return Mail(
    id: 'gift-${it.id}',
    kind: MailKind.social,
    from: name.isEmpty ? '?' : name,
    titleKey: 'social.mail.gift',
    reward: clampReward(it.reward, coins: 1000, energy: 20, stars: 1),
    at: it.at,
  );
}

/// 운영 공지.
class Notice {
  final String id;
  final Map<String, String> titles; // 언어 코드 → 제목
  final Map<String, String> bodies;
  final Reward reward;
  final DateTime? startAt;
  final DateTime? endAt;
  const Notice({
    required this.id,
    required this.titles,
    this.bodies = const {},
    this.reward = const Reward(),
    this.startAt,
    this.endAt,
  });

  static DateTime? _time(Object? v) => v is Timestamp
      ? v.toDate()
      : v is DateTime
      ? v
      : null;

  static Notice fromMap(String id, Map<String, dynamic> m) {
    final titles = <String, String>{};
    final bodies = <String, String>{};
    for (final e in m.entries) {
      if (e.value is! String) continue;
      if (e.key.startsWith('title_')) titles[e.key.substring(6)] = e.value;
      if (e.key.startsWith('body_')) bodies[e.key.substring(5)] = e.value;
      if (e.key == 'body') bodies[''] = e.value;
    }
    return Notice(
      id: id,
      titles: titles,
      bodies: bodies,
      reward: Reward.fromJson((m['reward'] as Map?)?.cast<String, dynamic>()),
      startAt: _time(m['startAt']),
      endAt: _time(m['endAt']),
    );
  }

  bool isActive(DateTime now) =>
      (startAt == null || !startAt!.isAfter(now)) &&
      (endAt == null || endAt!.isAfter(now));

  static String _pick(Map<String, String> m, String lang) =>
      m[lang] ??
      m[''] ??
      m['ko'] ??
      m['en'] ??
      (m.isEmpty ? '' : m.values.first);

  String text(String lang) {
    final t = _pick(titles, lang).trim();
    final b = _pick(bodies, lang).trim();
    return b.isEmpty ? t : '$t\n$b';
  }
}

Mail? noticeToMail(Notice n, String lang, DateTime now) {
  final text = n.text(lang);
  if (text.isEmpty || !n.isActive(now)) return null;
  return Mail(
    id: 'notice-${n.id}',
    kind: MailKind.notice,
    from: 'team',
    titleKey: '',
    text: text,
    reward: n.reward,
    at: n.startAt ?? now,
  );
}

// ================================================================ 네트워크

class SocialException implements Exception {
  /// 'timeout' | 'offline' | 'invalidCode' | 'notFound' | 'self' | 'already'
  /// | 'full' | 'limit' | 'notFriend' | 'signIn' | 'failed'
  final String code;
  SocialException(this.code);
  @override
  String toString() => 'SocialException($code)';
}

abstract class SocialBackend {
  bool get available;
  Future<Map<String, dynamic>?> getProfile(String uid);
  Future<void> putProfile(String uid, Map<String, dynamic> data);

  /// 코드를 내 것으로 예약. 이미 다른 사람 것이면 false.
  Future<bool> reserveCode(String code, String uid);
  Future<String?> lookupCode(String code);
  Future<List<FriendLink>> friendLinks(String uid);
  Future<void> addFriendLink(String uid, String friendUid);
  Future<void> removeFriendLink(String uid, String friendUid);

  /// 신고 남기기 (쓰기만, 읽기는 운영자가 Firebase 콘솔에서).
  Future<void> report(Map<String, dynamic> data);
  Future<Map<String, Map<String, dynamic>>> getProfiles(List<String> uids);
  Future<List<InboxItem>> inbox(String uid);
  Future<void> deleteInbox(String uid, List<String> ids);
  Future<List<Notice>> notices(DateTime now);

  /// 서버(sendGift)가 친구 관계 · 하루 한 번을 확인한다. 이미 보냈으면 SocialException('already').
  Future<void> sendGift(String to, String day);

  /// 나를 초대한 사람으로 적은 프로필들 (초대 친구 진행 · 보상 확인).
  Future<Map<String, Map<String, dynamic>>> invitees(String uid);
}

class FirestoreSocialBackend implements SocialBackend {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  @override
  bool get available => AppConfig.firebaseEnabled && Firebase.apps.isNotEmpty;

  @override
  Future<Map<String, dynamic>?> getProfile(String uid) async =>
      (await _db.collection('profiles').doc(uid).get()).data();

  @override
  Future<void> putProfile(String uid, Map<String, dynamic> data) => _db
      .collection('profiles')
      .doc(uid)
      .set({...data, 'updatedAt': FieldValue.serverTimestamp()});

  @override
  Future<bool> reserveCode(String code, String uid) =>
      _db.runTransaction((tx) async {
        final ref = _db.collection('codes').doc(code);
        final snap = await tx.get(ref);
        if (snap.exists) return snap.data()?['uid'] == uid;
        tx.set(ref, {'uid': uid, 'at': FieldValue.serverTimestamp()});
        return true;
      }, timeout: SocialConfig.timeout);

  @override
  Future<String?> lookupCode(String code) async {
    final v = (await _db.collection('codes').doc(code).get()).data()?['uid'];
    return v is String ? v : null;
  }

  CollectionReference<Map<String, dynamic>> _friends(String uid) =>
      _db.collection('users').doc(uid).collection('friends');

  @override
  Future<List<FriendLink>> friendLinks(String uid) async {
    final q = await _friends(uid).limit(SocialConfig.maxFriends + 10).get();
    return [
      for (final d in q.docs)
        FriendLink(
          d.id,
          lastGiftSentDay: d.data()['lastGiftSentDay'] as String?,
        ),
    ];
  }

  @override
  Future<void> addFriendLink(String uid, String friendUid) =>
      _friends(uid)
          .doc(friendUid)
          .set({'addedAt': FieldValue.serverTimestamp()});

  @override
  Future<void> removeFriendLink(String uid, String friendUid) =>
      _friends(uid).doc(friendUid).delete();

  @override
  Future<void> report(Map<String, dynamic> data) => _db
      .collection('reports')
      .add({...data, 'at': FieldValue.serverTimestamp()});

  @override
  Future<Map<String, Map<String, dynamic>>> invitees(String uid) async {
    final q = await _db
        .collection('profiles')
        .where('invitedBy', isEqualTo: uid)
        .limit(20)
        .get();
    return {for (final d in q.docs) d.id: d.data()};
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getProfiles(
    List<String> uids,
  ) async {
    final out = <String, Map<String, dynamic>>{};
    for (var i = 0; i < uids.length; i += 30) {
      final chunk = uids.sublist(i, min(i + 30, uids.length));
      final q = await _db
          .collection('profiles')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final d in q.docs) {
        out[d.id] = d.data();
      }
    }
    return out;
  }

  @override
  Future<List<InboxItem>> inbox(String uid) async {
    final q = await _db
        .collection('inbox')
        .doc(uid)
        .collection('items')
        .limit(50)
        .get();
    final now = DateTime.now();
    return [for (final d in q.docs) InboxItem.fromMap(d.id, d.data(), now)];
  }

  @override
  Future<void> deleteInbox(String uid, List<String> ids) async {
    if (ids.isEmpty) return;
    final b = _db.batch();
    final col = _db.collection('inbox').doc(uid).collection('items');
    for (final id in ids) {
      b.delete(col.doc(id));
    }
    await b.commit();
  }

  @override
  Future<List<Notice>> notices(DateTime now) async {
    final q = await _db
        .collection('notices')
        .where('endAt', isGreaterThan: Timestamp.fromDate(now))
        .limit(20)
        .get();
    return [for (final d in q.docs) Notice.fromMap(d.id, d.data())];
  }

  @override
  Future<void> sendGift(String to, String day) async {
    final fn = FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion)
        .httpsCallable(
          'sendGift',
          options: HttpsCallableOptions(timeout: SocialConfig.timeout),
        );
    try {
      await fn.call<dynamic>({'to': to, 'day': day});
    } on FirebaseFunctionsException catch (e) {
      throw SocialException(switch (e.code) {
        'already-exists' => 'already',
        'resource-exhausted' => 'limit',
        'failed-precondition' => 'notFriend',
        'not-found' => 'notFound',
        'deadline-exceeded' => 'timeout',
        'unavailable' => 'offline',
        _ => 'failed',
      });
    }
  }
}

// ================================================================ 서비스

class SocialService extends ChangeNotifier {
  SocialService({
    required this.backend,
    required this.prefs,
    required String? Function() uid,
    String? Function()? accountName,
    Random? random,
    DateTime Function()? clock,
  }) : _uidOf = uid,
       _accountName = accountName ?? (() => null),
       _rng = random ?? Random(),
       _clock = clock ?? DateTime.now;

  final SocialBackend backend;
  final SharedPreferences prefs;
  final String? Function() _uidOf;
  final String? Function() _accountName;
  final Random _rng;
  final DateTime Function() _clock;

  String? _uid;
  SocialProfile? me;
  List<SocialFriend> friends = [];
  bool friendsLoaded = false;
  bool loading = false;
  bool busy = false;

  String? _lastProfileSig;
  DateTime? _lastProfileAt;
  DateTime? _lastNoticesAt;
  DateTime? _lastFriendsAt;
  DateTime? _lastRefreshAt;
  Future<void>? _refreshing;
  Future<void>? _ensuring;

  /// Firebase 설정이 있고 초기화됐는지 (아니면 메뉴에서 친구를 숨긴다).
  bool get enabled => backend.available;

  /// 친구 기능을 쓸 수 있는 uid (기기 전용 게스트는 null).
  String? get uid => enabled ? _uidOf() : null;
  bool get canUse => uid != null;

  String get today => socialDayKey(_clock());

  /// 계정이 바뀌었으면 캐시를 비운다.
  String? _check() {
    final u = uid;
    if (u != _uid) {
      _uid = u;
      me = null;
      friends = [];
      friendsLoaded = false;
      _lastProfileSig = null;
      _lastProfileAt = null;
      _lastNoticesAt = null;
      _lastFriendsAt = null;
      _lastRefreshAt = null;
    }
    return u;
  }

  static Future<T> _net<T>(Future<T> f) async {
    try {
      return await f.timeout(SocialConfig.timeout);
    } on SocialException {
      rethrow;
    } on TimeoutException {
      throw SocialException('timeout');
    } on FirebaseException catch (e) {
      debugPrint('social: ${e.plugin} ${e.code}');
      throw SocialException(e.code == 'unavailable' ? 'offline' : 'failed');
    } catch (e) {
      debugPrint('social: $e');
      throw SocialException('failed');
    }
  }

  // ---------------------------------------------------------------- 로컬 기록

  String _k(String name) => 'social_${name}_$_uid';

  Set<String> get _seen => {...?prefs.getStringList(_k('seen'))};
  void _markSeen(Iterable<String> ids) {
    final list = [...?prefs.getStringList(_k('seen'))];
    for (final id in ids) {
      if (!list.contains(id)) list.add(id);
    }
    final keep = list.length > 300 ? list.sublist(list.length - 300) : list;
    prefs.setStringList(_k('seen'), keep);
  }

  Map<String, String> get _giftDays {
    try {
      final raw = prefs.getString(_k('giftDays'));
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  void _markGift(String friendUid) {
    final d = today;
    final m = _giftDays..removeWhere((_, v) => v != d);
    m[friendUid] = d;
    prefs.setString(_k('giftDays'), jsonEncode(m));
  }

  String get _avatarPref => safeAvatar(prefs.getString(_k('avatar')));

  // ---------------------------------------------------------------- 프로필

  /// 기본 닉네임: "포근한 토끼" 처럼 (형용사 + 동물 종류).
  String generatedName() {
    final adj = tr('social.adj.${_rng.nextInt(8)}');
    final f = Friends.all[_rng.nextInt(Friends.all.length)];
    return cleanName('$adj ${friendSpecies(f.id)}');
  }

  /// 내 프로필 · 친구 코드를 준비한다 (없으면 만든다).
  Future<SocialProfile> ensureProfile(GameState game) async {
    final u = _check();
    if (u == null) throw SocialException('signIn');
    if (me != null) return me!;
    _ensuring ??= _ensure(u, game).whenComplete(() => _ensuring = null);
    await _ensuring;
    if (me == null) throw SocialException('failed');
    return me!;
  }

  Future<void> _ensure(String u, GameState game) async {
    final data = await _net(backend.getProfile(u));
    var name = '', code = '', avatar = _avatarPref;
    if (data != null) {
      final p = SocialProfile.fromMap(u, data);
      name = p.name;
      code = p.code;
      avatar = p.avatar;
    }
    if (name.isEmpty) {
      final acc = cleanName(_accountName() ?? '');
      name = acc.isNotEmpty ? acc : generatedName();
    }
    if (!FriendCode.isValid(code)) {
      code = '';
      for (var i = 0; i < 6 && code.isEmpty; i++) {
        final c = FriendCode.generate(_rng);
        if (await _net(backend.reserveCode(c, u))) code = c;
      }
      if (code.isEmpty) throw SocialException('failed');
    }
    if (_uid != u) return; // 그 사이 계정이 바뀌었다
    me = SocialProfile.ofGame(u, game, name: name, code: code, avatar: avatar);
    await _writeProfile(force: true);
    notifyListeners();
  }

  /// 내 진행도를 공개 프로필에 반영 (바뀐 게 없으면 쓰지 않는다).
  Future<void> syncProfile(GameState game, {bool force = false}) async {
    final u = _check();
    final m = me;
    if (u == null || m == null) return;
    me = SocialProfile.ofGame(
      u,
      game,
      name: m.name,
      code: m.code,
      avatar: m.avatar,
    );
    try {
      await _writeProfile(force: force);
    } on SocialException catch (e) {
      debugPrint('profile sync failed: ${e.code}');
    }
  }

  Future<void> _writeProfile({bool force = false}) async {
    final m = me;
    if (m == null) return;
    final map = m.toMap();
    final sig = jsonEncode(map);
    final now = _clock();
    final last = _lastProfileAt;
    if (!force && last != null) {
      if (sig == _lastProfileSig &&
          now.difference(last) < SocialConfig.profileRefresh) {
        return;
      }
      if (now.difference(last) < SocialConfig.profileMinGap) return;
    }
    _lastProfileAt = now;
    await _net(backend.putProfile(m.uid, map));
    _lastProfileSig = sig;
  }

  Future<void> rename(String raw) async {
    final name = cleanName(raw);
    final m = me;
    if (name.isEmpty || m == null || name == m.name) return;
    final old = m;
    me = m.copyWith(name: name);
    notifyListeners();
    try {
      await _writeProfile(force: true);
    } on SocialException {
      me = old;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setAvatar(String id) async {
    final m = me;
    if (m == null) return;
    final a = safeAvatar(id);
    prefs.setString(_k('avatar'), a);
    me = m.copyWith(avatar: a);
    notifyListeners();
    await _writeProfile(force: true);
  }

  // ---------------------------------------------------------------- 시작 · 복귀

  /// 앱 시작 · 복귀 · 로그인 직후. 오류는 조용히 넘긴다 (다음 기회에 다시).
  Future<void> refresh(GameState game, {bool force = false}) {
    final u = _check();
    if (u == null) return Future.value();
    final now = _clock();
    if (!force &&
        _lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < SocialConfig.refreshGap) {
      return Future.value();
    }
    _lastRefreshAt = now;
    return _refreshing ??= _refresh(
      game,
      force,
    ).whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh(GameState game, bool force) async {
    try {
      await ensureProfile(game);
      await syncProfile(game);
    } on SocialException catch (e) {
      debugPrint('social profile: ${e.code}');
    }
    try {
      await checkInvites(game);
    } on SocialException catch (e) {
      debugPrint('invites: ${e.code}');
    }
    for (final step in [
      () => pullInbox(game),
      () => pullNotices(game, force: force),
      () => loadFriends(force: force),
    ]) {
      try {
        await step();
      } on SocialException catch (e) {
        debugPrint('social refresh: ${e.code}');
      }
    }
  }

  /// 받은 선물을 쪽지로 옮기고 서버에서 지운다. 새로 넣은 쪽지 수.
  Future<int> pullInbox(GameState game) async {
    final u = _check();
    if (u == null) return 0;
    final items = await _net(backend.inbox(u));
    if (items.isEmpty) return 0;
    final seen = _seen;
    var added = 0;
    for (final it in items) {
      final m = inboxToMail(it);
      if (m == null || seen.contains(m.id)) continue;
      if (!game.mail.any((x) => x.id == m.id)) added++;
      game.addMail(m);
    }
    _markSeen([for (final it in items) 'gift-${it.id}']);
    try {
      await _net(backend.deleteInbox(u, [for (final it in items) it.id]));
    } on SocialException catch (e) {
      debugPrint('inbox delete failed: ${e.code}'); // seen 목록이 중복을 막는다
    }
    return added;
  }

  /// 진행 중인 공지를 쪽지로 (한 번만).
  Future<int> pullNotices(GameState game, {bool force = false}) async {
    final u = _check();
    if (u == null) return 0;
    final now = _clock();
    if (!force &&
        _lastNoticesAt != null &&
        now.difference(_lastNoticesAt!) < SocialConfig.noticeGap) {
      return 0;
    }
    final list = await _net(backend.notices(now));
    _lastNoticesAt = now;
    final seen = _seen;
    final ids = <String>[];
    var added = 0;
    for (final n in list) {
      final m = noticeToMail(n, L10n.instance.lang, now);
      if (m == null || seen.contains(m.id)) continue;
      game.addMail(m);
      ids.add(m.id);
      added++;
    }
    _markSeen(ids);
    return added;
  }

  // ---------------------------------------------------------------- 친구

  Future<void> loadFriends({bool force = false}) async {
    final u = _check();
    if (u == null) return;
    final now = _clock();
    if (!force &&
        friendsLoaded &&
        _lastFriendsAt != null &&
        now.difference(_lastFriendsAt!) < SocialConfig.friendsGap) {
      return;
    }
    loading = true;
    notifyListeners();
    try {
      final links = await _net(backend.friendLinks(u));
      final profiles = links.isEmpty
          ? <String, Map<String, dynamic>>{}
          : await _net(backend.getProfiles([for (final l in links) l.uid]));
      if (_uid != u) return;
      final local = _giftDays;
      final list = <SocialFriend>[];
      for (final l in links) {
        final p = profiles[l.uid];
        if (p == null) {
          // 계정을 지운 친구: 목록에서 정리
          unawaited(
            _net(backend.removeFriendLink(u, l.uid)).catchError((_) {}),
          );
          continue;
        }
        final localDay = local[l.uid];
        list.add(
          SocialFriend(
            l.uid,
            SocialProfile.fromMap(l.uid, p),
            lastGiftSentDay: localDay == today ? localDay : l.lastGiftSentDay,
          ),
        );
      }
      list.sort((a, b) => b.profile.level.compareTo(a.profile.level));
      friends = list;
      friendsLoaded = true;
      _lastFriendsAt = now;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 친구 코드로 추가.
  Future<SocialFriend> addFriendByCode(String input) async {
    final u = _check();
    if (u == null) throw SocialException('signIn');
    final code = FriendCode.normalize(input);
    if (code == null) throw SocialException('invalidCode');
    if (code == me?.code) throw SocialException('self');
    if (friends.length >= SocialConfig.maxFriends) {
      throw SocialException('full');
    }
    busy = true;
    notifyListeners();
    try {
      final fuid = await _net(backend.lookupCode(code));
      if (fuid == null) throw SocialException('notFound');
      if (fuid == u) throw SocialException('self');
      if (friends.any((f) => f.uid == fuid)) throw SocialException('already');
      final p = await _net(backend.getProfile(fuid));
      if (p == null) throw SocialException('notFound');
      await _net(backend.addFriendLink(u, fuid));
      final f = SocialFriend(fuid, SocialProfile.fromMap(fuid, p));
      friends = [...friends, f];
      return f;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- 초대 (D-045)

  /// 내가 초대한 친구들 (진행 표시용, [checkInvites] 가 채운다).
  List<SocialFriend> invitees = [];

  /// 초대 코드로 시작 (설치 추천인 · 직접 입력). 새 계정이면 친구를 맺고 환영 선물.
  /// 받았으면 true. 이미 친구면 친구 맺기는 건너뛴다.
  Future<bool> applyInvite(String input, GameState game) async {
    final u = _check();
    if (u == null || !game.canBeInvited) return false;
    final code = FriendCode.normalize(input);
    if (code == null || code == me?.code) return false;
    final fuid = await _net(backend.lookupCode(code));
    if (fuid == null || fuid == u) return false;
    final p = await _net(backend.getProfile(fuid));
    if (p == null) return false;
    final prof = SocialProfile.fromMap(fuid, p);
    if (!friends.any((f) => f.uid == fuid) &&
        friends.length < SocialConfig.maxFriends) {
      await _net(backend.addFriendLink(u, fuid));
      friends = [...friends, SocialFriend(fuid, prof)];
    }
    if (!game.acceptInvite(fuid, prof.name)) return false;
    await ensureProfile(game);
    await syncProfile(game, force: true);
    notifyListeners();
    return true;
  }

  /// 내가 초대한 친구들을 불러와 친구로 맺고 (서로 친구), 조건을 채운 친구는 초대 보상.
  /// 새로 받은 보상 수.
  Future<int> checkInvites(GameState game) async {
    final u = _check();
    if (u == null) return 0;
    final data = await _net(backend.invitees(u));
    final list = [
      for (final e in data.entries)
        SocialFriend(e.key, SocialProfile.fromMap(e.key, e.value)),
    ]..sort((a, b) => a.profile.invitedAt.compareTo(b.profile.invitedAt));
    invitees = list;
    var got = 0;
    for (final f in list) {
      if (!friends.any((x) => x.uid == f.uid) &&
          friends.length < SocialConfig.maxFriends) {
        try {
          await _net(backend.addFriendLink(u, f.uid));
          friends = [...friends, f];
        } on SocialException {
          // 다음 기회에
        }
      }
      if (f.profile.inviteDone(_clock()) &&
          game.grantInviteReward(f.uid, f.profile.name)) {
        got++;
      }
    }
    if (got > 0) Analytics.instance.inviteReward(got);
    notifyListeners();
    return got;
  }

  /// 신고 이유 (Firestore 규칙과 같아야 한다).
  static const List<String> reportReasons = ['name', 'harass', 'other'];

  /// 친구 신고: 정원 이름 · 코드를 함께 남긴다. [alsoRemove] 면 친구에서도 뺀다 (차단).
  Future<void> reportFriend(
    SocialFriend f,
    String reason, {
    bool alsoRemove = true,
  }) async {
    final u = _check();
    if (u == null) return;
    await _net(
      backend.report({
        'from': u,
        'target': f.uid,
        'name': f.profile.name,
        'code': f.profile.code,
        'reason': reason,
      }),
    );
    if (alsoRemove) await removeFriend(f.uid);
  }

  Future<void> removeFriend(String friendUid) async {
    final u = _check();
    if (u == null) return;
    await _net(backend.removeFriendLink(u, friendUid));
    friends = friends.where((f) => f.uid != friendUid).toList();
    notifyListeners();
  }

  // ---------------------------------------------------------------- 선물

  bool giftSentToday(SocialFriend f) => !canGiftToday(f.lastGiftSentDay, today);

  int get giftableCount => friends.where((f) => !giftSentToday(f)).length;

  /// 메뉴 빨간 점: 오늘 선물할 수 있는 친구가 있다.
  bool get badge => canUse && giftableCount > 0;

  final Set<String> _sending = {};
  bool isSending(SocialFriend f) => _sending.contains(f.uid);

  /// 오늘의 선물 보내기. 이미 보냈으면 조용히 완료 상태로.
  Future<void> sendGift(SocialFriend f, GameState game) async {
    if (_check() == null) throw SocialException('signIn');
    if (giftSentToday(f) || _sending.contains(f.uid)) return;
    final day = today;
    _sending.add(f.uid);
    notifyListeners();
    try {
      await _net(backend.sendGift(f.uid, day));
      game.recordGiftSent();
      f.lastGiftSentDay = day;
      _markGift(f.uid);
    } on SocialException catch (e) {
      if (e.code != 'already') rethrow;
      f.lastGiftSentDay = day;
      _markGift(f.uid);
    } finally {
      _sending.remove(f.uid);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- 구경 답례

  bool get visitThanksReady => prefs.getString(_k('visitDay')) != today;

  /// 친구 정원 구경 답례 (하루 한 번, 쪽지로 남기고 바로 받는다).
  Reward? claimVisitThanks(GameState game, String friendName) {
    if (_check() == null || !visitThanksReady) return null;
    final d = today;
    prefs.setString(_k('visitDay'), d);
    final id = 'visit-$d';
    game.addMail(
      Mail(
        id: id,
        kind: MailKind.social,
        from: cleanName(friendName).isEmpty ? '?' : cleanName(friendName),
        titleKey: 'social.mail.visit',
        reward: SocialConfig.visitThanks,
        at: _clock(),
      ),
    );
    final r = game.claimMail(id);
    notifyListeners();
    return r;
  }
}
