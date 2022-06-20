extends Node

signal state_changed(new_state)

class_name StateMachine

export var is_enabled : bool = true

var states : Dictionary = {}
var current_state = null
var current_state_name = null
var previous_state_name = null
var current_state_handler = null
var previous_state_handler = null
var initial_state = null
var transition_to = null
var initialized = false
var cache_states = false

const PREVIOUS = -1

var states_cache : Dictionary = {}

func _process(delta):
    if !is_enabled: return
    
    if !initialized:
        transition_to_initial_state()
        return
        
    if transition_to != null and transition_to != current_state_name:
        if transition_to == PREVIOUS:
            restore_previous_state()
        elif states.has(transition_to):
            transition_to_state(transition_to)
        else:
            current_state_name = null
            current_state_handler = null
            
        transition_to = null
    
    if current_state_handler and current_state_handler.has_method("process"):
        current_state_handler.process(delta, owner)

func _physics_process(delta):
    if current_state_handler and current_state_handler.has_method("physics_process"):
        current_state_handler.physics_process(delta, owner)
        
func _input(event):
    if current_state_handler and current_state_handler.has_method("handle_input"):
        current_state_handler.handle_input(event, owner) 

func configure(states_obj = {}, initial_state_value = 0):
    # this loop supports states_obj either being an enum passed straight in,
    # or a custom configured object to support autonomy in state changes
    for key in states_obj.keys():
        if states_obj[key] is Dictionary:
            if states_obj[key].has("transition"): # check for commonly made typo
                print("StateMachine.configure warning - %s configuration has property 'transition' instead of 'transitions'" % owner.name)
            states[key] = states_obj[key]
        else:
            states[states_obj[key]] = {}
    
    initial_state = initial_state_value

func transition_to_initial_state():
    initialized = true
    transition_to_state(initial_state)
    
func transition_to_next_state(transition_key = null):
    if transition_to != null and transition_to != current_state_name: return
    
    if current_state.has("next_state"):
        transition_to = current_state.next_state
    elif current_state.has("transitions") and current_state.transitions.has(transition_key):
        transition_to = current_state.transitions[transition_key]
    elif current_state.has("transition_to"): # DEPRECATED - left for backwards compatibility
        print("state configuration using 'transition_to' is deprecated, please update to use 'next_state' or 'transitions'")
        if transition_key and current_state.transition_to.has(transition_key):
            transition_to = current_state.transition_to[transition_key]
        else:
            transition_to = current_state.transition_to
        

func transition_to_previous_state():
    if previous_state_name:
        transition_to = previous_state_name
    
func get_current_state():
    return current_state_name
    
func set_current_state(name):
    current_state_name = name
    current_state = states[current_state_name]
    
func get_previous_state():
    return previous_state_name
    
func get_current_state_context():
    if !current_state_handler: return {}
    
    return current_state_handler.context
    
func get_save_data():
    return {
        "current_state_name": current_state_name,
        "current_state_context": get_current_state_context(),
    }
    
func load_state(state_data):
    if !state_data.has("current_state_name"): return
    
    transition_to_state(state_data.current_state_name)

    if current_state_handler and current_state_handler.has_method("load_context"):
        current_state_handler.load_context(state_data.current_state_context)
    
func is_current_state(state_to_check):
    return get_current_state() == state_to_check

func _on_current_state_completed(transition_key):
    transition_to_next_state(transition_key)

func restore_previous_state():
    if !previous_state_name or previous_state_name == current_state_name: return
    
    set_current_state(previous_state_name)
    current_state_handler = previous_state_handler

    emit_signal("state_changed", current_state_name)

func transition_to(state_name):
    transition_to = state_name
    
func transition_to_state(state_name):
    # store for ability to go back one layer, this could later become a stack for a
    # lot more flexibility, but so far it has not been needed
    previous_state_name = current_state_name
    previous_state_handler = current_state_handler
    
    # after previous state info is stored, set the current state
    set_current_state(state_name)
    
    # let the current state exit if it wants
    if current_state_handler and current_state_handler.has_method("exit"):
        current_state_handler.exit(owner)
    
    # instance handler for current state if there is one
    if current_state.has("state_class") and current_state.state_class != null:
        if cache_states == false or states_cache.has(state_name) == false:
            states_cache[state_name] = current_state.state_class.new()
            
        current_state_handler = states_cache[state_name]
        
        # call init on the new state if it has one
        if current_state_handler.has_method("init"):
            current_state_handler.init(owner)
    
        # connect events to current state
        if !current_state_handler.is_connected("is_complete", self, "_on_current_state_completed"):
            current_state_handler.connect("is_complete", self, "_on_current_state_completed")
    else:
        current_state_handler = null
    
    emit_signal("state_changed", current_state_name)
