class_name TestCase
extends RefCounted
## Base class for a suite of tests. Subclass it, add [code]test_*[/code] methods,
## run them with [code]tests/run.ps1[/code].
##
## [codeblock]
## extends TestCase
##
## var _demo: Node
##
## func before_each() -> void:
##     _demo = await load_scene("res://scenes/demos/turnouts.tscn")
##
## func test_the_points_start_normal() -> void:
##     var west: Turnout = _demo.get_node("Turnouts/LoopWest")
##     assert_eq(west.turnout_position, Turnout.Position.NORMAL, "LoopWest starts normal")
## [/codeblock]
##
## Discovery, ordering, reporting and exit codes live in
## [code]tests/framework/test_runner.gd[/code]; how to run them is in
## [code]tests/README.md[/code].
##
## Two things differ from unittest or vitest:
##
## - [b]One instance per suite[/b], not per test. [method before_all] may stash
##   state in members, but nothing is reset between tests, so per-test state
##   belongs in [method before_each].
## - [b]A failed assertion does not abort the test.[/b] GDScript has no exceptions,
##   so every assertion records its verdict and returns it. Bail out by hand where
##   carrying on would be nonsense:
##   [code]if not assert_not_null(x, "..."): return[/code].
##
## Any hook or test may be a coroutine - [code]await[/code] whatever you need, the
## runner awaits the call.

## The tree the tests run in. Set by the runner before any hook is called; use it
## for [code]await tree.process_frame[/code] and friends, or the helpers below.
var tree: SceneTree

var _failures: Array[Dictionary] = []
var _notes: Array[String] = []
var _assertions := 0
var _skip_reason := ""
var _owned: Array[Node] = []
var _owned_mark := 0


#region Hooks
## Runs once before the suite's first test. Failing an assertion here, or calling
## [method skip], applies to the whole suite.
func before_all() -> void:
	pass


## Runs once after the suite's last test.
func after_all() -> void:
	pass


## Runs before every test in the suite.
func before_each() -> void:
	pass


## Runs after every test in the suite, pass or fail. Scenes taken with
## [method load_scene] are freed after this returns, so there is no need to free
## them here.
func after_each() -> void:
	pass
#endregion


#region Assertions
## Every assertion returns whether it held, records a failure if it did not, and
## lets the test carry on either way. [param what] is the claim being made, phrased
## so the report reads as a statement of fact: "the branch is welded to the points",
## not "check weld".
func assert_true(value: bool, what: String) -> bool:
	return _record(value, what, "expected true, got false")


func assert_false(value: bool, what: String) -> bool:
	return _record(not value, what, "expected false, got true")


func assert_eq(actual: Variant, expected: Variant, what: String) -> bool:
	return _record(actual == expected, what,
			"expected %s, got %s" % [_show(expected), _show(actual)])


func assert_ne(actual: Variant, unexpected: Variant, what: String) -> bool:
	return _record(actual != unexpected, what,
			"expected anything but %s" % _show(unexpected))


## The float assertion this project actually needs: distances along a rail are
## never exact, so say how close is close enough.
func assert_near(actual: float, expected: float, tolerance: float, what: String) -> bool:
	return _record(absf(actual - expected) <= tolerance, what,
			"expected %.4f +/- %.4f, got %.4f (off by %.4f)"
			% [expected, tolerance, actual, absf(actual - expected)])


func assert_less(actual: float, limit: float, what: String) -> bool:
	return _record(actual < limit, what, "expected < %.4f, got %.4f" % [limit, actual])


func assert_greater(actual: float, limit: float, what: String) -> bool:
	return _record(actual > limit, what, "expected > %.4f, got %.4f" % [limit, actual])


func assert_between(actual: float, low: float, high: float, what: String) -> bool:
	return _record(actual >= low and actual <= high, what,
			"expected %.4f to %.4f, got %.4f" % [low, high, actual])


func assert_null(value: Variant, what: String) -> bool:
	return _record(value == null, what, "expected null, got %s" % _show(value))


func assert_not_null(value: Variant, what: String) -> bool:
	return _record(value != null, what, "expected something, got null")


## Fails outright. [param detail] is the "expected x, got y" half of the report.
func fail(what: String, detail := "") -> bool:
	return _record(false, what, detail)


## Records a claim that held without an assertion of its own, so it still counts.
func succeed(what: String) -> bool:
	return _record(true, what, "")
#endregion


#region Output
## A line of context printed under the test and kept in the JSON report. This is
## where the numbers go - the gap in millimetres, the position of the train - so a
## human reading a passing run still sees what happened.
func note(text: String) -> void:
	_notes.append(text)


## Marks the test (or, from [method before_all], the whole suite) as not applicable
## rather than failing it - no window for a click test, say. Return straight after
## calling it; nothing else stops the test.
func skip(reason: String) -> void:
	_skip_reason = reason
#endregion


#region Helpers
## Instantiates a scene, adds it to the tree, lets it settle for two physics frames
## and hands it back. It is freed automatically after the test.
##
## Physics frames rather than idle frames because the runner speeds the clock up by
## stepping physics more often per idle frame: waiting on [signal SceneTree.process_frame]
## would advance the simulation by however many steps happened to fit, and a scene
## would start each run somewhere slightly different.
func load_scene(path: String) -> Node:
	var packed: PackedScene = load(path)
	if packed == null:
		fail("%s loads" % path, "load() returned null")
		return null
	var node := packed.instantiate()
	tree.root.add_child(node)
	_owned.append(node)
	await tree.physics_frame
	await tree.physics_frame
	return node


## Frees a node at the end of the test even though it did not come from
## [method load_scene]. Anything taken during [method before_all] lives until the
## suite ends instead, so a fixture built there survives every test in it.
func own(node: Node) -> Node:
	_owned.append(node)
	return node


## Waits [param count] idle frames.
func frames(count := 1) -> void:
	for _i in count:
		await tree.process_frame


## Waits [param count] physics frames. The runner speeds the clock up without
## changing the physics delta, so a frame count means the same thing however fast
## the suite runs - never measure simulation progress in wall-clock time.
func physics_frames(count := 1) -> void:
	for _i in count:
		await tree.physics_frame


## Whether the run has a window. Tests that feed synthetic clicks or read pixels
## need one, and should [method skip] themselves when it is missing.
func has_display() -> bool:
	return DisplayServer.get_name() != "headless"
#endregion


#region Runner interface
func _begin_test() -> void:
	_owned_mark = _owned.size()
	_failures.clear()
	_notes.clear()
	_assertions = 0
	_skip_reason = ""


func _take_result() -> Dictionary:
	return {
		"assertions": _assertions,
		"failures": _failures.duplicate(),
		"notes": _notes.duplicate(),
		"skipped": _skip_reason,
	}


## Frees what the test just took, leaving anything from [method before_all] alone.
func _release_owned() -> void:
	while _owned.size() > _owned_mark:
		var node: Node = _owned.pop_back()
		if is_instance_valid(node):
			node.queue_free()


## Frees the lot, once the suite is done with it.
func _release_all_owned() -> void:
	_owned_mark = 0
	_release_owned()
#endregion


func _record(ok: bool, what: String, detail: String) -> bool:
	_assertions += 1
	if not ok:
		_failures.append({"what": what, "detail": detail})
	return ok


## Formats a value for a failure line. Nodes print as [code]Turnout(LoopWest)[/code]
## rather than as an object id, which is the difference between a readable report
## and a useless one.
static func _show(value: Variant) -> String:
	if value == null:
		return "null"
	# `as Object` on a bool or an int is a runtime error rather than null, so the
	# type has to be established before anything is cast.
	if value is Object:
		var node := value as Node
		if node != null:
			return "%s(%s)" % [_type_name(node), node.name]
		var object := value as Object
		return "%s#%d" % [_type_name(object), object.get_instance_id()]
	if value is float:
		return "%.4f" % value
	if value is String or value is StringName:
		return "\"%s\"" % value
	return str(value)


static func _type_name(object: Object) -> String:
	var script := object.get_script() as Script
	if script != null and not script.get_global_name().is_empty():
		return String(script.get_global_name())
	return object.get_class()
