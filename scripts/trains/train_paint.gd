class_name TrainPaint
extends RefCounted
## The materials one [Train]'s cars share, and how they are coloured: the body blue,
## lighter while selected, grey once wrecked; the engine in its [Livery]; the load; and
## the front marker in the colour of the train's state. Every car is handed these same
## materials, so recolouring a train is a handful of material writes however long it is.
##
## Names neither [Train] nor its states: the train says what colour its marker shows.

## What every car's body is painted while the train is not selected or wrecked.
const BODY_COLOR := Color(0.16, 0.32, 0.52)
const _BODY_SELECTED := Color(0.45, 0.68, 0.96)
const _WRECK := Color(0.30, 0.32, 0.35)
const _WRECK_SELECTED := Color(0.55, 0.58, 0.62)
const _LOAD := Color(0.46, 0.31, 0.17)
## The share a selected locomotive's livery is lightened by.
const _SELECTED_LIGHTEN := 0.3
## How long each half of a blink lasts, in seconds.
const _BLINK := 0.25

## Every wagon's body, and the engine's without a livery.
var body: StandardMaterial3D
## What the wagons carry.
var cargo: StandardMaterial3D
## The front marker on the locomotive's roof.
var marker: StandardMaterial3D
## The engine's body when it has a livery.
var engine: StandardMaterial3D
## The engine's livery stripe.
var stripe: StandardMaterial3D


func _init() -> void:
	body = StandardMaterial3D.new()
	body.albedo_color = BODY_COLOR
	cargo = StandardMaterial3D.new()
	cargo.albedo_color = _LOAD
	marker = StandardMaterial3D.new()
	marker.emission_enabled = true
	engine = StandardMaterial3D.new()
	stripe = StandardMaterial3D.new()


## Recolours the bodies for [param selected] and [param wrecked], and the engine for
## [param livery] when there is one.
func refresh(livery: Livery, selected: bool, wrecked: bool) -> void:
	if wrecked:
		body.albedo_color = _WRECK_SELECTED if selected else _WRECK
	else:
		body.albedo_color = _BODY_SELECTED if selected else BODY_COLOR
	# The engine's paint, when it has some: a wreck is grey like the rest of it, and a
	# selected one is lightened, which the wagons - plain blue - show by going lighter.
	if livery != null:
		if wrecked:
			engine.albedo_color = body.albedo_color
			stripe.albedo_color = body.albedo_color.lightened(0.25)
		else:
			engine.albedo_color = (livery.body.lerp(Color.WHITE, _SELECTED_LIGHTEN)
					if selected else livery.body)
			stripe.albedo_color = livery.stripe


## Lights the marker in [param color], darkened every other [constant _BLINK] seconds
## when it [param blinks], and unlit on a [param wrecked] train.
func paint_marker(color: Color, blinks: bool, wrecked: bool) -> void:
	if blinks and int(Time.get_ticks_msec() / (_BLINK * 1000.0)) % 2 == 1:
		color = color.darkened(0.8)
	marker.albedo_color = color
	marker.emission = color
	marker.emission_energy_multiplier = 0.0 if wrecked else 0.6
