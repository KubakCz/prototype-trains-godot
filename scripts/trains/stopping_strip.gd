class_name StoppingStrip
extends MeshInstance3D
## A train's stopping distance, drawn on the track from its leading end in the front
## marker's colour, with a bar across where it would stand. A debug aid for the selected
## train ([member Train.show_stopping_strip]).
##
## Belongs to its [Train] as an internal child, [member Node3D.top_level], and is drawn
## straight in global space. Takes the train's figures as plain values rather than the
## train itself, so it never has to name [Train] back.

## Length of one segment of the strip along the track, in metres.
const _STEP := 1.0
const _HALF_WIDTH := 0.55
## Height above the railhead.
const _LIFT := 0.45


func _init() -> void:
	name = "StoppingStrip"
	top_level = true


## Draws [param reach] metres of strip starting [param half] metres out from
## [param at_distance] on [param on_rail], walking in [param direction].
func draw(on_rail: Rail, at_distance: float, direction: int, half: float, reach: float,
		color: Color) -> void:
	visible = true
	global_transform = Transform3D.IDENTITY
	var lines := ImmediateMesh.new()
	mesh = lines
	var walk := TrackWalker.walk(on_rail, at_distance, direction, half + reach)
	var steps := maxi(1, ceili(reach / _STEP))
	lines.surface_begin(Mesh.PRIMITIVE_LINES, DebugLines.material(true))
	var previous := Vector3.ZERO
	var previous_side := Vector3.ZERO
	for i in steps + 1:
		var spot := walk.locate(half + reach * float(i) / float(steps))
		var point := spot.position() + Vector3.UP * _LIFT
		var side := spot.rail.sample_transform(spot.distance).basis.x * _HALF_WIDTH
		if i > 0:
			for offset: float in [-1.0, 0.0, 1.0]:
				DebugLines.line(lines, previous + previous_side * offset, point + side * offset,
						color)
		previous = point
		previous_side = side
	DebugLines.line(lines, previous - previous_side * 2.0, previous + previous_side * 2.0, color)
	lines.surface_end()
