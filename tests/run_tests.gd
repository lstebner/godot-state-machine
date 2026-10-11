# runs every test_* method in tests/test_*.gd
#   godot --headless --path . -s res://tests/run_tests.gd
extends SceneTree

const TEST_DIR = "res://tests/"

class ErrorCatcher extends Logger:
	var errors : Array[String] = []

	func _log_error(_function, _file, _line, code, rationale, _editor_notify, _error_type, _script_backtraces) -> void:
		errors.append("%s %s" % [code, rationale])

	func _log_message(_message, _error) -> void:
		pass

var has_run = false

# tests run on the first frame so nodes added to the tree get _ready
func _process(_delta) -> bool:
	if !has_run:
		has_run = true
		_run_tests()
	return false

func _run_tests() -> void:
	var catcher = ErrorCatcher.new()
	OS.add_logger(catcher)
	print("Tests that check error reporting print those errors below. They are expected.\n")

	var passed = 0
	var failed = 0

	for file in DirAccess.get_files_at(TEST_DIR):
		if !file.begins_with("test_") or !file.ends_with(".gd") or file == "test_case.gd":
			continue

		var script : Script = load(TEST_DIR + file)
		for method in script.get_script_method_list():
			if !method.name.begins_with("test_"):
				continue

			catcher.errors.clear()
			var test = script.new()
			test.errors = catcher.errors
			test.set_meta("tree", self)

			if test.has_method("before_each"):
				test.before_each()
			test.call(method.name)
			if test.has_method("after_each"):
				test.after_each()

			for error in catcher.errors:
				test.failures.append("unexpected error: %s" % error.strip_edges())

			if test.failures.is_empty():
				passed += 1
			else:
				failed += 1
				print("FAIL %s:%s" % [file, method.name])
				for failure in test.failures:
					print("    " + failure)

	print("\n%d passed, %d failed" % [passed, failed])
	OS.remove_logger(catcher)
	quit(1 if failed > 0 else 0)
