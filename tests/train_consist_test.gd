extends TrainDemoCase
## What a train is made of, and the wagons following it: a locomotive and wagons
## end to end, the figures the physics runs on, and every car finding its own
## track through a crossover.


func test_a_train_is_its_cars_end_to_end() -> void:
	var cars := express.cars()
	note("%d cars, %.1f m: %s" % [cars.size(), express.train_length(),
			", ".join(cars.map(func(car: TrainCar) -> String: return car.car_type.label()))])
	assert_eq(cars.size(), 3, "the express is a locomotive and two coaches")
	assert_true(cars[0].car_type is LocomotiveType, "the locomotive leads")
	assert_near(express.train_length(), 16.0 + 2.0 * 15.0 + 2.0 * Train.COUPLING_GAP, 1e-4,
			"its length is every car plus the couplings between them")
	# On the straight every coupling gap is exactly as long as it should be.
	for i in cars.size() - 1:
		var rear := cars[i].global_transform * Vector3(0.0, 0.0, cars[i].length * 0.5)
		var front := cars[i + 1].global_transform * Vector3(0.0, 0.0, -cars[i + 1].length * 0.5)
		assert_near(rear.distance_to(front), Train.COUPLING_GAP, 0.01,
				"%s and %s are a coupling apart" % [cars[i].name, cars[i + 1].name])
	var nose := cars[0].global_transform * Vector3(0.0, 0.0, -cars[0].length * 0.5)
	var head := express.nose()
	assert_near(nose.distance_to(head.rail.sample_position(head.distance)), 0.0, 0.01,
			"the front of the locomotive is the train's nose")


## Mass-based, with brakes sized for the empty vehicle: load slows the start and the
## stop, length slows only the start.
func test_the_rates_come_from_the_consist() -> void:
	for train: Train in [express, loaded_freight, empty_freight]:
		note("%-13s %5.0f t (%3.0f carried)  accel %.3f  brake %.3f / %.3f m/s²" % [train.name,
				train.total_mass(), train.carried_mass(), train.acceleration_rate(),
				train.service_brake_rate(), train.full_brake_rate()])
	assert_near(express.total_mass(), 160.0, 1e-3, "the express weighs 160 t")
	assert_near(express.acceleration_rate(), 360.0 / 160.0, 1e-4, "traction over mass")
	assert_near(express.full_brake_rate(), 6.0, 1e-4, "every car brakes its own weight")
	assert_near(express.service_brake_rate(), 6.0 * Train.SERVICE_BRAKE, 1e-4,
			"a normal stop uses part of the full brake")

	assert_near(loaded_freight.total_mass(), 110.0 + 4.0 * (22.0 + 60.0), 1e-3,
			"the loaded freight carries 240 t")
	assert_less(loaded_freight.acceleration_rate(), empty_freight.acceleration_rate(),
			"a full freight gets going slower than an empty one")
	assert_less(loaded_freight.full_brake_rate(), empty_freight.full_brake_rate(),
			"and stops slower, because a load adds weight but no brakes")

	var accel := express.acceleration_rate()
	express.add_wagon(express.wagons[0])
	note("with a third coach: %.0f t, accel %.3f, brake %.3f" % [express.total_mass(),
			express.acceleration_rate(), express.full_brake_rate()])
	assert_less(express.acceleration_rate(), accel, "another coach makes it slower to start")
	assert_near(express.full_brake_rate(), 6.0, 1e-4, "but stops it no worse")

	loaded_freight.load_factor = 0.0
	assert_near(loaded_freight.total_mass(), empty_freight.total_mass(), 1e-3,
			"unloaded, it is the empty freight")


## Couplings and uncouplings happen at the back: the nose stays where it was.
func test_a_wagon_is_coupled_on_behind() -> void:
	place(express, north_line, 100.0)
	var nose := express.nose().distance
	var length := express.train_length()
	express.add_wagon(express.wagons[0])
	note("added: nose %.3f -> %.3f, %.1f -> %.1f m" % [nose, express.nose().distance, length,
			express.train_length()])
	assert_near(express.nose().distance, nose, 1e-3, "the nose stays put when a coach is added")
	assert_near(express.train_length(), length + 15.0 + Train.COUPLING_GAP, 1e-3,
			"and the train is a coach longer")
	express.remove_wagon()
	express.remove_wagon()
	assert_near(express.nose().distance, nose, 1e-3, "and when two come off")
	assert_eq(express.cars().size(), 2, "leaving the locomotive and one coach")


## The wagons follow the locomotive through the points: every car sits on track the
## whole way across, the train stands on three rails at once in the middle of it,
## and the whole of it comes out on the other line.
func test_the_wagons_follow_it_across_the_crossover() -> void:
	crossover.cycle()
	place_nose(express, north_line, north_points.points_distance(), 20.0, 10.0)
	var rails: Array[Rail] = [north_line, link, middle_line]
	var worst := 0.0
	var spanned_all := false
	for _frame in 480:
		await drive(1)
		for car in express.cars():
			worst = maxf(worst, _off_track(car.global_position, rails))
		var on: Array[Rail] = []
		for span in express.occupied_spans():
			if not on.has(span.rail):
				on.append(span.rail)
		spanned_all = spanned_all or on.size() == 3
	note("furthest any car got from the track: %.3f m" % worst)
	note("at the end: %s" % state(express))
	assert_true(spanned_all, "at one point the train stood on all three rails")
	# A car is the chord between its two ends, so on the link's S-bend its middle
	# sits inside the curve by length² / 8R - half a metre at the most.
	assert_less(worst, 0.7, "every car stayed on the track the whole way across")
	for car in express.cars():
		assert_less(_off_track(car.global_position, [middle_line]), 0.01,
				"%s came out on the middle line" % car.name)
	assert_eq(express.rail, middle_line, "and so did the train")
	assert_false(express.derailed, "without derailing")


func _off_track(at: Vector3, rails: Array[Rail]) -> float:
	var nearest := INF
	for rail in rails:
		var local := rail.curve.get_closest_point(rail.to_local(at))
		nearest = minf(nearest, rail.to_global(local).distance_to(at))
	return nearest
