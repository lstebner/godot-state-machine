extends "res://tests/test_case.gd"

enum S { A, B }

class CompletesInProcess extends State:
	func process(_delta, subject) -> void:
		subject.set_meta("processed", true)
		complete()

var parent : Node
var node : StateMachineNode

func before_each() -> void:
	parent = Node.new()
	node = StateMachineNode.new()
	parent.add_child(node)
	get_meta("tree").root.add_child(parent)

func after_each() -> void:
	parent.free()

func test_subject_defaults_to_parent() -> void:
	assert_true(node.subject == parent)

func test_process_drives_machine() -> void:
	node.configure({ S.A: { "state_class": CompletesInProcess, "next_state": S.B }, S.B: {} })
	node._process(0.1)
	node._process(0.1)

	assert_true(parent.has_meta("processed"))
	assert_eq(node.get_current_state(), S.B)

func test_disabled_node_does_not_process() -> void:
	node.configure({ S.A: {} })
	node.is_enabled = false
	node._process(0.1)
	assert_eq(node.get_current_state(), null)

func test_state_changed_is_forwarded() -> void:
	var changes = []
	node.state_changed.connect(func(new_state): changes.append(new_state))
	node.configure({ S.A: {}, S.B: {} })
	node.transition_to_state_now(S.B)
	assert_eq(changes, [S.B])

func test_scene_contains_state_machine_node() -> void:
	var instance = load("res://source/StateMachine.tscn").instantiate()
	assert_true(instance is StateMachineNode)
	instance.free()
