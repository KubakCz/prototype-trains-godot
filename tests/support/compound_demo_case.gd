class_name CompoundDemoCase
extends TestCase
## Fixture for the [code]scenes/demos/compound_turnouts.tscn[/code] layout, on
## flat ground, west to east along +X:
##
## - [b]ThreeWay[/b] on ThreeWayMain: LeftPoints at 100 m, RightPoints 4 m further
##   on, both toes facing west. Every track ends at buffers in the east.
## - [b]Crossover[/b]: NorthPoints on CrossoverNorth at 110 m (toe west) and
##   SouthPoints on CrossoverSouth at 140 m (toe east), joined by CrossoverLink.
##   An eastbound train on the north track can cross to the south one.
## - [b]Scissors[/b]: a double crossover between ScissorsNorth and ScissorsSouth,
##   points at 122 m and 158 m on both, links ScissorsDown (north to south,
##   eastbound) and ScissorsUp (south to north), which cross at ScissorsMiddle.
## - [b]Diamond[/b]: DiamondStraight crossed by DiamondDiagonal at about 31 deg.
## - [b]DoubleSlip[/b]: SlipLineOne (heading south-east) and SlipLineTwo (heading
##   north-east) crossing at 12 deg at DoubleSlipMiddle, halfway along both.
##   Points 14 m either side of the crossing on both tracks: WestOne and EastTwo
##   carry SlipRoadNorth, WestTwo and EastOne carry SlipRoadSouth. Track 1 is
##   SlipLineOne and slip 1 is SlipRoadNorth, because WestOne is the first member.
##
## A fresh copy for every test, with every train stopped.

const DEMO_SCENE := "res://scenes/demos/compound_turnouts.tscn"

var demo: Node
var three_way: CompoundTurnout
var crossover: CompoundTurnout
var scissors: CompoundTurnout
var double_slip: CompoundTurnout
var double_slip_middle: Crossing
var scissors_middle: Crossing
var diamond: Crossing


func before_each() -> void:
	demo = await load_scene(DEMO_SCENE)
	three_way = demo.get_node("Compounds/ThreeWay")
	crossover = demo.get_node("Compounds/Crossover")
	scissors = demo.get_node("Compounds/Scissors")
	double_slip = demo.get_node("Compounds/DoubleSlip")
	double_slip_middle = demo.get_node("Crossings/DoubleSlipMiddle")
	scissors_middle = demo.get_node("Crossings/ScissorsMiddle")
	diamond = demo.get_node("Crossings/Diamond")
	for train: Train in demo.get_node("Trains").get_children():
		train.throttle = 0


func rail(rail_name: String) -> Rail:
	return demo.get_node("Rails/%s" % rail_name)


func member(compound: CompoundTurnout, member_name: String) -> Turnout:
	return compound.get_node(member_name)


func train(train_name: String) -> Train:
	return demo.get_node("Trains/%s" % train_name)


func compounds() -> Array[CompoundTurnout]:
	return [three_way, crossover, scissors, double_slip]


## Every member's position, as N/R letters in member order - for notes.
func member_letters(compound: CompoundTurnout) -> String:
	var letters := ""
	for turnout in compound.members:
		letters += "R" if turnout.turnout_position == Turnout.Position.REVERSE else "N"
	return letters


## The same as [method member_letters], for what [param index] asks for.
func wanted_letters(compound: CompoundTurnout, index: int) -> String:
	var letters := ""
	for position in compound.member_positions(index):
		letters += "R" if position == Turnout.Position.REVERSE else "N"
	return letters


## Walks [param length] metres from [param at] on [param from], and says where it
## ended up - the question every passage test asks.
func walk(from: String, at: float, direction: int, length: float) -> TrackWalker.Step:
	return TrackWalker.walk(rail(from), at, direction, length)


func describe(step: TrackWalker.Step) -> String:
	return "%s @ %.1f m dir %+d  %s" % [step.rail.name, step.distance, step.direction,
			step.describe()]


## Puts a train somewhere with its throttle open.
func place(which: Train, on: String, at: float, facing: int) -> void:
	which.rail = rail(on)
	which.distance = at
	which.facing = facing
	which.throttle = 1


func state(which: Train) -> String:
	var blocked := which.blocked_description()
	return "%s on %s @ %.1f m  %s" % [which.name, which.rail.name, which.distance,
			blocked if not blocked.is_empty() else "clear"]
