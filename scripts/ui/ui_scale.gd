extends Node
## Picks the interface scale from the window size, the way most games do: the UI is
## authored for a reference height and stepped up on taller screens, rather than
## stretched in proportion to the window.
##
## The scale is applied as [member Window.content_scale_factor], which divides the
## canvas: a 1920x1009 window at factor 1.0 lays the UI out in 1920x1009 logical
## pixels, and at factor 2.0 in 960x505 drawn twice as large. Nothing about the 3D
## view changes - it always renders at the window's native resolution. See the
## coordinate-space note in CLAUDE.md.
##
## Registered as an autoload, so main.tscn and both demo scenes get it alike.

## The height the interface is authored for. A window this tall draws it 1:1.
const REFERENCE_HEIGHT := 1080.0

## Scales snap to this, so the UI sits at a few predictable sizes instead of creeping
## by a percent every time the window is nudged.
const STEP := 0.25

## Never below 1:1 - the debug readouts are dense enough already - and never so large
## that a 4K screen ends up showing less of the world than a 1440p one.
const MIN_SCALE := 1.0
const MAX_SCALE := 3.0


func _ready() -> void:
	var window := get_window()
	window.size_changed.connect(_apply)
	_apply()


func _apply() -> void:
	var window := get_window()
	var factor := scale_for_height(window.size.y)
	if not is_equal_approx(window.content_scale_factor, factor):
		window.content_scale_factor = factor


## The rule itself, kept static so a test can ask it about a height without a window.
static func scale_for_height(height: int) -> float:
	return clampf(snappedf(height / REFERENCE_HEIGHT, STEP), MIN_SCALE, MAX_SCALE)
