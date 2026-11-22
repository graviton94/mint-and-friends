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
    return s.contains('(') ? josa(s) : s;
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
