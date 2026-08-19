# MR Watcher v0.5.17

## Ajouts
- Les statuts Jira, CI, conflits, retards, approbations et fils utilisent des
  tags sémantiques cohérents dans la fenêtre principale et le panneau de barre
  de menus.

## Corrections
- Les tags denses passent à la ligne sans perdre leur libellé ni leur signal
  d’attention.
- **À revalider · N fils** ouvre le premier fil personnel qui nécessite
  réellement une revalidation, directement sur sa note GitLab.
- Le badge n’utilise plus les routes GitLab de diff indisponibles sur cette
  instance.

## Validation
- Revue ciblée, `swift build -c release`, `swift test` et installation locale
  validés.
