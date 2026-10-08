# Public API

Hero'sPath exposes `_G.HeroPathAPI`.

External addons should not read or modify `HeroPathDB` directly.

## Methods

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

The public API version and the SavedVariables schema are separate contracts.
