# State base class
#
# this is intended to be used as an interface for specific implementations
# to extend from. The StateMachine calls the hook methods below on the handler
# for the current state, so extending this class means you only need to
# override the ones you care about.
#
# every hook receives the state machine's `subject`, which is whatever object
# the machine is managing state for (usually the node that owns it).
extends RefCounted
class_name State

signal is_complete(transition_key)

# anything that should survive a save/load belongs in context
var context : Dictionary = {}

# call this to tell the StateMachine to move on to the next state. The
# transition happens on the machine's next update, not immediately.
func complete(transition_key = null) -> void:
	is_complete.emit(transition_key)

# for loading contextual values to resume an existing state
func load_context(saved_context : Dictionary) -> void:
	context = saved_context

# called when the state is entered. It is safe to call complete() from here.
func init(_subject) -> void:
	pass

# called from StateMachine.update
func process(_delta : float, _subject) -> void:
	pass

# called from StateMachine.physics_update
func physics_process(_delta : float, _subject) -> void:
	pass

# called from StateMachine.handle_input
func handle_input(_event : InputEvent, _subject) -> void:
	pass

# called when the machine leaves this state, before the next state's init
func exit(_subject) -> void:
	pass
