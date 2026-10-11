# Migrating from v1 to v2

v2 is a clean break from v1. It moves to Godot 4, splits the state machine from the `Node` that runs it, removes deprecated configuration, and fixes several bugs that could leave the machine in a broken state. This document lists every difference. Godot 3 projects can keep using the [`v1.0`](https://github.com/lstebner/godot-state-machine/tree/v1.0) tag.

Most mistakes you can make while migrating are reported as errors when `configure` runs, or when a removed method is called, rather than failing quietly.

## Quick checklist

1. Make sure your project is on Godot 4.
2. Replace the `StateMachine` nodes in your scenes with `StateMachineNode` (or re-instance `StateMachine.tscn`).
3. Rename the `"transition_to"` config key to `"next_state"`, or to `"transitions"` for keyed transitions.
4. Rename `transition_to_state(...)` calls to `transition_to_state_now(...)`.
5. Replace calls to `restore_previous_state()`, `set_current_state()` and `_on_current_state_completed()` (see [Methods](#methods)).
6. Read [Behavior changes](#behavior-changes) for anything your game relied on.

## Godot 4

- v2 requires Godot 4 and was tested with 4.7.
- `State` extends `RefCounted` instead of `Reference`.
- Connect to signals with the Godot 4 syntax: `state_machine.state_changed.connect(_on_state_changed)`.

## StateMachine is no longer a Node

In v1, `StateMachine` extended `Node` and ran itself from `_process`, `_physics_process` and `_input`. In v2:

- `StateMachine` extends `RefCounted` and does nothing on its own. Call `update(delta)` on it, plus `physics_update(delta)` and `handle_input(event)` if your states use them. This lets objects that are not nodes, like data models, use it without having to add a node to the tree or free one.
- `StateMachineNode` is a new `Node` that owns a `StateMachine` and calls those methods from its own `_process`, `_physics_process` and `_input`. It has the same methods as `StateMachine`, plus a `machine` property for the machine itself. Use it wherever you used the v1 node.
- `StateMachine.tscn` now contains a `StateMachineNode`, and its script path is `res://source/StateMachineNode.gd`. If you keep the files somewhere else, update that path, or add a `StateMachineNode` from the "Add Child Node" dialog instead.
- `is_enabled` is now on `StateMachineNode` only. To pause a plain `StateMachine`, stop calling `update`.

| v1 | v2 |
|----|----|
| `StateMachine` (a `Node`) | `StateMachineNode` |
| `$StateMachine` node in a scene | a `StateMachineNode` in the scene |
| `StateMachine.new()` + `add_child()` | `StateMachine.new(subject)` + call `update(delta)`, or `StateMachineNode.new()` + `add_child()` |

## The subject replaces the owner

v1 passed the state machine node's `owner` to every state hook. v2 passes the machine's `subject` instead:

- `StateMachineNode` uses its `owner`, or its parent when it has no owner. A node added with `add_child` in script has no owner, so in v1 its states received `null`. In v2 they receive its parent.
- A plain `StateMachine` uses the value passed to `StateMachine.new(subject)`, or whatever you assign to `state_machine.subject`. It can be any object, or a non-object value like a Dictionary.
- Objects are held by weak reference, so an object that owns its machine and passes itself as the subject does not create a reference cycle.

Your state classes don't need to change for this unless they relied on receiving `null`.

## Configuration

| v1 | v2 |
|----|----|
| `"transition_to": STATE` | `"next_state": STATE` |
| `"transition_to": { "key": STATE }` | `"transitions": { "key": STATE }` |

- **The `"transition_to"` key is removed.** v1 printed a deprecation warning and still used it. v2 reports an error from `configure` and ignores it.
- **`configure` validates the configuration.** It reports unknown keys (like the `"transition"` typo v1 warned about), transitions to states that don't exist, and an initial state that doesn't exist.
- **The initial state defaults to the first state.** v1 defaulted to `0`, which was only right for enums.
- **`configure` replaces the states.** v1 added to the states from earlier `configure` calls. v2 starts fresh each time, and also clears the state cache.
- **`"next_state"` and `"transitions"` can be used together.** Completing without a key uses `"next_state"`, and completing with a key uses `"transitions"`. In v1, when both were present, `"next_state"` always won and the key was ignored.
- **`StateMachine.PREVIOUS` can be used as a `"transitions"` target**, not only as a `"next_state"`.

## Methods

| v1 | v2 | notes |
|----|----|-------|
| `transition_to_state(state)` | `transition_to_state_now(state)` | Renamed so it's clear it happens immediately. v1's README said it was queued, but it never was. It now also cancels any queued transition. |
| `transition_to(state)` | `transition_to(state)` | Unchanged, still queued. Now reports unknown states. |
| `transition_to_next_state(key)` | `transition_to_next_state(key)` | Unchanged, still queued. See error handling below. |
| `transition_to_previous_state()` | `transition_to_previous_state()` | Still queued, but now resumes the previous state like `PREVIOUS` does. v1 created a new handler for it. |
| `restore_previous_state()` | `transition_to_state_now(StateMachine.PREVIOUS)` | |
| `set_current_state(state)` | `transition_to_state_now(state)` | v1's method changed the state without calling `init`, `exit` or emitting `state_changed`. There's no v2 equivalent for that. |
| `_on_current_state_completed(key)` | `transition_to_next_state(key)` | They did the same thing. Use the public method. |
| `current_state` (config Dictionary) | `states[get_current_state()]` | |
| `transition_to` (variable) | `pending_transition` | In v1, a variable and a method had the same name. That's an error in Godot 4. |
| `states_cache` | private | Use `cache_states` to control caching. |
| | `update(delta)`, `physics_update(delta)`, `handle_input(event)` | New. Run a plain `StateMachine`. |
| | `subject` | New. See [The subject replaces the owner](#the-subject-replaces-the-owner). |

`get_current_state`, `get_previous_state`, `is_current_state`, `get_current_state_context`, `get_save_data`, `load_state`, `transition_to_initial_state`, `cache_states`, `PREVIOUS` and the `state_changed` signal keep their v1 names.

## State class

The hooks keep their v1 names: `init`, `process`, `physics_process`, `handle_input`, `exit`, `complete` and `load_context`. Their parameter is now called `subject` instead of `owner`, but that is only a name, so existing overrides keep working, including ones without type hints.

## Behavior changes

These are the changes most likely to affect a game that worked with v1. Most of them were bugs.

### Transitions

- **A direct transition cancels a queued one.** In v1, if a state completed and then `transition_to_state` was called in the same frame, the queued completion was still applied on the next update. That could undo the direct transition. For example, an enemy killed on the frame its attack finished could go back to attacking. In v2, `transition_to_state_now` cancels anything queued.
- **The first update also processes the initial state.** In v1, the first `_process` only entered the initial state and returned. In v2, the first `update` enters the initial state and then calls its `process` in the same update.
- **Changing state before the first update sticks.** In v1, calling `transition_to_state` or `load_state` before the machine's first `_process` didn't count as starting it, so the first `_process` then switched to the initial state anyway. In v2, any immediate transition starts the machine.
- **String state names work with `PREVIOUS`.** Godot 4 raises an error when comparing an int to a String, and `PREVIOUS` is `-1`. v2 compares state names safely, so `is_current_state` and the transition checks work with any type of state id.

### Entering and leaving states

- **`exit` runs before the state changes.** In v1, by the time the old state's `exit` was called, the machine already reported the new state. In v2, `exit` runs while the old state is still current, then the new state's `init` runs, then `state_changed` is emitted.
- **Calling `complete()` from `init` works.** In v1, the completion signal was connected after `init`, so a state that completed straight away never transitioned. In v2 the transition is queued like any other completion.
- **A state that's no longer current can't trigger transitions.** In v1, a handler stayed connected after the machine left it, so a late `complete()` (from a timer, say) could move the machine on from whatever state it was in by then. In v2, a handler is disconnected when the machine leaves it, and reconnected if it is resumed or reused from the cache.
- **Returning to the previous state calls `exit` on the state being left.** v1 skipped it.
- **After returning to the previous state, `get_previous_state()` is the state that was left.** In v1, it still pointed at the state the machine had just returned to.

### Errors

v1 often failed silently or left the machine half-broken. v2 reports every case below with `push_error` and leaves the machine in its current state:

| mistake | v1 | v2 |
|---------|----|----|
| queued transition to a state that isn't configured | cleared the current state name and handler, leaving the machine broken | error, state unchanged |
| immediate transition to a state that isn't configured | crashed | error, state unchanged |
| `load_state` with a state that isn't configured | crashed | error, state unchanged |
| `complete(key)` with a key that isn't in `"transitions"` | did nothing silently (with the deprecated `"transition_to"` key, it broke the machine) | error, state unchanged |
| `complete()` without a key on a state that only has `"transitions"` | did nothing silently (with `"transition_to"`, it broke the machine) | error, state unchanged |

### Saving and loading

- **`state_changed` is emitted after the saved context is restored.** In v1, listeners saw the new state with a fresh context and the saved context was restored afterwards.

## Migrating from an older copy

Some projects have a copy of the state machine from before v1, with an `enter`/`update` API and `set_the_owner`/`set_global_context`. To move those to v2:

| older copy | v2 |
|------------|----|
| `State.enter(owner_or_context)` | `State.init(subject)` |
| `State.update(delta)` | `State.process(delta, subject)` |
| `State.exit()` | `State.exit(subject)` |
| `state_machine._process(delta)` | `state_machine.update(delta)` |
| `set_the_owner(obj)` | `StateMachine.new(obj)` or `state_machine.subject = obj` |
| `set_global_context(dict)` | pass the object the states need as the subject, or pass the Dictionary itself |
| `transition_to_state(state)` | `transition_to_state_now(state)` |
| `"transition_to"` config key | `"next_state"` / `"transitions"` |
