# StateMachine
#
# a finite state machine that can be used by any object, including plain
# RefCounted models. It does not process on its own: call update(delta) (and
# physics_update/handle_input if your states use them) from whatever owns it,
# or use StateMachineNode, which does that for you in a scene.
extends RefCounted
class_name StateMachine

signal state_changed(new_state)

# use as a "next_state" or "transitions" target to go back to the state that
# was active before this one. The previous state's handler is resumed as-is.
const PREVIOUS = -1

const CONFIG_KEYS = ["next_state", "transitions", "state_class"]

# when true, each state class is only instanced once and reused every time its
# state is entered again
var cache_states : bool = false

# the object passed to every state hook, usually whatever owns the machine.
# Objects are held by weak reference so a subject that owns its state machine
# is not kept alive by it.
var subject:
	get:
		if _subject_ref:
			return _subject_ref.get_ref()
		return _subject_value
	set(value):
		if value is Object:
			_subject_ref = weakref(value)
			_subject_value = null
		else:
			_subject_ref = null
			_subject_value = value

var states : Dictionary = {}
var initial_state = null
var current_state_name = null
var current_state_handler = null
var previous_state_name = null
var previous_state_handler = null
var pending_transition = null
var initialized : bool = false

var _states_cache : Dictionary = {}
var _subject_ref : WeakRef = null
var _subject_value = null

func _init(subject_value = null) -> void:
	subject = subject_value

# states_config is either an enum, or a Dictionary of state id => config:
#   {
#       "state_class": a State class to instance while in this state (optional),
#       "next_state": the state to go to when complete() is called (optional),
#       "transitions": { transition_key: state id } for complete(key) (optional),
#   }
# initial_state_value defaults to the first state.
func configure(states_config : Dictionary, initial_state_value = null) -> void:
	states = {}
	_states_cache = {}

	for key in states_config:
		var value = states_config[key]
		if value is Dictionary:
			states[key] = value
		elif key is String and value is int:
			# an enum was passed straight in, so its values are the state ids
			states[value] = {}
		else:
			push_error("StateMachine.configure: config for state %s must be a Dictionary" % str(key))

	if initial_state_value == null and !states.is_empty():
		initial_state_value = states.keys()[0]
	initial_state = initial_state_value

	_validate_config()

# enter the initial state. update() does this automatically on its first call.
func transition_to_initial_state() -> void:
	transition_to_state_now(initial_state)

func update(delta : float) -> void:
	if !initialized:
		transition_to_initial_state()

	_apply_pending_transition()

	if current_state_handler and current_state_handler.has_method("process"):
		current_state_handler.process(delta, subject)

func physics_update(delta : float) -> void:
	if current_state_handler and current_state_handler.has_method("physics_process"):
		current_state_handler.physics_process(delta, subject)

func handle_input(event : InputEvent) -> void:
	if current_state_handler and current_state_handler.has_method("handle_input"):
		current_state_handler.handle_input(event, subject)

# queue a transition to state_name, applied on the next update. This replaces
# any transition already queued, including one queued by a completed state.
func transition_to(state_name) -> void:
	if !_is_previous(state_name) and !_require_state(state_name, "transition_to"):
		return

	pending_transition = state_name

# queue the transition configured for the current state, applied on the next
# update. With a transition_key, it uses that key from "transitions", otherwise
# it uses "next_state". This is what State.complete() calls.
#
# a transition that is already queued wins over this one.
func transition_to_next_state(transition_key = null) -> void:
	# this is often called externally before the first update
	if !initialized:
		transition_to_initial_state()

	if _has_pending_transition():
		return

	var config : Dictionary = states.get(current_state_name, {})

	if transition_key != null:
		var transitions : Dictionary = config.get("transitions", {})
		if !transitions.has(transition_key):
			push_error("StateMachine: state %s has no transition '%s' (available: %s)" % [str(current_state_name), str(transition_key), str(transitions.keys())])
			return

		pending_transition = transitions[transition_key]
	elif config.has("next_state"):
		pending_transition = config.next_state
	elif config.has("transitions"):
		push_error("StateMachine: state %s has no next_state, so it needs a transition key (available: %s)" % [str(current_state_name), str(config.transitions.keys())])
	# otherwise this is a final state, and completing it does nothing

# queue a return to the previous state, resuming its handler as-is
func transition_to_previous_state() -> void:
	if previous_state_name != null:
		pending_transition = PREVIOUS

# change state immediately, cancelling any queued transition. Pass PREVIOUS to
# go back to the previous state.
func transition_to_state_now(state_name) -> void:
	if _is_previous(state_name):
		_restore_previous_state()
	elif _require_state(state_name, "transition_to_state_now"):
		_enter_state(state_name)

func get_current_state():
	return current_state_name

func get_previous_state():
	return previous_state_name

func is_current_state(state_to_check) -> bool:
	return _same_state(current_state_name, state_to_check)

func get_current_state_context() -> Dictionary:
	if !current_state_handler:
		return {}

	return current_state_handler.context

func get_save_data() -> Dictionary:
	return {
		"current_state_name": current_state_name,
		"current_state_context": get_current_state_context(),
	}

# enter the saved state and restore its context. state_changed is emitted after
# the context is restored.
func load_state(state_data : Dictionary) -> void:
	if !state_data.has("current_state_name"):
		return

	var state_name = state_data.current_state_name
	if _require_state(state_name, "load_state"):
		_enter_state(state_name, state_data.get("current_state_context"))

func _enter_state(state_name, saved_context = null) -> void:
	# an explicit transition overrides any queued one
	pending_transition = null
	initialized = true

	# exit before anything changes, so the state still sees itself as current
	_exit_current_state()

	previous_state_name = current_state_name
	previous_state_handler = current_state_handler
	current_state_name = state_name
	current_state_handler = _get_handler(state_name)

	if current_state_handler:
		# connect before init so a state that completes right away is honored
		_connect_handler(current_state_handler)

		if current_state_handler.has_method("init"):
			current_state_handler.init(subject)

		if saved_context != null and current_state_handler.has_method("load_context"):
			current_state_handler.load_context(saved_context)

	state_changed.emit(current_state_name)

func _restore_previous_state() -> void:
	if previous_state_name == null or _same_state(previous_state_name, current_state_name):
		return

	pending_transition = null
	_exit_current_state()

	var restored_name = previous_state_name
	var restored_handler = previous_state_handler
	previous_state_name = current_state_name
	previous_state_handler = current_state_handler
	current_state_name = restored_name
	current_state_handler = restored_handler

	# the restored handler resumes where it left off, so init is not called
	if current_state_handler:
		_connect_handler(current_state_handler)

	state_changed.emit(current_state_name)

func _exit_current_state() -> void:
	if !current_state_handler:
		return

	# a state that is no longer current must not be able to trigger transitions
	_disconnect_handler(current_state_handler)

	if current_state_handler.has_method("exit"):
		current_state_handler.exit(subject)

func _get_handler(state_name):
	var state_class = states[state_name].get("state_class")
	if state_class == null:
		return null

	if !cache_states:
		return state_class.new()

	if !_states_cache.has(state_name):
		_states_cache[state_name] = state_class.new()

	return _states_cache[state_name]

func _connect_handler(handler) -> void:
	if handler.has_signal("is_complete") and !handler.is_connected("is_complete", _on_current_state_completed):
		handler.connect("is_complete", _on_current_state_completed)

func _disconnect_handler(handler) -> void:
	if handler.has_signal("is_complete") and handler.is_connected("is_complete", _on_current_state_completed):
		handler.disconnect("is_complete", _on_current_state_completed)

func _on_current_state_completed(transition_key) -> void:
	transition_to_next_state(transition_key)

func _apply_pending_transition() -> void:
	if !_has_pending_transition():
		pending_transition = null
		return

	var target = pending_transition
	pending_transition = null
	transition_to_state_now(target)

func _has_pending_transition() -> bool:
	return pending_transition != null and !_same_state(pending_transition, current_state_name)

# Godot 4 raises an error when comparing some types (like int and String), and
# PREVIOUS is an int even when state names are strings
func _same_state(a, b) -> bool:
	var comparable = typeof(a) == typeof(b) \
		or a == null or b == null \
		or ((a is int or a is float) and (b is int or b is float)) \
		or ((a is String or a is StringName) and (b is String or b is StringName))
	return comparable and a == b

func _is_previous(state_name) -> bool:
	return typeof(state_name) == TYPE_INT and state_name == PREVIOUS

func _require_state(state_name, caller : String) -> bool:
	if states.has(state_name):
		return true

	push_error("StateMachine.%s: unknown state %s (configured states: %s)" % [caller, str(state_name), str(states.keys())])
	return false

func _validate_config() -> void:
	if !states.is_empty() and !states.has(initial_state):
		push_error("StateMachine.configure: initial state %s is not one of the configured states" % str(initial_state))

	for state_name in states:
		var config : Dictionary = states[state_name]

		for key in config:
			if key == "transition_to":
				push_error("StateMachine.configure: state %s uses 'transition_to', which was removed in v2. Use 'next_state', or 'transitions' for keyed transitions" % str(state_name))
			elif key not in CONFIG_KEYS:
				push_error("StateMachine.configure: state %s has unknown config key '%s' (expected one of %s)" % [str(state_name), str(key), str(CONFIG_KEYS)])

		var targets = []
		if config.get("next_state") != null:
			targets.append(config.next_state)
		if config.has("transitions"):
			targets.append_array(config.transitions.values())

		for target in targets:
			if !_is_previous(target) and !states.has(target):
				push_error("StateMachine.configure: state %s transitions to unknown state %s" % [str(state_name), str(target)])
