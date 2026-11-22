@tool
class_name TrainType
extends Resource
## A kind of train a [TrainSpawner] can put on the level: what pulls it, what it pulls
## and how many, and how full. A [Train] is a consist; this is the recipe for one, with
## the ranges left to the spawner's dice. Shared resources under [code]train_types/[/code],
## picked per route by [TrainRoute] so that passenger trains take passenger routes and
## freight trains take freight ones.

## What the readouts call a train of this type.
@export var display_name := "train"
@export var locomotive: LocomotiveType
## The wagon coupled on behind, as many of it as the dice say.
@export var wagon: WagonType
@export_range(0, 12) var min_wagons := 1
@export_range(0, 12) var max_wagons := 3
## How full the wagons are, from the least to the most. The same twice for a train that
## is always loaded or always empty.
@export_range(0.0, 1.0, 0.05) var min_load := 0.0
@export_range(0.0, 1.0, 0.05) var max_load := 0.0
@export_range(0.5, 60.0, 0.5, "suffix:m/s") var max_speed := 12.0


## The wagons of one train of this type: [member wagon], between the two counts.
func roll_wagons(rng: RandomNumberGenerator) -> Array[WagonType]:
	var wagons: Array[WagonType] = []
	if wagon == null:
		return wagons
	var count := rng.randi_range(mini(min_wagons, max_wagons), maxi(min_wagons, max_wagons))
	for i in count:
		wagons.append(wagon)
	return wagons


func roll_load(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(minf(min_load, max_load), maxf(min_load, max_load))


## The longest train this type can make, in metres: for a connection's room.
func longest_length() -> float:
	var length := locomotive.length if locomotive != null else 16.0
	if wagon != null:
		length += float(maxi(min_wagons, max_wagons)) * (wagon.length + Train.COUPLING_GAP)
	return length


func _get_configuration_warnings() -> PackedStringArray:
	return PackedStringArray() if locomotive != null else PackedStringArray(["No locomotive set."])
