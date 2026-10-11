extends "res://tests/test_case.gd"

enum S { A, B, C, D }

const STEP = 0.1

# subject that records the hooks called on it
class Recorder extends RefCounted:
	var log : Array[String] = []
	var machine : StateMachine

class RecordingState extends State:
	var label : String = "?"

	func init(subject) -> void:
		subject.log.append("init " + label)

	func process(_delta, subject) -> void:
		subject.log.append("process " + label)

	func exit(subject) -> void:
		subject.log.append("exit %s (current: %s)" % [label, str(subject.machine.get_current_state())])

class StateA extends RecordingState:
	func _init() -> void:
		label = "A"

class StateB extends RecordingState:
	func _init() -> void:
		label = "B"

class CompletesInInit extends State:
	func init(_subject) -> void:
		complete()

class CompletesInProcess extends State:
	func process(_delta, _subject) -> void:
		complete()

class Counter extends State:
	func init(_subject) -> void:
		context = { "count": 0 }

	func process(_delta, _subject) -> void:
		context.count += 1

var recorder : Recorder
var machine : StateMachine

func before_each() -> void:
	recorder = Recorder.new()
	machine = StateMachine.new(recorder)
	recorder.machine = machine

# configure

func test_configure_accepts_an_enum() -> void:
	machine.configure(S)
	machine.update(STEP)
	assert_eq(machine.states.keys(), [S.A, S.B, S.C, S.D])
	assert_eq(machine.get_current_state(), S.A)

func test_initial_state_defaults_to_first_state() -> void:
	machine.configure({ S.C: {}, S.A: {} })
	machine.update(STEP)
	assert_eq(machine.get_current_state(), S.C)

func test_configure_reports_unknown_targets() -> void:
	machine.configure({ S.A: { "next_state": S.B }, S.C: { "transitions": { "go": S.D } } })
	assert_error("transitions to unknown state 1")
	assert_error("transitions to unknown state 3")

func test_configure_reports_removed_transition_to_key() -> void:
	machine.configure({ S.A: { "transition_to": S.B }, S.B: {} })
	assert_error("'transition_to', which was removed in v2")

func test_configure_reports_unknown_keys() -> void:
	machine.configure({ S.A: { "transition": S.B }, S.B: {} })
	assert_error("unknown config key 'transition'")

func test_configure_reports_unknown_initial_state() -> void:
	machine.configure({ S.A: {} }, S.B)
	assert_error("initial state 1")

# starting

func test_first_update_enters_initial_state() -> void:
	machine.configure({ S.A: { "state_class": StateA } })
	assert_eq(machine.get_current_state(), null)

	machine.update(STEP)

	assert_eq(machine.get_current_state(), S.A)
	assert_eq(recorder.log, ["init A", "process A"])

func test_state_hooks_receive_subject() -> void:
	machine.configure({ S.A: { "state_class": StateA } })
	machine.update(STEP)
	assert_eq(recorder.log.size(), 2)

# completing states

func test_completed_state_transitions_on_next_update() -> void:
	machine.configure({ S.A: { "state_class": CompletesInProcess, "next_state": S.B }, S.B: {} })
	machine.update(STEP)
	assert_eq(machine.get_current_state(), S.A)

	machine.update(STEP)
	assert_eq(machine.get_current_state(), S.B)

func test_completing_in_init_is_honored() -> void:
	machine.configure({ S.A: { "state_class": CompletesInInit, "next_state": S.B }, S.B: {} })
	machine.transition_to_initial_state()

	machine.update(STEP)

	assert_eq(machine.get_current_state(), S.B)

func test_completing_with_a_key_uses_transitions() -> void:
	machine.configure({ S.A: { "transitions": { "left": S.B, "right": S.C } }, S.B: {}, S.C: {} })
	machine.transition_to_next_state("right")
	machine.update(STEP)
	assert_eq(machine.get_current_state(), S.C)

func test_completing_without_a_key_uses_next_state_alongside_transitions() -> void:
	machine.configure({ S.A: { "next_state": S.B, "transitions": { "skip": S.C } }, S.B: {}, S.C: {} })
	machine.transition_to_next_state()
	machine.update(STEP)
	assert_eq(machine.get_current_state(), S.B)

func test_unknown_transition_key_is_reported_and_ignored() -> void:
	machine.configure({ S.A: { "transitions": { "left": S.B } }, S.B: {} })
	machine.transition_to_next_state("up")
	machine.update(STEP)

	assert_error("has no transition 'up'")
	assert_eq(machine.get_current_state(), S.A)
	assert_eq(machine.pending_transition, null)

func test_completing_a_branching_state_without_a_key_is_reported() -> void:
	machine.configure({ S.A: { "transitions": { "left": S.B } }, S.B: {} })
	machine.transition_to_next_state()
	machine.update(STEP)

	assert_error("needs a transition key")
	assert_eq(machine.get_current_state(), S.A)
	# the machine still works afterwards
	machine.transition_to_next_state("left")
	machine.update(STEP)
	assert_eq(machine.get_current_state(), S.B)

func test_completing_a_final_state_does_nothing() -> void:
	machine.configure({ S.A: {} })
	machine.transition_to_next_state()
	machine.update(STEP)
	assert_eq(machine.get_current_state(), S.A)

func test_old_handler_cannot_trigger_transitions() -> void:
	machine.configure({ S.A: { "state_class": StateA, "next_state": S.C }, S.B: {}, S.C: {} })
	machine.update(STEP)
	var old_handler = machine.current_state_handler

	machine.transition_to_state_now(S.B)
	old_handler.complete()
	machine.update(STEP)

	assert_eq(machine.get_current_state(), S.B)

# explicit transitions

func test_unknown_state_is_reported_and_ignored() -> void:
	machine.configure({ S.A: {}, S.B: {} })
	machine.update(STEP)

	machine.transition_to_state_now(S.D)
	assert_error("transition_to_state_now: unknown state 3")
	machine.transition_to(S.D)
	assert_error("transition_to: unknown state 3")
	machine.update(STEP)

	assert_eq(machine.get_current_state(), S.A)

func test_transition_to_is_applied_on_next_update() -> void:
	machine.configure({ S.A: {}, S.B: {} })
	machine.update(STEP)
	machine.transition_to(S.B)
	assert_eq(machine.get_current_state(), S.A)

	machine.update(STEP)
	assert_eq(machine.get_current_state(), S.B)

func test_transition_now_overrides_queued_completion() -> void:
	machine.configure({ S.A: { "state_class": CompletesInProcess, "next_state": S.B }, S.B: {}, S.C: {} })
	machine.update(STEP) # A completes and queues B

	machine.transition_to_state_now(S.C)
	machine.update(STEP)

	assert_eq(machine.get_current_state(), S.C)

func test_transition_to_overrides_queued_completion() -> void:
	machine.configure({ S.A: { "state_class": CompletesInProcess, "next_state": S.B }, S.B: {}, S.C: {} })
	machine.update(STEP) # A completes and queues B

	machine.transition_to(S.C)
	machine.update(STEP)

	assert_eq(machine.get_current_state(), S.C)

func test_completion_does_not_override_queued_transition() -> void:
	machine.configure({ S.A: { "next_state": S.B }, S.B: {}, S.C: {} })
	machine.update(STEP)

	machine.transition_to(S.C)
	machine.transition_to_next_state()
	machine.update(STEP)

	assert_eq(machine.get_current_state(), S.C)

func test_transition_now_before_first_update_is_kept() -> void:
	machine.configure({ S.A: {}, S.B: {} })
	machine.transition_to_state_now(S.B)
	machine.update(STEP)
	assert_eq(machine.get_current_state(), S.B)

func test_exit_runs_while_state_is_still_current() -> void:
	machine.configure({ S.A: { "state_class": StateA }, S.B: { "state_class": StateB } })
	machine.update(STEP)
	recorder.log.clear()

	machine.transition_to_state_now(S.B)

	assert_eq(recorder.log, ["exit A (current: 0)", "init B"])

func test_state_changed_is_emitted_with_new_state() -> void:
	var changes = []
	machine.state_changed.connect(func(new_state): changes.append(new_state))
	machine.configure({ S.A: {}, S.B: {} })

	machine.update(STEP)
	machine.transition_to_state_now(S.B)

	assert_eq(changes, [S.A, S.B])

func test_string_state_names_work() -> void:
	machine.configure({ "idle": { "next_state": "walk" }, "walk": { "next_state": StateMachine.PREVIOUS } })
	machine.update(STEP)
	machine.transition_to_next_state()
	machine.update(STEP)
	assert_eq(machine.get_current_state(), "walk")

	machine.transition_to_next_state()
	machine.update(STEP)
	assert_eq(machine.get_current_state(), "idle")

# previous state

func test_previous_next_state_resumes_previous_handler() -> void:
	machine.configure({
		S.A: { "state_class": Counter },
		S.B: { "state_class": StateB, "next_state": StateMachine.PREVIOUS },
	})
	machine.update(STEP)
	machine.update(STEP)
	var counter = machine.current_state_handler

	machine.transition_to_state_now(S.B)
	machine.transition_to_next_state()
	machine.update(STEP)

	assert_eq(machine.get_current_state(), S.A)
	assert_eq(machine.get_previous_state(), S.B)
	assert_true(machine.current_state_handler == counter, "handler is resumed, not recreated")
	assert_eq(counter.context.count, 3, "init is not called again")
	assert_eq(recorder.log, ["init B", "exit B (current: 1)"])

func test_resumed_handler_can_complete() -> void:
	machine.configure({
		S.A: { "state_class": CompletesInProcess, "next_state": S.C },
		S.B: { "next_state": StateMachine.PREVIOUS },
		S.C: {},
	})
	machine.transition_to_initial_state()
	machine.transition_to_state_now(S.B)
	machine.transition_to_state_now(StateMachine.PREVIOUS)

	machine.update(STEP) # A completes and queues C
	machine.update(STEP)

	assert_eq(machine.get_current_state(), S.C)

func test_transition_to_previous_state_is_queued() -> void:
	machine.configure({ S.A: {}, S.B: {} })
	machine.update(STEP)
	machine.transition_to_state_now(S.B)

	machine.transition_to_previous_state()
	assert_eq(machine.get_current_state(), S.B)
	machine.update(STEP)

	assert_eq(machine.get_current_state(), S.A)

# cache

func test_states_are_recreated_without_cache() -> void:
	machine.configure({ S.A: { "state_class": StateA }, S.B: {} })
	machine.update(STEP)
	var first = machine.current_state_handler
	machine.transition_to_state_now(S.B)
	machine.transition_to_state_now(S.A)
	assert_false(machine.current_state_handler == first)

func test_states_are_reused_with_cache() -> void:
	machine.cache_states = true
	machine.configure({ S.A: { "state_class": StateA, "next_state": S.B }, S.B: {} })
	machine.update(STEP)
	var first = machine.current_state_handler
	machine.transition_to_state_now(S.B)
	machine.transition_to_state_now(S.A)
	assert_true(machine.current_state_handler == first)

	# the cached handler is connected again when re-entered
	first.complete()
	machine.update(STEP)
	assert_eq(machine.get_current_state(), S.B)

# save and load

func test_save_and_load_restores_state_and_context() -> void:
	machine.configure({ S.A: {}, S.B: { "state_class": Counter } })
	machine.transition_to_state_now(S.B)
	machine.update(STEP)
	machine.update(STEP)
	var save_data = machine.get_save_data()

	var loaded = StateMachine.new(recorder)
	loaded.configure({ S.A: {}, S.B: { "state_class": Counter } })
	var context_when_changed = []
	var record_context = func(_state): context_when_changed.append(loaded.get_current_state_context().duplicate())
	loaded.state_changed.connect(record_context)
	loaded.load_state(save_data)
	# the lambda captures loaded, so disconnect it to avoid a reference cycle
	loaded.state_changed.disconnect(record_context)
	loaded.update(STEP)

	assert_eq(loaded.get_current_state(), S.B)
	assert_eq(loaded.get_current_state_context(), { "count": 3 })
	assert_eq(context_when_changed, [{ "count": 2 }], "state_changed sees the loaded context")

func test_loading_unknown_state_is_reported() -> void:
	machine.configure({ S.A: {} })
	machine.load_state({ "current_state_name": S.D, "current_state_context": {} })
	assert_error("load_state: unknown state 3")
	assert_eq(machine.get_current_state(), null)

# subject

func test_subject_is_not_kept_alive_by_machine() -> void:
	var subject = RefCounted.new()
	var subject_ref = weakref(subject)
	machine.subject = subject
	subject = null
	assert_eq(subject_ref.get_ref(), null)

func test_subject_can_be_a_dictionary() -> void:
	machine.subject = { "speed": 3 }
	assert_eq(machine.subject, { "speed": 3 })

func test_is_current_state_handles_mismatched_types() -> void:
	machine.configure({ "idle": {} })
	machine.update(STEP)
	assert_true(machine.is_current_state("idle"))
	assert_true(machine.is_current_state(&"idle"))
	assert_false(machine.is_current_state(StateMachine.PREVIOUS))
	assert_false(machine.is_current_state(null))
