# State base class
# 
# this is intended to be used as an interface for specific implementations
# to extend from, because the StateMachine class does rely on a few key methods,
# but use is not required, and it could be instanced directly for a state that 
# is manually transitioned.
extends Reference

class_name State

signal is_complete(transition_key)

var context = {}

# call this to trigger StateMachine transition to next state
func complete(transition_key = null):
    emit_signal("is_complete", transition_key)

# for loading contextual values to resume an existing state
func load_context(saved_context):
    context = saved_context
    
# called from the StateMachine _process method    
func process(_delta, _owner):
    pass

# called from StateMachine._physics_process 
func physics_process(_delta, _owner):
    pass

# called from _input
func handle_input(_event, _owner):
    pass

# called when state is created
func init(_owner):
    pass

# called before transitioning to a new state
func exit(_owner):
    pass
