import 'dart:math';

const _units = ['', 'K', 'M', 'B', 'T'];

/// 1234 -> 1.23K, 큰 수는 aa, ab ... 표기.
String fmt(double v) {
  if (v.isNaN || v.isInfinite) return '∞';
  if (v < 1000) return v < 10 && v != v.floorToDouble() ? v.toStringAsFixed(1) : v.floor().toString();
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

String fmtDuration(Duration d) {
  if (d.inHours > 0) return '${d.inHours}시간 ${d.inMinutes % 60}분';
  if (d.inMinutes > 0) return '${d.inMinutes}분 ${d.inSeconds % 60}초';
  return '${d.inSeconds}초';
}
