# Architecture

The class map, the scenes, and the core model every subsystem builds on. The subsystems themselves are one file each in this directory - see the table in [CLAUDE.md](../CLAUDE.md).

```
scripts/rails/rail.gd             Rail        : Path3D   — a stretch of track
scripts/rails/turnout.gd          Turnout     : Node3D   — points joining two rails
scripts/rails/compound_turnout.gd CompoundTurnout : Node3D — turnouts worked as one (3-way, crossovers, double slip)
scripts/rails/crossing.gd         Crossing    : Node3D   — two rails crossing, no way between them
scripts/rails/rail_signal.gd      RailSignal  : Node3D   — a one-directional stop signal
scripts/rails/track_walker.gd     TrackWalker : RefCounted — arc length across the network
scripts/rails/surface_snapper.gd  SurfaceSnapper        — ground raycasts
scripts/trains/train.gd           Train       : Node3D   — a locomotive and wagons driving the network
scripts/trains/train_car.gd       TrainCar    : Node3D   — one car: its boxes, click target, collision box
scripts/trains/livery.gd          Livery      : Resource — how a locomotive is painted: a colour, plain or striped
scripts/trains/train_type.gd      TrainType   : Resource — a recipe for a train the spawner may make
scripts/trains/route_icons.gd     RouteIcons  : Node3D   — the row of shapes over a train showing its route
scripts/trains/car_type.gd        CarType     : Resource — a vehicle's size, mass and brakes
scripts/trains/locomotive_type.gd LocomotiveType : CarType — adds traction
scripts/trains/wagon_type.gd      WagonType   : CarType  — adds capacity
rolling_stock/*.tres                                     — the shared locomotive and wagon types
train_types/*.tres                                       — the train types spawners pick from
scripts/traffic/interest_point.gd InterestPoint : Node3D — somewhere trains are going: marker, colour, name
scripts/traffic/interest_track.gd InterestTrack : Node   — one track of an interest point: a rail and a mark on it
scripts/traffic/station.gd        Station     : InterestPoint — trains stop here, dwell, load or unload
scripts/traffic/outside_connection.gd OutsideConnection : InterestPoint — a way on to and off the level
scripts/traffic/train_route.gd    TrainRoute  : Node     — one line of a level's list of routes
scripts/traffic/train_spawner.gd  TrainSpawner : Node    — puts trains on the level and counts them
scripts/world/ground.gd           Ground      : MeshInstance3D — procedural or baked-heightmap terrain
scripts/track/track_mesher.gd     TrackMesher : Node3D   — one per level: builds the track meshes, rebuilds in the editor
scripts/track/track_layout.gd     TrackLayout : RefCounted — running lines and their cuts, blades, check rails, sleepers
scripts/track/track_mesh_builder.gd TrackMeshBuilder     — layout to chunked meshes, the blades' blend shape
scripts/track/mesh_surface.gd     MeshSurface : RefCounted — one surface being built: quads, boxes, beams
scripts/track/track_materials.gd  TrackMaterials        — the shared steel, timber, ballast, stone, bore
scripts/track/track_structure.gd  TrackStructure : Node3D — a stretch of one rail with something built on it
scripts/track/bridge.gd           Bridge      : TrackStructure — stone arches, steel truss or timber trestle
scripts/track/tunnel.gd           Tunnel      : TrackStructure — portals, a dark bore, a hole in the Ground
scripts/ui/ui_scale.gd            UiScale     : Node (autoload) — picks the interface scale
scripts/ui/marker_overlay.gd      MarkerOverlay      : Control — lays out every floating marker
scripts/ui/track_marker_widget.gd TrackMarkerWidget  : Control — base: follow, collapse, click
scripts/ui/turnout_widget.gd      TurnoutWidget      : TrackMarkerWidget
scripts/ui/signal_widget.gd       SignalWidget       : TrackMarkerWidget
scripts/ui/compound_turnout_widget.gd CompoundTurnoutWidget : TrackMarkerWidget — an assembly's one control
scripts/ui/route_list_view.gd     RouteListView : Control — the route list's drawn body
scripts/debug/camera_rig.gd       CameraRig   : Node3D   — orbit camera (debug)
scripts/debug/debug_panel.gd      DebugPanel  : PanelContainer — a collapsible HUD section
scripts/debug/train_debug_panel.gd            : DebugPanel — driving keys (debug)
scripts/debug/turnout_debug_panel.gd          : DebugPanel — turnout keys (debug)
scripts/debug/signal_debug_panel.gd           : DebugPanel — signal + presentation keys
scripts/debug/interest_debug_panel.gd InterestDebugPanel : DebugPanel — interest points, spawner counts, names switch
scripts/debug/route_list_panel.gd RouteListPanel : DebugPanel — the route list and the icons/list switch

tests/framework/test_case.gd      TestCase       : RefCounted — the base class suites extend
tests/framework/test_runner.gd                   : SceneTree — discovery, reporting, exit code
tests/support/turnout_demo_case.gd TurnoutDemoCase — fixture for the turnout demo layout
tests/support/signal_demo_case.gd  SignalDemoCase  — fixture for the signal demo layout
tests/support/compound_demo_case.gd CompoundDemoCase — fixture for the compound turnout demo
tests/support/train_demo_case.gd  TrainDemoCase   — fixture for the trains demo
tests/support/stations_demo_case.gd StationsDemoCase — fixture for the stations demo
tests/*_test.gd                                  — the suites themselves

tools/build_playground.gd                        : SceneTree — writes scenes/main.tscn + its heightmap
tools/build_structures_demo.gd                   : SceneTree — writes scenes/demos/structures.tscn + its heightmap
```

Scenes: `scenes/main.tscn` (the playground: one of every junction kind on a compact double-track
oval with a balloon loop, a wye, a yard and a freight line crossing it on the level, 46 signals
covering every way into every junction, four trains waiting at red, and one carved corner with a
bridge and a tunnel - **generated**: edit `tools/build_playground.gd` and re-run it, never the
`.tscn`), `scenes/demos/turnouts.tscn` (flat ground, a passing loop and a dead-end
stub — every turnout case in one place), `scenes/demos/signals.tscn` (a straight 280 m main line
with a siding: a back-to-back signal pair, a cluster of three that forces the widgets apart, a
signal past the points, and one on the branch) and `scenes/demos/compound_turnouts.tscn` (flat
ground, one of each: a three-way, a crossover, a double crossover with its middle crossing, a
plain diamond crossing and a double slip, each with trains), `scenes/demos/trains.tscn` (three
straight lines abreast: an express, a loaded and an empty freight to compare, a signal to put back
in front of a train, a crossover to throw under one and a stalled train to run into),
`scenes/demos/structures.tscn` (**generated** by `tools/build_structures_demo.gd`: three lines, one
per bridge style, each over a short, a middling and a long gully and through a ridge, a train
shuttling on each), `scenes/demos/stations.tscn` (the trains demo's three lines with two gates,
a three-track station, a mine, a factory and a spawner with five routes - hand-written, see
[docs/stations.md](stations.md)) and
`scenes/levels/desert.tscn` (a whole
level rebuilt from a reference - a balloon loop round a lake with a scissors crossover, a wye, a
tunnel under a ridge and a bridge over a gully, sixteen signals, four gates, five stations and a
spawner - on a baked terrain carved to fit
the track; see [docs/level_authoring.md](level_authoring.md)). All eight are driven by the tests
under `tests/`; keep them working. Every one has a `Track` node (`TrackMesher`): without it the
rails are not drawn at all, since their own line drawing (`Rail.debug_draw`) is off by default.

The overlay is `scripts/ui/`, not `scripts/debug/`: clicking a signal or a turnout is the
player's actual interface, so it is gameplay UI that happens to still carry step 2's debug
presentation modes. The panels and the camera rig stay debug.

**Rails are `Path3D` + `Curve3D`.** Free in-editor point/tangent gizmos, arc-length-accurate
`sample_baked`, and scene serialisation for nothing. `Rail` adds an arc-length sampling API
(`rail_length`, `sample_position/forward/up/transform`, all mirrored in `sample_local_*`).

**`PathFollow3D` is deliberately not used.** Trains keep their own `distance` along the rail,
because turnouts (step 2) need to hand a train from one rail to another mid-travel and to
refuse entry from an unconnected direction — neither fits `PathFollow3D`'s model.

**Train direction is two independent values**, and this is the crux of goal 1:
- `facing` (`ALONG_RAIL` / `AGAINST_RAIL`) — which way the nose points along the rail.
- `throttle` (`-1` / `0` / `1`) — drive nose-first, stand, or back up.

Since step 5 a third value, `current_speed` (never negative), is how fast it is going; the
throttle only asks for it to change. The train moves along the rail in the direction
`motion * facing`, where `motion` follows the throttle's sign but **only changes at a
standstill** — a train reversed at speed brakes first. Driving forward always moves the nose
forward, whichever way the underlying curve was drawn. Never collapse these into a signed
speed — reversing a train and turning it around are different operations.

A train is a **consist** — a `LocomotiveType` and a list of `WagonType`s, shared resources under
`rolling_stock/` — and how fast it starts and stops comes from it: traction over mass, brakes
sized for the empty cars. `distance` is the middle of the whole train, and the `Train` node sits
exactly on the arc there. Each car is placed from the rail positions under its own two **ends**,
so it sits along a curve as a chord, its middle inside the arc by `L² / 8R` — a metre for a 16 m
car round the playground's 32 m balloon. That is correct, not drift. All of it, with the braking
rules, is in [docs/trains.md](trains.md).

`end_behavior` (`STOP` / `REVERSE` / `TURN_AROUND`) now fires **only at a genuine dead end** —
a rail end with no turnout attached, once the train has braked to a stand against it. A rail end
that connects onward hands the train over. It
stays a placeholder — real levels will want buffer stops and off-level connections there — but a
much smaller one than it was.
