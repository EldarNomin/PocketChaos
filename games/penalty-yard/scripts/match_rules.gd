extends RefCounted
## Scoring and fair paired turns. Transport and graphics are independent.

const REGULAR_ROUNDS := 5
const EXTRA_ROUNDS := 5
var scores: Array[int] = [0, 0]
var initial_first := 0
var round_index := 0
var shot_in_round := 0
var attempts := 0
var finished := false

func reset(first: int) -> void:
	scores = [0, 0]
	initial_first = clampi(first, 0, 1)
	round_index = 0
	shot_in_round = 0
	attempts = 0
	finished = false

func shooter_slot() -> int:
	return (initial_first + round_index + shot_in_round) % 2

func record(goal: bool) -> void:
	if finished:
		return
	if goal:
		scores[shooter_slot()] += 1
	attempts += 1
	shot_in_round += 1
	if shot_in_round == 2:
		shot_in_round = 0
		round_index += 1
		if round_index >= REGULAR_ROUNDS:
			finished = scores[0] != scores[1] or round_index >= REGULAR_ROUNDS + EXTRA_ROUNDS

func winner() -> int:
	if not finished or scores[0] == scores[1]:
		return -1
	return 0 if scores[0] > scores[1] else 1

