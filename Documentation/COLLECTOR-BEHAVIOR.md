# Comportement du collecteur

Ce document décrit la chaîne position -> classification -> continuité -> sampling -> stockage -> compaction -> reprise -> export.

## Position

- observation à 4 Hz ;
- coordonnées monde en yards ;
- `C_Map` comme source principale ;
- `UnitPosition` comme contrôle indépendant ;
- calibration XY/YX par observations concordantes ;
- rejet des valeurs non finies ou hors bornes ;
- un désaccord entre capteurs rend la position indisponible pour l’observation concernée.

## Géométrie adaptative

La persistance combine distance, intervalle temporel, changement de mode et courbure. Le point qui porte réellement un virage peut être protégé. Les petites boucles conservent leur forme tandis que les longues lignes droites restent peu denses.

Les tests couvrent notamment les angles droits, boucles serrées, petites boucles lentes, jitter sub-yard, nage, fantôme, changements de mode, fin de session et longues lignes droites.

## Continuité

Les coordonnées manquantes, chargements, changements de monde, reprises ambiguës et déplacements physiquement impossibles créent des frontières explicites. Les indices de sorts peuvent qualifier une rupture déjà observée, mais ne créent jamais un déplacement à eux seuls.

## Morts et instances

Une mort peut utiliser une position exacte, une dernière position extérieure fiable, une ancre d’entrée d’instance ou une position inconnue. Une ancienne ancre extérieure n’est pas réutilisée comme position de décès si elle n’est plus fiable.

Les intérieurs d’instance et de champ de bataille ne sont pas enregistrés comme polyline extérieure.

## Stockage et compaction

- chunks HP1 sparse delta-varint ;
- tail mutable borné ;
- contrôle d’intégrité des chunks ;
- simplification géométrique en yards ;
- conservation des courbures utiles ;
- keyframes temporelles ;
- compaction fractionnée ;
- conservation de la dernière observation extérieure fiable lors d’une sauvegarde propre.

Une erreur transitoire de compaction peut être retentée de façon bornée. Une corruption structurelle conserve les données autoritatives et demande une récupération explicite.

## Temps et ordre

`/played` est la base temporelle. Les timestamps non monotones sont rejetés. `order` fournit un ordre total pour les événements simultanés.

## API WoW

La frontière `SafeRead/Public` contient les exceptions API et refuse les valeurs secrètes ou non sûres. Le cœur ne consomme que des valeurs validées.

## Transitions et contextes

Les départs et arrivées sont corrélés par `transitionId`. La cause peut être inconnue, Hearth, sort de téléportation, frontière monde ou téléport observé. Les contextes `uiMapID`, zone et sous-zone sont enregistrés aux moments significatifs au lieu d’être dupliqués sur chaque point.
