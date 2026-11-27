import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 다국어 모듈.
///
/// - 문구는 `assets/i18n/<언어>.json` 에 "키": "문구" 로 둔다. `{name}` 같은 자리표시자를 쓸 수 있다.
/// - 코드에서는 `tr('키', {'name': ...})` 로 쓴다.
/// - 언어를 바꾸면 [L10n] 이 notify 하고, 앱 루트가 다시 그린다.
/// - 없는 키는 기본 언어(ko) → 키 자체 순으로 대체한다.
/// - 새 언어 추가: json 파일 추가 + [supported] 에 한 줄 추가.
class L10n extends ChangeNotifier {
  L10n._();
  static final L10n instance = L10n._();

  /// 기기 언어를 지원하지 않거나 문구가 빠졌을 때 쓰는 언어 (스토어 기본 언어와 같게 영어).
  static const String fallbackLang = 'en';
  static const String _prefKey = 'lang';

  /// 지원 언어: 코드 → 해당 언어로 쓴 언어 이름 (언어 선택 화면에 그대로 표시).
  static const Map<String, String> supported = {
    'ko': '한국어',
    'en': 'English',
    'ja': '日本語',
    'es': 'Español',
  };

  String _lang = fallbackLang;
  Map<String, String> _table = {};
  Map<String, String> _fallback = {};

  String get lang => _lang;
  ui.Locale get locale => ui.Locale(_lang);

  /// 저장된 언어 → 기기 언어 → 기본 언어 순으로 고른다.
  Future<void> init() async {
    _fallback = await _loadTable(fallbackLang);
    String? saved;
    try {
      saved = (await SharedPreferences.getInstance()).getString(_prefKey);
    } catch (_) {}
    final device = ui.PlatformDispatcher.instance.locale.languageCode;
    final pick =
        saved ?? (supported.containsKey(device) ? device : fallbackLang);
    await _apply(pick);
  }

  Future<void> setLanguage(String code) async {
    if (!supported.containsKey(code) || code == _lang) return;
    await _apply(code);
    try {
      await (await SharedPreferences.getInstance()).setString(_prefKey, code);
    } catch (_) {}
  }

  Future<void> _apply(String code) async {
    _lang = code;
    _table = code == fallbackLang ? _fallback : await _loadTable(code);
    notifyListeners();
  }

  static Future<Map<String, String>> _loadTable(String code) async {
    try {
      final raw = await rootBundle.loadString('assets/i18n/$code.json');
      return parse(raw);
    } catch (_) {
      return {};
    }
  }

  /// json 문자열을 표로 바꾼다. "_" 로 시작하는 키는 주석으로 보고 건너뛴다.
  static Map<String, String> parse(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final e in m.entries)
        if (!e.key.startsWith('_')) e.key: e.value as String,
    };
  }

  /// 테스트나 미리보기에서 표를 직접 넣을 때 사용.
  @visibleForTesting
  void debugSetTables(
    String lang,
    Map<String, String> table, {
    Map<String, String>? fallback,
  }) {
    _lang = lang;
    _table = table;
    _fallback = fallback ?? table;
    notifyListeners();
  }

  String t(String key, [Map<String, Object?> params = const {}]) {
    var s = _table[key] ?? _fallback[key] ?? key;
    if (params.isNotEmpty) {
      params.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    }
    s = s.contains('(') ? josa(s) : s;
    return _lang == 'ja' ? jaPhrases(s) : s;
  }

  bool has(String key) => _table.containsKey(key) || _fallback.containsKey(key);
}

/// 짧게 쓰기 위한 전역 함수.
String tr(String key, [Map<String, Object?> params = const {}]) =>
    L10n.instance.t(key, params);

/// 한국어 조사 고르기: "로즈마리(이)가" → "로즈마리가", "세이지(을)를" → "세이지를".
/// 앞 글자가 한글이면 받침으로 고르고, 아니면 괄호만 지운 뒷말을 쓴다.
String josa(String s) {
  const pairs = {
    '(이)가': ('이', '가'),
    '(을)를': ('을', '를'),
    '(은)는': ('은', '는'),
    '(과)와': ('과', '와'),
    '(이)랑': ('이랑', '랑'),
    '(이)에요': ('이에요', '예요'),
  };
  for (final e in pairs.entries) {
    var i = s.indexOf(e.key);
    while (i >= 0) {
      final before = i > 0 ? s.codeUnitAt(i - 1) : 0;
      final hangul = before >= 0xAC00 && before <= 0xD7A3;
      final batchim = hangul && (before - 0xAC00) % 28 != 0;
      final pick = hangul ? (batchim ? e.value.$1 : e.value.$2) : e.value.$2;
      s = s.replaceRange(i, i + e.key.length, pick);
      i = s.indexOf(e.key, i + pick.length);
    }
  }
  return s;
}

/// 일본어 줄바꿈을 말 덩어리(문절) 사이에서만 (D-105).
/// 일본어는 띄어쓰기가 없어 글자 사이 어디서나 줄이 바뀌어 'アカウ/ント' 처럼 낱말이 잘렸다.
/// 덩어리 안 글자 사이에 '줄 바꾸지 않음'(U+2060)을 넣는다. 덩어리 경계(줄을 바꿔도 되는 곳):
/// 히라가나(조사 · 어미) 다음에 한자 · 가타카나 · 숫자가 시작할 때, 문장부호 · 빈칸 뒤, 여는 괄호 앞.
/// [[아이콘]] · 줄바꿈은 건드리지 않는다. 한 덩어리가 줄보다 길면 Flutter 가 그래도 잘라 준다.
String jaPhrases(String s) {
  const wj = '⁠';
  int kind(int c) {
    if (c >= 0x3041 && c <= 0x309F) return 1; // 히라가나
    if ((c >= 0x30A0 && c <= 0x30FF) || c == 0x30FC) return 2; // 가타카나
    if (c >= 0x4E00 && c <= 0x9FFF) return 3; // 한자
    if ((c >= 0x30 && c <= 0x39) || (c >= 0xFF10 && c <= 0xFF19))
      return 4; // 숫자
    return 0;
  }

  const breakAfter = '、。！？!?・」』）)〕】…♪ ,';
  const breakBefore = '「『（(〔【';
  final out = StringBuffer();
  var prev = -1; // 앞 글자 (code point), -1 = 경계
  var i = 0;
  while (i < s.length) {
    // [[토큰]] 은 통째로, 앞뒤는 경계
    if (s.startsWith('[[', i)) {
      final j = s.indexOf(']]', i);
      if (j > 0) {
        out.write(s.substring(i, j + 2));
        i = j + 2;
        prev = -1;
        continue;
      }
    }
    final c = s.codeUnitAt(i);
    final ch = s[i];
    if (ch == '\n' || ch == ' ') {
      out.write(ch);
      prev = -1;
      i++;
      continue;
    }
    // 영문 · 숫자끼리(링크 · 시각 등)는 원래 규칙대로. 숫자와 일본어 사이('1回')는 붙여 둔다
    if (prev >= 0 && prev < 0x80 && c < 0x80) prev = -1;
    if (prev >= 0) {
      final pk = kind(prev), ck = kind(c);
      final boundary =
          breakAfter.contains(String.fromCharCode(prev)) ||
          breakBefore.contains(ch) ||
          (pk == 1 && ck >= 2) || // 조사 · 어미 뒤에 새 낱말
          (pk == 2 && ck == 3) || // 가타카나 낱말 다음 한자 낱말 (オフライン|収益)
          (pk == 3 && ck == 2) ||
          (pk == 0 &&
              ck != 0 &&
              prev > 0x7F &&
              !'ー〜~'.contains(String.fromCharCode(prev)));
      if (!boundary) out.write(wj);
    }
    out.write(ch);
    prev = c;
    i++;
  }
  return out.toString();
}

/// 화면 밖으로 나가는 글(공유 · 알림)용: 일본어 줄바꿈 기호를 뺀 문구.
String trPlain(String key, [Map<String, Object?> params = const {}]) =>
    tr(key, params).replaceAll('\u2060', '');
