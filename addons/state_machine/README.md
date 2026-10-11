# StateMachine

StateMachine is a Godot script class that implements a finite state machine for generic use. I built this for use in my own personal projects and am making it free to use for anyone else out there working on a game using Godot.

This is version 2, which requires **Godot 4** (tested with 4.7). The last version for Godot 3 is tagged [`v1.0`](https://github.com/lstebner/godot-state-machine/tree/v1.0). If you are upgrading from v1, see [MIGRATION.md](https://github.com/lstebner/godot-state-machine/blob/main/MIGRATION.md).

## When to use

There's already a lot of information written about when to use the state machine pattern that you should read. [Here is a great one I recommend](https://gameprogrammingpatterns.com/state.html).

If you're using Godot engine and a finite state machine is what you need for your situation, this is a great choice!

## How to use

There are two main parts to this, the `StateMachine`, and the `State`. The `StateMachine` keeps track of the current state and moves between states, while `State` is an interface meant to be extended by classes that implement states. Of course, Godot does not support a true interface, but that is the intention of the `State` class provided. The `StateMachine` requires a small amount of configuration, and then it does the rest on its own.

`StateMachine` is a plain `RefCounted` object, so it can be used by anything, including data models that are not nodes. For scenes, `StateMachineNode` wraps it in a `Node` that runs it automatically.

### Add the files to your project

Copy the `addons/state_machine/` folder from this repository into your project as `res://addons/state_machine/`. You can put the files somewhere else if you prefer: since they set a `class_name`, they can be globally referenced by name no matter where they are.

| file | what it is |
|------|------------|
| `StateMachine.gd` | the state machine itself |
| `State.gd` | the base class for state classes |
| `StateMachineNode.gd` | a `Node` that runs a `StateMachine` for you |
| `StateMachine.tscn` | a scene containing just a `StateMachineNode`. If you put the files somewhere other than `res://addons/state_machine/`, update the script path in it (or just add a `StateMachineNode` from the "Add Child Node" dialog instead) |

### In a scene

Add a `StateMachineNode` as a child of the node that needs state, either from the "Add Child Node" dialog or by instancing `StateMachine.tscn`. Then configure it:

```gdscript
enum STATES {
	ONE,
	TWO,
}

@onready var state_machine = $StateMachine

func _ready():
	state_machine.configure(STATES)
	state_machine.state_changed.connect(_on_state_changed)
```

The node calls the machine's `update`, `physics_update` and `handle_input` from its own `_process`, `_physics_process` and `_input`, so there is nothing else to do. Set `is_enabled` to `false` to pause it. If you need the underlying `StateMachine` itself, it's available as the node's `machine` property.

### Anywhere else

Create a `StateMachine` and call `update(delta)` yourself whenever the owner updates. Pass the object the states should act on (the "subject") to `new`:

```gdscript
extends RefCounted
class_name Crop

var state_machine = StateMachine.new(self)

func _init():
	state_machine.configure(CROP_STATES)

func update(delta):
	state_machine.update(delta)
```

If your states use `physics_process` or `handle_input`, call `physics_update(delta)` and `handle_input(event)` as well.

### The subject

Every `State` hook receives the machine's `subject`. This is how a state gets access to the thing it is managing. `StateMachineNode` uses its `owner` (or its parent if it has no owner) unless you set `subject` yourself. A plain `StateMachine` uses whatever was passed to `new`, or whatever you assign to `subject`.

Objects are held by weak reference, so an object that owns its own state machine and passes itself as the subject does not create a reference cycle. This also means the machine does not keep its subject alive: if nothing else holds a reference to the subject, it is freed and your states receive `null`. Keep a reference to it somewhere else, such as a variable on the object that owns the machine. Values that aren't objects, like a Dictionary, are held normally.

### Configure: manual transitions

There are two different ways to configure and use `StateMachine` depending on your needs. The first way is the "lightweight" version that doesn't use any classes for implementing state logic, and leans on manual transitions. The second way is more or less a fully automated approach (once configured). A blend of the two could even be used if it makes sense for your situation.

Either way, it's recommended that you put all your available states into an enum.

```gdscript
enum STATES {
	WALKING,
	RUNNING,
	JUMPING,
}
```

`configure` takes the available states and, optionally, the initial state. If you don't pass an initial state, the first state is used. This is the absolute barebones configuration for a state machine using the `STATES` above.

```gdscript
func _ready():
	state_machine.configure(STATES)
```

The machine enters its initial state on its first update. You can also call `transition_to_initial_state()` to enter it right away.

There are two ways to change state manually:

- `transition_to(state)` queues the change, and it happens at the start of the machine's next update.
- `transition_to_state_now(state)` changes state immediately, and cancels anything that was queued.

```gdscript
func _input(event):
	if event.is_action_pressed("jump"):
		state_machine.transition_to(STATES.JUMPING)
```

States can be any value you like (strings work too), but an enum is the least error prone.

### Configure: automata

The manual transitioning can work out well for very simple cases, but the real power of the finite state machine comes into play when things get automated. This is done through a bit more complex of a configuration where we tell the `StateMachine` not only about the available states, but also about classes to use to handle them, and where they will transition to.

We will build out an object like so:

```gdscript
{
	state_id: {
		"state_class": SomeState,
		"next_state": some_other_state_id,
		"transitions": {
			"some_key": another_state_id,
		},
	},
	# repeat for as many states as needed
}
```

All three keys are optional.

- `"state_class"` is a class to instance while the machine is in this state. You won't typically use the base `State` class directly since it is just an interface, but instead use an extension of it that implements the specific state behavior needed. More information is in the "State interface" section below.
- `"next_state"` is the state to go to when the state completes. Leave it out for a final state, like "dead", that never moves on by itself.
- `"transitions"` names the states this state can go to when there is more than one option. Completing the state with one of these keys goes to that state. A state can have both, in which case completing it without a key uses `"next_state"`.

`configure` checks the configuration and reports mistakes like unknown keys or transitions to states that don't exist as errors, so you find out right away instead of when the transition happens.

Here's the same states from the manual transitions example being configured for automated transitions.

```gdscript
enum STATES {
	IDLE,
	JUMP,
	WALK,
}

@onready var state_machine = $StateMachine

func _ready():
	var states = {
		STATES.IDLE: {
			# IDLE can transition to multiple states depending on input
			"transitions": {
				"walk": STATES.WALK,
				"jump": STATES.JUMP,
			},
			"state_class": IdleState,
		},
		STATES.WALK: {
			"next_state": STATES.IDLE,
			"state_class": WalkState,
		},
		STATES.JUMP: {
			"next_state": STATES.IDLE,
			"state_class": JumpState,
		},
	}

	state_machine.configure(states, STATES.IDLE)
```

Each of these requires a class existing to implement that state. Let's take a look first at how `JumpState` could be built since it's the most simple here.

```gdscript
class JumpState extends State:
	func init(player):
		player.velocity.y = player.jump_strength

	func physics_process(delta, player):
		if player.is_on_floor():
			complete()
```

When the state machine enters this state it creates an instance of this state class, and `init` is called with the subject. For a state like `JumpState`, this is where we could tell the player to do its jump action. Then, in `physics_process` (which is called every physics frame just like `_physics_process`) we can check for the player to have made it back to the floor, at which point we call `complete` (which is in the `State` base class) to tell the `StateMachine` to transition to the next state.

When using `next_state` the call to `complete` doesn't require any additional args.

Now, let's look at how that `IdleState` could be implemented since it's a bit more complex.

```gdscript
class IdleState extends State:
	func handle_input(event, player):
		if event.is_action_pressed("jump") and player.is_on_floor():
			complete("jump")
			return

		for dir in ["right", "left"]:
			if event.is_action_pressed("walk_%s" % dir):
				player.set_walking_direction(dir)
				complete("walk")
```

This state isn't really concerned about doing anything every frame, but instead is just waiting for input, validating that input can be done (if needed), and initiating the action. In this case it can go to multiple states from IDLE, so the call to `complete` specifies which key from the `transitions` field to use. Completing with a key that isn't in `transitions` is reported as an error and the state does not change.

The WalkState implementation would be something of a mix of the two. It could handle updating the position based on the walk speed inside of the `physics_process` method, while also using `handle_input` to make sure the walk button is still held, and what to do if it's released (back to idle), or if the direction is changed. It also might handle going straight into JUMP in a real use case, and JUMP might also be able to go back into WALK. Dealing with those complexities and beyond is where the StateMachine really shines!

A state without a `"state_class"` can still be completed from outside with `transition_to_next_state(key)`, which does exactly what `complete(key)` does.

### When transitions happen

Transitions from `complete`, `transition_to`, `transition_to_next_state` and `transition_to_previous_state` are queued and happen at the start of the machine's next update. The exception is calling `transition_to_next_state` before the machine's first update: it enters the initial state immediately, then queues the transition from there. Only one transition can be queued at a time:

- `transition_to(state)` replaces anything already queued, including a transition queued by a completed state.
- A state completing does not replace a transition that was already queued.
- `transition_to_state_now(state)` happens immediately and cancels anything queued.

When the state changes, the old state's `exit` is called first (while it is still the current state), then the new state's `init`, and then `state_changed` is emitted.

### state_changed signal

The `StateMachine` signals whenever the state changes so that the scene listening for it can react. This is most helpful for playing SFX, animations, and other things that happen as a _result_ of a state change. Listening for it is simple.

```gdscript
extends CharacterBody2D

@onready var state_machine = $StateMachine

func _ready():
	state_machine.state_changed.connect(_on_state_changed)
	# state_machine configuration can happen before, or after

func _on_state_changed(new_state):
	# do stuff based on what that new_state is, if needed
	queue_redraw()
```

## State interface

The provided `State` class is meant to act as an interface, but since GDScript doesn't support those it is built as a class that is meant to be extended. When using a state class to implement a state's behavior the `StateMachine` will call these methods on it. Every method receives the machine's subject.

| method name | purpose | args | called when.. |
|-------------|---------|------|---------------|
| `init` | set up any initial context values | `subject` | the state is entered. It's fine to call `complete` from here |
| `process` | logic processing and calling `complete` | `delta`, `subject` | from `StateMachine.update` |
| `physics_process` | if process logic needs to be synced with physics, use this instead of `process` | `delta`, `subject` | from `StateMachine.physics_update` |
| `handle_input` | state specific input handling | the input `event`, `subject` | from `StateMachine.handle_input` |
| `exit` | do any cleanup needed | `subject` | the machine is leaving this state, before the next state's `init` |

There are also two methods that are meant to be used as-is rather than implemented per state.

| method name | purpose | args |
|-------------|---------|------|
| `complete` | call this to tell the state machine to transition to the next state | takes an optional `transition_key` for when there is more than one possible transition |
| `load_context` | called when loading a saved state | the `saved_context` to use to set `context` |

The `State` class only relies on one instance variable so that it is easy to save and load at any point in time. This variable is called `context`. When making your own states you can make as many instance variables as you like, but anything that you want to be able to save/load should go into `context`.

Once the machine leaves a state, that state's handler can no longer trigger transitions, so a state that calls `complete` late (from a timer, for example) can't move the machine on from a state it's no longer in.

### Completing a state

If the state configuration set a `"next_state"` then you don't need any args for calling `complete`

```gdscript
class OneTakeState extends State:
	func process(_delta, _subject):
		complete()
```

If there are multiple `"transitions"` then complete needs to be told where to go next

```gdscript
class MiddleState extends State:
	func process(_delta, _subject):
		complete("next") # "next" must be a key in the "transitions" object
```

### Transitioning back to the previous state

Certain states are not going to fit into a flow that can be configured ahead of time and instead might interrupt another state, and then want to return back to that previous state upon completion. An example could be something like a momentary freeze when damaged. Being damaged could happen while running, walking, jumping, swimming, etc. To handle this there is a special value which can be used, `StateMachine.PREVIOUS`. Using this as the `"next_state"` (or a `"transitions"` target) will cause the state machine to return to the previous state when this one completes.

```gdscript
{
	"state_class": DamagedState,
	"next_state": StateMachine.PREVIOUS,
}
```

Returning to the previous state resumes its existing handler: `init` is not called again, so it picks up where it left off. You can also go back from outside with `transition_to_previous_state()` (queued) or `transition_to_state_now(StateMachine.PREVIOUS)`.

Currently, this is only implemented one level deep. After returning, the "previous" state is the one that was just left, so be careful not to return to a state which is also trying to return to a "previous" state.

## StateMachine

There are a few handy methods to know about for controlling the machine and gathering state information. `StateMachineNode` has all of these too.

| method name | purpose | args |
|-------------|---------|------|
| `configure` | set up the states | the states (an enum or a config Dictionary), and optionally the initial state |
| `transition_to_initial_state` | enter the initial state now | none |
| `transition_to` | queue a change to a new state | the `state_id` to transition to |
| `transition_to_state_now` | change to a new state immediately | the `state_id` to transition to |
| `transition_to_next_state` | queue the current state's configured transition (entering the initial state first if the machine hasn't started) | an optional `transition_key` |
| `transition_to_previous_state` | queue a return to the previous state | none |
| `get_current_state` | get the id of the current state | none |
| `get_previous_state` | get the id of the state the machine was in before this one | none |
| `is_current_state` | check if the current state is some specific state | the `state_id` to compare against |
| `get_current_state_context` | get the current state handler's `context` | none |
| `get_save_data` | get a Dictionary with the current state and its context, to save | none |
| `load_state` | restore data from `get_save_data` | the saved data |

Some examples, because examples make everything easier!

```gdscript
func _on_state_changed(new_state):
	match new_state:
		STATES.IDLE:
			$AnimatedSprite2D.play("idle")

		STATES.WALKING:
			$AnimatedSprite2D.play("walking")
```

```gdscript
func _process(_delta):
	$FireParticles.emitting = state_machine.is_current_state(STATES.BURNING)
```

```gdscript
func hit(damage_amount):
	hp -= damage_amount

	if hp < 1:
		state_machine.transition_to(STATES.DYING)
	else:
		state_machine.transition_to(STATES.HIT)
```

Using a state that wasn't configured, whether in a transition or in `load_state`, is reported as an error and the machine stays in its current state.

## Saving and loading

`get_save_data()` returns the current state and the current handler's `context`. Passing that to `load_state()` enters the saved state, calls its `init`, restores its `context`, and then emits `state_changed`, so listeners see the restored context.

## Cache

By default, `StateMachine` will create a new instance of the specific state class it needs every time the state changes. This behavior can be changed by setting `state_machine.cache_states = true`. When cache is enabled it will only create state class instances once, and then will use that any time it needs to transition to the state.

If using cache make sure that any local variables are set to their defaults inside the state's `init` function, otherwise you will see "resume state" behavior, though this may be desirable depending on what you're trying to do.

## Tests

Run `./run-tests.sh` to run the test suite headless. Set `GODOT` to your Godot 4 executable if it isn't on your `PATH` as `godot`.

## Issues

If you notice any bugs, or have any issues using the code in a way I've documented here feel free to file a github issue. I will do my best to keep up with them, but you're also more than welcome to open the code and try to fix things yourself. I will give any bug fix PRs a high priority for review.

## License

Standard MIT license is included.
