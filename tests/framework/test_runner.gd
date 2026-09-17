extends SceneTree
## Finds, runs and reports the suites under [code]res://tests[/code].
##
## Not meant to be typed out by hand - use [code]tests/run.ps1[/code] (or
## [code]tests/run.sh[/code]), which finds the Godot binary and passes everything
## through. The long form is:
##
## [codeblock]
## Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##     --script res://tests/framework/test_runner.gd -- [options] [filters]
## [/codeblock]
##
## Everything after the bare [code]--[/code] belongs to the runner:
##
## [codeblock]
## <filter>          run matching suites; "driving", "turnout_driving",
##                   "driving::held" or "::spanning" all work
## --list            list what would run and stop
## --json <path>     write a machine-readable report as well
## --speed <n>       run the clock n times faster (default 16)
## --quiet           result lines only, no per-test notes
## --color <when>    always, never, or auto - the default, which colours unless
##                   NO_COLOR is set (run.ps1 / run.sh turn it off when redirected)
## --help
## [/codeblock]
##
## A suite is any [code]*_test.gd[/code] under [code]res://tests[/code] whose
## script extends [TestCase]; a test is any [code]test_*[/code] method on it, run
## in declaration order. Shared fixtures live in [code]tests/support[/code] and are
## not collected, since they do not match the suffix.
##
## Exits 0 when everything passed or skipped, 1 on any failure, 2 on bad arguments.

const TESTS_ROOT := "res://tests"
const SUITE_SUFFIX := "_test.gd"

## Physics steps per second per unit of speed-up. The runner multiplies both
## [member Engine.physics_ticks_per_second] and [member Engine.time_scale] by the
## speed factor, which leaves the physics delta at exactly 1/60 s while stepping
## the simulation that many times faster than real time. Frame counts inside a test
## therefore mean the same thing at any speed.
const BASE_TICKS := 60

const _LABELS: Dictionary[String, String] = {
	"passed": "PASS", "failed": "FAIL", "skipped": "SKIP",
}

## Terminal styling, as SGR parameters. Only bold, faint and the eight colours a
## terminal theme is free to redefine, so the report reads the same on a light
## background as on a dark one, and a terminal that ignores faint loses shading
## rather than text.
const _STYLES: Dictionary[String, String] = {
	"suite": "1",      # bold: suite headers, and the names in the failure list
	"faint": "2",      # notes, counts, rules - everything that is context
	"good": "32",      # green
	"bad": "1;31",     # bold red
	"warn": "33",      # yellow
	"fault": "31",     # red: what a failed assertion said
}

const _STATUS_STYLES: Dictionary[String, String] = {
	"PASS": "good", "FAIL": "bad", "SKIP": "warn",
}

const _COLOUR_CHOICES: PackedStringArray = ["auto", "always", "never"]

var _filters: PackedStringArray = []
var _json_path := ""
var _speed := 16
var _quiet := false
var _list_only := false
var _colour_when := "auto"
## Resolved from [member _colour_when] once the arguments are in.
var _colour := false

var _suites: Array[Dictionary] = []
var _passed := 0
var _failed := 0
var _skipped := 0
## Suites that could not be run at all, as opposed to tests that failed.
var _errors := 0


func _initialize() -> void:
	if not _parse_arguments():
		quit(2)
		return
	_colour = _colour_enabled()
	_run()


func _run() -> void:
	var paths := _discover()
	var plan: Array[Dictionary] = []
	for path: String in paths:
		var entry := _plan_suite(path)
		if not (entry["tests"] as PackedStringArray).is_empty() or entry.has("error"):
			plan.append(entry)

	if _list_only:
		_print_plan(plan)
		quit(0)
		return

	if plan.is_empty():
		printerr("no tests matched %s" % " ".join(_filters))
		quit(2)
		return

	Engine.physics_ticks_per_second = BASE_TICKS * _speed
	Engine.time_scale = float(_speed)
	Engine.max_physics_steps_per_frame = maxi(8, 2 * _speed)

	var total := 0
	for entry: Dictionary in plan:
		total += (entry["tests"] as PackedStringArray).size()
	print(_paint("%d test%s in %d suite%s, clock x%d, %s"
			% [total, "" if total == 1 else "s", plan.size(),
			"" if plan.size() == 1 else "s", _speed,
			"headless" if DisplayServer.get_name() == "headless" else "windowed"], "faint"))

	var started := Time.get_ticks_msec()
	for entry: Dictionary in plan:
		await _run_suite(entry)
	var duration := Time.get_ticks_msec() - started

	_print_summary(duration)
	if not _json_path.is_empty():
		_write_json(duration)
	quit(1 if _failed + _errors > 0 else 0)


#region Running
func _run_suite(entry: Dictionary) -> void:
	var path: String = entry["path"]
	var report := {"path": path, "name": entry["name"], "tests": []}
	_suites.append(report)
	print("\n%s %s %s" % [_paint("===", "faint"),
			_paint(path.trim_prefix("res://"), "suite"), _paint("===", "faint")])

	if entry.has("error"):
		var message: String = entry["error"]
		print("  %s  %s" % [_paint("ERROR", "bad"), _paint(message, "fault")])
		report["error"] = message
		_errors += 1
		return

	var script: Script = entry["script"]
	var case := script.new() as TestCase
	case.tree = self

	case._begin_test()
	await _invoke(case, "before_all")
	var setup: Dictionary = case._take_result()
	var suite_skip: String = setup["skipped"]
	var setup_failures: Array = setup["failures"]
	if not setup_failures.is_empty():
		_print_name("before_all")
		_print_result("FAIL", setup, 0)
		report["tests"].append(_test_report("before_all", "failed", setup, 0))
		_failed += 1
		case._release_all_owned()
		return
	if not (setup["notes"] as Array).is_empty():
		_print_name("before_all")
		_print_result("PASS", setup, 0)

	for method: String in entry["tests"] as PackedStringArray:
		_print_name(method)
		var started := Time.get_ticks_msec()
		case._begin_test()
		if suite_skip.is_empty():
			await _invoke(case, "before_each")
			await _invoke(case, method)
			await _invoke(case, "after_each")
			case._release_owned()
			await process_frame
		else:
			case.skip(suite_skip)
		var result: Dictionary = case._take_result()
		var elapsed := Time.get_ticks_msec() - started

		var status := "passed"
		if not (result["failures"] as Array).is_empty():
			status = "failed"
			_failed += 1
		elif not (result["skipped"] as String).is_empty():
			status = "skipped"
			_skipped += 1
		else:
			_passed += 1
		_print_result(_LABELS[status], result, elapsed)
		report["tests"].append(_test_report(method, status, result, elapsed))

	case._begin_test()
	await _invoke(case, "after_all")
	var teardown: Dictionary = case._take_result()
	if not (teardown["failures"] as Array).is_empty():
		_print_name("after_all")
		_print_result("FAIL", teardown, 0)
		report["tests"].append(_test_report("after_all", "failed", teardown, 0))
		_failed += 1
	case._release_all_owned()
	await process_frame


## Hooks and tests may or may not be coroutines; awaiting the [method Object.call]
## covers both, because a suspended GDScript call hands back a signal to await and
## a plain one hands back its return value.
func _invoke(case: TestCase, method: String) -> void:
	await case.call(method)
#endregion


#region Discovery
func _discover() -> PackedStringArray:
	var found: PackedStringArray = []
	_scan(TESTS_ROOT, found)
	found.sort()
	return found


func _scan(directory: String, into: PackedStringArray) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		printerr("cannot read %s" % directory)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var path := directory.path_join(entry)
		if dir.current_is_dir():
			_scan(path, into)
		elif entry.ends_with(SUITE_SUFFIX):
			into.append(path)
		entry = dir.get_next()
	dir.list_dir_end()


## Loads one suite and works out which of its tests the filters ask for.
func _plan_suite(path: String) -> Dictionary:
	var suite := _suite_name(path)
	var plan := {"path": path, "name": suite, "tests": PackedStringArray()}
	var script := load(path) as Script
	if script == null:
		plan["error"] = "does not load as a script"
		return plan
	# Walked rather than instantiated: building one to ask what it is would leak
	# an orphan node for any suite that turned out not to be a TestCase.
	if not _extends_test_case(script):
		plan["error"] = "extends %s, not TestCase" % script.get_instance_base_type()
		return plan
	plan["script"] = script

	var seen: PackedStringArray = []
	var wanted: PackedStringArray = []
	for method: Dictionary in script.get_script_method_list():
		var method_name: String = method["name"]
		# get_script_method_list() walks up the script chain, so an inherited test
		# shows up twice; the first sighting is the most derived one.
		if not method_name.begins_with("test_") or seen.has(method_name):
			continue
		seen.append(method_name)
		if _wanted(suite, method_name):
			wanted.append(method_name)
	plan["tests"] = wanted
	return plan


func _extends_test_case(script: Script) -> bool:
	var current := script
	while current != null:
		if current.get_global_name() == &"TestCase":
			return true
		current = current.get_base_script()
	return false


func _suite_name(path: String) -> String:
	return path.get_file().trim_suffix(SUITE_SUFFIX)


## A filter is [code]suite[/code], [code]suite::test[/code] or [code]::test[/code],
## and both halves match on substrings, so [code]driving[/code] finds
## [code]turnout_driving_test.gd[/code] and [code]::held[/code] finds every test
## about being held at the points.
func _wanted(suite: String, method: String) -> bool:
	if _filters.is_empty():
		return true
	for filter: String in _filters:
		var suite_part := filter
		var method_part := ""
		var split := filter.find("::")
		if split >= 0:
			suite_part = filter.substr(0, split)
			method_part = filter.substr(split + 2)
		if not suite_part.is_empty() and not suite.containsn(suite_part):
			continue
		if not method_part.is_empty() and not method.containsn(method_part):
			continue
		return true
	return false
#endregion


#region Reporting
func _print_name(method: String) -> void:
	print("  %s %s" % [_paint("-", "faint"), method])


func _print_result(status: String, result: Dictionary, elapsed: int) -> void:
	if not _quiet:
		for line: String in result["notes"] as Array:
			print("        %s" % _paint(line, "faint"))
	print("    %s %s" % [_paint("%-4s" % status, _STATUS_STYLES[status]),
			_paint("%d assertions in %d ms" % [result["assertions"], elapsed], "faint")])
	var skipped: String = result["skipped"]
	if not skipped.is_empty():
		print("      %s" % _paint("~ %s" % skipped, "warn"))
	for failure: Dictionary in result["failures"] as Array:
		print("      %s" % _paint(_failure_line(failure), "fault"))


func _failure_line(failure: Dictionary) -> String:
	var detail: String = failure["detail"]
	if detail.is_empty():
		return "! %s" % failure["what"]
	return "! %s: %s" % [failure["what"], detail]


func _print_summary(duration: int) -> void:
	print("\n" + _paint("".lpad(70, "="), "faint"))
	var total := _passed + _failed + _skipped
	var tally := "%d tests: %s, %s, %s" % [total, _tally(_passed, "passed", "good"),
			_tally(_failed, "failed", "bad"), _tally(_skipped, "skipped", "warn")]
	if _errors > 0:
		tally += ", " + _paint("%d suite%s could not run"
				% [_errors, "" if _errors == 1 else "s"], "bad")
	print("%s   %s" % [tally, _paint("(%.1f s)" % (duration / 1000.0), "faint")])
	if _failed + _errors > 0:
		print("\n" + _paint("FAILED", "bad"))
		for suite: Dictionary in _suites:
			if suite.has("error"):
				print("  %s: %s" % [_paint(suite["path"], "suite"),
						_paint(suite["error"], "fault")])
			for test: Dictionary in suite["tests"] as Array:
				if test["status"] != "failed":
					continue
				print("  %s" % _paint("%s::%s"
						% [_suite_name(suite["path"]), test["name"]], "suite"))
				for failure: Dictionary in test["failures"] as Array:
					print("      %s" % _paint(_failure_line(failure), "fault"))
	# One stable line for whatever is reading the log rather than the report file.
	print("\nRESULT ok=%s tests=%d passed=%d failed=%d skipped=%d errors=%d duration_ms=%d"
			% ["true" if _failed + _errors == 0 else "false", total, _passed,
					_failed, _skipped, _errors, duration])


## One count in the summary line, coloured only when it has something to say -
## a zero is context, whatever it is counting.
func _tally(count: int, word: String, style: String) -> String:
	return _paint("%d %s" % [count, word], style if count > 0 else "faint")


func _test_report(method: String, status: String, result: Dictionary,
		elapsed: int) -> Dictionary:
	return {
		"name": method,
		"status": status,
		"duration_ms": elapsed,
		"assertions": result["assertions"],
		"failures": result["failures"],
		"notes": result["notes"],
		"skipped": result["skipped"],
	}


func _print_plan(plan: Array[Dictionary]) -> void:
	for entry: Dictionary in plan:
		if entry.has("error"):
			print("%s  %s" % [entry["path"], _paint("(%s)" % entry["error"], "fault")])
			continue
		for method: String in entry["tests"] as PackedStringArray:
			print("%s%s%s" % [_paint(entry["name"], "suite"), _paint("::", "faint"), method])


func _write_json(duration: int) -> void:
	var report := {
		"ok": _failed + _errors == 0,
		"duration_ms": duration,
		"totals": {
			"suites": _suites.size(),
			"tests": _passed + _failed + _skipped,
			"passed": _passed,
			"failed": _failed,
			"skipped": _skipped,
			"errors": _errors,
		},
		"suites": _suites,
	}
	var target := _json_path
	if not target.is_absolute_path():
		target = "res://".path_join(target)
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		printerr("cannot write %s: %s"
				% [target, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print(_paint("report written to %s" % target, "faint"))
#endregion


#region Colour
## Wraps [param text] in the codes for [param style], or hands it back untouched
## when colour is off. Pad before painting and never after: the escapes count
## towards a format's field width.
func _paint(text: String, style: String) -> String:
	if not _colour:
		return text
	return "\u001b[%sm%s\u001b[0m" % [_STYLES[style], text]


## Godot does no terminal detection of its own - [method print_rich] emits the
## same escapes into a pipe as into a console - so the decision is made here.
## [code]run.ps1[/code] and [code]run.sh[/code] pass [code]--color never[/code]
## when their own output is redirected, which covers the piped case; this covers
## the rest.
func _colour_enabled() -> bool:
	if _colour_when != "auto":
		return _colour_when == "always"
	if not OS.get_environment("NO_COLOR").is_empty():
		return false
	return OS.get_environment("TERM") != "dumb"
#endregion


#region Arguments
func _parse_arguments() -> bool:
	var args := OS.get_cmdline_user_args()
	var index := 0
	while index < args.size():
		var arg := args[index]
		var value := ""
		var equals := arg.find("=")
		if arg.begins_with("--") and equals > 0:
			value = arg.substr(equals + 1)
			arg = arg.substr(0, equals)
		match arg:
			"--help", "-h":
				_print_usage()
				return false
			"--list":
				_list_only = true
			"--windowed":
				# Acted on by run.ps1 / run.sh, which decide whether to pass
				# --headless to the engine. Accepted here so that spelling it
				# out is never an error.
				pass
			"--quiet":
				_quiet = true
			"--no-color", "--no-colour":
				_colour_when = "never"
			"--color", "--colour":
				var when: String = value if not value.is_empty() else _next(args, index)
				if value.is_empty():
					index += 1
				if not _COLOUR_CHOICES.has(when):
					printerr("--color wants always, never or auto")
					return false
				_colour_when = when
			"--json":
				_json_path = value if not value.is_empty() else _next(args, index)
				if value.is_empty():
					index += 1
			"--speed":
				var raw: String = value if not value.is_empty() else _next(args, index)
				if value.is_empty():
					index += 1
				if not raw.is_valid_int() or raw.to_int() < 1:
					printerr("--speed wants a whole number of times real time")
					return false
				_speed = raw.to_int()
			_:
				if arg.begins_with("-"):
					printerr("unknown option %s" % arg)
					_print_usage()
					return false
				_filters.append(arg)
		index += 1
	return true


func _next(args: PackedStringArray, index: int) -> String:
	if index + 1 >= args.size():
		return ""
	return args[index + 1]


func _print_usage() -> void:
	print("""usage: run.ps1 [options] [filters]

  <filter>        run matching suites or tests: "driving", "turnout_driving",
                  "driving::held" and "::spanning" all work
  --list          list what would run and stop
  --json <path>   also write a machine-readable report
  --speed <n>     run the clock n times faster than real time (default 16)
  --quiet         result lines only, no per-test notes
  --color <when>  always, never or auto (the default; honours NO_COLOR)
  --windowed      keep a window, so the click tests run too (or -Windowed)""")
#endregion
