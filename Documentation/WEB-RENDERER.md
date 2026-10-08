# Renderer web Hero’sPath

Le renderer actif est `Demo/index.html`. Les modules `Web/` regroupent la projection, l’adaptation des cartes et le replay.

## Fonctionnalités

- replay progressif avec pause, vitesse et scrub ;
- retour arrière qui retire la partie future du tracé ;
- suivi joueur activable et bouton Recentrer ;
- zoom molette ;
- styles distincts pour marche, monture, nage, vol/taxi et fantôme ;
- événements décès, instance, raid, BG, arène et transport ;
- POI vol, cimetières, auberges, instances, ports et zeppelins ;
- ports et zeppelins visibles à tous les niveaux de zoom lorsque leur couche est active ;
- réglages visuels individuels depuis le bouton de configuration.

## Satellite

Le zoom caméra est indépendant du zoom natif des tuiles. Le renderer essaie la tuile WorldAtlas exacte, puis la tuile satellite locale correspondante, puis un parent recadré, puis le fond neutre.

## Profil visuel par défaut

- héros : 1,30 ;
- badge de vol : 1,15 ;
- POI vol et auberge : 1,15 ;
- POI instance, bateau et zeppelin : 1,20 ;
- points de trace : facteur 2, masqués par défaut ;
- texte de légende : 1,30 ;
- icônes de légende : 1,75 ;
- coordonnées : visibles.

## Debug

`window.__HEROPATH_DEBUG__` expose l’état utile aux tests navigateur : scénario, caméra, tuiles, couches, événements visibles et réglages visuels.
