@tool
class_name Livery
extends Resource
## How a locomotive is painted: one plain colour, or a colour with a horizontal stripe
## round the body.
##
## Spawned trains get a random one ([method random]). The colours are the few
## well-known ones in [constant PALETTE] - no two of a kind, so no two engines differ
## only by a shade - and a stripe is only ever put on a colour it stands out from: a
## [member CONTRAST] ratio of luminance, from a different part of the colour wheel.

## The colours an engine is painted in, by name.
const PALETTE := {
	"red": Color(0.85, 0.12, 0.10),
	"orange": Color(1.0, 0.55, 0.08),
	"yellow": Color(1.0, 0.85, 0.10),
	"green": Color(0.10, 0.60, 0.20),
	"blue": Color(0.10, 0.30, 0.85),
	"purple": Color(0.50, 0.20, 0.70),
	"pink": Color(1.0, 0.50, 0.75),
	"white": Color(0.95, 0.95, 0.95),
}
## Colours a stripe may be but a body never is: the medium-bright oranges and pinks have
## no stripe they could be read against in the palette, and an all-black engine is
## lost against the ground and the wrecks.
const STRIPE_ONLY := {
	"black": Color(0.06, 0.06, 0.07),
}
## The least luminance contrast ratio (WCAG's: 1 to 21) a stripe has to the body.
const CONTRAST := 3.0
## The least distance round the colour wheel, out of a whole turn, between a stripe and
## the body it is on. White has no hue and is judged by contrast alone.
const MIN_HUE_GAP := 0.12
## How often a new engine is striped.
const STRIPED_SHARE := 0.5

static var _pairs: Array[Array] = []

@export var body := Color(0.16, 0.32, 0.52):
	set(value):
		body = value
		emit_changed()
@export var striped := false:
	set(value):
		striped = value
		emit_changed()
@export var stripe := Color.WHITE:
	set(value):
		stripe = value
		emit_changed()


## A random livery, plain or striped, from [param rng].
static func random(rng: RandomNumberGenerator) -> Livery:
	var livery := Livery.new()
	var names: Array = PALETTE.keys()
	if rng.randf() < STRIPED_SHARE:
		var pair: Array = stripe_pairs()[rng.randi_range(0, stripe_pairs().size() - 1)]
		livery.body = PALETTE[pair[0]]
		livery.stripe = _color_named(pair[1])
		livery.striped = true
	else:
		livery.body = PALETTE[names[rng.randi_range(0, names.size() - 1)]]
	return livery


## Every (body name, stripe name) a stripe may be painted in.
static func stripe_pairs() -> Array[Array]:
	if _pairs.is_empty():
		var stripes := PALETTE.duplicate()
		stripes.merge(STRIPE_ONLY)
		for body_name: String in PALETTE:
			for stripe_name: String in stripes:
				if stands_out(PALETTE[body_name], stripes[stripe_name]):
					_pairs.append([body_name, stripe_name])
	return _pairs


## Whether [param stripe_color] reads clearly on [param body_color].
static func stands_out(body_color: Color, stripe_color: Color) -> bool:
	if contrast_ratio(body_color, stripe_color) < CONTRAST:
		return false
	if _is_grey(body_color) or _is_grey(stripe_color):
		return true
	var gap := absf(body_color.h - stripe_color.h)
	return minf(gap, 1.0 - gap) >= MIN_HUE_GAP


## WCAG's contrast ratio between two colours: 1 for the same, 21 for black on white.
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b


static func _is_grey(color: Color) -> bool:
	return color.s < 0.15


## "blue with a white stripe", "green"; "custom" for a colour not in the palette.
func label() -> String:
	var text := _name_of(body)
	return "%s with a %s stripe" % [text, _name_of(stripe)] if striped else text


static func _name_of(color: Color) -> String:
	for key: String in PALETTE:
		if (PALETTE[key] as Color).is_equal_approx(color):
			return key
	for key: String in STRIPE_ONLY:
		if (STRIPE_ONLY[key] as Color).is_equal_approx(color):
			return key
	return "custom"


static func _color_named(color_name: String) -> Color:
	return PALETTE[color_name] if PALETTE.has(color_name) else STRIPE_ONLY[color_name]
