# DoorSix Agent Notes

## Project Context

DoorSix is a Flutter prototype for the Tianjin-area poker game usually called `砸六家`.

Important naming note:

- Early project wording used `砸六门`.
- The intended game is `砸六家`, not a six-door tapping game.
- Treat `DoorSix` as the app/project name, and `砸六家` as the actual card-game subject.

## Origin

`砸六家` is understood as a folk poker game popular in Tianjin and nearby areas. Public rule notes describe it as a six-player, two-team poker game. The exact rule set differs by local variant, including Tianjin common play, Tanggu-style rules, online variants, and privately agreed table rules.

Current source assumptions:

- It is associated with Tianjin-area folk card play.
- It uses poker cards.
- It is played by 6 people.
- Players are split into 2 teams of 3.
- Teammates sit in alternating seats.
- Round results are determined from finishing order and local settlement rules.

Reference material used by this project:

- `docs/app-ui-prototype.md`
- `docs/init-design.md`
- Scribd document: `砸六家竞赛规则2024版`
- Public web snippets describing `砸六家` as a Tianjin six-player team poker game

Because local rules vary, do not hard-code one claimed definitive rule set without confirming it with the user.

## Core Gameplay

Stable gameplay model for this app:

1. Six players sit around one table.
2. Players are split into Team A and Team B.
3. Each team has three players.
4. Teammates are seated alternately so each player is between opponents.
5. Cards are dealt according to the selected rule set.
6. Players take turns playing cards or passing.
7. A player may play a valid card combination that can beat the current table combination.
8. If a player cannot or chooses not to beat the current combination, they pass.
9. When enough players pass, the table starts a new lead.
10. Players who empty their hand are recorded by finishing rank.
11. A round is settled when the selected rule set says the result is determined.
12. Settlement can depend on finishing order, caught players, tribute rules, follow-lead rules, and local table conventions.

## Rule Variants

The app should preserve rule-set flexibility. Known variant buckets:

- `天津通用`
- `塘沽路`
- `自定义`

Potential configurable rules:

- Deck count
- Dealt card count
- First lead rule
- Valid combination types
- Card rank order
- Wild cards or mixed cards
- Tribute / return tribute
- Anti-tribute
- Follow-lead / 接风
- Round settlement
- Score calculation

When in doubt, implement a conservative simplified rule engine and expose clear UI text saying the current version is a prototype.

## Current Implementation Scope

The current Flutter code implements a playable prototype, not a complete local-rule simulator.

Implemented:

- Flutter root project
- Home screen
- Rule selection screen
- Six-seat table screen
- Team A / Team B seat colors
- User seated at the bottom
- Two-deck dealing
- User hand display
- Card selection
- Hint
- Play
- Pass
- Simplified AI turns
- Simplified combination recognition:
  - Single
  - Pair
  - Triple
  - Bomb
  - Joker pair
- Simplified finish-order tracking
- Simplified round result dialog
- GitHub Actions APK build

Not yet fully implemented:

- Complete Tianjin rules
- Complete Tanggu rules
- Tribute / return tribute / anti-tribute flow
- Follow-lead / 接风 flow
- Wild-card or mixed-card rules
- Online multiplayer
- Room creation and join flow
- Persistent scoreboard
- Custom card art
- Production Android package metadata, app icon, signing, and release config

## Flutter / Build Notes

The project is a Flutter root project. Do not create a nested Flutter app directory.

Recommended CI version:

- Flutter `3.41.9`
- Dart `3.11.5`

Relevant files:

- `pubspec.yaml`
- `lib/main.dart`
- `lib/pages/game_table_page.dart`
- `lib/services/rule_engine.dart`
- `lib/models/card_model.dart`
- `docs/app-ui-prototype.md`
- `.github/workflows/build-doorsix-apk.yml`

Run checks when Flutter is available:

```bash
flutter pub get
flutter analyze
flutter test
```

## Coding Guidance

- Keep the app rooted at `/Users/wyn/code/DoorSix`.
- Prefer small, readable Flutter widgets over large monolithic files.
- Keep card-game logic in `lib/services/rule_engine.dart` or dedicated services.
- Keep data structures in `lib/models/`.
- Keep visual table components in `lib/widgets/`.
- Do not silently change core rule assumptions; update docs when gameplay changes.
- Do not present the simplified rule engine as complete Tianjin/Tanggu rules.
- Preserve rule configurability where practical.

## Product Direction

The near-term product should be a clear, usable single-player practice table:

- Open app
- Choose rule version
- Enter six-player table
- Play against simple AI
- Understand teammates and opponents at a glance
- See current table combo and turn owner
- Select cards at the bottom
- Play, pass, or use hint
- See finishing order and round result

Online multiplayer and full local-rule fidelity come after the base table interaction feels stable.
