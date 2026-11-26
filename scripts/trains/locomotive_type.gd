@tool
class_name LocomotiveType
extends CarType
## A vehicle that pulls: the one at the front of every [Train], carrying the front
## marker. Its [member traction] divided by the whole train's mass is how fast the
## train gets going, so every wagon and every tonne of load slows the start.

static var _stand_in: LocomotiveType

## Pulling force at the rail, in kilonewtons. Constant at every speed: there is no
## power curve, the train simply accelerates at this over its mass until it
## reaches [member Train.max_speed].
@export_range(10.0, 1500.0, 5.0, "suffix:kN") var traction := 300.0:
	set(value):
		traction = value
		emit_changed()


## What a train or a [TrainType] without a locomotive is drawn and measured with.
static func stand_in() -> LocomotiveType:
	if _stand_in == null:
		_stand_in = LocomotiveType.new()
		_stand_in.display_name = "stand-in locomotive"
		_stand_in.length = 16.0
		_stand_in.mass = 80.0
		_stand_in.traction = 360.0
	return _stand_in
