# StateMachine

StateMachine is a Godot script class that implements a finite state machine for generic use. I built this for use in my own personal projects and am making it free to use for anyone else out there working on a game using Godot.

## When to use

There's already a lot of information written about when to use the state machine pattern that you should read. [Here is a great one I recommend](https://gameprogrammingpatterns.com/state.html).

If you're using Godot engine and a finite state machine is what you need for your situation, this is a great choice!

## How to use

There are two main parts to this, the `StateMachine`, and the `State`. The `StateMachine` is meant to be added as a child to some other Node that would like to have state, while `State` is an interface meant to be extended by classes that implement states. Of course, Godot does not support a true interface, but that is the intention of the State class provided. The `StateMachine` requires a small amount of configuration, and then it does the rest on its own.

### Add the files to your project

You'll need to add `source/StateMachine.gd` and `source/State.gd` to your project. I usually add them in a directory like `res://scripts/`, but you can put them wherever you like. Since they set a `class_name`, they can be globally referenced by name no matter where you decide to put them.

I have also provided a `StateMachine.tscn` which is nothing more than a Node which the `StateMachine.gd` script attached. Using this is the quickest and easiest way to add a state machine to any scene in a project. Once added you can get a reference to it in script like so:

```gdscript
onready var state_machine = $StateMachine
```

Then you'll need to configure it like so:

```gdscript
enum STATES {
    ONE,
    TWO,
}

func _ready():
    state_machine.configure(STATES)
    state_machine.connect("state_changed", self, "_on_state_changed")

```

This is the most basic form of configuration. See the rest of this document for more info about configuration, and state classes.

### Setup

#### add to scene

There are several ways to use `StateMachine`. They ultimately do the same thing so the preference is really your own.

1. (preferred way) Use the provided `StateMachine.tscn` and add it to your scene
2. Add a new `Node` to your scene, and then attach the `StateMachine.gd` script to it.
3. Create an instance in script, and use `add_child` to add it.

#### configure - manual transitions

There are actually two different ways to configure and use `StateMachine` depending on your needs. The first way is the "lightweight" version that doesn't use any classes for implementing state logic, and leans on manual transitions. The second way is more or less a fully automated approach (once configured). A blend of the two could even be used if it makes sense for your situation.

Either way, it's recommended that you put all your available states into an enum.

```gdscript
enum STATES {
    WALKING,
    RUNNING,
    JUMPING,
}
```

The `StateMachine` class exposes a `configure` method you can use to tell it about the available states. You can also specify the initial state to be in, if it's not the first one in the list. This would be the absolute barebones configuration for a state machine using the `STATES` above.

```gdscript
onready var state_machine = $StateMachine

func _ready():
    state_machine.configure(STATES)
```

Once added to a scene and configured the `StateMachine` will get updated every frame just like any other Node because it implements a `_process` method. When going this manual transition route, the only thing `_process` will really ever do is transition to a new state when instructed to do so.

Manually transitioning to a new state can be triggered at any time, but the change will only happen internally at the beginning of a `_process` tick. Initiating a transition on input for example might look like this:

```gdscript
func _input(event):
    if event.is_action_pressed("jump"):
        state_machine.transition_to_state(STATES.JUMPING)
```

As long as the state passed into `transition_to_state` is one of the ones that was sent to `configure` then the current state will update next time `_process` ticks. It will emit a signal if the state changes, which is further documented below.

#### configure - automata

The manual transitioning can work out well for very simple cases, but the real power of the finite state machine comes into play when things get automated. This is done through a bit more complex of a configuration where we tell the `StateMachine` not only about the available states, but also about classes to use to handle them, and where they will transition to.

We will build out an object like so:

```gdscript
{
    state_id: {
        "next_state": some_other_state_id,
        "state_class": State,
    },
    # repeat for as many states as needed
}
```

If you're using an enum, the keys in this object should be the enum values. The state machine class does not care if you just use strings, or your own integers, but it's more error prone to do this compared to using the enum approach.

The "next_state" key in the object must be one of the other state_ids; this property indicates what state to transition to next when this current one completes. This can be omitted if the state does not transition to any other state. This would be common with states like "death" where the node is cleared immediately after entering the state.

The "state_class" is a class reference to instance for use when this state becomes active. You won't typically use the base `State` class directly since it is just an interface, but instead use an extension of it that implements the specific state behavior needed. More information about how to use this is available in the "State class" section below.

If there are multiple states that are available as the "next state", use the key "transitions" instead. The value would be an object where the key is the "name" you use to reference the transition, and the value is the state_id to transition to. This is shown in some of the examples below.

Here's the same states from the manual transitions example being configured for automated transitions.

```gdscript
enum STATES {
    IDLE,
    JUMP,
    WALK,
}

onready var state_machine = $StateMachine

func _ready():
    # create the states configuration object
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

    # configure the state_machine instance
    state_machine.configure(states, STATES.IDLE)
```

Each of these requires a class existing to implement that state. Let's take a look first at how `JumpState` could be built since it's the most simple here.

```gdscript
class JumpState extends State:
    func init(owner):
        owner.velocity.y = owner.jump_strength

    func process(delta, owner):
        if owner.is_on_floor():
            complete()
```

When the state machine enters this state it creates an instance of this state class, and `init` is called with `owner` node. For a state like `JumpState`, this is where we could tell the node to do its jump action. Then, in `process` (which is called every frame just like `_process`) we can check for the owner to have made it back to the floor, at which point we call the method `complete` (which is in the `State` base class) to emit a signal to tell the `StateMachine` to transition to the next state.

When using `next_state` the call to `complete` doesn't require any additional args.

Now, let's look at how that `IdleState` could be implemented since it's a bit more complex.

```gdscript
class IdleState extends State:
    func handle_input(event, owner):
        if event.is_action_pressed("jump") and owner.is_on_floor():
            complete("jump")
            return

        for dir in ["right", "left"]:
            if event.is_action_pressed("walk_%s" % dir):
                object.set_walking_direction(dir)
                complete("walk")
```

This state isn't really concerned about doing anything every frame, but instead is just waiting for input, validating that input can be done (if needed), and initiating the action. In this case it can go to multiple states from IDLE, so the call to `complete` specifies which key from the `transitions` field to reference.

The WalkState implementation would be something of a mix of the two. It could handle updating the position based on the walk speed inside of the `process` method, while also using `handle_input` to make sure the walk button is still held, and what to do if it's released (back to idle), or if the direction is changed. It also might handle going straight into JUMP in a real use case, and JUMP might also be able to go back into WALK. Dealing with those complexities and beyond is where the StateMachine really shines!

#### state_changed signal

The `StateMachine` signals whenever the state changes so that the scene listening for it can react. this is most helpful for playing SFX, animations, and other things that happen as a _result_ of a state change. Listening for it is simple.

```gdscript
extends KinematicBody2D

onready var state_machine = $StateMachine

func _ready():
    state_machine.connect("state_changed", self, "_on_state_changed")
    # state_machine configuration can happen before, or after

func _on_state_changed(new_state):
    # do stuff based on what that new_state is, if needed
    update() # trigger a redraw, if desired
```

## State interface

The provided `State` class is meant to act as an interface, but since gdscript doesn't support those it is built as a class that is meant to be extended. When using a state class to implement a state's behavior the `StateMachine` will call methods on the `current_state_handler` to allow it to perform actions. You can technically avoid using this class, but you will still need to implement these same methods so I recommend using it for convenience.

Several of the methods are called from a standard gdscript method and so they receive the standard arg unmodified along with a reference to the node that owns the `StateMachine`. This reference is how the state has access to directly modify the node using the state machine. The other methods are hooks that are called during transitions in and out of the state. Everything is listed below.

| method name | purpose | args | called when.. |
|-------------|---------|------|---------------|
| `init`        | set up any initial context values | `owner` node ref | the state is initialized |
| `process`      | logic processing and calling `complete` | `delta` since the last update, and an `owner` node ref | called from `StateMachine._process` when this state is the `current_state_handler` |
| `physics_process`      | if process logic needs synced with physics, use this instead of `process` | `delta` since the last update, and an `owner` node ref | called from `StateMachine._physics_process` when this state is the `current_state_handler` |
| `handle_input` | state specific input handling | the input `event`, and an `owner` node ref | called from `StateMachine._input` when this state is `current_state_handler` |
| `exit` | do any cleanup needed | `owner` node ref | when `StateMachine` is transitioning out of this state |


There are also two methods that are meant to be internal methods that you don't implement on a per state basis.

| method name | purpose | args |
|-------------|---------|------|
| `complete`    | call this to tell the state machine to transition to the next state | takes an optional `transition_key` for when there are more than one possible transitions |
| `load_context` | called when loading a saved state | the `saved_context` to use to set `context` |

The `State` class only relies on one instance variable so that it is easy to save and load at any point in time. This variable is called `context`. When making your own states you can make as many instance variables as you like, but anything that you want to be able to save/load should go into `context`.


### completing a state

In order for a state class to tell the state machine it has completed, it needs to emit the signal "is_complete". The `State` base class provides this functionality through the `complete` method. This method also takes an argument for the "key" to transition with if there are more than one possible target states.

If the state configuration set a `"next_state"` then you don't need any args for calling `complete`

```gdscript
class OneTakeState extends State:
    func process(_delta, _owner_ref):
        complete()
```

If there are multiple `"transitions"` then complete needs told where to go next

```gdscript
class MiddleState extends State:
    func process(_delta, _owner_ref):
        complete("next") // "next" must be a key in the "transitions" object
```

### transitioning back to the previous state

Certain states are not going to fit into a flow that can be configured ahead of time and instead might interrupt another state, and then want to return back to that previous state upon completion. An example could be something like a momentary freeze when damaged. Being damaged could happen while running, walking, jumping, swimming, etc. To handle this there is a special value which can be used, `StateMachine.PREVIOUS`. Using this as the "next_state" value will cause the state machine to return to the previous state when this one completes.

Currently, this is only implemented one level deep, so be careful not to return to a state which is also trying to return to a "previous" state. A future enhancemet would be to keep a larger stack of the history, but I haven't had a need for this yet.

```gdscript
{
    "state_class": DamagedState,
    "next_state": StateMachine.PREVIOUS,
}
```

Under the hood the value of `PREVIOUS` is `-1`. In case this ever changes it would be safest to use the constant, but technically this value will work as well if it makes more sense to you.

## StateMachine

The `StateMachine` class is intended to be attached to a node and used as is. It relies on configuration to operate. Once configured it can operate all on its own as described earlier in this document. There are a few handy methods to know about for gathering state information.

| method name | purpose | args |
|-------------|---------|------|
| `get_current_state` | get the id of the current state | none |
| `get_previous_state` | get the id of the state the machine was in before this one | none |
| `is_current_state` | check if the current state is some specific state | the `state_id` to compare against |
| `transition_to` | manually change to a new state | the `state_id` to transition to |

Some examples, because examples make everything easier!

```gdscript
func _draw():
  match state_machine.get_current_state():
      STATES.IDLE:
          $AnimatedSprite.play("idle")

      STATES.WALKING:
          $AnimatedSprite.play("walking")
```

```gdscript
func _draw():
    $FireParticles.emitting = state_machine.is_current_state(STATE.BURNING)
```

```gdscript
func hit(damage_amount):
    hp -= damage_amount

    if hp < 1:
        state_machine.transition_to(STATES.DYING)
    else:
        state_machine.transition_to(STATES.HIT)
```

## Cache

By default, `StateMachine` will create a new instance of the specific state class it needs every time the state changes. This behavior can be changed by setting `state_machine_instance.cache_states = true`. When cache is enabled it will only create state class instances once, and then will use that any time it needs to transition to the state. 

If using cache make sure that any local variables are set to their defaults inside the state's `init` function, otherwise you will see "resume state" behavior, though this may be desirable depending on what you're trying to do.

## Issues

If you notice any bugs, or have any issues using the code in a way I've documented here feel free to file a github issue. I will do my best to keep up with them, but you're also more than welcome to open the code and try to fix things yourself. I will give any bug fix PRs a high priority for review.


## License

Standard MIT license is included.
