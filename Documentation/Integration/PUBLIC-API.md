# API publique Hero’sPath

Hero’sPath expose `_G.HeroPathAPI`. Un consommateur ne doit jamais lire ou modifier directement `HeroPathDB`.

## Méthodes

- `GetAPIVersion()`
- `GetVersion()`
- `GetSchema()`
- `GetProduct()`
- `GetAuthor()`
- `GetArchiveState()`
- `GetHealth()`
- `GetStorageStats()`
- `GetCurrentWorldPosition()`
- `GetCurrentMapContext()`
- `GetExportSnapshot()`
- `DecodeChunk(chunk)`

La version d’API et le schéma de stockage sont deux contrats distincts.
