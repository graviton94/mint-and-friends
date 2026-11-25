import '../game/config.dart';
import 'l10n.dart';

/// 게임 콘텐츠(id) → 현재 언어 이름. 화면 코드는 이 함수들만 쓰고 직접 키를 만들지 않는다.

String itemName(ItemDef d) => tr(d.key);

String friendName(String id) => tr('friend.$id.name');
String friendSpecies(String id) => tr('friend.$id.species');
String friendLine(String id) => tr('friend.$id.line');

String decorName(DecorDef d) => tr(d.key);

String areaName(AreaDef a) {
  final base = tr(a.key);
  return a.round <= 1 ? base : tr('area.round', {'name': base, 'n': a.round});
}

String featureName(Feature f) => tr('feature.${f.name}');

String upgradeTitle(UpgradeType t) => tr('upgrade.${t.name}');

/// 강화 효과 값만 (짧게): '150초', '×1.10', '8%' …
String upgradeValue(UpgradeType t, int lv) {
  switch (t) {
    case UpgradeType.energyRegen:
      return tr('unit.sec', {'n': Upgrades.energyRegenSeconds(lv).round()});
    case UpgradeType.income:
      return '×${Upgrades.incomeMultiplier(lv).toStringAsFixed(2)}';
    case UpgradeType.autoMerge:
      final i = Upgrades.autoMergeInterval(lv);
      return i == null
          ? tr('upgrade.autoMerge.off')
          : tr('unit.secF', {'n': i.toStringAsFixed(1)});
    case UpgradeType.autoSpawn:
      final i = Upgrades.autoSpawnInterval(lv);
      return i == null
          ? tr('upgrade.autoMerge.off')
          : tr('unit.secF', {'n': i.toStringAsFixed(1)});
    case UpgradeType.spawnLevel:
      return '${((GameConfig.luckySpawnChance + Upgrades.qualityChance(lv)) * 100).toStringAsFixed(1)}%';
    case UpgradeType.offlineCap:
      return tr('unit.hour', {'n': Upgrades.offlineCap(lv).inHours});
    case UpgradeType.flowerPower:
    case UpgradeType.snackPower:
    case UpgradeType.teaPower:
    case UpgradeType.stardustPower:
      return '×${Upgrades.chainPower(lv).toStringAsFixed(2)}';
    case UpgradeType.basketTier:
      return 'Lv.${1 + lv}';
  }
}

/// 강화 한 줄 설명: '[[energy]]회복 150초 → 144초'.
String upgradeLine(UpgradeType t, int lv, {bool maxed = false}) {
  final head = tr('upgrade.${t.name}.short');
  final now = upgradeValue(t, lv);
  return maxed ? '$head $now' : '$head $now → ${upgradeValue(t, lv + 1)}';
}

String buffText(FriendDef f, int level) {
  final v = f.perLevel * Friends.effectiveLevel(level) * 100;
  final s = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);
  return tr('buff.${f.buff.name}', {'v': s});
}

String chainName(Chain c) => tr('chain.${c.name}');

String fmtDuration(Duration d) {
  if (d.inHours > 0)
    return tr('time.hm', {'h': d.inHours, 'm': d.inMinutes % 60});
  if (d.inMinutes > 0)
    return tr('time.ms', {'m': d.inMinutes, 's': d.inSeconds % 60});
  return tr('time.s', {'s': d.inSeconds});
}
