# Hero'sPath

Hero'sPath records player movement in World of Warcraft and stores a compact trail that can be replayed later.

The collector samples world position at 4 Hz. It keeps more points around turns and fewer points on long straight paths. It also records movement states and important travel transitions without drawing false links across teleports, loading screens, instances, or missing position data.

## Features

- World coordinates in yards
- Cross-check between C_Map and UnitPosition
- Adaptive path sampling
- Walking, mounted, swimming, taxi, ghost, and special movement states
- Explicit gaps when continuity cannot be proven
- Departure and arrival transitions for semantic travel events
- Map context on important events
- Chunk validation and recovery
- Read-only mode for newer SavedVariables schemas
- Versioned public API for other addons

## Project layout

- `Addon/HeroPath/` - addon source
- `Documentation/` - architecture, data format, recovery, testing, and integration notes
- `Tests/Collector/` - collector tests
- `Demo/` and `Web/` - local journey replay demo
- `Maps/` - local map assets used by the demo

## Install

Copy `Addon/HeroPath` to your World of Warcraft `Interface/AddOns` folder.

SavedVariables are stored per character in `HeroPathDB`.

Useful commands:

- `/hp check`
- `/hp pos`
- `/hp stats`
- `/hp contract`

## Integration

Other addons should use `_G.HeroPathAPI` instead of reading `HeroPathDB` directly.

Integration notes are available in `Documentation/Integration/`.

## Author

Darwyn
