# Azeroth Fieldbook integration proposal

## Goal

Use Hero'sPath as an optional trail provider for Adventurer's Annals without merging the internal data models of both addons.

## Proposed shape

```text
Azeroth Fieldbook
  -> Annals TrailProvider
       -> native provider
       -> optional HeroPath provider -> HeroPathAPI
```

Fieldbook keeps ownership of its UI, statistics, quests, and journals.

Hero'sPath provides movement geometry, movement states, travel transitions, and map context.

## Suggested first PR

Keep the first change small:

- add a small `TrailProvider` interface
- detect `HeroPathAPI` only when available
- never read `HeroPathDB` directly
- fall back to the native provider
- test missing, incompatible, and read-only providers
- compare CPU and memory use before and after

Correlated transitions and map context can be added in a later change. This keeps the first review focused.
