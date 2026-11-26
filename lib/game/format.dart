import 'dart:math';

const _units = ['', 'K', 'M', 'B', 'T'];

/// 1234 -> 1.23K, 큰 수는 aa, ab ... 표기.
String fmt(double v) {
  if (v.isNaN || v.isInfinite) return '∞';
  if (v < 1000) {
    return v < 10 && v != v.floorToDouble()
        ? v.toStringAsFixed(1)
        : v.floor().toString();
  }
  final exp = (log(v) / ln10).floor();
  var tier = exp ~/ 3;
  var scaled = v / pow(10, tier * 3);
  if (scaled >= 999.995) {
    // 부동소수점 log 오차 보정 및 반올림 경계 처리
    tier += 1;
    scaled = v / pow(10, tier * 3);
  }
  final digits = scaled >= 100 ? 0 : (scaled >= 10 ? 1 : 2);
  final s = scaled.toStringAsFixed(digits);
  return '$s${_unit(tier)}';
}

String _unit(int tier) {
  if (tier < _units.length) return _units[tier];
  final i = tier - _units.length;
  final a = String.fromCharCode(97 + (i ~/ 26) % 26);
  final b = String.fromCharCode(97 + i % 26);
  return '$a$b';
}

/// 천 단위 쉼표 정수 (가격 · 다이아 개수).
String fmtInt(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// 한 화면 안의 비용을 같은 단위로 보여 준다.
/// 가장 큰 값의 단위에 맞춘다: 큰 값이 1,000 미만이면 '800', 아니면 '0.80K' · '2.00K' · '12.5K' · '125K'.
class UnitFmt {
  UnitFmt(this.tier);
  factory UnitFmt.of(Iterable<double> values) {
    var top = 0.0;
    for (final v in values) {
      if (v.isFinite && v > top) top = v;
    }
    return UnitFmt(top < 1000 ? 0 : _tierOf(top));
  }
  final int tier;

  static int _tierOf(double v) {
    var t = (log(v) / ln10).floor() ~/ 3;
    if (v / pow(10, t * 3) >= 999.995) t += 1;
    return t;
  }

  /// 화면마다 단위가 달라 보이던 문제(같은 값이 강화 창 K · 상점 M, 시장 '0.01K')로
  /// 모든 값을 제 단위로 표기한다 (D-087). 어디서나 같은 값은 같은 글자.
  String call(num value) => fmt(value.toDouble());
}
