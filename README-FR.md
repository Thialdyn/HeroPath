# Hero’sPath 1.0.0

Hero’sPath enregistre les déplacements du joueur dans World of Warcraft et conserve une trajectoire exploitable sur de longues sessions.

## Contenu

- `Addon/HeroPath/` : addon installable et source runtime.
- `Documentation/` : architecture, format de données, récupération, API et intégration.
- `Demo/` : démonstration locale du replay et de la carte.
- `Maps/` : données cartographiques et assets utilisés par la démonstration.
- `Tests/Collector/` : tests du collecteur.
- `Tests/Release/` : tests du paquet, du renderer et des assets.
- `Web/` : modules de projection et de replay.

## Collecte

- observation des coordonnées monde à 4 Hz ;
- stockage adaptatif selon la distance, la courbure, les changements d’état et les keyframes ;
- coordonnées monde en yards ;
- contrôle croisé entre `C_Map` et `UnitPosition` ;
- modes distincts pour marche, monture, nage, taxi, fantôme et mouvement spécial ;
- ruptures explicites lorsque la continuité n’est pas prouvée ;
- transitions départ/arrivée pour les déplacements sémantiques ;
- contextes de carte enregistrés uniquement aux événements utiles ;
- API publique en lecture seule pour les intégrations externes.

Auteur : **Darwyn**.
