# MR Watcher v0.5.13

## Ajouts
- Labels GitLab configurables pour la file **À revoir**.
- Actualisation configurable jusqu'à 24 h, avec désactivation des répétitions
  automatiques via **Jamais**.
- Avertissement visible lorsque Jira/acli n'est pas disponible, sans bloquer
  l'affichage GitLab.

## Corrections
- Les identifiants GitLab techniques sont affichés en `Prénom N.` dans les
  trois listes.
- Les tickets Jira sont des liens indépendants des liens GitLab.
- Les tooltips s'affichent instantanément, sans rognage, et ne bloquent plus le
  premier clic sur une action.
- Les MRs portant le statut Jira `TICKET ABANDONNÉ` sont exclues de **À revoir**.

## Validation
- `swift build -c release`, `swift test` et installation locale validés.
