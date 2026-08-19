# MR Watcher v0.5.15

## Ajouts
- **Mes revues** regroupe les MRs commentées et celles que vous avez
  approuvées.
- Les MRs déjà approuvées, sans fil personnel ouvert, sont classées dans la
  section **Approved**.
- **À revoir** exclut les MRs déjà présentes dans **Mes revues**.
- Chaque ticket affiche **Chargement Jira** pendant sa récupération asynchrone.

## Corrections
- Le statut Jira est publié dès la réponse `acli` : plus de blanc entre
  **Chargement Jira** et `Code review` ou tout autre état Jira.
- Les tickets Jira `TICKET ABANDONNÉ` sont retirés de **À revoir** après
  enrichissement.

## Validation
- `swift build -c release`, `swift test` et installation locale validés.
