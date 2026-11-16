# Cop Start Spots by Driving Distance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cops (human and AI) start 50-150 m from the runner by road, facing toward the runner along a legal route.

**Architecture:** `roads.findCopSpot` (`client/lua/ge/extensions/copsAndRobbers/roads.lua`) gets a shortest-first walk of
the game's road graph outward from the runner's road, against the flow on one-way roads. Spots, their road distance
and their facing come from that walk. Today's straight-line search stays as the fallback, fixed to see every link.
The signature of `findCopSpot` doesn't change, so its three callers (setup, AI setup, AI relocate) need no edits.

**Tech Stack:** Lua (BeamNG GE, LuaJIT in game; tests run with `lua5.3` or `lua` through `make test`).

**Spec:** `docs/superpowers/specs/2026-11-16-cop-spots-by-road-design.md`

## Global Constraints

- No code comments (AGENTS.md).
- Lua that runs in both LuaJIT and Lua 5.3: no `//`, no bit operators, no `goto`.
- Use vector methods the test stubs have (`+ - * /`, `:length()`, `:distance()`, `:normalized()`); do dot products
  with field arithmetic (`a.x * b.x + a.y * b.y + a.z * b.z`).
- Setting keys stay `copSpawnMinMeters` / `copSpawnMaxMeters`, defaults 50 / 150.
- Unchanged constants: `COP_SPACING = 8`, `LINK_STEP = 15`, `MAX_SPAWN_RING = 2000`, `ROAD_SEARCH_MAX = 2000`.
- Version 2.3.1.
- Commit messages: `feat:` / `fix:` / `docs:` prefix, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Baseline: `make test` prints `665 passed, 0 failed`. Every task ends with 0 failed.

## Review Focus

- Two human cops place themselves on different machines with index 1 and 2: equal road distances (a runner on a
  node, both sides at 50 m) must sort the same on every machine, or both cops take the same spot.
- The runner stands exactly on a node, or at the end of a dead end: the projection lands on the link's end and
  every link around it still gets spots.
- `findClosestRoad` returns node ids that `getGraphpath().graph` lacks (BeamNG.Earth swapping road graphs): no
  error, the straight-line fallback runs.
- A zero-length link (two nodes at one position): no NaN facing, no division by zero.
- `copSpawnMaxMeters` set above 2000 (say 3000): spots up to the max are still found by road.

---

### Task 1: Graph access and the straight-line search fixed

The straight-line search and `nearestRoad`'s backup read `map.getMap().nodes[id].links`, which the game stores
one-sided, and skip about half the links. Switch both to `map.getGraphpath().graph`, and face straight-line spots
toward the runner.

**Files:**
- Create: `tests/test_roads.lua`
- Modify: `client/lua/ge/extensions/copsAndRobbers/roads.lua`
- Modify: `tests/client_stubs.lua:102-106` (add `getGraphpath`)

**Interfaces:**
- Produces (test helper in `tests/test_roads.lua`, reused by Task 2):
  `useMap(nodes, links, opts)` where `nodes = { id = {x, y} }` and `links = { {from, to, oneWay = bool, gated = n} }`.
  It sets `_G.vec3` (metatable vector like `client_stubs.lua`), `_G.quatFromDir = function(dir, up) return { dir = dir } end`
  and `_G.map` with:
  - `getMap().nodes[id] = { pos = vec3, links = {} }`, each link stored one-sided like the game:
    at `nodes[to].links[from]` (that's `nodes[outNode].links[inNode]`);
  - `getGraphpath().graph[a][b]` and `[b][a]` = the same table `{ inNode = from, outNode = to, oneWay = bool, gated = n or 0, len = 1 }`.
    `len = 1` on purpose: the code must not use it as a length;
  - `findClosestRoad(pos, radius)`: the nearest link by distance to its segment within `radius` (default 200),
    returning `from, to, dist`; returns nil when `opts.noKdTree`, or `opts.closest` (a pair) when given.
- Produces in `roads.lua` (local): `graph()` returning `gp.graph, nodes` or nil; `canDrive(link, x)` true when a
  cop may drive the link starting from node `x` (not `oneWay`, or `inNode == x`).
- `findCopSpot(center, minD, maxD, index) -> pos, rot` and `nearestRoad(pos) -> pos, rot` keep their signatures.

- [ ] **Step 1: Write the failing tests** in `tests/test_roads.lua` (start with
  `package.path = "client/lua/ge/extensions/?.lua;" .. package.path`, clear `package.loaded["copsAndRobbers/roads"]`
  and require it):

```lua
test("straight line: links stored at the node with the larger id are seen", function()
  useMap({ a = { 0, 100 }, z = { 0, 200 } }, { { "a", "z" } })
  local pos = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 1)
  assertEq(pos ~= nil, true)
  assertEq(pos.x, 0)
end)

test("straight line: a two-way spot faces toward the runner", function()
  useMap({ a = { 100, 0 }, b = { 300, 0 } }, { { "b", "a" } }, { noKdTree = true })
  local pos, rot = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 1)
  assertNear(pos.x, 100, 0.01)
  assertNear(rot.dir.x, -1, 1e-6)
end)

test("straight line: a one-way spot faces with the flow", function()
  useMap({ a = { 100, 0 }, b = { 300, 0 } }, { { "a", "b", oneWay = true } }, { noKdTree = true })
  local _, rot = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 1)
  assertNear(rot.dir.x, 1, 1e-6)
end)

test("nearest road backup finds a node whose links are stored elsewhere", function()
  useMap({ a = { 10, 0 }, b = { 500, 0 } }, { { "a", "b" } }, { noKdTree = true })
  local pos = roads.nearestRoad(vec3(0, 0, 0))
  assertEq(pos.x, 10)
end)
```

  `{ noKdTree = true }` makes `findClosestRoad` return nil, so in Task 2 these straight-line tests still exercise
  the fallback.

- [ ] **Step 2: Run to verify they fail**

  Run: `lua tests/run.lua tests/test_roads.lua`
  Expected: all four FAIL. The first and last because the old id filter skips the link (stored at `z` and `b`), the
  facing tests on `rot.dir.x` or a nil spot.

- [ ] **Step 3: Implement in `roads.lua`**
  - `graph()`: `local gp = map.getGraphpath and map.getGraphpath()`; nil unless `gp.graph` and `map.getMap().nodes`.
  - The straight-line search iterates `graph[id]` (both ends listed, so dedupe with `tostring(id) < tostring(linkId)`)
    instead of `nodes[id].links`, skips links shorter than 1e-3 as today, and sets each spot's `dir`: on a one-way
    link `inNode -> outNode`; otherwise whichever link direction has a dot product `>= 0` with `center - pos`.
  - `closestNodeFallback` checks `graph[id]` for a neighbour instead of `n.links`.

- [ ] **Step 4: Add `getGraphpath` to `tests/client_stubs.lua`** next to the existing two-node `map` stub:
  `graph = { a = { b = L }, b = { a = L } }` with `L = { inNode = "a", outNode = "b", oneWay = false, gated = 0, len = 1 }`.

- [ ] **Step 5: Run all tests**

  Run: `make test`
  Expected: `669 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add client/lua/ge/extensions/copsAndRobbers/roads.lua tests/test_roads.lua tests/client_stubs.lua
git commit -m "fix: cop spots see every road link and face the runner

The game stores each road link once, so filtering by id order skipped
about half the roads as cop spots and road-reset targets."
```

---

### Task 2: Spots by driving distance

**Files:**
- Modify: `client/lua/ge/extensions/copsAndRobbers/roads.lua`
- Test: `tests/test_roads.lua`

**Interfaces:**
- Consumes: `useMap`, `graph()`, `canDrive(link, x)` from Task 1.
- Produces: `findCopSpot(center, minD, maxD, index) -> pos, rot` now by road, falling back to the Task 1 search.

- [ ] **Step 1: Write the failing tests** in `tests/test_roads.lua`. Helper for straight roads:
  `chain(prefix, points, oneWay)` returns nodes and links joining the points in order. Distances below are road
  distances from the runner's road point.

```lua
test("hairpin: the other leg is close in a straight line but not by road", function()
  -- also guards the link cost: with len = 1 the other leg would look close by road
  useMap({ a = { 0, -100 }, b = { 0, 0 }, c = { 0, 150 }, d = { 30, 150 }, e = { 30, 0 }, f = { 30, -100 } },
    { { "a", "b" }, { "b", "c" }, { "c", "d" }, { "d", "e" }, { "e", "f" } })
  for i = 1, 4 do
    local pos = roads.findCopSpot(vec3(0, 10, 0), 50, 150, i)
    assertEq(pos.x, 0, "spot " .. i)
  end
end)

test("divided highway: cops start behind the runner on its own carriageway, facing it", function()
  -- northbound x=0 from y=-500 to 500 (one-way, nodes every 100 m), southbound x=20 back down,
  -- joined only at the ends; runner at (0, 10)
  for i = 1, 3 do
    local pos, rot = roads.findCopSpot(vec3(0, 10, 0), 50, 150, i)
    assertEq(pos.x, 0); assertEq(pos.y < 10, true); assertNear(rot.dir.y, 1, 1e-6)
  end
end)

test("two-way: spots on both sides face toward the runner", function()
  -- road x=-1000..1000 along y=0, nodes every 100 m, links stored in mixed directions; runner at (0, 0)
  local p1, r1 = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 1)
  local p2, r2 = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 2)
  assertNear(math.abs(p1.x), 50, 0.01); assertNear(p2.x, -p1.x, 0.01)
  assertEq(r1.dir.x * p1.x < 0, true); assertEq(r2.dir.x * p2.x < 0, true)
end)

test("ties sort the same whatever order the graph was built in", function()
  -- same road as above twice: ids "n1".."n21" and the same geometry with ids reversed ("m21".."m1")
  -- index 1 and 2 give the same positions in both, and index 1 ~= index 2
end)

test("cops stay 8 m apart and later indexes are not closer", function()
  -- straight road, runner at its middle: index 1..6 pairwise >= 8 m apart, road distance non-decreasing
end)

test("too few spots widens by road but keeps the minimum", function()
  -- straight two-way road x=0..1000, nodes every 100 m, runner at (0, 0): [50,150] holds 7 spots
  -- (50, 66.7 .. 150), so index 8 widens; keeping the minimum gives 166.7 (from 0 it would give 116.7)
  local pos = roads.findCopSpot(vec3(0, 0, 0), 50, 150, 8)
  assertEq(pos.x > 150 and pos.x <= 300, true)
end)

test("runner on a node at a dead end still gets spots", function()
  -- road x=0..400, runner at (0, 0) on node a: index 1 at x=50
end)

test("a dead-end island falls back to the straight-line search", function()
  useMap({ a = { 0, 0 }, b = { 20, 0 }, c = { -500, 100 }, d = { 500, 100 } }, { { "a", "b" }, { "c", "d" } })
  local pos = roads.findCopSpot(vec3(10, 0, 0), 50, 150, 1)
  assertEq(pos.y, 100)
end)

test("closest road ids missing from the graph fall back without an error", function()
  -- opts.closest = { "x", "y" } (not in the graph): findCopSpot returns the straight-line spot
end)

test("a gated link is neither walked nor used for spots", function()
  -- main road x=-500..500 along y=0, nodes every 100 m; at (0,0) a branch north: gated (0,0)-(0,30), then (0,30)-(0,500)
  -- runner at (0, 0): index 1..6 all have y == 0
end)

test("a zero-length link gives no NaN", function()
  -- nodes b and b2 at the same position joined by a link inside a straight road: all returned dir components equal themselves
end)

test("a max above 2 km is still searched by road", function()
  -- L-shaped road (0,0) -> (1500,0) -> (1500,1500), nodes every 100 m, runner at (0, 0):
  -- findCopSpot(center, 2400, 3000, 1) gives x == 1500, y near 900 (straight-line finds nothing that far)
end)
```

  Fill in the commented tests with `useMap` and `chain`, using the values in their comments. The finished tests
  carry no comments.

- [ ] **Step 2: Run to verify they fail**

  Run: `lua tests/run.lua tests/test_roads.lua`
  Expected: hairpin, divided highway, widening, gated and max-above-2-km FAIL. The others guard the Review Focus
  cases and may pass already, since the straight-line search gives the same answer there. Task 1's tests PASS.

- [ ] **Step 3: Implement the walk in `roads.lua`**

  `local function roadSpots(center, limit)` returns a list of `{ pos, d, dir }` sorted by the tie-safe order, or nil
  when there's no graph or the closest road isn't in it.
  - Start: `n1, n2 = map.findClosestRoad(center, ROAD_SEARCH_MAX)`; `P` = `center` projected onto `n1 n2`, clamped to
    the segment. Seed `n1` with `|n1 P|` when `canDrive(link, n1)`, `n2` with `|n2 P|` when `canDrive(link, n2)`.
  - Walk: binary min-heap over `(dist, node)`. From a popped node `u` (skip if already settled), each neighbour `v` in
    `graph[u]` gets `dist(u) + nodes[u].pos:distance(nodes[v].pos)` when `canDrive(graph[u][v], v)` and the link isn't
    gated (`(link.gated or 0) > 0`). Stop when the popped distance exceeds `limit`.
  - Spots: every non-gated link (deduped as in Task 1) with length above 1e-3 and at least one settled end, sampled as
    today (`steps = max(1, floor(len / LINK_STEP))`). For spot `S` on link `u v`: option via `u` when `u` is settled
    and `canDrive(link, v)`: `dist(u) + |S u|`, facing `(u - v):normalized()`; option via `v` likewise. On the runner's
    link also: `|S P|` facing toward `P`, when the link may be driven in that direction. Keep the smallest option.
    No legal option: no spot.
  - Order: by `math.floor(d * 100 + 0.5)`, then `pos.x`, then `pos.y`.

  `findCopSpot`: `local spots = roadSpots(center, math.max(maxD, MAX_SPAWN_RING))`. When there are spots, `hi` runs
  `maxD`, then doubles up to `MAX_SPAWN_RING` (`lo` stays `minD`); return the first `pickSpot` hit with
  `quatFromDir(spot.dir, vec3(0, 0, 1))`. Otherwise run the Task 1 straight-line loop (widening from 0, as today).
  `pickSpot` takes `(candidates, lo, hi, index)` and filters by range itself, with the spacing rule unchanged. The
  straight-line candidates are computed once (up to `MAX_SPAWN_RING`) and sorted in the same tie-safe order.

- [ ] **Step 4: Run tests**

  Run: `make test`
  Expected: `681 passed, 0 failed`. The client test "an allowed road reset puts a cop on the road" still expects
  `y == 60`. Cop setups on the two-node stub now land further along `a b`; no client test asserts those positions.

- [ ] **Step 5: Commit**

```bash
git add client/lua/ge/extensions/copsAndRobbers/roads.lua tests/test_roads.lua
git commit -m "feat: cops start a short drive from the runner, facing it

Cop spots were picked by straight-line distance, so a road on the hill
above or the far side of a hairpin counted as close."
```

---

### Task 3: Docs and 2.3.1

**Files:**
- Modify: `client/ui/modules/apps/CopsAndRobbersPanel/settings.js:62-65`
- Modify: `README.md:89`, `docs/FEATURES.md:1,11,98`, `docs/DEPENDENCIES.md:97-99`
- Modify: `server/CopsAndRobbers/main.lua:18`, `client/lua/ge/extensions/copsAndRobbers.lua:18`
- Modify: `tests/test_client.lua` (every `"2.3.0"`)

- [ ] **Step 1: Copy**
  - `settings.js` help: "Cops start at least this far from the runner, by road" / "Cops start at most this far from
    the runner, by road".
  - README row: `Cop start distance from the runner, by road`.
  - FEATURES line 1: `2.3.1`. Line 11: "Cops are placed on a road 50–150 m by road from the runner, facing toward
    the runner." Line 98: "**Cop placement:** cops start a short drive from the runner (by road, following one-way
    roads), facing toward the runner, and spread out so they do not overlap. The search widens up to 2 km by road.
    A runner on a piece of road that isn't connected to the rest gets cops placed by straight-line distance. If no
    road is found at all, the cop gets a notice and starts where they are."
  - DEPENDENCIES `roads.lua` entry: add `map.getGraphpath().graph[a][b].{oneWay,inNode,gated}` (both ends of every
    link; `len` is a routing cost, not used) and `map.findClosestRoad(pos, radius)`. Add a check: on update,
    confirm `getMap().nodes[].links` is still one-sided (`convertToSingleSided` in `lua/ge/map.lua`) and the graph
    fields keep these names.
- [ ] **Step 2: Version** `VERSION` and `CLIENT_VERSION` to `"2.3.1"`; replace `"2.3.0"` with `"2.3.1"` in
  `tests/test_client.lua`.
- [ ] **Step 3: Verify**

  Run: `make test && make vuecheck && grep -rn "2\.3\.0" server client README.md docs/FEATURES.md tests`
  Expected: `681 passed, 0 failed`, vuecheck clean, grep prints nothing.
- [ ] **Step 4: Commit** `docs: cop start distance is by road, 2.3.1`

---

### Task 4: In-game check (with the user)

Follow the in-game testing workflow: a throwaway GE extension in
`~/.local/share/BeamNG/BeamNG.drive/current/lua/ge/extensions/cnrRoadCheck.lua`, one-line console commands,
results from `beamng.log` under a fixed tag.

- [ ] **Step 1: Local server.** `make install-local` and restart the local server. The user joins it on
  west_coast_usa; the checks below run outside a round (the console is locked during one).
- [ ] **Step 2: Confirm the half-skipped bug.** The extension logs: link count over
  `getMap().nodes[].links`, how many pass the old `tostring(id) < tostring(linkId)` filter, and the graph's link count
  (`getGraphpath().graph`, halved). Expected: all links one-sided, about half pass the old filter.
- [ ] **Step 3: Placement check.** The extension calls `copsAndRobbers/roads` `findCopSpot` for indexes 1-4 at the
  player's position and logs each spot's straight-line distance, position and facing, plus the runtime. The user
  stands near a hairpin and then on the highway. Expected: no spot on the other leg or carriageway, facing toward
  the player, runtime well under 100 ms.
- [ ] **Step 4: Practice round.** "Practice as runner" near a hairpin: both AI cops start a short drive away and
  face the user. "Practice as cop": the user starts close by road, facing the AI runner.
- [ ] **Step 5:** Ask the user before deleting the test extension and before `make deploy`.
