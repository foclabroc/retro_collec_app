import 'package:flutter/material.dart';

import 'game.dart';
import 'layout.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Guide du jeu : comment marchent le score, les paquets, la Bourse, les duels…
// Ouvert depuis le menu latéral (GuideMenuTile). Valeurs reprises du serveur
// (sql/schema) ; chances et prix lus en direct (rcLive, kPackPrice) quand ils
// existent. Si une règle change côté serveur, mettre ce texte à jour.
// ═══════════════════════════════════════════════════════════════════════════

class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = _sections();
    return MaxWidth(
      child: Scaffold(
        appBar: AppBar(title: Text(t('Guide du jeu', 'Game guide'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Text(
                t('Tout ce qu\'il faut savoir pour compléter ta collection. Touche un thème pour l\'ouvrir.',
                    'Everything you need to complete your collection. Tap a topic to open it.'),
                style: const TextStyle(color: Colors.white70, fontSize: 13.5),
              ),
            ),
            for (final s in sections) _SectionCard(s),
          ],
        ),
      ),
    );
  }
}

class _Section {
  final String icon, title;
  final List<Widget> body;
  const _Section(this.icon, this.title, this.body);
}

class _SectionCard extends StatelessWidget {
  final _Section s;
  const _SectionCard(this.s);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: kGold,
          collapsedIconColor: Colors.white54,
          leading: Text(s.icon, style: const TextStyle(fontSize: 22)),
          title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          children: s.body,
        ),
      ),
    );
  }
}

// ─── Petits blocs de texte ────────────────────────────────────────────────
Widget _p(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4)),
    );

Widget _b(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 5, left: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(top: 1), child: Text('•  ', style: TextStyle(color: kGold, fontWeight: FontWeight.w900))),
        Expanded(child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.35))),
      ]),
    );

Widget _h(String s) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Text(s, style: const TextStyle(color: kGold, fontWeight: FontWeight.w800, fontSize: 13.5)),
    );

/// Tableau simple : en-tête + lignes
Widget _table(List<String> head, List<List<String>> rows, {List<Color?>? rowColors}) {
  TableRow row(List<String> cells, {bool header = false, Color? color}) => TableRow(
        decoration: header ? BoxDecoration(color: Colors.white.withOpacity(0.06)) : null,
        children: [
          for (var i = 0; i < cells.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(cells[i],
                  textAlign: i == 0 ? TextAlign.left : TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: header || i == 0 ? FontWeight.w800 : FontWeight.w600,
                    color: header ? Colors.white70 : (i == 0 ? color ?? Colors.white : Colors.white),
                  )),
            ),
        ],
      );
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(10)),
        child: Table(
          border: TableBorder.symmetric(inside: const BorderSide(color: Colors.white10)),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            row(head, header: true),
            for (var r = 0; r < rows.length; r++) row(rows[r], color: rowColors?[r]),
          ],
        ),
      ),
    ),
  );
}

String _price(String k) => '${kPackPrice[k] ?? kPackBase[k] ?? 0}';

// ─── Contenu ──────────────────────────────────────────────────────────────
List<_Section> _sections() {
  const pts = [1, 2, 5, 15, 50];
  final rar = [for (var r = 0; r < 5; r++) rarityName(r)];
  final rarColors = <Color?>[for (var r = 0; r < 5; r++) kRarityLight[r]];

  return [
    _Section('🃏', t('Les cartes', 'Cards'), [
      _p(t('Chaque carte est la jaquette d\'un jeu rétro, rangée par console. Touche une carte débloquée pour voir sa fiche (description, studio, année, capture).',
          'Each card is a retro game box art, sorted by console. Tap an unlocked card to see its details (description, studio, year, screenshot).')),
      _h(t('5 raretés', '5 rarities')),
      _table(
        [t('Rareté', 'Rarity'), t('Chance', 'Chance')],
        [
          [rar[0], '60 %'],
          [rar[1], '26 %'],
          [rar[2], '10 %'],
          [rar[3], '3,2 %'],
          [rar[4], '0,8 %'],
        ],
        rowColors: rarColors,
      ),
      _h(t('4 finitions', '4 finishes')),
      _b(t('Normale : la carte de base.', 'Normal: the basic card.')),
      _b(t('Brillante : reflet holographique (≈ ${livePct('holo')} par carte).', 'Holo: holographic shine (≈ ${livePct('holo')} per card).')),
      _b(t('Dorée : cadre or (≈ ${livePct('gold')}).', 'Gold: golden frame (≈ ${livePct('gold')}).')),
      _b(t('Full art : illustration pleine carte, seulement sur les épiques et légendaires (≈ ${livePct('fullart')}).',
          'Full art: full-card artwork, epic and legendary only (≈ ${livePct('fullart')}).')),
      _h(t('Sagas', 'Sagas')),
      _p(t('Des cartes spéciales de grandes séries (Mario, Sonic, Zelda, Pokémon, Resident Evil, Castlevania) peuvent sortir des paquets (≈ ${livePct('saga')}). Elles ont leur propre album.',
          'Special cards from big series (Mario, Sonic, Zelda, Pokémon, Resident Evil, Castlevania) can drop from packs (≈ ${livePct('saga')}). They have their own album.')),
    ]),
    _Section('🏆', t('Le score et le classement', 'Score and ranking'), [
      _p(t('Ton score mesure la valeur de ta collection. Chaque carte possédée rapporte des points selon sa rareté, multipliés par sa finition.',
          'Your score measures how valuable your collection is. Each card you own scores points by rarity, multiplied by its finish.')),
      _table(
        [t('Rareté', 'Rarity'), t('Points', 'Points')],
        [for (var r = 0; r < 5; r++) [rar[r], '${pts[r]}']],
        rowColors: rarColors,
      ),
      _table(
        [t('Finition', 'Finish'), t('Multiplicateur', 'Multiplier')],
        [
          [finishName(0), '×1'],
          [finishName(1), '×1'],
          [finishName(2), '×3'],
          [finishName(3), '×6'],
        ],
      ),
      _b(t('Chaque carte compte une fois par finition : 3 exemplaires normaux d\'une même carte ne rapportent pas plus qu\'un seul. Les doublons ne servent pas au score, mais à échanger, vendre, recycler ou fusionner.',
          'Each card counts once per finish: 3 normal copies of the same card score no more than one. Duplicates don\'t add to the score, but you can trade, sell, recycle or fuse them.')),
      _b(t('Exemple : une légendaire dorée = 50 × 3 = 150 points. Si tu as aussi la version normale, +50.',
          'Example: a gold legendary = 50 × 3 = 150 points. If you also own the normal one, +50.')),
      _b(t('Le classement montre les joueurs qui ont ouvert au moins un paquet et sont venus dans les 7 derniers jours.',
          'The ranking shows players who opened at least one pack and played in the last 7 days.')),
    ]),
    _Section('📦', t('Les paquets', 'Packs'), [
      _b(t('Paquet gratuit : un toutes les 6 heures.', 'Free pack: one every 6 hours.')),
      _b(t('Mixte (${_price('mixte')} pièces) : 5 cartes de toutes les consoles.', 'Mixed (${_price('mixte')} coins): 5 cards from every console.')),
      _b(t('Console (${_price('console')} pièces) : 5 cartes de la console de ton choix.', 'Console (${_price('console')} coins): 5 cards from the console you pick.')),
      _b(t('Premium (${_price('premium')} pièces) : 5 cartes, dont la dernière au moins rare (5 % de légendaire, 20 % d\'épique).',
          'Premium (${_price('premium')} coins): 5 cards, the last one at least rare (5% legendary, 20% epic).')),
      _b(t('Mystère (${_price('mystery')} pièces) : 3, 5 ou 8 cartes au hasard.', 'Mystery (${_price('mystery')} coins): 3, 5 or 8 random cards.')),
      _b(t('Lot de 5 paquets mixtes (25 cartes) : gratuit chaque samedi.', '5 mixed packs bundle (25 cards): free every Saturday.')),
      _b(t('Boosters spéciaux en pixels : étoile 15, console spéciale 25, or 40.', 'Special boosters for pixels: star 15, special console 25, gold 40.')),
      _b(t('Garantie : après 30 paquets sans épique ni légendaire, le suivant en contient forcément une.',
          'Pity: after 30 packs without an epic or legendary, the next one is guaranteed to have one.')),
      _p(t('Les prix peuvent baisser pendant les événements (promos affichées dans la boutique).', 'Prices can drop during events (promos shown in the shop).')),
    ]),
    _Section('🪙', t('Pièces et pixels', 'Coins and pixels'), [
      _h(t('Gagner des pièces', 'Earning coins')),
      _b(t('Connexion du jour : +50 pièces, +200 tous les 7 jours d\'affilée.', 'Daily login: +50 coins, +200 every 7 days in a row.')),
      _b(t('Roue du jour (Bonus) : un tour gratuit par jour, roue dorée le 7e jour de série.', 'Daily wheel (Bonus): one free spin a day, golden wheel on the 7th day of your streak.')),
      _b(t('Gamedle : devine le jeu du jour, de 100 pièces (1er essai) à 20.', 'Gamedle: guess the game of the day, from 100 coins (1st try) down to 20.')),
      _b(t('Quiz : 5 pièces par bonne réponse, jusqu\'à 100 par jour.', 'Quiz: 5 coins per right answer, up to 100 a day.')),
      _b(t('Paliers de collection par console : 25 %, 50 %, 75 %, 100 % → 100, 250, 500, 2 000 pièces. Sagas : 50 % et 100 % → 100 et 500 pièces (+2 pixels).',
          'Collection milestones per console: 25%, 50%, 75%, 100% → 100, 250, 500, 2,000 coins. Sagas: 50% and 100% → 100 and 500 coins (+2 pixels).')),
      _b(t('Vendre à la Bourse, gagner des duels, réussir les défis et les événements.', 'Selling on the Exchange, winning duels, completing challenges and events.')),
      _h(t('Pixels', 'Pixels')),
      _p(t('Monnaie rare : 1 pixel par duel gagné, et dans certaines récompenses (défis, trophées, paliers, coffre). Ils achètent les boosters spéciaux.',
          'Rare currency: 1 pixel per duel won, and in some rewards (challenges, trophies, milestones, chest). They buy special boosters.')),
    ]),
    _Section('♻️', t('Doublons : recycler, fusionner, fabriquer', 'Duplicates: recycle, fuse, craft'), [
      _b(t('Recycler : un doublon rapporte des pièces (commune 5, peu commune 15, rare 50, épique 150, légendaire 500), ×3 en brillante, ×10 en dorée, ×30 en full art.',
          'Recycle: a duplicate gives coins (common 5, uncommon 15, rare 50, epic 150, legendary 500), ×3 holo, ×10 gold, ×30 full art.')),
      _b(t('Fusionner : 5 exemplaires normaux → 1 brillant ; 3 brillants → 1 doré. Le full art ne s\'obtient qu\'en paquet.',
          'Fuse: 5 normal copies → 1 holo; 3 holo → 1 gold. Full art only comes from packs.')),
      _b(t('Fabriquer une carte manquante : commune 50, peu commune 150, rare 500, épique 1 500, légendaire 5 000 pièces.',
          'Craft a missing card: common 50, uncommon 150, rare 500, epic 1,500, legendary 5,000 coins.')),
    ]),
    _Section('💱', t('Bourse, échanges et cadeaux', 'Exchange, trades and gifts'), [
      _b(t('Bourse : mets en vente jusqu\'à 12 cartes au prix que tu veux (1 à 99 999 pièces). Tu es payé dès qu\'un joueur achète.',
          'Exchange: list up to 12 cards at the price you want (1 to 99,999 coins). You get paid as soon as someone buys.')),
      _b(t('Achat groupé : « ☑ Plusieurs » ou appui long pour acheter jusqu\'à 30 cartes d\'un coup, au prix maximum que tu fixes.',
          'Bulk buy: “☑ Several” or long press to buy up to 30 cards at once, at a max price you set.')),
      _b(t('Échanges : propose jusqu\'à 5 cartes contre 5 cartes à un autre joueur. Il accepte ou refuse.',
          'Trades: offer up to 5 cards for 5 cards to another player. They accept or decline.')),
      _b(t('Cadeaux : offre jusqu\'à 3 paquets gratuits par jour à d\'autres joueurs (un par joueur et par jour). Ça ne te coûte rien !',
          'Gifts: give up to 3 free packs a day to other players (one per player per day). It costs you nothing!')),
      _b(t('Voisinage → cartes manquantes : trouve qui a en double les cartes qu\'il te manque.', 'Neighbors → missing cards: find who has duplicates of the cards you\'re missing.')),
      _p(t('Un nouveau compte peut utiliser la Bourse, les cadeaux et les échanges 24 h après sa création.',
          'A new account can use the Exchange, gifts and trades 24 h after it was created.')),
    ]),
    _Section('⚔️', t('Duels (Salle de jeux)', 'Duels (Game room)'), [
      _p(t('Défie un joueur au 4 en ligne ou à Console Wars (bataille navale avec des consoles), en direct ou en tour par tour.',
          'Challenge a player to Connect 4 or Console Wars (battleship with consoles), live or turn by turn.')),
      _b(t('Victoire : +150 pièces et +1 pixel. Défaite ou égalité : +10 pièces.', 'Win: +150 coins and +1 pixel. Loss or draw: +10 coins.')),
      _b(t('Gains limités à 4 duels par jour contre le même joueur, et pas avec un compte créé depuis moins d\'un jour (parties amicales ensuite).',
          'Rewards are limited to 4 duels a day against the same player, and not with an account less than a day old (friendly games after that).')),
      _b(t('Certains événements multiplient les gains des duels.', 'Some events multiply duel rewards.')),
      _b(t('Regarde les duels en direct des autres (👁) et envoie des réactions.', 'Watch other players\' live duels (👁) and send reactions.')),
    ]),
    _Section('🏆', t('Tournois', 'Tournaments'), [
      _p(t('L\'admin organise des tournois au 4 en ligne ou à Console Wars (4, 8 ou 16 places). Inscris-toi dans la Salle de jeux avant l\'heure de début.',
          'The admin runs Connect 4 or Console Wars tournaments (4, 8 or 16 spots). Sign up in the Game room before the start time.')),
      _b(t('Tous les matchs se jouent en direct, à élimination directe : 1 manche, finale en 2 manches gagnantes. Un match nul se rejoue.',
          'All matches are live knockout games: 1 round, final best of 3. A draw is replayed.')),
      _b(t('Sois connecté à l\'heure : quand ton match commence, touche « Jouer ». Absent au bout de 3 minutes = forfait (les deux absents : tirage au sort).',
          'Be online on time: when your match starts, tap "Play". Not there after 3 minutes = forfeit (both missing: random draw).')),
      _b(t('Inscription gratuite ou payante : les mises forment une cagnotte pour le vainqueur (ou 70 % / 30 % avec le finaliste), en plus des lots.',
          'Free or paid entry: fees make a pot for the winner (or 70% / 30% with the runner-up), on top of the prizes.')),
      _b(t('Pas de gains par partie : les lots (1er, 2e, demi-finalistes) arrivent à la fin. Trophée « Champion » pour les tournois gagnés.',
          'No reward per game: prizes (1st, 2nd, semi-finalists) come at the end. "Champion" trophy for tournaments won.')),
      _b(t('Moins de 2 inscrits : tournoi annulé et mises rendues. Tu peux te désinscrire (remboursé) jusqu\'au début.',
          'Fewer than 2 players: tournament cancelled and fees refunded. You can leave (refunded) until it starts.')),
    ]),
    _Section('🎯', t('Défis, trophées et événements', 'Challenges, trophies and events'), [
      _b(t('Défis de la semaine : 6 défis chaque lundi, les mêmes pour tous. Fais-les tous pour ouvrir le coffre (pièces, 2 pixels, paquet premium).',
          'Weekly challenges: 6 challenges every Monday, the same for everyone. Do them all to open the chest (coins, 2 pixels, premium pack).')),
      _b(t('Trophées : bronze, argent, or, avec une récompense à chaque palier. Choisis-en 3 à montrer sur ton profil et ta borne.',
          'Trophies: bronze, silver, gold, with a reward at each tier. Pick 3 to show on your profile and arcade cabinet.')),
      _b(t('Événements : promos, chances doublées, défis à paliers… pendant un temps limité (menu → Événements).',
          'Events: promos, boosted odds, tiered challenges… for a limited time (menu → Events).')),
    ]),
    _Section('🏘️', t('Voisinage, messages et parrainage', 'Neighbors, messages and referral'), [
      _b(t('Voisinage : la salle d\'arcade, une borne par joueur venu dans les 7 derniers jours. Personnalise la tienne.',
          'Neighbors: the arcade, one cabinet per player seen in the last 7 days. Customize yours.')),
      _b(t('En ligne : un joueur apparaît en ligne dès qu\'il ouvre le jeu, et disparaît quelques secondes après l\'avoir fermé.',
          'Online: a player shows as online as soon as they open the game, and disappears a few seconds after closing it.')),
      _b(t('Messages : tape @ puis un pseudo pour citer quelqu\'un ; il est prévenu.', 'Messages: type @ then a name to mention someone; they get notified.')),
      _b(t('Parrainage : donne ton code à un ami (à entrer dans les 7 jours suivant son inscription). Quand il a ouvert 5 paquets et joué 2 jours, vous recevez chacun un paquet premium (10 filleuls max).',
          'Referral: give your code to a friend (to enter within 7 days of signing up). Once they open 5 packs and play 2 days, you both get a premium pack (10 referrals max).')),
      _b(t('Mot de passe (Profil) : il te permet de retrouver ton compte sur un autre appareil.', 'Password (Profile): lets you get your account back on another device.')),
    ]),
  ];
}

/// Entrée « Guide du jeu » du menu latéral
class GuideMenuTile extends StatelessWidget {
  final bool compact;
  final VoidCallback? beforeOpen;
  const GuideMenuTile({super.key, this.compact = false, this.beforeOpen});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF8FD3FF);
    void go() {
      final nav = Navigator.of(context);
      beforeOpen?.call();
      nav.push(MaterialPageRoute(builder: (_) => const GuidePage()));
    }

    if (compact) {
      return Tooltip(
        message: t('Guide du jeu', 'Game guide'),
        child: InkWell(
          onTap: go,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              const Icon(Icons.menu_book, color: blue, size: 20),
              const SizedBox(height: 2),
              Text(t('Guide', 'Guide'), style: const TextStyle(fontSize: 10.5, color: Colors.white60)),
            ]),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: blue.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: go,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: blue.withOpacity(0.5))),
            child: Row(children: [
              const Icon(Icons.menu_book, color: blue, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(t('Guide du jeu', 'Game guide'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ]),
          ),
        ),
      ),
    );
  }
}
