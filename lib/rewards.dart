import 'package:flutter/material.dart';

import 'game.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Récompenses (événements, paliers de défi, courrier de l'admin) :
//   {"coins":500,"pixels":5,"lots":1,"packs":{"premium":1,"star":1},"cards":{"3":1}}
// Les paquets arrivent dans « Cadeaux », les lots dans « En stock », les cartes
// (au hasard dans la rareté) directement dans la collection.
// ═══════════════════════════════════════════════════════════════════════════

/// Paquets possibles en récompense (le paquet console demande un choix : pas proposé)
const kRewardPacks = ['mixte', 'premium', 'mystery', 'star', 'gold'];

String rewardPackName(String k, {int n = 1}) => switch (k) {
      'mixte' => t('paquet mixte', 'mixed pack'),
      'premium' => t('paquet premium', 'premium pack'),
      'mystery' => t('paquet mystère', 'mystery pack'),
      'star' => t('booster Étoile', 'Star booster'),
      'gold' => t('booster Rétro d\'or', 'Retro Gold booster'),
      _ => k,
    };

String rewardPackIcon(String k) => switch (k) { 'premium' => '💎', 'mystery' => '❓', 'star' => '⭐', 'gold' => '🏆', _ => '📦' };

int _n(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// Copie propre d'une récompense (clés connues, quantités > 0)
Map<String, dynamic> rewardClean(dynamic r) {
  final out = <String, dynamic>{};
  if (r is! Map) return out;
  for (final k in const ['coins', 'pixels', 'lots']) {
    if (_n(r[k]) > 0) out[k] = _n(r[k]);
  }
  for (final k in const ['packs', 'cards']) {
    final m = r[k];
    if (m is Map) {
      final mm = <String, int>{for (final e in m.entries) if (_n(e.value) > 0) e.key.toString(): _n(e.value)};
      if (mm.isNotEmpty) out[k] = mm;
    }
  }
  return out;
}

/// Récompense complète d'un événement ou d'un palier : pièces / pixels (anciens champs) + « reward »
Map<String, dynamic> rewardOf(Map e) => rewardAdd({'coins': _n(e['coins']), 'pixels': _n(e['pixels'])}, e['reward']);

Map<String, dynamic> rewardAdd(dynamic a, dynamic b) {
  final x = rewardClean(a), y = rewardClean(b);
  final out = <String, dynamic>{};
  for (final k in const ['coins', 'pixels', 'lots']) {
    final v = _n(x[k]) + _n(y[k]);
    if (v > 0) out[k] = v;
  }
  for (final k in const ['packs', 'cards']) {
    final m = <String, int>{};
    for (final src in [x[k], y[k]]) {
      if (src is Map) {
        for (final e in src.entries) {
          m[e.key.toString()] = (m[e.key.toString()] ?? 0) + _n(e.value);
        }
      }
    }
    if (m.isNotEmpty) out[k] = m;
  }
  return out;
}

bool rewardAny(dynamic r) => rewardClean(r).isNotEmpty;

/// Morceaux lisibles : « 500 🪙 », « 1 paquet premium », « 1 carte épique »
List<String> rewardParts(dynamic r, {bool icons = true}) {
  final x = rewardClean(r);
  final parts = <String>[];
  if (_n(x['coins']) > 0) parts.add(icons ? '${x['coins']} 🪙' : t('${x['coins']} pièces', '${x['coins']} coins'));
  if (_n(x['pixels']) > 0) parts.add(icons ? '${x['pixels']} ▦' : t('${x['pixels']} pixels', '${x['pixels']} pixels'));
  for (final e in ((x['packs'] as Map?) ?? const {}).entries) {
    parts.add('${e.value} ${rewardPackName(e.key.toString())}');
  }
  if (_n(x['lots']) > 0) parts.add(t('${x['lots']} lot ×5', '${x['lots']} bundle ×5'));
  for (final e in ((x['cards'] as Map?) ?? const {}).entries) {
    parts.add(t('${e.value} carte ${rarityName(_n(e.key)).toLowerCase()}', '${e.value} ${rarityName(_n(e.key)).toLowerCase()} card'));
  }
  return parts;
}

String rewardText(dynamic r, {bool icons = true}) => rewardParts(r, icons: icons).join(' + ');

/// Le joueur reçoit-il des paquets (à ouvrir depuis les cadeaux) ?
bool rewardHasPacks(dynamic r) {
  final x = rewardClean(r);
  return x['packs'] != null || x['lots'] != null;
}

// ─── Modèles pré-remplis (page admin) ──────────────────────────────────────

List<(String, Map<String, dynamic>)> get kRewardPresets => [
  (t('Petit merci', 'Small thanks'), {'coins': 200}),
  (t('Week-end', 'Weekend'), {'coins': 500, 'pixels': 5}),
  (t('Excuses bug', 'Bug apology'), {'coins': 300, 'packs': {'premium': 1}}),
  (t('Booster Étoile', 'Star booster'), {'packs': {'star': 1}}),
  (t('Lot ×5', 'Bundle ×5'), {'lots': 1}),
  (t('Carte épique', 'Epic card'), {'cards': {'3': 1}}),
  (t('Gros lot', 'Jackpot'), {'packs': {'premium': 3, 'gold': 1}}),
];

/// Éditeur de récompense : modèles, lignes avec − / +, ajout par menu.
class RewardEditor extends StatefulWidget {
  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool presets;
  const RewardEditor({super.key, required this.value, required this.onChanged, this.presets = true});
  @override
  State<RewardEditor> createState() => _RewardEditorState();
}

class _RewardEditorState extends State<RewardEditor> {
  late Map<String, dynamic> r = rewardClean(widget.value);

  void _set(Map<String, dynamic> v) {
    setState(() => r = rewardClean(v));
    widget.onChanged(r);
  }

  /// Ligne : (clé, sous-clé) → ('coins', null), ('packs', 'premium'), ('cards', '3')
  int _get(String k, String? sub) => sub == null ? _n(r[k]) : _n((r[k] as Map?)?[sub]);

  void _put(String k, String? sub, int v) {
    final m = Map<String, dynamic>.from(r);
    v = v.clamp(0, k == 'coins' ? 100000 : (k == 'pixels' ? 1000 : (k == 'lots' ? 5 : 10))).toInt();
    if (sub == null) {
      m[k] = v;
    } else {
      final mm = Map<String, dynamic>.from((m[k] as Map?) ?? const {});
      mm[sub] = v;
      m[k] = mm;
    }
    _set(m);
  }

  (String, String) _label(String k, String? sub) => switch (k) {
        'coins' => ('🪙', t('Pièces', 'Coins')),
        'pixels' => ('▦', t('Pixels', 'Pixels')),
        'lots' => ('📦', t('Lot de 5 paquets mixtes', 'Bundle of 5 mixed packs')),
        'packs' => (rewardPackIcon(sub ?? ''), rewardPackName(sub ?? '')),
        _ => ('🃏', t('Carte ${rarityName(_n(sub)).toLowerCase()} au hasard', 'Random ${rarityName(_n(sub)).toLowerCase()} card')),
      };

  Future<void> _edit(String k, String? sub) async {
    final ctl = TextEditingController(text: '${_get(k, sub)}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_label(k, sub).$2),
        content: TextField(controller: ctl, autofocus: true, keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Annuler', 'Cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text.trim()) ?? 0), child: const Text('OK')),
        ],
      ),
    );
    if (v != null) _put(k, sub, v);
  }

  Widget _row(String k, String? sub) {
    final (ic, label) = _label(k, sub);
    final v = _get(k, sub);
    final step = k == 'coins' ? 100 : 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
      child: Row(children: [
        SizedBox(width: 26, child: Text(ic, style: const TextStyle(fontSize: 16))),
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove, size: 18), onPressed: () => _put(k, sub, v - step)),
        GestureDetector(
          onTap: () => _edit(k, sub),
          child: Container(
            constraints: const BoxConstraints(minWidth: 40),
            alignment: Alignment.center,
            child: Text('$v', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFFFD166), fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ),
        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add, size: 18), onPressed: () => _put(k, sub, v + step)),
      ]),
    );
  }

  Future<void> _add() async {
    final items = <(String, String?)>[
      ('coins', null),
      ('pixels', null),
      for (final p in kRewardPacks) ('packs', p),
      ('lots', null),
      for (final c in const ['1', '2', '3', '4']) ('cards', c),
    ];
    final pick = await showModalBottomSheet<(String, String?)>(
      context: context,
      backgroundColor: kBg,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(padding: const EdgeInsets.all(14), child: Text(t('Ajouter à la récompense', 'Add to the reward'), style: const TextStyle(fontWeight: FontWeight.w900))),
          for (final it in items)
            ListTile(
              dense: true,
              leading: Text(_label(it.$1, it.$2).$1, style: const TextStyle(fontSize: 18)),
              title: Text(_label(it.$1, it.$2).$2),
              onTap: () => Navigator.pop(ctx, it),
            ),
        ]),
      ),
    );
    if (pick != null && _get(pick.$1, pick.$2) == 0) _put(pick.$1, pick.$2, pick.$1 == 'coins' ? 100 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String?)>[
      if (_n(r['coins']) > 0) ('coins', null),
      if (_n(r['pixels']) > 0) ('pixels', null),
      for (final k in ((r['packs'] as Map?) ?? const {}).keys) ('packs', k.toString()),
      if (_n(r['lots']) > 0) ('lots', null),
      for (final k in ((r['cards'] as Map?) ?? const {}).keys) ('cards', k.toString()),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.presets) ...[
        Wrap(spacing: 6, runSpacing: 6, children: [
          ActionChip(label: Text(t('Rien', 'Nothing')), onPressed: () => _set({})),
          for (final (name, v) in kRewardPresets)
            ActionChip(
              label: Text('$name · ${rewardText(v)}', style: const TextStyle(fontSize: 12)),
              side: BorderSide(color: rewardText(v) == rewardText(r) ? kGold : Colors.white24),
              onPressed: () => _set(v),
            ),
        ]),
        const SizedBox(height: 10),
      ],
      for (final (k, sub) in rows) _row(k, sub),
      OutlinedButton.icon(
        onPressed: _add,
        icon: const Icon(Icons.add, size: 18),
        label: Text(t('Ajouter : pièces, pixels, paquet, booster, lot, carte', 'Add: coins, pixels, pack, booster, bundle, card')),
      ),
    ]);
  }
}
