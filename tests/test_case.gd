# base class for tests run by run_tests.gd
extends RefCounted

var failures : Array[String] = []

# errors logged while the current test runs, shared with the runner. A test
# fails if it leaves any here, so expected errors must be claimed with
# assert_error.
var errors : Array[String] = []

func assert_eq(actual, expected, message : String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail("expected %s, got %s" % [var_to_str(expected), var_to_str(actual)], message)

func assert_true(value : bool, message : String = "") -> void:
	if !value:
		_fail("expected true", message)

func assert_false(value : bool, message : String = "") -> void:
	if value:
		_fail("expected false", message)

func assert_error(text : String) -> void:
	for i in errors.size():
		if text in errors[i]:
			errors.remove_at(i)
			return

	_fail("expected an error containing '%s'" % text, "")

func _fail(reason : String, message : String) -> void:
	failures.append(reason if message.is_empty() else "%s (%s)" % [reason, message])
