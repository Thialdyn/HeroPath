# Assets et cartes

La démonstration utilise uniquement des assets présents dans `Maps/`.

## Organisation

- `Maps/icons/` : icônes Hero’sPath et classes ;
- `Maps/WorldAtlas/icons/` : POI et services ;
- `Maps/WorldAtlas/class-icons/` : icônes de classe ;
- `Maps/WorldAtlas/data/` : manifestes, overlays et routes ;
- `Maps/WorldAtlas/tiles/` et `fallback/` : tuiles haute résolution et fallbacks ;
- `Maps/tiles/` : corpus cartographique local complémentaire.

Les tests de release vérifient la présence des assets actifs, l’absence d’orphelins dans les familles contrôlées et la cohérence des cartes utilisées par la démo.
