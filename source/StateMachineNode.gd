# StateMachineNode
#
# a Node wrapper around StateMachine for use in scenes. It drives the machine
# from _process, _physics_process and _input, and uses its owner (or its parent
# when it has no owner) as the machine's subject unless one is set.
extends Node
class_name StateMachineNode

signal state_changed(new_state)

@export var is_enabled : bool = true

var machine : StateMachine = StateMachine.new()

var cache_states : bool:
	get:
		return machine.cache_states
	set(value):
		machine.cache_states = value

var subject:
	get:
		return machine.subject
	set(value):
		machine.subject = value

func _init() -> void:
	machine.state_changed.connect(state_changed.emit)

func _ready() -> void:
	if machine.subject == null:
		machine.subject = owner if owner else get_parent()

func _process(delta : float) -> void:
	if is_enabled:
		machine.update(delta)

func _physics_process(delta : float) -> void:
	if is_enabled:
		machine.physics_update(delta)

func _input(event : InputEvent) -> void:
	if is_enabled:
		machine.handle_input(event)

func configure(states_config : Dictionary, initial_state_value = null) -> void:
	machine.configure(states_config, initial_state_value)

func transition_to_initial_state() -> void:
	machine.transition_to_initial_state()

func transition_to(state_name) -> void:
	machine.transition_to(state_name)

func transition_to_next_state(transition_key = null) -> void:
	machine.transition_to_next_state(transition_key)

func transition_to_previous_state() -> void:
	machine.transition_to_previous_state()

func transition_to_state_now(state_name) -> void:
	machine.transition_to_state_now(state_name)

func get_current_state():
	return machine.get_current_state()

func get_previous_state():
	return machine.get_previous_state()

func is_current_state(state_to_check) -> bool:
	return machine.is_current_state(state_to_check)

func get_current_state_context() -> Dictionary:
	return machine.get_current_state_context()

func get_save_data() -> Dictionary:
	return machine.get_save_data()

func load_state(state_data : Dictionary) -> void:
	machine.load_state(state_data)
