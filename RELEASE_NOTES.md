# MR Watcher v0.6.0

La fenêtre principale devient une table à colonnes. Une colonne porte une
information, à la même place sur chaque ligne : on descend une colonne du
regard au lieu de lire chaque ligne. Le panneau de barre de menus est
inchangé.

## Ajouts

- **Table à colonnes** dans les trois onglets, en-tête aligné sur les lignes,
  chiffres en caractères tabulaires. Une donnée absente laisse une cellule
  vide, jamais un marqueur qui ne dit rien.
- **Rail de gravité** et **pastille d'état unique** : l'état nomme la prochaine
  action — `Conflit`, `CI KO`, `Rebase requis`, `CI en cours`, `En attente de
  revue`, `Prête à merger` — et ouvre le pipeline quand il s'agit d'un état CI.
  Le détail complet reste au survol. La couleur n'est jamais le seul porteur de
  sens.
- **Tri par urgence**, figé, à la place du tri par date. Sur vos MRs : bloquée,
  en retard, fils ouverts, en attente d'approbation, prête. En revue : à
  revalider, à reviewer, j'attends l'auteur, approuvée — la plus vieille dette
  de review d'abord.
- **Chips de filtre à compteurs** dans les onglets de revue (`Tout`,
  `À revalider`, `Mes fils`, `Sans revue`, `To Review`, `Approuvées`), sur une
  liste plate. Une chip à zéro reste affichée et grisée : les positions ne
  bougent jamais. Elles remplacent le groupement par statut Jira, qui plaçait
  les MRs déjà approuvées au-dessus de celles qui demandaient une action.
- **Colonne « Votre implication »** en revue : ce que *vous* avez à faire sur
  cette MR, séparé de l'état objectif de la MR. Ses libellés ouvrent
  directement le fil concerné dans GitLab.
- **Densité** : environ 18 lignes visibles là où il en tenait 8.

## Corrections

- Les numéros de MR s'affichaient `!57 020` : l'interpolation d'un entier dans
  un libellé appliquait le séparateur de milliers français. Corrigé partout,
  y compris dans les libellés d'accessibilité.
- La colonne Actions était coupée à la largeur minimale de la fenêtre, rendant
  **Masquer** inatteignable. La largeur minimale est désormais calculée à
  partir des colonnes réelles et ne peut plus être inférieure au contenu.
- Le bouton `/rebase` restait masqué grâce à une comparaison de texte, donc
  serait réapparu sur les MRs en conflit si le libellé changeait. La règle
  s'appuie maintenant sur l'état de conflit lui-même.
- Le titre d'une MR n'est plus étiré indéfiniment dans une fenêtre large.
- Le ticket n'est plus écrit deux fois quand le titre le répète déjà.
- Les compteurs de retard à quatre chiffres sont bornés à `999+` : ils
  écrasaient la colonne alors qu'ils en disent moins qu'un petit nombre.

## À savoir

- La largeur minimale de la fenêtre passe de 760 à 986 points : une fenêtre
  plus étroite s'élargira une fois au premier lancement.
- Le panneau de barre de menus conserve son affichage compact en cartes et son
  groupement par statut Jira.

## Validation

- `swift build -c release` sans avertissement, `swift test` (60 tests), et
  installation locale.
- Les quatre commits compilent chacun isolément : l'historique reste bisectable.
- Vérifié dans l'application installée, en clair et en sombre, à 986, 1140 et
  1600 points de large : les trois onglets, les actions de ligne, les ancres de
  fils GitLab et le filtrage par chips.
