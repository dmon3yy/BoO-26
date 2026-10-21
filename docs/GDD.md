# Ballad of Orpheus — Game Design Document (v1, M0)

A side-scrolling, fully seamless Metroidvania. The quest structure of *The Battle of Olympus* carries the story of Orpheus and Eurydice, retold the way *Hadestown* retells it: an industrial underworld, a messenger narrator, three Fates who sell doubt, and a walk you must finish without looking back. Everything here is original (see [IP_RULES.md](IP_RULES.md)).

**Length:** 4–6 hours. **Platforms:** web (every milestone), Windows/Mac/Linux. **Controls:** keyboard and gamepad.

## Contents
1. [Pillars](#pillars)
2. [Story](#story)
3. [Characters](#characters)
4. [World and progression](#world-and-progression)
5. [Bosses and enemies](#bosses-and-enemies)
6. [Systems](#systems)
7. [Endings](#endings)
8. [Homage map](#homage-map)

## Pillars
- **The song is the key.** Orpheus's music opens the world, wins fights on the beat, and decides the ending.
- **Everything is connected.** One seamless world; every new ability changes how old places can be read.
- **Greedy gods, hungry people.** Olympus and the Underworld run on the same economy of debt; the game is a little funny about it.
- **Fair, but it bites.** Souls-lite stakes, modern conveniences, and a validator that guarantees no route can trap you.

## Story

Hermes tells this story as one that has been told many times. *The Battle of Olympus* is treated as an **earlier telling**: its heroine Helene waits in Asphodel as a shade, still waiting for "a boy with a club", and her statue stands in the Palace of Hades.

| Part | What happens |
|---|---|
| **Prologue — Arcadia** | An unnatural winter: Hades has called Persephone home too early and the seasons have broken. Orpheus, a poor lyre player, meets Eurydice, a hungry drifter, and swears to finish a song that will bring spring back. Zeus starts him on his way. |
| **Act I — the Surface** | Orpheus crosses Greece earning the gods' help (for a price) and gathering the **nine verses** of his song, one for each Muse. His mother is the Muse Calliope — hence the rhythm meter's name, *Muse*. |
| **Interlude — Eurydice** *(playable)* | Starving, she takes Hades' offer, rides **Charon's steam ferry** down the Styx, signs away her name, and works a shift in the Foundry. She scratches marks on the walls that will later guide Orpheus. Triggers once the first fork of regions is complete. |
| **Act II — the Descent** | Two ways down: Hermes's secret road through **Taenarum** (Laconia), or the original's **sea entrance** between Crete and Argolis. Four tiers: Styx Docks and Asphodel → **Erebos**, the company town behind the Wall → the Deep Works → **Tartarus** and the Palace. Persephone, tending a hidden pomegranate garden, becomes an ally; her **Song of Seasons** thaws the surface and reopens old regions. |
| **Act III — the Duel** | In a pitch-dark throne room, Artemis's Moon Crystal shows Hades by his reflection in the Styx. He mirrors Orpheus — the fight is **call and response** on the beat. Orpheus's song reconciles Hades and Persephone. One condition: walk ahead, and don't look back. |
| **Finale — the Walk** | A rhythm-and-nerve sequence. The Fates whisper; sound and screen lie. Each verse is a line Orpheus can sing on the beat to push the doubt back. |

## Characters

All public-domain myth figures, with designs drawn from mythology.

| Character | Role | Design notes |
|---|---|---|
| Orpheus | Hero | Wine-red cloak, laurel, lyre on his back. Reads against blue winter and orange foundry alike. |
| Eurydice | Playable interlude | A survivor: practical layers, a scarf, quick and light. Different moveset (wall-jump, slide, no weapon). |
| Hermes | Narrator, mentor | Winged courier; speaks to the player as much as to Orpheus. |
| The Fates | Tempters, mini-bosses | Clotho (spindle), Lachesis (measuring rod), Atropos (shears). Thread motifs. |
| Hades | Final boss | Foundry baron: molten-iron crown, ledger, soot. Not a villain so much as a lonely man who built a wall. |
| Persephone | Ally | Pomegranates, keeper of the only living garden below. |
| Charon | Ferry captain | Steam ferry on the Styx. |
| The Workers | Shades of Erebos | Nameless; returning their **names** frees them, and freed shades open shortcuts and run shops. |
| Helene | Easter egg | A shade from an earlier telling. |

## World and progression

The world is one grid of rooms (`content/world.json`). The intended route echoes the original's, including its doubling back; **forks** can be played in any order, and **sequence breaks** are legal.

1. Arcadia (tutorial) → 2. Attica (hub) → 3. **first fork, any order:** Argolis · Peloponnese · Laconia → 4. back through Attica and Argolis → 5. **second fork, any order:** Phthia · Crete · Phrygia → 6. the Underworld.

| Region | Who | Ability / item | Opens |
|---|---|---|---|
| Arcadia (start, return junction) | Zeus; Colchis Bull (guardian) | Lyre and first song; Club. **Relay:** meet Hermes in Argolis, then receive the **Sandals of Hermes** (high jump, ceiling-walk) at Zeus's altar | Song seals; ceilings |
| Attica (hub) | Athena; Lamia; Demeter at Eleusis; a resident of Athens | **Shield of Athena** (parry); **Staff of Fennel**; **Key of Athens** (show verse 1); the winter questline | Projectiles; locked grotto |
| Argolis | Nemean Lion; Prometheus; Hermes; salamander nest | Fire for the Staff (lights caves, burns thorns); **Salamander Skins**; Ambrosia (50 olives); verse grotto 1 (needs the Eye) | Dark caves; thorns |
| Peloponnese | Apollo; Hydra; a nymph | **Harp of Apollo** (Song of Pegasus, counters the Siren); **Sword**; hidden Ambrosia tree | Long gaps; Sun Monuments |
| Laconia | Poseidon; Cyclops; the Sirens; the Graeae | **Song of the Dolphin** (60 olives); **Eye of the Graeae**; Taenarum | Water; hidden doors |
| Phthia | Gaea (woken by the Dolphin song); Hephaestus; Centaur*; Ladon* | **Divine Sword** (70 olives; Power of Argus beam at full health); free Ambrosia; verse grotto 2 (Eye + upper ledge + Key); **Golden Apple*** | Ancient mechanisms |
| Crete (by dolphin) | Talos; Ares; Circe; the Minotaur | **Power Bracelet** (80 olives; doubles attack; short-pay and Ares repossesses the Sandals); **Salamander Shield** (20 skins + 80 olives); verse grotto 3 (needs 2 verses) | Labyrinth; heat; verse barrier |
| Phrygia (by dolphin) | Dark Pegasus; Artemis | **Moon Crystal** (moonlight aura with real shadows) | Darkness |
| Underworld | Persephone | **Song of Seasons** | Frozen ↔ thawed world |

\* optional

- **Verses:** nine. Three in the original's three nymph grottos; six of ours across surface and Underworld.
- **Travel:** Pegasus from **Sun Monuments** (fast travel); **dolphin sea lanes** between coasts.
- **Logic tiers:** *intended* (standard movement) and *advanced* (dodge-jump extensions, pogo bounces). `tools/validate_world.py` proves completion in both, in every fork order, with no softlocks.

## Bosses and enemies

- **Major (10):** Lamia, Hydra, Cyclops, Sirens, Graeae, Gaea, Minotaur, Cerberus, the Fates, Hades.
- **Guardians (5):** Colchis Bull (tutorial), Nemean Lion, Talos, Dark Pegasus, Centaur*.
- **Optional:** Ladon. **Rematches:** the Palace Lamia; echo fights behind wrong Tartarus doors.
- **Thematic bridge:** the Colchis Bulls and Talos are Hephaestus-made bronze machines in myth. Hades' Foundry has been **mass-producing copies**: the surface is being quietly industrialised from below.
- **Signature fights:** Sirens = a sing-off (the Harp counters their song); Hydra = heads hittable only when surfaced; Cerberus = kill every head within one bar or they regrow; Minotaur and Hades = pin them to the wall.
- **Enemies (~20):** surface bestiary in the original's spirit (satyrs, snakes, bats, stone-dropping eagles, monkeys, scorpions, shielded amazons, cockatrices) and industrial Underworld types (foremen, furnace imps, bronze automata). **Rule:** every ability meets an enemy that tests it.

## Systems

| System | Design |
|---|---|
| Combat | Club → Staff of Fennel → Sword → Divine Sword; dodge; shield parry; **crouch strike**; combat songs. **On the beat:** ×1.5 damage, perfect parry (stagger), Muse gain. Never required. |
| Songs | Hold Lyre, play 3–5 notes on the d-pad. Traversal songs are free; combat songs cost Muse. |
| Seasons | Global world state. Winter: ice walkable, snow blocks. Spring: rivers flow (need the dolphin), vines climbable. |
| Death (Souls-lite) | Respawn at the last **Hearth of Hestia**; your olives stay where you fell, guarded by your echo; die again first and they're gone. (The original's *Continue* halved olives; *Retry* returned you to the last Word.) |
| Saving | Kneel at a Hearth: autosave, and the god there grants a **Word** — a copyable code that *is* your save (the original's passwords, doing a real job for browser saves). |
| Conveniences | Auto-map (the Eye reveals secrets on it); journal of every hint, verse, name and god; completion checklist; optional markers. |
| Accessibility | Visual beat pulse; audio / visual / input calibration (Beat Lab); rhythm assist (wider windows); remapping; colour-blind-safe telegraphs; shake and flash toggles. |
| Music identity | Each region in its namesake Greek mode: Attica Ionian, Laconia Dorian, Phthia Aeolian, Phrygia Phrygian, Underworld Locrian. Surface: Mediterranean folk with a blues lyre. Underworld: industrial swing and blues, anvils and brass. Hermes: ragtime. |

## Endings

- **Triumphant:** all nine verses → the doubt can be sung down → they walk out together; spring returns.
- **Tragic:** verses missing → Orpheus turns. Hermes picks the story up again: **New Game+** with every item kept.
- **Choice:** the player may turn at any time.
- Speedrun support: in-game timer, skippable cutscenes. Ways to finish: any% (tragic), all verses (triumphant), 100%.

## Homage map

Mechanics we carry over from the original, in our own form — see [reference/original_notes.md](reference/original_notes.md) for what each one was.

| Original | Ours |
|---|---|
| Olives as currency | Same |
| Three Fragments of Love from nymphs | Three of the nine verses, same grottos and dependency chain |
| Words of the Gods (passwords) | Save codes granted at Hearths |
| Continue (½ olives) / Retry (last Word) | Souls-lite olive drop + Hearth respawn |
| Sandals: Hermes → Zeus relay | Same relay, across the seamless world |
| Ares takes the Sandals if you short-pay | Same, foreshadowed and softlock-proof |
| Harp counters the Siren; summons Pegasus at sun monuments | Sing-off boss; Sun Monument fast travel |
| Ocarina: dolphins, wakes Gaea | Song of the Dolphin does both |
| Moon Crystal shows Hades in the dark | Moonlight aura; reflection in the Styx |
| Hades mirrors Orpheus | Call-and-response rhythm duel |
| Tartarus door sequence; wrong doors = stronger repeats | New sequence, hinted by Eurydice's marks; echo rematches |
| One-way loop exits | One-way shortcuts back to the surface |
| False staircase to a healing nymph | Same |
| Helene's statue | Helene's statue, and Helene herself as a shade |
