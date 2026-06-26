# PokeWorld

A self-hosted Pokemon GO-style mobile game. Players walk around using real GPS, catch Pokemon that spawn near landmarks, spin Pokestops for items, and build their collection — no third-party data sharing.

---

## Prerequisites

- Java 17
- Gradle (wrapper included)
- HSQLDB server running on port 9002

---

## Build

```powershell
cd pokemon\pokemonServer
.\gradlew.bat build
```

JAR output: `build\libs\pokemonServer-1.0.0.jar`

---

## Run

```powershell
java -jar build\libs\pokemonServer-1.0.0.jar
```

Runs on port **8090**. Database tables and seed data (species, moves, learnsets) are created automatically on first startup.

---

## Directory structure

```
pokemon/
  pokemonServer/              Spring Boot API (port 8090)
    src/main/java/pokemon/
      api/                    REST controllers (zero logic)
      logic/                  All game logic (catch, leveling, moves, evolution)
      data/                   Database layer
      object/                 Data models
    src/main/resources/
      species.csv             151 Gen 1 Pokemon with base stats
      moves.csv               165 Gen 1 moves
      learnsets.csv           Level-up movesets for all 151 Pokemon
      evolutions.csv          Gen 1 evolution chains (level + stone-based)
      application.properties
  pogo_assets/                Sprites and game assets (not tracked in git)
    Images/                   Pokemon sprites served at /api/pokemon/sprites/
    Sounds/                   Sound effects
    3D Assets/                3D models for CatchScreen
```

## Assets

Sprites and other game assets live in `pogo_assets/` (excluded from git via `.gitignore`).
The server serves them as static resources — `pokemonServer` maps `/api/pokemon/sprites/{filename}`
to the `pogo_assets/Images/` directory via `application.properties`:

```properties
pokemon.assets.sprites=../pogo_assets/Images
```

When deploying to a new machine, copy the `pogo_assets/` folder from the original install
alongside the `pokemon/` directory.

---

## Database tables

Created automatically in the shared HSQLDB:

| Table | Purpose |
|---|---|
| `POKEMON_SPECIES` | Species base stats and types |
| `POKEMON_SPAWNS` | Active wild spawns |
| `CAUGHT_POKEMON` | Player collections |
| `POKESTOPS` | Stop locations |
| `PLAYER_POKEMON_ITEMS` | Item inventory |
| `POKEMON_MOVES` | Master move list |
| `POKEMON_LEARNSET` | Level-up learnsets per species |
| `CAUGHT_POKEMON_MOVES` | Moves each caught Pokemon knows |
| `POKEMON_PLAYER_STATS` | Trainer XP and coins |

---

## API

Base URL: `http://localhost:8090`

| Method | Path | Description |
|---|---|---|
| GET | `/api/pokemon/nearby` | Spawns near a lat/lng |
| POST | `/api/pokemon/catch` | Attempt to catch a spawn |
| GET | `/api/pokemon/collection` | Player's caught Pokemon |
| GET | `/api/pokemon/moves/{id}` | Moves for a caught Pokemon |
| POST | `/api/pokemon/moves/replace` | Swap a move slot |
| POST | `/api/pokemon/grind` | Sacrifice Pokemon for EXP candy |
| POST | `/api/pokemon/use-candy` | Use candy to gain EXP |
| GET | `/api/pokemon/pokestops/nearby` | Pokestops near a lat/lng |
| POST | `/api/pokemon/pokestop/spin` | Spin a Pokestop for items |
| GET | `/api/pokemon/items` | Player item counts |
| GET | `/api/pokemon/species` | Full Pokedex |
