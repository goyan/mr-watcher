# MR Watcher v0.6.2

Trois corrections, toutes issues d'une seule question : pourquoi cliquer sur le
numéro de version ne faisait-il rien ?

## Corrections

- **Le numéro de version est cliquable en permanence.** Il ne l'était que
  lorsqu'une mise à jour avait déjà été détectée — un état qui n'apparaît qu'à la
  vérification horaire, donc presque jamais. Le survol, lui, affichait les notes
  de la version installée et invitait donc à cliquer. Un clic lance désormais la
  recherche de mises à jour, qui répond dans les deux cas. La pastille orange
  reste réservée à une mise à jour réellement disponible : c'est une autre
  information que « cliquable ».
- **Les info-bulles du panneau de barre de menus sont instantanées.** Sur les 39
  du panneau, 19 attendaient encore le délai système, alors que la même
  information s'affichait immédiatement dans la fenêtre principale. Survoler un
  auteur, une date, un nombre de commits ou un état de CI donnait l'impression
  que l'application hésitait ; il manquait deux modificateurs.
- **Neuf libellés visibles retrouvent leurs accents** — « Date de création »,
  « fil non résolu », et le titre de notification « Approbation échouée », qui
  était identique et fautif dans les deux interfaces.

## Validation

- `swift build -c release` sans avertissement, `swift test` (67 tests).
- Clic souris réel sur la version, dans la fenêtre et dans le panneau : la
  fenêtre de mise à jour s'ouvre et annonce que la version installée est à jour.
- Info-bulles vérifiées en déplaçant réellement le curseur et en capturant
  l'écran 300 ms plus tard, avec une capture de contrôle curseur écarté — lire
  l'attribut d'aide n'aurait rien prouvé, il était déjà présent avant.
