extends StationsDemoCase
## Engine liveries: a few well-known colours, a stripe only where it stands out, and a
## locomotive painted without the wagons behind it changing.


static func _hue_gap(a: Color, b: Color) -> float:
	var gap := absf(a.h - b.h)
	return minf(gap, 1.0 - gap)


func test_the_palette_has_no_two_shades_of_one_colour() -> void:
	var names: Array = Livery.PALETTE.keys()
	assert_between(float(names.size()), 6.0, 10.0, "a handful of well-known colours: %s" % [names])
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Color = Livery.PALETTE[names[i]]
			var b: Color = Livery.PALETTE[names[j]]
			if a.s < 0.15 or b.s < 0.15:
				continue
			assert_greater(_hue_gap(a, b), 0.05, "%s and %s are different colours, not shades" % [
					names[i], names[j]])


func test_every_stripe_stands_out_from_its_body() -> void:
	var pairs := Livery.stripe_pairs()
	assert_greater(float(pairs.size()), 12.0, "there are plenty of striped liveries to choose from")
	var bodies := {}
	for pair in pairs:
		var body: Color = Livery.PALETTE[pair[0]]
		var stripe: Color = Livery._color_named(pair[1])
		bodies[pair[0]] = true
		assert_greater(Livery.contrast_ratio(body, stripe), Livery.CONTRAST - 0.001,
				"%s with a %s stripe has the contrast" % [pair[0], pair[1]])
		assert_ne(pair[0], pair[1], "a stripe is never the colour of the body")
		assert_false(Livery.STRIPE_ONLY.has(pair[0]), "no body is a stripe-only colour")
	assert_eq(bodies.size(), Livery.PALETTE.size(), "every colour can carry a stripe")


func test_yellow_on_white_is_not_a_livery() -> void:
	assert_false(Livery.stands_out(Livery.PALETTE["white"], Livery.PALETTE["yellow"]),
			"yellow on white does not read")
	assert_true(Livery.stands_out(Livery.PALETTE["blue"], Livery.PALETTE["white"]),
			"white on blue does")
	assert_false(Livery.stands_out(Livery.PALETTE["red"], Livery.PALETTE["pink"]),
			"pink on red is the same colour twice")


func test_random_liveries_are_plain_or_striped_from_the_palette() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var striped := 0
	for i in 400:
		var livery := Livery.random(rng)
		assert_true(Livery.PALETTE.values().has(livery.body), "the body is a palette colour")
		if livery.striped:
			assert_ne(livery.body, livery.stripe, "a stripe is not its body's colour")
			striped += 1
			assert_true(Livery.stands_out(livery.body, livery.stripe), "the stripe stands out")
	note("%d of 400 striped" % striped)
	assert_between(float(striped), 140.0, 260.0, "about half are striped")


func test_a_livery_describes_itself() -> void:
	var livery := Livery.new()
	livery.body = Livery.PALETTE["blue"]
	assert_eq(livery.label(), "blue", "plain")
	livery.striped = true
	livery.stripe = Livery.PALETTE["white"]
	assert_eq(livery.label(), "blue with a white stripe", "striped")


func test_only_the_locomotive_is_painted() -> void:
	var train := make_train(express_type, north_main, 100.0, 1, stops([east_gate]))
	var wagon_blue := train.body_color()
	var livery := Livery.new()
	livery.body = Livery.PALETTE["red"]
	livery.striped = true
	livery.stripe = Livery.PALETTE["white"]
	train.livery = livery
	await physics_frames(2)
	assert_eq(train.engine_color(), Livery.PALETTE["red"], "the engine is red")
	assert_eq(train.body_color(), wagon_blue, "the wagons are as they were")
	var cars := train.cars()
	assert_not_null(cars[0].get_node_or_null("Stripe"), "the engine has a stripe")
	assert_true((cars[0].get_node("Stripe") as MeshInstance3D).visible, "showing")
	assert_eq(((cars[0].get_node("Stripe") as MeshInstance3D).material_override as StandardMaterial3D).albedo_color,
			Livery.PALETTE["white"], "in the stripe colour")
	assert_null(cars[1].get_node_or_null("Stripe"), "and no wagon does")
	livery.striped = false
	await physics_frames(2)
	assert_false((cars[0].get_node("Stripe") as MeshInstance3D).visible, "a plain livery hides the stripe")


func test_a_selected_engine_is_lightened_and_a_wreck_goes_grey() -> void:
	var train := make_train(express_type, north_main, 100.0, 1, stops([east_gate]))
	var livery := Livery.new()
	livery.body = Livery.PALETTE["green"]
	train.livery = livery
	await physics_frames(2)
	var plain := train.engine_color()
	train.select()
	assert_greater(train.engine_color().get_luminance(), plain.get_luminance(), "selected, it is lighter")
	assert_greater(train.body_color().get_luminance(), Color(0.16, 0.32, 0.52).get_luminance(),
			"and so are the wagons")
	train.derail("test")
	assert_eq(train.engine_color(), train.body_color(), "a wreck is grey all through")
	Train.clear_selection()


func test_a_train_without_a_livery_is_blue_all_through() -> void:
	var train := make_train(express_type, north_main, 100.0, 1, stops([east_gate]))
	await physics_frames(2)
	assert_eq(train.engine_color(), train.body_color(), "the engine matches the wagons")
	assert_null(train.cars()[0].get_node_or_null("Stripe"), "with no stripe")
