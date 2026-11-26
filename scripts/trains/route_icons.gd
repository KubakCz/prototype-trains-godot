class_name RouteIcons
extends Node3D
## The first of the two ways a train's route is shown: a row of flat icons floating over
## the locomotive, one for each stop still to come - a circle for a station, a square for
## a connection, in the colour of the point - with the next stop the bigger one, at the
## end of the row the nose points to on screen.
##
## The icons are billboards: they always face the camera and keep one size on screen,
## sized in interface pixels like the station badges ([InterestPointWidget]), so they
## grow with the UI scale and do not shrink to nothing as the camera pulls back.
##
## Belongs to its [Train] as an internal child and is placed from it every frame. The
## other way is the route list ([RouteListPanel]); [member mode] picks between them,
## and only one is showing at a time.

enum Mode {
	## The icons over each train.
	ICONS,
	## The list panel, and nothing over the trains.
	LIST,
}

## Which way routes are shown. A debug panel row.
static var mode := Mode.ICONS

## An icon's size and the gap between two, in interface pixels at UI scale 1.
const ICON_PIXELS := 16.0
const GAP_PIXELS := 4.0
## The next stop is a little bigger than the rest.
const NEXT_SCALE := 1.35
## How high over the locomotive's rails the row floats, in metres.
const HEIGHT := 7.0

## The icons' textures are drawn at this size and scaled on screen.
const _TEXTURE_SIZE := 64
const _OUTLINE := 5

static var _circle: ImageTexture
static var _square: ImageTexture

var _train: Train
var _icons: Array[Sprite3D] = []
var _points: Array[InterestPoint] = []


func _ready() -> void:
	top_level = true


## Attaches to [param train] and builds the row for its route.
func follow(train: Train) -> void:
	_train = train
	refresh()


## Builds the icons again for the stops still to come.
func refresh() -> void:
	if _train == null:
		return
	for icon in _icons:
		remove_child(icon)
		icon.queue_free()
	_icons.clear()
	_points = _train.remaining_stops()
	for i in _points.size():
		var icon := Sprite3D.new()
		icon.name = "Stop%d" % i
		icon.texture = _texture(_points[i].is_square())
		icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		icon.fixed_size = true
		icon.no_depth_test = true
		icon.shaded = false
		icon.double_sided = true
		icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# Drawn after the rest of the scene's transparent things, the next stop last.
		icon.render_priority = 10 + (_points.size() - i)
		add_child(icon)
		_icons.append(icon)
	_place()


func _process(_delta: float) -> void:
	_place()


## Number of icons showing, for tests.
func icon_count() -> int:
	return _icons.size()


## The icons, the next stop first.
func icons() -> Array[Sprite3D]:
	return _icons


## The stop each icon stands for, in the same order.
func points() -> Array[InterestPoint]:
	return _points


## Where the row hangs: over the locomotive.
func anchor() -> Vector3:
	var cars := _train.cars()
	var under := cars[0].global_position if not cars.is_empty() else _train.global_position
	return under + Vector3.UP * HEIGHT


func _place() -> void:
	if _train == null or not is_inside_tree():
		return
	visible = mode == Mode.ICONS and not _train.derailed and not _icons.is_empty()
	if not visible:
		return
	global_position = anchor()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	# Metres per window pixel at distance one, so that a fixed-size sprite is an
	# exact number of interface pixels tall: the 3D view always renders at the
	# window's native size, and an interface pixel is the UI scale's worth of those.
	var window := get_window()
	var viewport_height := float(window.size.y)
	var ui_scale := window.content_scale_factor
	var metres_per_pixel := 2.0 * tan(deg_to_rad(camera.fov) * 0.5) / maxf(viewport_height, 1.0)
	# Which way the nose points on screen: the next stop goes on that end.
	var nose_side := 1.0
	var nose := _train.nose()
	if nose.rail != null and not camera.is_position_behind(global_position):
		var towards := camera.unproject_position(nose.rail.sample_position(nose.distance)) \
				- camera.unproject_position(_train.global_position)
		nose_side = -1.0 if towards.x < 0.0 else 1.0
	var sizes: Array[float] = []
	var row := 0.0
	for i in _icons.size():
		sizes.append(ICON_PIXELS * (NEXT_SCALE if i == 0 else 1.0))
		row += sizes[i] + (GAP_PIXELS if i > 0 else 0.0)
	# From the nose end of the row inwards, the row centred over the locomotive.
	var x := row * 0.5
	for i in _icons.size():
		var icon := _icons[i]
		var pixels := sizes[i]
		icon.pixel_size = pixels * ui_scale * metres_per_pixel / float(_TEXTURE_SIZE)
		# The offset is in texture pixels of this icon.
		var centre := x - pixels * 0.5
		icon.offset = Vector2(nose_side * centre * float(_TEXTURE_SIZE) / pixels, 0.0)
		icon.modulate = _points[i].color()
		x -= pixels + GAP_PIXELS


## A white shape with a dark rim, tinted per icon by [member Sprite3D.modulate].
static func _texture(square: bool) -> ImageTexture:
	if square and _square != null:
		return _square
	if not square and _circle != null:
		return _circle
	var size := _TEXTURE_SIZE
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	var rim := Color(0.12, 0.12, 0.14)
	for y in size:
		for x in size:
			var dx := absf(float(x) + 0.5 - half)
			var dy := absf(float(y) + 0.5 - half)
			# Distance in from the shape's edge, in pixels.
			var inside := half - maxf(dx, dy) if square else half - Vector2(dx, dy).length()
			var alpha := clampf(inside, 0.0, 1.0)
			var color := Color.WHITE if inside > float(_OUTLINE) else rim
			color.a = alpha
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	if square:
		_square = texture
	else:
		_circle = texture
	return texture
