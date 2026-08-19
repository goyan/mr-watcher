# MR Watcher v0.5.16

## Ajouts
- Un fil personnel inclut désormais tout fil créé par vous ou auquel vous avez
  répondu.
- Le badge orange actionnable **À revalider · N fils** signale les fils
  personnels non résolus auxquels un commit de tête plus récent se rapporte.

## Corrections
- Les compteurs `Mes fils` / `autres`, le garde-fou d’approbation et la section
  `Approved` prennent correctement en compte vos réponses à un fil existant.
- Le signal de relecture compare les timestamps GitLab des notes et du commit
  de tête, sans faux positif causé par `updated_at`.

## Validation
- `swift build -c release`, `swift test` et installation locale validés.
