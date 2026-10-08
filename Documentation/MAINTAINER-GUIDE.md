# Guide de maintenance

| Sujet | Source principale | Tests |
|---|---|---|
| Contrats et seuils | `Addon/HeroPath/Contract.lua` | `contract_architecture.lua` |
| Coordonnées monde | `Bootstrap.lua` | `coordinate_autocalibration.lua`, `integration_bootstrap.lua` |
| Codec et validation | `DataModel.lua` | `chunk_integrity.lua`, `corruption_recovery.lua` |
| Courbure et sampling | `HeroPath.lua`, `Contract.Sampling` | `adaptive_geometry_sampling.lua` |
| Continuité et reprise | `HeroPath.lua` | `regression_resume_stability.lua` |
| Morts et instances | `HeroPath.lua` | `regression_data_integrity.lua` |
| Transitions et contextes | `Metadata.lua` | `metadata_schema_safety.lua`, `regression_release_boundaries.lua` |
| API publique | `API.lua` | `contract_architecture.lua` |
| Diagnostic en jeu | `Diagnostics.lua` | `/hp check`, `/hp pos`, `/hp contract` |

## Règles de modification

Les seuils métier appartiennent à `Contract.lua`. `DataModel.lua` reste indépendant des API WoW. Les valeurs venant du client passent par la couche d’intégration. Un indice sémantique ne peut pas créer seul un déplacement.

Une modification du collecteur doit conserver les invariants concernés et ajouter ou adapter un test lorsque son comportement change.
