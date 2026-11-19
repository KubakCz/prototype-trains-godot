class_name TrackMaterials
extends RefCounted
## The handful of materials every generated track and structure mesh shares:
## steel, timber, ballast, stone and the dark of a tunnel bore. One instance of
## each per run, so a whole level's track is a few materials however many chunks
## it is cut into.
##
## Colour comes from the vertices - a rusty rail side against a polished head,
## sleepers that are not all the same brown, ballast that fades into the grass -
## and the texture only adds grain, mapped in world space so neighbouring chunks
## and overlapping beds line up.

static var _metal: StandardMaterial3D
static var _wood: StandardMaterial3D
static var _ballast: StandardMaterial3D
static var _stone: StandardMaterial3D
static var _bore: StandardMaterial3D


static func metal() -> StandardMaterial3D:
	if _metal == null:
		_metal = _vertex_coloured(0.45)
		_metal.metallic = 0.65
		_metal.metallic_specular = 0.6
	return _metal


static func wood() -> StandardMaterial3D:
	if _wood == null:
		_wood = _vertex_coloured(0.9)
		_wood.albedo_texture = _grain(0.9, 0.2, 0.25)
		_wood.uv1_scale = Vector3(0.5, 0.5, 0.5)
		_world_mapped(_wood)
	return _wood


static func ballast() -> StandardMaterial3D:
	if _ballast == null:
		_ballast = _vertex_coloured(1.0)
		_ballast.albedo_texture = _grain(0.8, 0.45, 0.35)
		_ballast.uv1_scale = Vector3(1.5, 1.5, 1.5)
		_world_mapped(_ballast)
	return _ballast


static func stone() -> StandardMaterial3D:
	if _stone == null:
		_stone = _vertex_coloured(0.95)
		_stone.albedo_texture = _grain(1.0, 0.35, 0.12)
		_stone.uv1_scale = Vector3(0.25, 0.25, 0.25)
		_world_mapped(_stone)
	return _stone


## Unshaded, so the inside of a tunnel stays dark whatever the sun is doing; the
## vertex colours fade it to black a few metres in.
static func bore() -> StandardMaterial3D:
	if _bore == null:
		_bore = StandardMaterial3D.new()
		_bore.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bore.vertex_color_use_as_albedo = true
		_bore.vertex_color_is_srgb = true
		_bore.disable_receive_shadows = true
	return _bore


static func _vertex_coloured(roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	# Authored by eye, so sRGB - linear renders them far darker (see CLAUDE.md).
	material.vertex_color_is_srgb = true
	material.roughness = roughness
	return material


static func _world_mapped(material: StandardMaterial3D) -> void:
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true


## A grey noise texture multiplied over the vertex colour, mapped triplanar in
## world space by [method _world_mapped]: no UVs to generate, and seamless
## across chunk boundaries and between overlapping beds.
static func _grain(brightness: float, contrast: float, frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = frequency
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	var low := brightness - contrast * 0.5
	var high := minf(brightness + contrast * 0.5, 1.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(low, low, low))
	ramp.set_color(1, Color(high, high, high))
	texture.color_ramp = ramp
	return texture
