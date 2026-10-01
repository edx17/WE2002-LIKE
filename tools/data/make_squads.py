"""Generates two 11-player squads (players, appearances, match setup).

    python3 tools/data/make_squads.py

Deterministic (fixed seed): re-running gives the same squads. Attributes are
derived from the position on the team sheet with some individual variance,
appearances are random picks from data/appearance/components.json. Edit the
generated JSON by hand afterwards if you like: it's all just data.
"""

import json
import os
import random

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(ROOT, "data")

# Position -> attribute profile (before variance).
PROFILES = {
    "GK":  dict(speed=60, acceleration=64, agility=76, balance=74, strength=76, passing=60, shooting=30, shot_power=72,
                heading=60, tackling=30, control=60, technique=55, aggression=50, reaction=84, goalkeeping=82),
    "CB":  dict(speed=72, acceleration=70, agility=64, balance=80, strength=84, passing=66, shooting=48, shot_power=72,
                heading=84, tackling=84, control=62, technique=58, aggression=78, reaction=74),
    "FB":  dict(speed=82, acceleration=80, agility=76, balance=74, strength=70, passing=72, shooting=55, shot_power=70,
                heading=66, tackling=76, control=70, technique=66, aggression=68, reaction=76),
    "DMF": dict(speed=72, acceleration=72, agility=70, balance=80, strength=80, passing=80, shooting=62, shot_power=76,
                heading=72, tackling=82, control=74, technique=70, aggression=78, reaction=78),
    "CMF": dict(speed=76, acceleration=76, agility=76, balance=76, strength=70, passing=84, shooting=72, shot_power=74,
                heading=64, tackling=68, control=82, technique=80, aggression=64, reaction=80),
    "WM":  dict(speed=86, acceleration=86, agility=84, balance=72, strength=62, passing=78, shooting=70, shot_power=70,
                heading=58, tackling=56, control=82, technique=80, aggression=58, reaction=80),
    "CF":  dict(speed=82, acceleration=84, agility=80, balance=74, strength=76, passing=70, shooting=84, shot_power=84,
                heading=78, tackling=40, control=80, technique=76, aggression=66, reaction=82),
}
GROUP = {"GK": "GK", "CB": "CB", "LB": "FB", "RB": "FB", "LWB": "FB", "RWB": "FB", "DMF": "DMF", "CMF": "CMF",
         "AMF": "CMF", "LMF": "WM", "RMF": "WM", "WG": "WM", "CF": "CF"}
NUMBERS = {"GK": [1], "LB": [3], "CB": [4, 2, 5], "RB": [2], "LMF": [11], "RMF": [7], "CMF": [8, 6], "DMF": [5],
           "WG": [7, 11], "CF": [9, 10], "LWB": [3], "RWB": [2]}

# Five substitutes per team (WE2002: three changes allowed).
BENCH_ROLES = ["GK", "CB", "CMF", "RMF", "CF"]

SQUADS = [
    {"prefix": "cap", "team": "team_a", "formation": "4-4-2", "tactics": "equilibrado", "attack_dir": 1, "first_number": 1},
    {"prefix": "dvs", "team": "team_b", "formation": "4-3-3", "tactics": "presion_alta", "attack_dir": -1, "first_number": 21},
]


def write(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def main():
    rng = random.Random(2002)
    lib = json.load(open(os.path.join(DATA, "appearance", "components.json"), encoding="utf-8"))
    match_teams = []
    name_counter = 11
    for squad in SQUADS:
        form = json.load(open(os.path.join(DATA, "formations", squad["formation"] + ".json"), encoding="utf-8"))
        used_numbers, entries, bench = set(), [], []
        roles = [slot["role"] for slot in form["slots"]] + BENCH_ROLES
        for i, role in enumerate(roles):
            on_bench = i >= len(form["slots"])
            pid = f"{squad['prefix']}_{i + 1:02d}"
            number = next((n for n in NUMBERS.get(role, []) if n not in used_numbers), None)
            if number is None:
                number = next(n for n in range(12, 99) if n not in used_numbers)
            used_numbers.add(number)
            profile = PROFILES[GROUP.get(role, "CMF")]
            stats = {k: max(30, min(99, v + rng.randint(-6, 6))) for k, v in profile.items()}
            stats.setdefault("goalkeeping", 40 + rng.randint(-5, 5))
            stats.update(stamina=rng.randint(72, 92), weak_foot=rng.randint(1, 4))
            name_counter += 1
            appearance = f"p_{pid}"
            write(os.path.join(DATA, "players", pid + ".json"), {
                "name": f"Jugador {name_counter:02d}", "number": number, "position": role,
                "preferred_foot": "left" if role in ("LB", "LMF", "LWB") or rng.random() < 0.2 else "right",
                "appearance": appearance, **stats})
            height = round(rng.uniform(1.84, 1.93) if role in ("GK", "CB") else rng.uniform(1.68, 1.86), 2)
            write(os.path.join(DATA, "appearance", appearance + ".json"), {
                "id": appearance, "body": rng.choice([0, 1, 1, 2]) if role not in ("CB", "GK") else rng.choice([1, 2]),
                "face": rng.randrange(len(lib["faces"])), "hair": rng.choice([0, 1, 1, 1, 2, 2, 3, 4, 5]),
                "hair_color": rng.randrange(len(lib["hair_colors"])), "boot": rng.randrange(len(lib["boots"])),
                "boot_color": rng.choice(["#111111", "#111111", "#f2f2f2", "#1e3a8a", "#b91c1c"]),
                "skin": rng.randrange(len(lib["skin_tones"])), "height": height,
                "weight": round(height * height * rng.uniform(21.5, 25.0)), "facial_hair": rng.choice([0, 0, 0, 1, 2, 3])})
            if on_bench:
                bench.append({"id": pid})
                continue
            entries.append({"id": pid, "control": "human" if squad["prefix"] == "cap" and role == "CF" and
                            not any(e["control"] == "human" for e in entries) else "ai"})
        match_teams.append({"id": squad["team"], "attack_dir": squad["attack_dir"], "formation": squad["formation"],
                            "tactics": squad["tactics"], "players": entries, "bench": bench})
    write(os.path.join(DATA, "matches", "stage3_11v11.json"), {
        "name": "Etapa 3 — 11 vs 11", "direction_steps": 8, "teams": match_teams})
    write(os.path.join(DATA, "matches", "stage4_partido.json"), {
        "name": "Etapa 4 — partido completo", "direction_steps": 8, "half_minutes": 5,
        "referee": True, "referee_strictness": 0.5, "max_substitutions": 3, "teams": match_teams})
    print("squads written: 32 players (22 + 10 subs), appearances, stage3_11v11 and stage4_partido")


if __name__ == "__main__":
    main()
