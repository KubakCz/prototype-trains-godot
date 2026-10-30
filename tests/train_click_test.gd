extends TrainDemoCase
## Selecting a train the player's way: a left click on any of its cars, fed through
## the real input path so physics object picking is exercised for real. A click on
## empty ground clears the selection; a click on a signal leaves it alone.
##
## Needs a window - skipped under --headless. Run it with
## [code]tests/run.ps1 -Windowed[/code].

var _camera: Camera3D


func before_all() -> void:
	if not has_display():
		skip("no window (run with -Windowed)")


func before_each() -> void:
	await super.before_each()
	_camera = demo.get_node("CameraRig/Camera3D")
	# The express standing a little short of NorthOverrun, the camera close in.
	place_nose(express, north_line, north_overrun.signal_distance(), 30.0)
	express.throttle = 0
	var rig: CameraRig = demo.get_node("CameraRig")
	rig.position = express.global_position
	rig.yaw_degrees = -20.0
	rig.pitch_degrees = -35.0
	rig.zoom = 70.0
	rig._apply()


func after_each() -> void:
	Train.clear_selection()


func test_a_click_on_a_wagon_selects_the_train() -> void:
	await _settle()
	var coach := express.cars()[1]
	await click_at(_camera.unproject_position(_middle_of(coach)))
	assert_eq(Train.selected_train(), express, "clicking its coach selected the express")


func test_a_click_on_empty_ground_clears_the_selection() -> void:
	express.select()
	await _settle()
	var ground := express.global_position + Vector3(0.0, 0.0, 30.0)
	await click_at(_camera.unproject_position(ground))
	await physics_frames(2)
	assert_null(Train.selected_train(), "clicking the ground deselected it")


func test_a_click_on_a_signal_keeps_the_selection() -> void:
	express.select()
	await _settle()
	var before := north_overrun.aspect
	await click_at(_camera.unproject_position(north_overrun.click_target_position()))
	await physics_frames(2)
	assert_ne(north_overrun.aspect, before, "the click changed the signal")
	assert_eq(Train.selected_train(), express, "and left the express selected")


func _middle_of(car: TrainCar) -> Vector3:
	return car.global_transform * Vector3(0.0, car.height * 0.5, 0.0)


func _settle() -> void:
	await frames(3)
	await physics_frames(3)
