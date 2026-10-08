# Contributing

Changes to the collector should have a clear responsibility and a regression test.

A few rules keep the codebase predictable:

- Gameplay thresholds belong in `Contract.lua`.
- WoW API access belongs in `Bootstrap.lua`.
- Pure validation and encoding belong in `DataModel.lua`.
- Map context and travel transitions belong in `Metadata.lua`.
- `HeroPath.lua` owns the collector state machine.
- External addons should use `HeroPathAPI` instead of internal tables.

Before opening a pull request, run `Tests/Collector/run-release-tests.sh`.

Run the stress tests when changing sampling, compaction, recovery, or long-session behavior.

Do not guess a transport type when the client does not provide enough evidence. Unknown data should stay unknown instead of creating a false path.

Comments should explain decisions, invariants, or client limitations. They should not repeat what the code already says.
