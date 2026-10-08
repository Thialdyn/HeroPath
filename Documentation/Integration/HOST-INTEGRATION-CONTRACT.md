# Host integration contract

Hero'sPath integration should stay optional.

A host addon checks `_G.HeroPathAPI`, verifies `GetAPIVersion() == 1`, then uses the API only when it is available and compatible.

## Rules

- Hero'sPath owns its 4 Hz ticker and `HeroPathDB`.
- A host should avoid running a second equivalent position tracker when Hero'sPath already provides the trail.
- Export snapshots are read-only data.
- The storage schema is not the public API version.
- `positionKnown = 0` means the host must not draw a continuous line to that endpoint.
- The host keeps ownership of its own UI, filters, and statistics.

## Host-side tests

A host integration should cover:

- provider missing
- incompatible API version
- read-only archive mode
- empty export
- multiple characters
- unknown world
- restricted API values
- save and reload
- CPU and memory comparison with and without the provider
