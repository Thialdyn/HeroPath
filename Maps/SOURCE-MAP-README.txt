HeroPath - corpus cartographique local
=====================================

Ce dossier contient les cartes, tuiles et données locales utilisées par la démonstration HeroPath.

Source cartographique publique observée :
- CDN : https://assets.wowforevermap.com/20261005
- moteur : Leaflet 1.9.4
- tuiles : 512 x 512 px
- Azeroth : grille logique 72 x 47 au zoom natif 7
- terrain : /tiles/world/{z}/{x}/{y}.webp
- carte illustrée : /tiles/worldMaps/{z}/{x}/{y}.webp

La couverture locale est décrite dans `TILE-COVERAGE.txt`. `download_full_map.py` peut compléter la pyramide publique sans remplacer les fichiers déjà présents.
