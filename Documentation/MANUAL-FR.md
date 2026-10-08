# Manuel Hero’sPath 1.0.0

## Installation

Copier `HeroPath` depuis `Addon/HeroPath/` dans `World of Warcraft/_retail_/Interface/AddOns/` ou dans le dossier équivalent du client ciblé. Le ZIP `Distributables/HeroPath-1.0.0.zip` contient exactement ce dossier installable.

## Commandes

- `/hp check` - état général et anomalies immédiates ;
- `/hp stats` - taille et structure du stockage ;
- `/hp pos` - sources de coordonnées et calibration ;
- `/hp contract` - version, schéma, API et paramètres principaux ;
- `/hp help` - rappel des commandes.

## Collecte

Hero’sPath observe la position extérieure à 4 Hz. Il ne sauvegarde pas chaque observation : la persistance est adaptative afin de préserver les virages, les changements de mode et les keyframes tout en réduisant fortement les lignes droites.

Les modes distingués sont marche, monture, nage, taxi, fantôme et mouvement spécial/inconnu. Les téléports, changements de monde, périodes sans coordonnées, morts et reprises peuvent créer des ruptures explicites.

## Instances et BG

Aucune trajectoire intérieure n’est projetée sur la carte extérieure. Hero’sPath conserve l’entrée, la sortie, la durée, le type et l’identité de l’instance ainsi que les événements pertinents.

## Données

Le stockage utilise le schéma 1 et des chunks HP1 sparse delta-varint. Les chunks finalisés sont immuables ; le tail récent reste mutable et borné. Les données invalides sont isolées dans une quarantaine de récupération.

## Démo locale

Lancer `launch-demo.bat` sous Windows ou :

```bash
python launch-demo.py
```

puis ouvrir l’adresse locale indiquée. La démo permet de rejouer un parcours, changer de carte, suivre le joueur, afficher/masquer les couches et calibrer les tailles visuelles via le bouton ⚙.

## Intégration avec un autre addon

Les consommateurs utilisent `_G.HeroPathAPI`. Ils ne doivent pas lire ou modifier directement `HeroPathDB`. Voir `Documentation/Integration/PUBLIC-API.md`.
