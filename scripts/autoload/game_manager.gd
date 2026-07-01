extends Node
## Tracks score, game state and the "psychedelic intensity" that the rest of
## the game scales its visuals off of. First team to WIN_SCORE wins.

enum Team { A, B }
enum State { PLAYING, REPLAY, GAME_OVER }

const WIN_SCORE := 5
## Total combined points at which visuals/effects hit full intensity (1.0).
## A first-to-5 game can run up to 5+4=9 total points before someone wins.
const MAX_INTENSITY_TOTAL := 7.0

signal score_changed(score_a: int, score_b: int)
signal shot_made(scoring_team: Team, world_pos: Vector3)
signal possession_changed(team: Team)
signal game_over(winning_team: Team)
signal state_changed(new_state: State)

var state: State = State.PLAYING
var score := { Team.A: 0, Team.B: 0 }
var possession: Team = Team.A

## 0.0 (calm, normal) -> 1.0 (full psychedelic chaos), driven by total points scored.
var psychedelic_intensity: float = 0.0


func _ready() -> void:
	reset_game()


func reset_game() -> void:
	score[Team.A] = 0
	score[Team.B] = 0
	possession = Team.A
	psychedelic_intensity = 0.0
	_set_state(State.PLAYING)
	score_changed.emit(score[Team.A], score[Team.B])


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(state)


func register_basket(scoring_team: Team, world_pos: Vector3) -> void:
	if state != State.PLAYING:
		return

	score[scoring_team] += 1
	_recompute_intensity()
	score_changed.emit(score[Team.A], score[Team.B])

	if score[scoring_team] >= WIN_SCORE:
		_set_state(State.GAME_OVER)
		game_over.emit(scoring_team)
	else:
		# Loser's outball: the team that got scored on takes the ball next.
		possession = Team.B if scoring_team == Team.A else Team.A
		possession_changed.emit(possession)

	shot_made.emit(scoring_team, world_pos)


func _recompute_intensity() -> void:
	var total: int = score[Team.A] + score[Team.B]
	psychedelic_intensity = clampf(float(total) / MAX_INTENSITY_TOTAL, 0.0, 1.0)


func opposing_team(team: Team) -> Team:
	return Team.B if team == Team.A else Team.A
