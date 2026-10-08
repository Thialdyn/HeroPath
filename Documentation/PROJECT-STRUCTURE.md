# Structure du projet

```text
HeroPath/
├── .github/
├── Addon/
│   └── HeroPath/
├── Demo/
├── Documentation/
│   └── Integration/
├── Maps/
├── Tests/
│   ├── Collector/
│   ├── Fixtures/
│   └── Release/
├── Web/
├── .gitattributes
├── .gitignore
├── CONTRIBUTING.md
├── README-FR.md
├── launch-demo.bat
└── launch-demo.py
```

## Responsabilités

- `Addon/HeroPath/` : source runtime et addon installable.
- `Web/` : projection, adaptation cartographique et replay.
- `Demo/` : démonstration locale.
- `Maps/` : corpus cartographique et assets.
- `Tests/` : tests du collecteur, du renderer et du paquet.
- `Documentation/` : architecture, format, maintenance et intégration.
