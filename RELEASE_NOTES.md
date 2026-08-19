# MR Watcher v0.5.14

## Ajouts
- La détection de l'approbation Claude utilise la liste GitLab `approved_by`.

## Corrections
- `Lancer l'auto review` n'est plus proposé si le bot Claude a déjà approuvé
  la merge request.
- La détection s'appuie sur le nom GitLab du bot, plutôt que son username
  variable selon le projet.

## Validation
- `swift build -c release`, `swift test` et installation locale validés.
