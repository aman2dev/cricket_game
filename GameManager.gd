extends Node

## GameManager.gd (Autoload)
## Core global state machine and match scoring logic for the Beach Cricket game.

enum State {
	TUTORIAL,            # Displays UI instruction cards for holding the phone/bat
	BOWLER_RUNUP,        # Waiting for the bowling gesture/input
	BALL_IN_FLIGHT,      # The ball travels from the pitcher toward the batsman
	BAT_SWING_WINDOW,    # The 0.3-second matrix where hit collision is valid
	FIELDING,            # Ball tracking after hit, calculating runs or catches
	RESULT               # Triggers full-screen text splash like "Six Runs!", "Out!", or "Too Late!"
}

# Signals
signal state_changed(old_state: State, new_state: State)
signal score_updated(runs: int, wickets: int, balls_left: int)
signal result_triggered(result_text: String)
signal game_over(final_runs: int, final_wickets: int)

# Game variables
@export var max_balls: int = 6
var current_state: State = State.TUTORIAL
var runs: int = 0
var wickets: int = 0
var balls_remaining: int = 6

func _ready() -> void:
	reset_game()

func change_state(new_state: State) -> void:
	var old_state = current_state
	current_state = new_state
	state_changed.emit(old_state, new_state)
	print("[GameManager] State changed: ", State.keys()[old_state], " -> ", State.keys()[new_state])
	
	if current_state == State.RESULT:
		# Automatically transition back to BOWLER_RUNUP or game over after showing result
		await get_tree().create_timer(3.0).timeout
		_advance_game_after_result()

func reset_game() -> void:
	runs = 0
	wickets = 0
	balls_remaining = max_balls
	current_state = State.TUTORIAL
	score_updated.emit(runs, wickets, balls_remaining)
	state_changed.emit(State.TUTORIAL, State.TUTORIAL)

func record_runs(amount: int) -> void:
	runs += amount
	balls_remaining -= 1
	score_updated.emit(runs, wickets, balls_remaining)
	result_triggered.emit(str(amount) + " RUNS!")
	change_state(State.RESULT)

func record_wicket(reason: String = "OUT!") -> void:
	wickets += 1
	balls_remaining -= 1
	score_updated.emit(runs, wickets, balls_remaining)
	result_triggered.emit(reason)
	change_state(State.RESULT)

func record_dot_ball(reason: String = "DOT BALL") -> void:
	balls_remaining -= 1
	score_updated.emit(runs, wickets, balls_remaining)
	result_triggered.emit(reason)
	change_state(State.RESULT)

func _advance_game_after_result() -> void:
	if balls_remaining <= 0:
		game_over.emit(runs, wickets)
		result_triggered.emit("GAME OVER!\nFinal: %d Runs | %d Wickets" % [runs, wickets])
		await get_tree().create_timer(4.0).timeout
		reset_game()
	else:
		change_state(State.BOWLER_RUNUP)
