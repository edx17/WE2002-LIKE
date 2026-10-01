class_name FoulJudge
extends RefCounted
## How the referee reads a foul.
##
## Severity grows with: a slide, coming from behind, the offender's speed and
## aggression, plus a little randomness (referees are human). Then:
##   * denying an obvious goal-scoring opportunity (last man) -> red
##   * very high severity -> red; high -> yellow (stricter refs book sooner)
##   * second yellow -> red
##   * inside the offender's own penalty area -> penalty
##   * hard fouls can injure the victim

const YELLOW := "AMARILLA"
const RED := "ROJA"

var match_ctx: MatchController
## 0 lenient .. 1 strict.
var strictness := 0.5
var rng := RandomNumberGenerator.new()


func _init(m: MatchController) -> void:
	match_ctx = m


func judge(offender: PlayerController, victim: PlayerController, slide: bool) -> Dictionary:
	var to_victim := DirectionResolver.flat(victim.global_position - offender.global_position)
	var from_behind := to_victim.length() > 0.05 and victim.facing.dot(to_victim.normalized()) > 0.35
	var severity := 0.2
	if slide:
		severity += 0.25
	if from_behind:
		severity += 0.3
	severity += clampf(offender.speed / maxf(offender.sprint_speed(), 0.1), 0.0, 1.0) * 0.15
	severity += offender.stats.n(&"aggression") * 0.1
	severity += rng.randf_range(-0.08, 0.12)

	var dogso := is_goal_scoring_chance(offender, victim)
	var card := ""
	if dogso or severity > 0.92:
		card = RED
	elif severity > 0.62 - strictness * 0.15:
		card = YELLOW
	if card == YELLOW and offender.yellow_cards >= 1:
		card = RED  # second yellow

	var penalty := match_ctx.in_penalty_area(victim.global_position, -offender.attack_dir)
	var injury := severity > 0.75 and rng.randf() < (severity - 0.6) * 1.2
	return {"card": card, "penalty": penalty, "injury": injury, "severity": severity, "dogso": dogso,
		"from_behind": from_behind}


## Last man: the victim was heading for goal, close enough to score, with no
## defender (other than the offender and the keeper) between him and goal.
func is_goal_scoring_chance(offender: PlayerController, victim: PlayerController) -> bool:
	var goal := match_ctx.goal_center(victim.attack_dir)
	var to_goal := DirectionResolver.flat(goal - victim.global_position)
	if to_goal.length() > 30.0:
		return false
	if match_ctx.ball.owner_player != victim and victim.global_position.distance_to(match_ctx.ball.global_position) > 2.5:
		return false
	for d in match_ctx.opponents_of(victim):
		if d == offender or d.is_keeper:
			continue
		var rel := DirectionResolver.flat(d.global_position - victim.global_position)
		if rel.dot(to_goal.normalized()) > 0.0 and rel.length() < to_goal.length():
			var lateral := (rel - to_goal.normalized() * rel.dot(to_goal.normalized())).length()
			if lateral < 8.0:
				return false
	return true
