# Cop start spots by driving distance

## Why

Cops are placed 50-150 m from the runner in a straight line. A road on the hill above, the far side of a hairpin,
or a road across a river or divided highway counts as close even when driving there takes much longer, so some
cops start a long way behind. Placement should go by how far a cop has to drive to reach the runner.

## Goals

- Every placement goes by driving distance: human cops at round setup, AI cars in practice rounds, and AI cars
  moved back near the player after a BeamNG.Earth teleport. All three already go through `roads.findCopSpot`,
  so the change lives there.
- A cop's route to the runner follows one-way roads (no wrong-way shortcuts).
- A cop starts facing toward the runner along that route, so it never faces oncoming traffic on a one-way road
  and doesn't need a U-turn at release (decided: option A).
- `copSpawnMinMeters` / `copSpawnMaxMeters` keep their names and 50 / 150 defaults but mean distance by road.
  Old server configs keep working.

## Non-goals

- Lane choice: cops still start on the road's centre line, as today.
- Travel time (speed limits, road type): distance only.
- Spreading cops over different directions: they still take the nearest free spots, 8 m apart, as today.
- Skipping private, gated or dirt roads: every road the game's graph has stays a candidate, as today.

## Found in the current code

- The game stores each road link once (`map.lua` `convertToSingleSided`: at `nodes[outNode].links[inNode]`).
  `roadSpots` keeps a link only when `tostring(id) < tostring(linkId)`, so about half the roads are never offered
  as spots. `closestNodeFallback` (backup for `nearestRoad`) reads the same one-sided links. Found by reading the
  code; to be confirmed in game.
- A spot faces along its link in whichever direction the link happened to be stored.

## Approaches

1. **Picked: one search outward from the runner.** Shortest-first walk of the game's road graph from the runner's
   road, against the flow on one-way roads, stopping at the max distance. Spots, their distances and their facing
   all come from that one walk. Pure Lua over a graph table, so a stub graph tests it.
2. Straight-line candidates filtered by the game's pathfinder (`map.getPointToPointPath` per spot). No search code
   of our own, but one full route search per candidate (dozens to hundreds per cop, more when widening). The game
   only adds a cost to wrong-way driving (`dirMult`) instead of forbidding it, and it's hard to test outside the
   game. Rejected.

## Design

**Graph.** `map.getGraphpath().graph[a][b]` has every link from both ends, with `len`, `oneWay` and `inNode`
(traffic on a one-way link flows from `inNode` to `outNode`). Node positions come from `map.getMap().nodes[id].pos`.
A cop may drive a link from `x` to `y` when it is not one-way or `inNode == x`.

**Start.** `map.findClosestRoad(center, 2000)` gives the runner's link `(a, b)`. Project the runner onto it at
point `P`. Seed `a` with `|aP|` if a cop may drive `a` to `b`, and `b` with `|bP|` if a cop may drive `b` to `a`.
The runner's own distance from the road doesn't count.

**Walk.** Dijkstra with a small binary heap. From a reached node `u`, a neighbour `v` gets `dist(u) + len` when
a cop may drive `v` to `u`. Stop once the cheapest open node is past the current upper bound.

**Spots.** Every link with at least one reached end is sampled every 15 m (as today). A spot's distance is the
smaller of the legal options: a reached end's distance plus the distance along the link to that end. It faces
toward the end it uses. Spots on the runner's own link measure straight along the link to `P`, again only in a
direction a cop may drive.

**Pick.** Unchanged: keep spots with `min <= distance <= max`, sort by distance, keep spots 8 m apart, and take
the `index`-th. When there are too few, widen as today (`lo = 0`, `hi` doubles, up to 2 km), now by road.

**Fallback.** When no road is within 2 km of the runner, or the roads a cop can reach within 2 km hold too few
spots (a car park or track not connected to the rest of the map), use today's straight-line search instead.
It is fixed to see every link, and a spot faces along its link toward the runner (the legal direction on one-way
links). If that finds nothing either, the cop gets today's notice and starts where they are.

**Same misread elsewhere.** `closestNodeFallback` walks `getGraphpath().graph` instead of the one-sided links.

## Docs and version

- Panel help (`settings.js`): "Cops start at least / at most this far from the runner, by road".
- README settings table: "Cop start distance from the runner, by road".
- FEATURES: start-round row ("placed on a road 50-150 m by road from the runner, facing toward the runner") and
  the Cop placement bullet (by road; straight-line fallback for road islands).
- DEPENDENCIES `roads.lua` entry: add `map.getGraphpath().graph` (`len`, `oneWay`, `inNode`) and
  `map.findClosestRoad(pos, radius)`, plus an update check for the link storage.
- 2.3.1 (a fix): `VERSION` in `server/CopsAndRobbers/main.lua`, `CLIENT_VERSION` in the client main file,
  FEATURES title.

## Testing

- New `tests/test_roads.lua` with stub graphs:
  - hairpin: straight-line 30 m but 300 m by road is not picked;
  - divided highway: the other carriageway (one-way, opposite flow) is not close;
  - one-way: the spot faces the legal direction, toward the runner;
  - two-way: the spot faces toward the runner, from either side;
  - spacing and `index` still work;
  - widening to 2 km by road;
  - road island falls back to straight-line;
  - links stored one-sided are all seen.
- Existing client stubs (`tests/client_stubs.lua`) get a `getGraphpath` matching their two-node map.
- In game (console test extension, see the in-game testing workflow): count links seen through `nodes[].links`
  with the old filter against `getGraphpath().graph` on west_coast_usa to confirm the half-skipped bug. Then a
  practice round near a hairpin or the highway: cops start close by road and face the runner.

## Left to the builder

- Heap implementation, sampling at link ends (avoid duplicate spots at shared nodes), and what "too few spots"
  means for the fallback (fewer than `index`).
