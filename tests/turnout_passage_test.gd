extends TurnoutDemoCase
## The passage table - the rule the whole turnout step turns on - taken straight
## through [method Turnout.traverse], every leg of every turnout in both positions:
##
## [codeblock]
## arriving on           normal                    reverse
## toe (facing move)     on down the main rail     switched onto the branch
## through (trailing)    on to the toe             refused
## diverging (trailing)  refused                   on to the toe
## [/codeblock]
##
## No train is involved: this is the geometry-free half of the rule, and
## turnout_driving_test.gd is the half a train has to obey.

## Both positions, in the order the report should read. Untyped on purpose - an
## array literal is Variant, so the loop variable is where the type goes.
const POSITIONS := [Turnout.Position.NORMAL, Turnout.Position.REVERSE]


func test_a_facing_move_out_of_the_toe_is_always_admitted() -> void:
	for turnout: Turnout in turnouts():
		for position: Turnout.Position in POSITIONS:
			turnout.turnout_position = position
			var exit := turnout.traverse(turnout.main_rail, turnout.points_distance(),
					turnout.diverge_sign())
			note("%-11s %-7s toe -> %s" % [turnout.name, _label(position), _exit(exit)])
			assert_not_null(exit, "%s %s: facing move admitted"
					% [turnout.name, _label(position)])


func test_a_facing_move_lands_on_the_leg_the_points_are_set_to() -> void:
	for turnout: Turnout in turnouts():
		for position: Turnout.Position in POSITIONS:
			turnout.turnout_position = position
			var exit := turnout.traverse(turnout.main_rail, turnout.points_distance(),
					turnout.diverge_sign())
			if not assert_not_null(exit, "%s %s: facing move admitted"
					% [turnout.name, _label(position)]):
				continue
			var expected: Rail = turnout.main_rail if _is_normal(position) else turnout.branch_rail
			note("%-11s %-7s toe -> %s" % [turnout.name, _label(position), _exit(exit)])
			assert_eq(exit.rail, expected, "%s %s: facing move lands on %s"
					% [turnout.name, _label(position), expected.name])


func test_a_trailing_move_down_the_through_leg_needs_the_points_normal() -> void:
	for turnout: Turnout in turnouts():
		for position: Turnout.Position in POSITIONS:
			turnout.turnout_position = position
			var exit := turnout.traverse(turnout.main_rail, turnout.points_distance(),
					-turnout.diverge_sign())
			note("%-11s %-7s through -> %s" % [turnout.name, _label(position), _exit(exit)])
			assert_eq(exit != null, _is_normal(position), "%s %s: through leg %s"
					% [turnout.name, _label(position),
					"admitted" if _is_normal(position) else "refused"])


func test_a_trailing_move_up_the_branch_needs_the_points_reverse() -> void:
	for turnout: Turnout in turnouts():
		for position: Turnout.Position in POSITIONS:
			turnout.turnout_position = position
			var exit := turnout.traverse(turnout.branch_rail, turnout.branch_distance(),
					-turnout.branch_exit_sign())
			note("%-11s %-7s branch -> %s" % [turnout.name, _label(position), _exit(exit)])
			assert_eq(exit != null, not _is_normal(position), "%s %s: branch leg %s"
					% [turnout.name, _label(position),
					"refused" if _is_normal(position) else "admitted"])


func _is_normal(position: Turnout.Position) -> bool:
	return position == Turnout.Position.NORMAL


func _label(position: Turnout.Position) -> String:
	return Turnout.Position.keys()[position]


func _exit(exit: Turnout.Exit) -> String:
	if exit == null:
		return "REFUSED"
	return "%s @ %.1f m dir %+d" % [exit.rail.name, exit.distance, exit.direction]
