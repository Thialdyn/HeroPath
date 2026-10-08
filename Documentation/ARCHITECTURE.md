# Architecture du collecteur Hero’sPath

## Objectif

Le collecteur conserve la forme du déplacement sans relier artificiellement deux positions lorsque la continuité n’est pas prouvée.

## Modules runtime

1. `Contract.lua` - identité produit, schéma, enums, seuils et politiques.
2. `DataModel.lua` - validation pure, codec HP1 et opérations sans API WoW.
3. `Bootstrap.lua` - frontière avec les API WoW et capteurs de position.
4. `Metadata.lua` - contextes cartographiques et transitions corrélées.
5. `HeroPath.lua` - machine d’état, sampling, continuité, stockage et compaction.
6. `API.lua` - API publique en lecture seule.
7. `Diagnostics.lua` - commandes `/hp` et état du collecteur.

Le `.toc` impose cet ordre de chargement.

## Chemin chaud

Toutes les 0,25 s :

```text
position monde
-> validation
-> classification du mouvement
-> contrôle de continuité
-> décision de persistance
-> append éventuel dans le tail
```

La décision de persistance est O(1) et ne parcourt pas l’historique complet.

## Sources de position

`C_Map.GetBestMapForUnit`, `C_Map.GetPlayerMapPosition` et `C_Map.GetWorldPosFromMapPos` fournissent la position monde principale. `UnitPosition` sert de source indépendante de contrôle. Son orientation XY/YX est apprise à partir d’observations comparées à `C_Map`.

Un désaccord supérieur à la tolérance prévue ne produit pas de coordonnée moyenne : la position est considérée indisponible.

## Stockage adaptatif

Une observation peut être conservée pour quatre raisons : distance, courbure, changement de mode ou keyframe temporelle. Un virage serré conserve donc plus de points qu’une longue ligne droite sans augmenter la fréquence d’observation.

## Stockage persistant

- `chunks` : blocs HP1 finalisés et immuables ;
- `tail` : zone mutable bornée ;
- `events` : morts, instances et états ;
- `semanticEvents` : signaux sémantiques observés ;
- `transitions` : départs et arrivées corrélés ;
- `contextEvents` : contexte de carte aux moments significatifs.

La compaction travaille sur une copie logique et ne remplace les données courantes qu’après validation du résultat.

## Invariants

- aucune coordonnée synthétique ;
- aucune continuité au travers d’un intervalle inconnu ;
- ordre temporel monotone ;
- coordonnées finies et bornées ;
- les indices de sorts annotent un déplacement observé, ils ne le créent pas ;
- les chunks finalisés sont immuables ;
- le schéma SavedVariables est indépendant de la version produit ;
- un schéma plus récent que celui compris par le build est ouvert en lecture seule.
