# Format de données Hero’sPath

- Version produit : **1.0.0**
- Schéma SavedVariables : **1**
- API publique : **1**
- Variable par personnage : `HeroPathDB`

## Point de trajectoire

```text
{ played, worldInstanceID, worldX, worldY, movementMode,
  breakBefore, protectedAnchor, order, breakReason }
```

Les coordonnées sont exprimées en yards monde. `played` utilise le temps `/played` et `order` fournit un ordre total pour les événements partageant le même timestamp.

## Chunks HP1

Les chunks utilisent un encodage sparse delta-varint. Le premier point fournit l’état complet ; les points suivants encodent les deltas et seulement les champs qui changent. Les métadonnées contiennent le nombre de points, les bornes temporelles et d’ordre, le dernier état, un checksum et les indicateurs d’intégrité.

## Ruptures

`breakBefore=1` signifie que le renderer ne doit pas relier ce point au précédent. `breakReason` distingue notamment initialisation, mort, téléport, changement de monde, coordonnées indisponibles, sortie d’instance, reprise et continuité incertaine.

## Événements

- décès : position exacte, dernière position fiable, ancre d’instance ou inconnue ;
- instance/BG : entrée, sortie, durée et identité ;
- état : release, résurrection, taxi, gap, transition monde, téléport, Hearth, tram et transport inconnu.

## Métadonnées sémantiques

Les transitions possèdent un identifiant, une cause, un niveau de confiance et des endpoints départ/arrivée. Les contextes de carte sont enregistrés de manière parcimonieuse aux événements significatifs.

## Sécurité de schéma

Si un fichier contient un schéma strictement supérieur à celui compris par ce build, Hero’sPath passe en mode archive read-only : aucun sampling, aucune compaction et aucune écriture ne sont effectués.
