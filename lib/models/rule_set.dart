enum RulePreset {
  tianjin,
  tanggu,
  custom,
}

class RuleSet {
  const RuleSet({
    required this.preset,
    required this.name,
    required this.deckCount,
    required this.enableTribute,
    required this.enableFollowLead,
    required this.enableWildCards,
    required this.summary,
  });

  final RulePreset preset;
  final String name;
  final int deckCount;
  final bool enableTribute;
  final bool enableFollowLead;
  final bool enableWildCards;
  final String summary;

  static const tianjin = RuleSet(
    preset: RulePreset.tianjin,
    name: '天津通用',
    deckCount: 1,
    enableTribute: false,
    enableFollowLead: false,
    enableWildCards: true,
    summary: '1副牌，红桃4先出，逆时针出牌，大小王、3、2可作混儿',
  );

  static const tanggu = RuleSet(
    preset: RulePreset.tanggu,
    name: '塘沽路',
    deckCount: 2,
    enableTribute: true,
    enableFollowLead: true,
    enableWildCards: false,
    summary: '启用进贡、还贡、接风等熟手规则',
  );

  static const custom = RuleSet(
    preset: RulePreset.custom,
    name: '自定义',
    deckCount: 2,
    enableTribute: false,
    enableFollowLead: false,
    enableWildCards: false,
    summary: '后续支持调整发牌、混牌与结算方式',
  );
}

const rulePresets = [
  RuleSet.tianjin,
  RuleSet.tanggu,
  RuleSet.custom,
];
