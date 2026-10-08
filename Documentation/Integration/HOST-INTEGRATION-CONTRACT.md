# Contrat d’intégration pour un projet hôte

## Principe

L’intégration doit rester optionnelle : l’hôte détecte `_G.HeroPathAPI`, vérifie `GetAPIVersion() == 1`, puis utilise Hero’sPath comme fournisseur de télémétrie lorsque disponible. Il ne dépend pas des tables internes du collecteur.

## Frontières

- Hero’sPath reste l’unique propriétaire de son ticker 4 Hz et de `HeroPathDB` ;
- l’hôte évite un second tracker de position équivalent lorsque Hero’sPath fournit le trail ;
- les snapshots exportés sont traités comme des données en lecture seule ;
- le schéma de stockage ne sert jamais de version d’API ;
- `positionKnown=0` interdit de dessiner un segment continu vers l’endpoint concerné ;
- l’hôte garde la responsabilité de son UI, de ses filtres et de ses statistiques.

## Tests attendus côté hôte

Absence du fournisseur, version API incompatible, archive read-only, export vide, multi-personnages, monde inconnu, API restreinte, sauvegarde/rechargement, et benchmark CPU/mémoire avec et sans fournisseur.
