extends SceneTree
const MatchRules = preload("res://scripts/match_rules.gd")
var checks := 0
var failures := 0

func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(text)

func _init() -> void:
	var rules := MatchRules.new()
	rules.reset(0)
	var sequence: Array[int] = []
	for i in range(10):
		sequence.append(rules.shooter_slot())
		rules.record(rules.shooter_slot() == 0)
	check(sequence == [0,1,1,0,0,1,1,0,0,1], "First shooter alternates by round")
	check(rules.scores == [5,0] and rules.finished, "Five paired rounds finish a non-tied match")
	check(rules.winner() == 0 and rules.attempts == 10, "Winner and attempt count are correct")
	rules.record(true)
	check(rules.attempts == 10, "Finished match cannot score again")
	rules.reset(1)
	for i in range(10):
		rules.record(false)
	check(not rules.finished and rules.round_index == 5, "Draw goes to extra pairs")
	rules.record(true)
	check(not rules.finished, "First extra goal alone cannot end the pair")
	rules.record(false)
	check(rules.finished and rules.winner() == 0, "Winner determined only after both extra shots")
	rules.reset(0)
	for i in range(20):
		rules.record(false)
	check(rules.finished and rules.winner() == -1, "Five extra tied pairs end in a draw")
	rules.reset(1)
	check(rules.scores == [0,0] and rules.attempts == 0 and rules.shooter_slot() == 1, "Rematch resets scores and changes starter")
	print("Match: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

