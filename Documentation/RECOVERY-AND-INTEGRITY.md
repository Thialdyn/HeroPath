# Récupération et intégrité

Hero’sPath applique une politique fail-closed : une donnée douteuse ne doit jamais créer une trajectoire apparemment continue.

## Contrôles

- valeurs numériques finies et bornées ;
- flags et enums stricts ;
- tables numériques parcourues de façon à détecter les trous ;
- timestamps et ordres monotones ;
- checksums de chunks ;
- validation approfondie d’un chunk avant utilisation ;
- cohérence entre métadonnées de chunk et points décodés ;
- reconstruction de `lastPlayed` depuis l’historique fiable ;
- retry borné uniquement pour les exceptions transitoires de compaction.

## Quarantaine

Les éléments rejetés sont copiés dans `recoveryQuarantine` avec un motif et un contexte minimal. Lorsqu’un élément invalide coupe une séquence, le prochain point fiable est marqué comme rupture afin d’éviter un pont visuel artificiel.

## Compaction

Une corruption structurelle bloque la compaction concernée et conserve le tail autoritatif. Une exception transitoire peut être retentée jusqu’à la limite contractuelle. Une sauvegarde propre protège aussi la dernière observation extérieure fiable afin que le replay atteigne réellement la fin de session.
