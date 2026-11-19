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

String upgradeDescribe(UpgradeType t, int lv) {
  switch (t) {
    case UpgradeType.energyRegen:
      return tr('upgrade.energyRegen.desc', {
        'v': Upgrades.energyRegenSeconds(lv).toStringAsFixed(0),
      });
    case UpgradeType.income:
      return tr('upgrade.income.desc', {
        'v': Upgrades.incomeMultiplier(lv).toStringAsFixed(2),
      });
    case UpgradeType.autoMerge:
      final i = Upgrades.autoMergeInterval(lv);
      return i == null
          ? tr('upgrade.autoMerge.off')
          : tr('upgrade.autoMerge.desc', {'v': i.toStringAsFixed(1)});
    case UpgradeType.spawnLevel:
      return tr('upgrade.spawnLevel.desc', {'v': Upgrades.spawnLevel(lv)});
    case UpgradeType.offlineCap:
      return tr('upgrade.offlineCap.desc', {
        'v': fmtDuration(Upgrades.offlineCap(lv)),
      });
  }
}

String buffText(FriendDef f, int affection) {
  final v = f.perLevel * affection * 100;
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
