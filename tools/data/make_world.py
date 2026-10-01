"""Generates the fictional football world for the Master League.

    python3 tools/data/make_world.py

Writes (deterministic, fixed seed):
  data/world/world.json              clubs, divisions, the default "Master" squad
  data/world/players.json            every player (attributes + career data)
  data/kits/club_XX[_gk].json        one home kit per club (+ keeper kits)
  data/appearance/pool_XX.json       a pool of appearances shared by all players

No licences: every club, name and kit is invented. Edit the JSON freely, or
write your own world with the same shape (that's what the editor will do).
Then generate the appearance pool and kits:
  python tools/asset_pipeline/player_generator.py $(ls data/appearance | grep pool_ | sed 's/.json//')
  python3 tools/asset_pipeline/kit_generator.py
"""

import json
import os
import random

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(ROOT, "data")
SEED = 2002
POOL_SIZE = 40

FIRST = ["Adrián", "Bruno", "Ciro", "Dante", "Elías", "Fabio", "Gael", "Hugo", "Iván", "Joel", "Kevin", "Lisandro",
         "Mateo", "Nahuel", "Óscar", "Pablo", "Quique", "Ramiro", "Santino", "Tobías", "Ulises", "Valentín",
         "Walter", "Ximo", "Yago", "Zenón", "Abel", "Benja", "Camilo", "Darío", "Emiliano", "Facundo", "Gonzalo",
         "Hernán", "Ignacio", "Julián", "Leandro", "Matías", "Nicolás", "Octavio", "Rodrigo", "Sergio", "Tadeo"]
LAST_A = ["Al", "Bar", "Cas", "Dal", "Es", "Fer", "Gar", "Her", "Ib", "Lo", "Mar", "Nu", "Or", "Pe", "Qui", "Ro",
          "Sal", "Tor", "Ur", "Val", "Za", "Bel", "Cor", "Mon", "Ri", "Sol", "Ve"]
LAST_B = ["ballo", "dona", "telli", "vera", "pino", "nández", "cía", "rera", "arra", "zano", "tínez", "ñez",
          "tiz", "reyra", "roga", "mero", "gado", "res", "quiza", "dés", "mora", "trán", "dero", "tiel",
          "vas", "lano", "monte", "gueira"]

CITIES = ["Puerto Alto", "Villa Sur", "San Ciro", "Río Claro", "Monte Verde", "Las Lomas", "Valle Hondo",
          "Ciudad Nueva", "Bahía Azul", "Cerro Norte", "Santa Brisa", "El Molino", "Punta Sierra", "Llanura",
          "Costa Real", "Altamira", "Piedra Negra", "Tres Ríos", "Los Pinos", "Campo Grande"]
PREFIX = ["Atlético", "Deportivo", "Sporting", "Unión", "Racing", "Club", "Real", "Juventud", "Estrella", "Olímpico"]

COLORS = ["#c62828", "#1e5bc6", "#2e7d32", "#f9a825", "#6a1b9a", "#ef6c00", "#00838f", "#212121", "#ffffff",
          "#ad1457", "#4e342e", "#0d47a1", "#9e9d24", "#37474f", "#d84315", "#1565c0", "#7cb342", "#5d4037"]
PATTERNS = ["plain", "plain", "stripes", "hoops", "halves", "sash"]
GK_KITS = [("#3fae4a", "#1f6a2a"), ("#d98ac4", "#b0609c"), ("#212121", "#555555"), ("#f2c200", "#6b5600")]

# 4-4-2 squad template (starting XI + 11 reserves) by position.
SQUAD = ["GK", "GK", "CB", "CB", "CB", "CB", "LB", "RB", "LB", "RB", "DMF", "CMF", "CMF", "CMF", "LMF", "RMF",
         "AMF", "WG", "CF", "CF", "CF", "CB"]

PROFILES = {
    "GK": dict(speed=60, acceleration=64, agility=76, balance=74, strength=76, passing=60, shooting=30, shot_power=72,
               heading=60, tackling=30, control=60, technique=55, aggression=50, reaction=82, goalkeeping=82),
    "CB": dict(speed=72, acceleration=70, agility=64, balance=80, strength=84, passing=66, shooting=48, shot_power=72,
               heading=84, tackling=84, control=62, technique=58, aggression=78, reaction=74),
    "FB": dict(speed=82, acceleration=80, agility=76, balance=74, strength=70, passing=72, shooting=55, shot_power=70,
               heading=66, tackling=76, control=70, technique=66, aggression=68, reaction=76),
    "DMF": dict(speed=72, acceleration=72, agility=70, balance=80, strength=80, passing=80, shooting=62, shot_power=76,
                heading=72, tackling=82, control=74, technique=70, aggression=78, reaction=78),
    "CMF": dict(speed=76, acceleration=76, agility=76, balance=76, strength=70, passing=84, shooting=72, shot_power=74,
                heading=64, tackling=68, control=82, technique=80, aggression=64, reaction=80),
    "WM": dict(speed=86, acceleration=86, agility=84, balance=72, strength=62, passing=78, shooting=70, shot_power=70,
               heading=58, tackling=56, control=82, technique=80, aggression=58, reaction=80),
    "CF": dict(speed=82, acceleration=84, agility=80, balance=74, strength=76, passing=70, shooting=84, shot_power=84,
               heading=78, tackling=40, control=80, technique=76, aggression=66, reaction=82),
}
GROUP = {"GK": "GK", "CB": "CB", "LB": "FB", "RB": "FB", "DMF": "DMF", "CMF": "CMF", "AMF": "CMF",
         "LMF": "WM", "RMF": "WM", "WG": "WM", "CF": "CF"}


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")


def make_player(rng, pid, role, level, used_names):
    """level: club quality offset (-20 weak .. +6 strong)."""
    while True:
        name = f"{rng.choice(FIRST)[0]}. {rng.choice(LAST_A)}{rng.choice(LAST_B)}"
        if name not in used_names:
            used_names.add(name)
            break
    age = rng.choice([18, 19, 20, 21, 22, 23, 24, 24, 25, 25, 26, 26, 27, 27, 28, 29, 30, 31, 32, 33, 34])
    growth = rng.choice(["precoz", "normal", "normal", "tardio"])
    profile = PROFILES[GROUP[role]]
    # Young players start below their peak; the potential is what they can reach.
    youth_gap = max(0, 25 - age) * rng.uniform(1.0, 2.2)
    stats = {}
    for k, v in profile.items():
        stats[k] = int(max(25, min(99, v + level + rng.randint(-7, 7) - youth_gap)))
    stats.setdefault("goalkeeping", 38 + rng.randint(-5, 5))
    stats["stamina"] = int(max(40, min(99, 78 + level // 2 + rng.randint(-8, 8))))
    stats["weak_foot"] = rng.randint(1, 4)
    potential = int(min(99, 72 + level + rng.randint(-6, 10) + (6 if age < 22 else 0)))
    return {
        "id": pid, "name": name, "position": role,
        "preferred_foot": "left" if role in ("LB", "LMF") or rng.random() < 0.2 else "right",
        "appearance": f"pool_{rng.randrange(POOL_SIZE) + 1:02d}",
        "age": age, "growth": growth, "potential": potential,
        "contract_years": rng.randint(1, 4),
        **stats,
    }


def make_appearance(rng, i):
    return {"id": f"pool_{i:02d}", "body": rng.choice([0, 1, 1, 2]), "face": rng.randrange(3),
            "hair": rng.choice([0, 1, 1, 1, 2, 2, 3, 4, 5]), "hair_color": rng.randrange(6),
            "boot": rng.randrange(3), "boot_color": rng.choice(["#111111", "#111111", "#f2f2f2", "#1e3a8a", "#b91c1c"]),
            "skin": rng.randrange(6), "height": round(rng.uniform(1.70, 1.92), 2),
            "weight": round(1.8 * 1.8 * rng.uniform(21.5, 25.0)), "facial_hair": rng.choice([0, 0, 0, 1, 2, 3])}


def main():
    rng = random.Random(SEED)
    used_names, players, clubs = set(), [], []
    for i in range(1, POOL_SIZE + 1):
        write(os.path.join(DATA, "appearance", f"pool_{i:02d}.json"), make_appearance(rng, i))

    cities = CITIES[:]
    rng.shuffle(cities)
    for c in range(20):
        cid = f"club_{c + 1:02d}"
        division = 1 if c < 10 else 2
        level = (6 - c) if division == 1 else (-4 - (c - 10))  # D1 stronger than D2
        primary, secondary = rng.sample(COLORS, 2)
        kit = {"id": cid, "pattern": rng.choice(PATTERNS), "primary": primary, "secondary": secondary,
               "collar": secondary, "shorts": rng.choice([primary, secondary, "#ffffff", "#111111"]),
               "socks": primary, "number": secondary if secondary != primary else "#ffffff",
               "number_outline": "#111111" if secondary in ("#ffffff", "#f9a825") else "#ffffff",
               "crest": {"primary": primary, "secondary": secondary, "border": "#202020"}}
        gk = rng.choice(GK_KITS)
        gk_kit = {"id": cid + "_gk", "pattern": "plain", "sleeves": "long", "primary": gk[0], "secondary": gk[1],
                  "collar": gk[1], "shorts": "#111111", "socks": gk[0], "number": "#111111", "number_outline": "#ffffff"}
        write(os.path.join(DATA, "kits", cid + ".json"), kit)
        write(os.path.join(DATA, "kits", cid + "_gk.json"), gk_kit)
        squad = []
        for n, role in enumerate(SQUAD):
            p = make_player(rng, f"{cid}_p{n + 1:02d}", role, level, used_names)
            players.append(p)
            squad.append(p["id"])
        name = f"{rng.choice(PREFIX)} {cities[c]}"
        clubs.append({"id": cid, "name": name, "short": "".join(w[0] for w in name.split())[:3].upper() + str(c % 10),
                      "division": division, "kit": cid, "gk_kit": cid + "_gk", "formation": rng.choice(["4-4-2", "4-4-2", "4-3-3", "3-5-2"]),
                      "tactics": rng.choice(["equilibrado", "equilibrado", "presion_alta", "repliegue"]),
                      "prestige": max(1, min(5, 3 + level // 4)), "squad": squad})

    # The Master League starting team: modest generic players (like the original).
    master = []
    for n, role in enumerate(SQUAD[:20]):
        p = make_player(rng, f"master_p{n + 1:02d}", role, -14, used_names)
        p["age"] = rng.randint(21, 29)
        players.append(p)
        master.append(p["id"])
    write(os.path.join(DATA, "kits", "master.json"), {
        "id": "master", "pattern": "plain", "primary": "#e8e8e8", "secondary": "#1a237e", "collar": "#1a237e",
        "shorts": "#1a237e", "socks": "#e8e8e8", "number": "#1a237e", "number_outline": "#ffffff",
        "crest": {"primary": "#1a237e", "secondary": "#e8e8e8", "border": "#111111"}})
    write(os.path.join(DATA, "kits", "master_gk.json"), {
        "id": "master_gk", "pattern": "plain", "sleeves": "long", "primary": "#f2c200", "secondary": "#6b5600",
        "collar": "#6b5600", "shorts": "#111111", "socks": "#f2c200", "number": "#111111", "number_outline": "#ffffff"})

    write(os.path.join(DATA, "world", "world.json"), {
        "_doc": "Mundo ficticio de la Master League. 'division' 1 o 2. La Master League arranca con 'master_team' en la segunda división, en lugar del último club.",
        "name": "Liga Mundial WE", "season_start_year": 2002,
        "master_team": {"id": "master", "name": "Equipo Master", "short": "MST", "kit": "master", "gk_kit": "master_gk",
                        "formation": "4-4-2", "tactics": "equilibrado", "prestige": 1, "squad": master},
        "clubs": clubs})
    write(os.path.join(DATA, "world", "players.json"), {"players": players})
    print(f"world: {len(clubs)} clubs, {len(players)} players, {POOL_SIZE} appearances")


if __name__ == "__main__":
    main()
