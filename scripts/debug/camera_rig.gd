class_name CameraRig
extends Node3D
## Orbit camera for looking at the prototype.
##
## Right mouse drag orbits, middle drag or WASD pans, wheel zooms. Debug-only;
## the real game will want a constrained top-down dispatcher view.

@export var camera: Camera3D

@export_group("Orbit")
@export var yaw_degrees := -35.0
@export var pitch_degrees := -38.0
@export var min_pitch_degrees := -89.0
@export var max_pitch_degrees := -5.0
@export var orbit_sensitivity := 0.4

@export_group("Zoom")
@export var zoom := 70.0
@export var min_zoom := 6.0
@export var max_zoom := 400.0
@export var zoom_step := 1.12

@export_group("Pan")
## Metres per second at the reference zoom. Panning scales with zoom so it feels
## the same whether you are looking at a whole level or a single turnout.
@export var pan_speed := 30.0
@export var drag_pan_sensitivity := 0.06


func _ready() -> void:
	_apply()


func _process(delta: float) -> void:
	var input := _pan_input()
	if input != Vector2.ZERO:
		_pan(input * pan_speed * delta * _zoom_scale())
		_apply()


## Physical keys rather than input actions: these are debug controls, and keeping
## them out of the InputMap leaves the project's action list for actual gameplay.
func _pan_input() -> Vector2:
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y += 1.0
	return input.normalized()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw_degrees -= motion.relative.x * orbit_sensitivity
			pitch_degrees -= motion.relative.y * orbit_sensitivity
			_apply()
		elif motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_pan(Vector2(-motion.relative.x, -motion.relative.y)
					* drag_pan_sensitivity * _zoom_scale())
			_apply()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom /= zoom_step
			_apply()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom *= zoom_step
			_apply()


## Moves the pivot in the camera's horizontal plane, so panning never changes
## height and the ground stays put under the cursor.
func _pan(amount: Vector2) -> void:
	var flat_forward := Vector3(-basis.z.x, 0.0, -basis.z.z)
	if flat_forward.length_squared() < 1e-6:
		flat_forward = Vector3.FORWARD
	flat_forward = flat_forward.normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	position += right * amount.x - flat_forward * amount.y


func _zoom_scale() -> float:
	const REFERENCE_ZOOM := 70.0
	return zoom / REFERENCE_ZOOM


func _apply() -> void:
	pitch_degrees = clampf(pitch_degrees, min_pitch_degrees, max_pitch_degrees)
	zoom = clampf(zoom, min_zoom, max_zoom)
	rotation = Vector3(deg_to_rad(pitch_degrees), deg_to_rad(yaw_degrees), 0.0)
	if camera != null:
		camera.position = Vector3(0.0, 0.0, zoom)
