@tool
class_name CarType
extends Resource
## What one vehicle of a [Train] is: how big it is, what it weighs and how hard its
## brakes are. A resource rather than something authored on the train, because a
## type is shared by every train that runs one - see [LocomotiveType] and
## [WagonType], the two kinds there are.
##
## Brakes are sized for the [i]empty[/i] vehicle: [member brake_rate] is the
## deceleration its own brakes give its own [member mass] at 100%. Whatever a wagon
## carries adds weight but no brake, which is what makes a loaded train stop longer
## than an empty one, while a longer train of the same cars stops no worse.
##
## Every setter emits [signal Resource.changed], so a train showing this type in
## the editor rebuilds when the type is edited.

## What the readouts call it.
@export var display_name := "":
	set(value):
		display_name = value
		emit_changed()
@export_range(1.0, 40.0, 0.1, "suffix:m") var length := 14.0:
	set(value):
		length = value
		emit_changed()
@export_range(1.0, 5.0, 0.05, "suffix:m") var width := 2.9:
	set(value):
		width = value
		emit_changed()
@export_range(1.0, 6.0, 0.05, "suffix:m") var height := 3.4:
	set(value):
		height = value
		emit_changed()
## Empty weight, in tonnes.
@export_range(1.0, 300.0, 0.5, "suffix:t") var mass := 40.0:
	set(value):
		mass = value
		emit_changed()
## Deceleration this vehicle's brakes give its own empty [member mass] at 100%, in
## m/s². Deliberately livelier than a real railway's, because this is a game.
@export_range(0.5, 12.0, 0.1, "suffix:m/s²") var brake_rate := 6.0:
	set(value):
		brake_rate = value
		emit_changed()


## Braking force at 100%, in kilonewtons. A tonne at 1 m/s² is a kilonewton, so
## dividing a whole train's worth of these by its mass in tonnes gives m/s².
func brake_force() -> float:
	return mass * brake_rate


func label() -> String:
	return display_name if not display_name.is_empty() else resource_path.get_file().get_basename()
