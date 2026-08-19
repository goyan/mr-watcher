# Publier une release

Ce runbook publie une version Sparkle signée, un DMG manuel et une release
GitHub. Les artefacts et l'appcast ne doivent jamais être modifiés après leur
signature.

## Préparation

1. Vérifier que les changements ont passé `swift build -c release` et
   `swift test`.
2. Mettre à jour `README.md`, `PRD.md`, `TRACKING.md` et
   `RELEASE_NOTES.md`. Les notes doivent contenir les rubriques `Ajouts`,
   `Corrections` et `Validation`.
3. Créer et pousser le commit fonctionnel. Le script de release exige un
   worktree propre.

## Génération et publication

Pour une version `X.Y.Z` :

```bash
MRWATCHER_RELEASE_DRY_RUN=1 bash scripts/release.sh X.Y.Z
bash scripts/release.sh X.Y.Z
```

Le second appel reconstruit l'application, crée
`dist/MRWatcher-vX.Y.Z.zip` et `dist/MRWatcher-vX.Y.Z.dmg`, met à jour
`VERSION`, signe et vérifie `appcast.xml`.

Après vérification des fichiers générés :

```bash
git add VERSION appcast.xml
git commit -m "chore: publish vX.Y.Z update feed"
git push origin main
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z \
  dist/MRWatcher-vX.Y.Z.zip \
  dist/MRWatcher-vX.Y.Z.dmg \
  --title "MR Watcher vX.Y.Z" \
  --notes-file RELEASE_NOTES.md
```

## Vérification post-release

```bash
gh release view vX.Y.Z
git ls-remote --tags origin vX.Y.Z
git status --short
```

Confirmer que la release contient le ZIP et le DMG, que le tag pointe vers le
commit contenant `VERSION` et `appcast.xml`, et que le worktree est propre.
Installer ensuite le bundle courant avec `bash install.sh` si nécessaire.

## Incident de publication

Avant le commit du feed, corriger le problème puis relancer le script avec un
nouveau worktree propre. Après publication GitHub, ne remplacez pas le ZIP ou
le DMG signé : publiez un nouveau correctif avec une nouvelle version.
