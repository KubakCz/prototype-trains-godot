extends TurnoutDemoCase
## The shape of a turnout: that the branch is welded to the points, leaves tangent
## to the main rail, and reports which hand it is - none of which is authored by
## hand, all of which is read back off the curves.


func test_every_branch_is_welded_to_the_points() -> void:
	for turnout: Turnout in turnouts():
		var gap := turnout.points_position().distance_to(
				turnout.branch_rail.sample_position(turnout.branch_distance()))
		note("%-11s @ %7.2f m on %-9s  side %-5s  diverge %+d  branch_end %-5s  gap %.4f m"
				% [turnout.name, turnout.points_distance(), turnout.main_rail.name,
				"right" if turnout.branch_side() > 0 else "left", turnout.diverge_sign(),
				Turnout.RailEnd.keys()[turnout.branch_end], gap])
		assert_less(gap, 0.05, "%s: branch welded to the points" % turnout.name)


func test_every_branch_leaves_tangent_to_the_main_rail() -> void:
	# Tangency is what makes the handover smooth: a train crossing the points must
	# not change direction abruptly, so the branch curves away over its next
	# segment rather than at the points themselves.
	for turnout: Turnout in turnouts():
		var angle := turnout.diverge_angle_degrees()
		note("%-11s departs at %.2f deg" % [turnout.name, angle])
		assert_less(angle, 1.0, "%s: branch leaves tangent to the main rail" % turnout.name)


func test_the_hand_of_a_turnout_is_read_off_the_curves() -> void:
	# Which side the branch leaves on is derived, not authored, and that is what
	# lets one script be a left-hand turnout, a right-hand one, a turnout on a
	# curve or a symmetric Y.
	assert_eq(west.branch_side(), -1, "LoopWest is a left-hand turnout")
	assert_eq(east.branch_side(), 1, "LoopEast is a right-hand turnout")
	assert_eq(stub.branch_side(), 1, "StubPoints is a right-hand turnout")


func test_the_demo_layout_has_no_configuration_warnings() -> void:
	for turnout: Turnout in turnouts():
		var warnings := turnout._get_configuration_warnings()
		if not warnings.is_empty():
			note("%s: %s" % [turnout.name, ", ".join(warnings)])
		assert_true(warnings.is_empty(), "%s: no configuration warnings" % turnout.name)


## The editor-facing path: a turnout that has been misconfigured must say so, and
## must stop saying so once it is fixed.
func test_a_main_distance_off_the_rail_is_reported() -> void:
	stub.main_distance = stub.main_rail.rail_length() + 50.0
	var warnings := stub._get_configuration_warnings()
	note("off-rail main_distance -> %s" % ", ".join(warnings))
	assert_false(warnings.is_empty(), "a main_distance off the rail is reported")

	stub.main_distance = 135.0
	assert_true(stub._get_configuration_warnings().is_empty(),
			"the warning clears again once the distance is back on the rail")
