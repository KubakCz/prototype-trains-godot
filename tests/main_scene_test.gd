extends TestCase
## The running prototype, scenes/main.tscn: turnouts that survive surface snapping,
## a train held at the junction from the moment the level opens, and bodies that sit
## where their distance says they do.
##
## The scene is built once for the whole suite and run for 460 physics frames
## (7.7 s of game time) in before_all, because every test here observes the same
## settled state rather than changing it.

const MAIN_SCENE := "res://scenes/main.tscn"
const SETTLE_FRAMES := 460

var _scene: Node
var _turnouts: Array[Turnout] = []
var _trains: Array[Train] = []


func before_all() -> void:
	_scene = await load_scene(MAIN_SCENE)
	for turnout: Turnout in _scene.get_node("Turnouts").get_children():
		_turnouts.append(turnout)
	for train: Train in _scene.get_node("Trains").get_children():
		_trains.append(train)
	await physics_frames(SETTLE_FRAMES)


## Snapping moves each rail onto the terrain independently, so without
## Turnout.align_branch_on_ready the branch drifts off the points here and trains
## visibly jump on handover.
func test_every_turnout_is_still_welded_after_surface_snapping() -> void:
	for turnout: Turnout in _turnouts:
		var gap := turnout.points_position().distance_to(
				turnout.branch_rail.sample_position(turnout.branch_distance()))
		note("%-13s @ %6.1f m  %-5s hand  gap %.4f m  tangent %.2f deg"
				% [turnout.name, turnout.points_distance(),
				"right" if turnout.branch_side() > 0 else "left", gap,
				turnout.diverge_angle_degrees()])
		assert_less(gap, 0.05, "%s: still welded after surface snapping" % turnout.name)


func test_the_level_has_no_configuration_warnings() -> void:
	for turnout: Turnout in _turnouts:
		var warnings := turnout._get_configuration_warnings()
		if not warnings.is_empty():
			note("%s: %s" % [turnout.name, ", ".join(warnings)])
		assert_true(warnings.is_empty(), "%s: no configuration warnings" % turnout.name)


## The prototype is meant to open with a train already held at the junction, so the
## refusal case is visible without touching anything.
func test_a_train_runs_up_to_the_junction_and_is_held_there() -> void:
	var freight: Train = _scene.get_node("Trains/FreightTrain")
	var junction: Turnout = _scene.get_node("Turnouts/MainJunction")
	note("FreightTrain on %s @ %.1f m  %s"
			% [freight.rail.name, freight.distance, freight.blocked_description()])
	assert_eq(freight.blocking_turnout, junction, "FreightTrain is held at MainJunction")
	assert_eq(freight.throttle, 1, "with its throttle still open")


## A train's body is a chord, so its origin sits inside the arc - by 1.4 m for a
## 14 m body on this layout's tighter bends, which is correct rather than drift.
## What must hold whatever the curvature is the arc position: the chord midpoint is
## symmetric about the train's own distance, so projecting the origin back onto the
## curve has to return that distance.
func test_every_train_sits_at_the_arc_position_its_distance_says() -> void:
	for train: Train in _trains:
		var projected := train.rail.curve.get_closest_offset(
				train.rail.to_local(train.global_position))
		var inset := train.global_position.distance_to(
				train.rail.sample_position(train.rail.clamp_distance(train.distance)))
		note("%-14s on %-10s distance %6.1f m, projects back to %6.1f m, chord inset %.2f m"
				% [train.name, train.rail.name, train.distance, projected, inset])
		assert_near(projected, train.distance, 0.6,
				"%s sits at the arc position its distance says" % train.name)
		assert_less(inset, 2.5, "%s is not flung off %s" % [train.name, train.rail.name])
