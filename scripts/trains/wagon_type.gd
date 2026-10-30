@tool
class_name WagonType
extends CarType
## A vehicle that is pulled: everything behind the locomotive of a [Train].
##
## A wagon type says how much it [i]can[/i] carry; how full a train's wagons
## actually are is the train's own [member Train.load_factor]. Loading is something
## that happens to a train - at a station, in step 7 - not a different kind of
## wagon, so an empty and a full freight are the same consist with a different load.

## Tonnes it carries when full. Zero for coaches: passengers are not worth weighing.
@export_range(0.0, 200.0, 1.0, "suffix:t") var capacity := 0.0:
	set(value):
		capacity = value
		emit_changed()
