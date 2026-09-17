extends SceneTree
## Headless checks for turnouts (step 2). Run with:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##       --script res://scripts/debug/turnout_checks.gd
##
## Exits non-zero on the first failing expectation, so it works as a smoke test
## after touching [Turnout], [TrackWalker] or [Train]. The click checks need a
## real window and are skipped under [code]--headless[/code]; drop the flag to
## include them.
##
## Kept rather than thrown away because step 4 builds compound turnouts out of
## these, and the passage table below is the thing that must not regress.

const DEMO := "res://scenes/demos/turnouts.tscn"
const MAIN := "res://scenes/main.tscn"

var failures: Array[String] = []

var demo: Node
var main_line: Rail
var loop_line: Rail
var stub_line: Rail
var west: Turnout
var stub: Turnout
var east: Turnout
var shuttle: Train


func _initialize() -> void:
	_run()


func _run() -> void:
	demo = (load(DEMO) as PackedScene).instantiate()
	root.add_child(demo)
	await process_frame
	await process_frame

	main_line = demo.get_node("Rails/MainLine")
	loop_line = demo.get_node("Rails/LoopLine")
	stub_line = demo.get_node("Rails/StubLine")
	west = demo.get_node("Turnouts/LoopWest")
	stub = demo.get_node("Turnouts/StubPoints")
	east = demo.get_node("Turnouts/LoopEast")
	shuttle = demo.get_node("Trains/Shuttle")
	demo.get_node("Trains/LoopShunter").throttle = 0

	_check_geometry()
	_check_passage_table()
	_check_warnings()
	await _check_driving()
	demo.queue_free()
	await process_frame

	await _check_main_scene()
	if DisplayServer.get_name() == "headless":
		print("\n== CLICKS ==\n  skipped: no window (drop --headless to run these)")
	else:
		await _check_clicks()

	print("")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
	else:
		print("FAILURES (%d):" % failures.size())
		for f in failures:
			print("  - ", f)
	quit(0 if failures.is_empty() else 1)


func check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures.append(what)


#region Geometry
func _check_geometry() -> void:
	print("\n== GEOMETRY ==")
	for t: Turnout in [west, stub, east]:
		var gap := t.points_position().distance_to(
				t.branch_rail.sample_position(t.branch_distance()))
		print("  %-11s @ %7.2f m on %-9s  side %-5s  diverge %+d  branch_end %-5s  "
				% [t.name, t.points_distance(), t.main_rail.name,
				"right" if t.branch_side() > 0 else "left", t.diverge_sign(),
				Turnout.RailEnd.keys()[t.branch_end]]
				+ "gap %.4f m  tangent %.2f deg" % [gap, t.diverge_angle_degrees()])
		check(gap < 0.05, "%s: branch welded to the points (gap %.4f m)" % [t.name, gap])
		check(t.diverge_angle_degrees() < 1.0,
				"%s: branch leaves tangent to the main rail (%.2f deg)"
				% [t.name, t.diverge_angle_degrees()])
		check(t._get_configuration_warnings().is_empty(),
				"%s: no configuration warnings" % t.name)
	# Which hand a turnout is falls out of the curves, so it is worth asserting.
	check(west.branch_side() < 0, "LoopWest is a left-hand turnout")
	check(east.branch_side() > 0, "LoopEast is a right-hand turnout")
	check(stub.branch_side() > 0, "StubPoints is a right-hand turnout")


## The editor-facing path: a turnout that has been misconfigured must say so.
func _check_warnings() -> void:
	print("\n== CONFIGURATION WARNINGS ==")
	var was := stub.main_distance
	stub.main_distance = stub.main_rail.rail_length() + 50.0
	var warnings := stub._get_configuration_warnings()
	print("  off-rail main_distance -> %s" % ", ".join(warnings))
	check(not warnings.is_empty(), "a main_distance off the rail is reported")
	stub.main_distance = was
	check(stub._get_configuration_warnings().is_empty(), "warnings clear again once fixed")
#endregion


#region Passage table
## Every leg of every turnout, in both positions, straight through
## Turnout.traverse. This is the rule the whole step turns on.
func _check_passage_table() -> void:
	print("\n== PASSAGE TABLE ==")
	for t: Turnout in [west, stub, east]:
		print("  %s" % t.name)
		for position: Turnout.Position in [Turnout.Position.NORMAL, Turnout.Position.REVERSE]:
			t.turnout_position = position
			var label: String = Turnout.Position.keys()[position]
			var normal := position == Turnout.Position.NORMAL
			# Facing move out of the toe: must always be admitted.
			var facing := t.traverse(t.main_rail, t.points_distance(), t.diverge_sign())
			# Trailing move down the through leg: only with the points normal.
			var through := t.traverse(t.main_rail, t.points_distance(), -t.diverge_sign())
			# Trailing move up the branch: only with the points reverse.
			var branch := t.traverse(t.branch_rail, t.branch_distance(), -t.branch_exit_sign())
			print("    %-8s toe->%-24s through->%-12s branch->%s"
					% [label, _exit(facing), _exit(through), _exit(branch)])
			check(facing != null, "%s %s: facing move admitted" % [t.name, label])
			check((through != null) == normal, "%s %s: through leg %s"
					% [t.name, label, "admitted" if normal else "refused"])
			check((branch != null) == not normal, "%s %s: branch leg %s"
					% [t.name, label, "refused" if normal else "admitted"])
			var lands_on: Rail = t.main_rail if normal else t.branch_rail
			check(facing.rail == lands_on, "%s %s: facing move lands on %s"
					% [t.name, label, lands_on.name])
		t.turnout_position = Turnout.Position.NORMAL


func _exit(exit: Turnout.Exit) -> String:
	if exit == null:
		return "REFUSED"
	return "%s @ %.1f dir %+d" % [exit.rail.name, exit.distance, exit.direction]
#endregion


#region Driving
func _check_driving() -> void:
	print("\n== A: all normal, eastbound run to the dead end ==")
	_set_points(Turnout.Position.NORMAL, Turnout.Position.NORMAL, Turnout.Position.NORMAL)
	_place(main_line, 20.0, Train.ALONG_RAIL)
	shuttle.end_behavior = Train.EndBehavior.STOP
	await _drive(900)
	print("    %s" % _state())
	# `at_dead_end` is cleared once the throttle drops, by design: a stopped train
	# is not being held by anything. STOP having fired is the lasting evidence.
	check(shuttle.rail == main_line and shuttle.throttle == 0,
			"A: ran the length of the main line and stopped at the east dead end")
	check(absf(shuttle.distance - (main_line.rail_length() - 8.0)) < 0.2,
			"A: stopped with its nose on the rail end, body length behind it")

	print("\n== B: LoopWest reverse, held at LoopEast, then let through ==")
	_set_points(Turnout.Position.REVERSE, Turnout.Position.NORMAL, Turnout.Position.NORMAL)
	_place(main_line, 20.0, Train.ALONG_RAIL)
	shuttle.end_behavior = Train.EndBehavior.STOP
	await _drive(200)
	print("    after diverging: %s" % _state())
	check(shuttle.rail == loop_line, "B: facing move at LoopWest put the train on the loop")
	check(shuttle.facing == Train.ALONG_RAIL,
			"B: nose still points the way it was going")
	await _drive(700)
	print("    at the far end:  %s" % _state())
	check(shuttle.blocking_turnout == east, "B: held by LoopEast, which is set against it")
	check(shuttle.throttle == 1, "B: throttle still open while held")
	var held_at := shuttle.distance
	await _drive(60)
	check(absf(shuttle.distance - held_at) < 1e-3, "B: stays put while held")
	check(absf(loop_line.rail_length() - shuttle.distance - 8.0) < 0.2,
			"B: waiting with its nose on the points, not past them")
	east.throw_points()
	await _drive(120)
	print("    after throwing:  %s" % _state())
	check(shuttle.rail == main_line and shuttle.blocking_turnout == null,
			"B: rolled on to the main line as soon as LoopEast was thrown")
	check(shuttle.facing == Train.ALONG_RAIL, "B: still nose-east after rejoining")

	print("\n== C: trailing move on the main line, LoopEast reverse ==")
	_set_points(Turnout.Position.NORMAL, Turnout.Position.NORMAL, Turnout.Position.REVERSE)
	_place(main_line, 20.0, Train.ALONG_RAIL)
	await _drive(700)
	print("    %s" % _state())
	check(shuttle.blocking_turnout == east,
			"C: held at LoopEast on the through leg with the points reverse")
	check(shuttle.rail == main_line, "C: never left the main line")
	east.throw_points()
	await _drive(120)
	check(shuttle.blocking_turnout == null and shuttle.distance > 175.0,
			"C: carried straight on once LoopEast went normal")

	print("\n== D: StubPoints reverse, into the dead-end siding and back ==")
	_set_points(Turnout.Position.NORMAL, Turnout.Position.REVERSE, Turnout.Position.NORMAL)
	_place(main_line, 20.0, Train.ALONG_RAIL)
	shuttle.end_behavior = Train.EndBehavior.TURN_AROUND
	await _drive(500)
	print("    %s" % _state())
	check(shuttle.rail == stub_line, "D: diverged into the stub siding")
	await _drive(200)
	check(shuttle.rail == stub_line and shuttle.facing == Train.AGAINST_RAIL,
			"D: turned around at the buffer stop (end_behavior at a real dead end)")
	await _drive(400)
	print("    coming back:     %s" % _state())
	check(shuttle.rail == main_line, "D: trailed back out through the reverse points")

	print("\n== E: refused coming out of the siding ==")
	_place(stub_line, stub_line.rail_length() - 8.0, Train.AGAINST_RAIL)
	shuttle.end_behavior = Train.EndBehavior.STOP
	stub.turnout_position = Turnout.Position.NORMAL
	await _drive(400)
	print("    %s" % _state())
	check(shuttle.blocking_turnout == stub, "E: held inside the siding by StubPoints normal")
	stub.throw_points()
	await _drive(200)
	print("    after throwing:  %s" % _state())
	check(shuttle.rail == main_line and shuttle.facing == Train.AGAINST_RAIL,
			"E: came out onto the main line nose-west once the points were thrown")

	print("\n== BODY SPANNING THE POINTS ==")
	_set_points(Turnout.Position.REVERSE, Turnout.Position.NORMAL, Turnout.Position.NORMAL)
	_place(main_line, 20.0, Train.ALONG_RAIL)
	var spanned := false
	for _i in 400:
		await physics_frame
		var half := shuttle.body_length * 0.5
		var nose := TrackWalker.walk(shuttle.rail, shuttle.distance, shuttle.facing, half)
		var tail := TrackWalker.walk(shuttle.rail, shuttle.distance, -shuttle.facing, half)
		if nose.rail != tail.rail:
			spanned = true
			var chord := tail.rail.sample_position(tail.distance).distance_to(
					nose.rail.sample_position(nose.distance))
			print("    tail on %s @ %.1f, nose on %s @ %.1f, chord %.2f m"
					% [tail.rail.name, tail.distance, nose.rail.name, nose.distance, chord])
			check(absf(chord - shuttle.body_length) < 0.5,
					"body drawn as a full-length chord across two rails")
			break
	check(spanned, "the body does span two rails while passing the points")

	# Throwing points under a train is allowed for now (step 8 locks them). The
	# body kinks, which is expected - what must not happen is a stuck or
	# teleported train.
	if spanned:
		var was := shuttle.global_position
		west.throw_points()
		await _drive(30)
		var jump := was.distance_to(shuttle.global_position)
		print("    thrown under the train: moved %.2f m in 30 frames, now on %s"
				% [jump, shuttle.rail.name])
		check(shuttle.global_position.is_finite(),
				"throwing points under a train leaves a finite position")
		check(jump > 1.0 and jump < 20.0,
				"the train keeps running at roughly its own speed (%.2f m)" % jump)


func _set_points(w: Turnout.Position, s: Turnout.Position, e: Turnout.Position) -> void:
	west.turnout_position = w
	stub.turnout_position = s
	east.turnout_position = e


func _place(rail: Rail, at: float, facing: int) -> void:
	shuttle.rail = rail
	shuttle.distance = at
	shuttle.facing = facing
	shuttle.throttle = 1


func _drive(frames: int) -> void:
	for _i in frames:
		await physics_frame


func _state() -> String:
	var blocked := shuttle.blocked_description()
	return "on %-9s @ %6.1f / %6.1f m  nose %-12s throttle %+d  %s" % [
		shuttle.rail.name, shuttle.distance, shuttle.rail.rail_length(),
		"along rail" if shuttle.facing == Train.ALONG_RAIL else "against rail",
		shuttle.throttle, blocked if not blocked.is_empty() else "clear"]
#endregion


#region The running prototype
func _check_main_scene() -> void:
	print("\n== MAIN SCENE ==")
	var scene := (load(MAIN) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame

	for t: Turnout in scene.get_node("Turnouts").get_children():
		var gap := t.points_position().distance_to(
				t.branch_rail.sample_position(t.branch_distance()))
		print("  %-13s @ %6.1f m  %-5s hand  gap %.4f m  tangent %.2f deg"
				% [t.name, t.points_distance(),
				"right" if t.branch_side() > 0 else "left", gap,
				t.diverge_angle_degrees()])
		# Snapping moves each rail onto the terrain independently, so without
		# Turnout.align_branch_on_ready the branch drifts off the points here.
		check(gap < 0.05, "%s: still welded after surface snapping (gap %.4f m)"
				% [t.name, gap])
		check(t._get_configuration_warnings().is_empty(),
				"%s: no configuration warnings" % t.name)

	# The prototype is meant to open with a train already held at the junction,
	# so the refusal case is visible without touching anything.
	var freight: Train = scene.get_node("Trains/FreightTrain")
	var junction: Turnout = scene.get_node("Turnouts/MainJunction")
	for _i in 460:
		await physics_frame
	print("  FreightTrain on %s @ %.1f m  %s"
			% [freight.rail.name, freight.distance, freight.blocked_description()])
	check(freight.blocking_turnout == junction,
			"FreightTrain runs up to MainJunction and is held there")

	# A train's body is a chord, so its origin sits inside the arc - by 1.4 m for
	# a 14 m body on this layout's tighter bends, which is correct rather than
	# drift. What must hold regardless of curvature is the *arc* position: the
	# chord midpoint is symmetric about the train's own distance, so projecting
	# the origin back onto the curve has to return that distance.
	for train: Train in scene.get_node("Trains").get_children():
		var at := train.rail.curve.get_closest_offset(
				train.rail.to_local(train.global_position))
		var inset := train.global_position.distance_to(
				train.rail.sample_position(train.rail.clamp_distance(train.distance)))
		print("  %-14s on %-10s distance %6.1f m, projects back to %6.1f m, chord inset %.2f m"
				% [train.name, train.rail.name, train.distance, at, inset])
		check(absf(at - train.distance) < 0.6,
				"%s sits at the arc position its distance says (%.2f m out)"
				% [train.name, absf(at - train.distance)])
		check(inset < 2.5, "%s is not flung off %s (%.2f m from the railhead)"
				% [train.name, train.rail.name, inset])
	scene.queue_free()
	await process_frame
#endregion


#region Clicks
## Both routes into Turnout.throw_points: the collider on the marker, and the
## floating widget. Needs a window, and the window must not be resized away from
## the project's viewport size or the two coordinate spaces stop agreeing.
func _check_clicks() -> void:
	print("\n== CLICKS ==")
	var scene := (load(DEMO) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	for train: Train in scene.get_node("Trains").get_children():
		train.throttle = 0

	var turnout: Turnout = scene.get_node("Turnouts/StubPoints")
	var overlay: TurnoutOverlay = scene.get_node("DebugUi/TurnoutOverlay")
	var rig: CameraRig = scene.get_node("CameraRig")
	var camera: Camera3D = scene.get_node("CameraRig/Camera3D")
	rig.position = turnout.points_position()
	rig.yaw_degrees = -18.0
	rig.pitch_degrees = -30.0
	rig.zoom = 40.0
	rig._apply()

	overlay.mode = TurnoutOverlay.Mode.LEGS_3D
	await _settle()
	# The click target sits beside the track on the branch side; see
	# Turnout._rebuild_marker.
	var marker := turnout.global_transform * Vector3(float(turnout.branch_side()) * 2.4, 0.9, 0.0)
	var before := turnout.turnout_position
	await _click(camera.unproject_position(marker))
	check(turnout.turnout_position != before, "3D click on the marker throws the points")

	before = turnout.turnout_position
	await _click(Vector2(60.0, root.get_visible_rect().size.y - 300.0))
	check(turnout.turnout_position == before, "click on empty ground throws nothing")

	overlay.mode = TurnoutOverlay.Mode.LEGS_AND_SCHEMATIC
	await _settle()
	var widget: TurnoutWidget = null
	for child: Node in overlay.get_children():
		var candidate := child as TurnoutWidget
		if candidate != null and candidate.turnout == turnout:
			widget = candidate
	if widget == null or not widget.visible:
		check(false, "widget for %s is on screen" % turnout.name)
	else:
		before = turnout.turnout_position
		await _click(widget.get_global_rect().get_center())
		# One flip, not two: if the collider under the widget also saw the click
		# the points would come straight back and this would read as unchanged.
		check(turnout.turnout_position != before,
				"click on the widget throws the points exactly once")
	scene.queue_free()
	await process_frame


func _settle() -> void:
	for _i in 4:
		await process_frame


## A press and release, pushed through the real input path so that GUI routing
## and physics object picking are both exercised.
func _click(at: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
		await process_frame
	await process_frame
#endregion
