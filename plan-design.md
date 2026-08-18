# Plan de redesign — MR Watcher

## Contexte et intention

Les références DisplayLink Manager montrent une application de barre de menus macOS dense
mais calme : un panneau sombre ancré sous la barre système, une navigation courte,
des zones de contenu clairement séparées et des contrôles natifs à faible bruit visuel.

Le redesign doit reprendre cette grammaire sans imiter un gestionnaire d'écrans :
MR Watcher reste un outil de décision rapide. L'information la plus importante est de
savoir quelles MRs demandent une action, puis d'ouvrir GitLab, Jira ou de lancer un
rebase sans chercher le contrôle.

Ce document est un plan de design. Il ne modifie pas le comportement métier, les appels
GitLab/Jira, le polling, les notifications ni les garanties de sécurité.

## Décision de surface

| Surface | Rôle | Direction |
|---|---|---|
| Popover barre de menus | Consultation et actions courantes | Panneau sombre/translucide ancré sous l'icône, largeur cible 680 px (min. 600, max. 760), hauteur plafonnée avec liste scrollable. |

Pour obtenir la composition libre des références (entête, onglets, cartes et liste
scrollable), passer le `MenuBarExtra` de `.menu` à `.window`. Le menu système actuel est
contraint à des lignes de menu et ne peut pas porter fidèlement cette hiérarchie. Valider
au prototype que le comportement attendu reste intact : ancrage sous l'icône, fermeture au
clic extérieur, navigation clavier, aucune fenêtre Dock supplémentaire.

## Hiérarchie de l'information

### Barre de menus

- Garder l'icône de synchronisation ; le compteur reste le seul chiffre affiché en permanence.
- Sémantique d'état : aucun signal pour l'état sain, badge pour événement non lu, accent
  orange/rouge seulement lorsqu'une action est requise. Ne pas encoder l'ensemble de l'état
  CI dans l'icône de barre de menus.
- Prévoir un libellé d'accessibilité et une infobulle qui résument le nombre d'alertes et le
  dernier état de synchronisation.

### Cadre et entête du popover

- Reprendre le cadre des références : fenêtre sombre en material, bordure discrète, rayon
  d'environ 16 pt pour le conteneur principal et petite encoche centrée vers l'icône de barre
  des menus. Les surfaces internes restent à 6 à 8 pt de rayon.
- Ligne haute : marque MR Watcher à gauche, état de synchronisation concis et bouton icône
  actualiser à droite.
- Sous l'entête : contrôle segmenté centré à deux vues, `À traiter` et `Toutes`, avec l'onglet
  sélectionné en bleu système, comme `Displays` / `Settings` dans la référence.
- `À traiter` regroupe les MRs avec CI en échec, conflit, rebase nécessaire, threads non
  résolus ou approbations manquantes. `Toutes` conserve le regroupement Ouvertes / Mergées.
- Une erreur d'authentification remplace le statut de synchronisation par un message court
  et une action claire vers la configuration, sans afficher l'erreur technique brute comme
  contenu principal.

### Carte MR

Chaque MR devient une ligne-carte de hauteur stable (environ 68 à 76 pt), pas une concaténation
monospace de marqueurs. Dans une largeur de 680 px, les MRs peuvent être présentées sur deux
colonnes lorsque l'espace le permet, comme les deux écrans de la référence ; une seule colonne
est conservée quand le contenu ou les réglages d'accessibilité l'exigent.

1. Première ligne : symbole de gravité, `!IID`, nom du projet, titre de MR tronqué sur une ligne.
2. Seconde ligne : ticket Jira, CI, approbations, threads, retard de branche et âge, sous forme
   d'icône SF Symbol + valeur courte. Les données absentes ne laissent pas de placeholder.
3. À droite : un seul affordance d'action contextuelle. Le clic sur la zone principale ouvre
   GitLab ; un bouton icône ouvre Jira lorsqu'un ticket est trouvé ; `/rebase` et retrait sont
   des boutons explicites avec infobulle.
4. L'état visuel est porté en priorité par une barre/point de statut et les SF Symbols, puis
   confirmé par le texte. Une couleur seule ne doit jamais être la seule source de sens.

Les MRs mergées passent dans `Toutes`, section repliée par défaut dans le popover. Elles
restent accessibles mais ne concurrencent pas les MRs qui nécessitent une action.

### Événements et pied de panneau

- Conserver les événements récents, mais les placer dans une section repliable après les MRs.
- Afficher au plus trois événements dans le popover ; un éventuel historique étendu reste hors
  périmètre de ce redesign.
- Le pied fixe reprend la composition de la référence : version et dernier refresh au centre,
  menus secondaires à gauche, commande Quitter à droite. Utiliser `Menu` et des icônes SF
  Symbols, pas des boutons textuels larges.

## Langage visuel

Les captures de référence sont une direction de densité et de structure, non une raison
d'imposer une palette fixe. La palette doit rester sémantique et compatible clair/sombre.

| Élément | Traitement |
|---|---|
| Fond | Material macOS sombre adapté par le système ; pas de fond opaque custom ni de gradient. |
| Conteneur de section | `quaternarySystemFill` ou équivalent adaptatif, rayon 6 à 8 pt maximum. |
| Texte primaire | `primary`, titre en `.callout.weight(.semibold)`. |
| Métadonnées | `secondary`, `.caption` ou `.caption2`, une ligne. |
| Succès | vert sémantique : CI réussi, toutes approvals. |
| Attention | orange sémantique : en cours, retard, thread, ticket Jira stale. |
| Erreur/blocage | rouge sémantique : CI failed, conflit, erreur d'authentification. |
| Espacement | grille de 4 pt : marges panneau 12 pt, groupes 8 pt, gap icône/texte 6 pt. |

Les emojis actuellement utilisés dans le contenu des lignes doivent être remplacés par des SF
Symbols là où un symbole existe. Les emojis restent éventuellement dans les notifications,
où la compacité de la ligne n'est pas un enjeu.

## Comportements et accessibilité

- Conserver toutes les actions existantes : ouvrir GitLab, ouvrir Jira, actualiser, rebase
  confirmé, retirer une MR mergée, configurer, régler le poll, rechercher les mises à jour,
  quitter.
- Les lignes, boutons de statut et actions utilisent des zones de clic distinctes ; le clic
  principal ne doit jamais déclencher un rebase ou un retrait.
- Ajouter `.help` à toute action iconique et des libellés VoiceOver complets qui incluent
  l'IID et l'effet de l'action.
- Respecter `Reduce Transparency`, `Increase Contrast` et Dynamic Type macOS : aucune
  information critique ne doit être coupée ou uniquement visible au survol.
- Préserver le dernier contenu connu pendant un refresh ; seul le bouton actualiser reflète
  le chargement.

## Plan d'implémentation

1. **Figer le modèle de présentation.** Ajouter une couche de données de vue pure qui calcule
   la gravité, les métadonnées visibles et le regroupement `À traiter` / `Toutes`. La logique
   GitLab/Jira existante reste la source de vérité. Couvrir les règles de priorité avec des tests.

2. **Poser le conteneur de popover.** Migrer `MenuBarExtra` vers `.window`, définir la largeur
   600-760 px, les hauteurs stables, l'encoche, l'entête, le sélecteur et le pied. Vérifier les
   comportements macOS de fermeture et de focus avant de déplacer les actions.

3. **Construire la ligne MR réutilisable.** Extraire un composant de ligne partagé, alimenté
   par le modèle de présentation. Implémenter les états CI, conflit, approbation, discussions,
   rebase et merge, y compris les tooltips et labels d'accessibilité.

4. **Refondre le contenu du popover.** Brancher la liste `À traiter`, la liste complète, les
   sections repliables et les états configuration vide / erreur / absence de MR. S'assurer que
   les MRs mergées persistent et restent retirable comme aujourd'hui.

5. **Valider et ajuster.** Tester les parcours fonctionnels et capturer des screenshots clair
   et sombre. Installer localement seulement après build et tests propres.

## Fichiers concernés

| Fichier | Évolution attendue |
|---|---|
| `Sources/MRWatcher/App.swift` | Style du `MenuBarExtra` et état de sélection éventuel. |
| `Sources/MRWatcher/MenuBarView.swift` | Nouveau popover, sections, actions et états. |
| `Sources/MRWatcher/StateStore.swift` ou nouveau modèle de présentation | Calcul pur des priorités et des groupes. |
| `Tests/MRWatcherTests/` | Tests de priorité, regroupement et libellés de statut. |
| `PRD.md`, `TRACKING.md` | Mise à jour à la livraison du redesign, pas pendant ce plan. |

## Critères d'acceptation

- À l'ouverture du popover, une MR en échec ou bloquée est identifiable en moins d'une seconde.
- La liste reste lisible avec des titres très longs, des tickets absents et toutes les
  combinaisons de statut connues.
- Chaque action existante est encore atteignable et possède une aide au survol.
- Le popover reste utilisable au clavier et avec VoiceOver, en mode clair comme sombre.
- `swift build -c release` et `swift test` passent ; `bash install.sh` n'est exécuté qu'après.
- Les screenshots de validation montrent un panneau sans chevauchement, sans largeur instable et
  sans éléments tronqués autrement que les titres volontairement ellipsés.

## Hors périmètre

- Nouvelles intégrations métier (Slack, multi-auteur).
- Refonte de la configuration ou du système de notifications.
- Modification du contrat GitLab/Jira, du polling ou de la persistance des MRs mergées.
- Imitation pixel-perfect de DisplayLink Manager.
- Modification de `StatusView.swift` ou de la fenêtre principale de l'application.
