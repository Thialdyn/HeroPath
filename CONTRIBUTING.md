# Contribuer à Hero’sPath

Une modification du collecteur doit avoir une responsabilité claire, un invariant explicite et un test de régression. Les seuils métier appartiennent à `Contract.lua`. Les données externes passent par `Bootstrap.lua`. La logique pure de format reste dans `DataModel.lua`. Les contextes/transitions et la compatibilité de schéma appartiennent à `Metadata.lua`. `HeroPath.lua` orchestre la machine d'état. Les consommateurs externes utilisent uniquement `HeroPathAPI`.

Avant une PR : exécuter `Tests/Collector/run-release-tests.sh`, les tests Release concernés, puis les stress-tests lorsque la collecte, la compaction ou la récupération changent. Ne jamais déduire un moyen de transport lorsque le client ne fournit pas assez de preuves. Une donnée incertaine doit devenir inconnue ou créer une rupture, jamais une fausse continuité.

Les commentaires doivent expliquer une décision, un invariant ou une limite du client ; ils ne doivent pas paraphraser le code. Éviter les abstractions sans propriétaire, les helpers génériques non testés et les valeurs métier enfouies dans la machine d'état.
