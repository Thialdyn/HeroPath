# Tests

## Suites

- `Tests/Collector/run-release-tests.sh` : comportement, intégrité, transitions, sampling et architecture.
- `Tests/Collector/run-stress-tests.sh` : sessions longues et profils de charge.
- `Tests/Release/run-tests.sh` : paquet, démo, projection, assets, navigateur et replay.

## Couverture du collecteur

Les tests couvrent notamment :

- géométrie adaptative et petites boucles ;
- marche, monture, nage, taxi, fantôme et mouvement spécial ;
- Hearth, téléports, tram et traversées de monde ;
- mort, release, résurrection et instance ;
- reload, login et reprise ;
- gaps de sampling ;
- corruption et structures incomplètes ;
- chunks, compaction et récupération ;
- calibration `UnitPosition` XY/YX ;
- valeurs API restreintes ;
- identité personnage ;
- schéma futur en lecture seule.

Le code runtime testé est le contenu de `Addon/HeroPath/`, qui est aussi le contenu du ZIP addon installable.
