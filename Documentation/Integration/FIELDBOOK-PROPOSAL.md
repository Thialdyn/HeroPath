# Proposition d’intégration - Azeroth Fieldbook

## Objectif

Utiliser Hero’sPath comme fournisseur optionnel de trail pour Adventurer’s Annals sans fusionner les deux modèles internes.

## Architecture proposée

```text
Azeroth Fieldbook
  └─ Annals TrailProvider
       ├─ provider natif
       └─ HeroPath provider → HeroPathAPI
```

Fieldbook conserve son UI, ses statistiques, ses quêtes et ses journaux. Hero’sPath fournit la géométrie, les modes de déplacement, les transitions et les contextes cartographiques.

## Première PR recommandée

- petite interface `TrailProvider` ;
- détection optionnelle de `HeroPathAPI` ;
- aucun accès direct à `HeroPathDB` ;
- fallback vers le provider natif ;
- tests absence/incompatibilité/read-only ;
- benchmark avant/après.

Les transitions corrélées et contextes cartographiques peuvent être consommés dans une étape séparée afin de garder une PR initiale facile à relire.
