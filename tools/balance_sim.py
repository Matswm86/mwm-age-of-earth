"""Age of Earth balance sim: economy pacing to each age-up, plus equal-cost counter fights.

Reads data/balance.json (the single balance file) and plays one side's economy second by second
with the AI profile rules (easy / normal / hard). No opponent pressure: this is the pace an
undisturbed band reaches, i.e. the upper bound on speed. Prints a timeline and PASS/FAIL against
the GDD pacing targets (section 7.1).

Run: python3 tools/balance_sim.py            (all profiles + counter check)
     python3 tools/balance_sim.py --trace normal   (minute-by-minute log for one profile)
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
B = json.loads((ROOT / "data" / "balance.json").read_text())

RES = ("food", "wood", "stone", "ochre")
SIM_END_S = 25 * 60

# Pacing targets (GDD 7.1). Normal = reference player. (lo, hi) minutes, age reached.
TARGETS = {
    "easy": {"age2": (8.0, 11.0), "age3": (17.0, 24.0)},
    "normal": {"age2": (6.5, 9.0), "age3": (13.0, 16.5)},
    "hard": {
        "age2": (6.0, 9.0),
        "age3": (13.0, 17.0),
    },  # Hard ages like Normal but fields more army (checked below)
}

# Age-up prerequisite buildings the AI builds, in order (GDD 9.2 build orders).
AGE1_BUILDS = ["knapping_floor", "display_ground", "throwing_ground"]
AGE2_BUILDS = ["ochre_cache", "watch_fire"]  # ochre first: Age 3 needs ochre
ECO_TECHS = {
    1: ["digging_sticks"],
    2: ["carry_slings"],
    3: ["cooking", "handaxe", "heat_treated_stone"],
}


def cost(d: dict) -> dict:
    return {r: d.get(r, 0) for r in RES}


def can_pay(wallet: dict, c: dict) -> bool:
    return all(wallet[r] >= c[r] for r in RES)


def pay(wallet: dict, c: dict) -> None:
    for r in RES:
        wallet[r] -= c[r]


@dataclass
class Source:
    kind: str
    left: float
    dist: float
    dist_cache: float
    renewable: bool
    slots: int = 99
    cached: bool = False


@dataclass
class Side:
    prof: dict
    name: str
    t: int = 0
    age: int = 1
    eco: dict = field(default_factory=dict)  # wallet for foragers, buildings, techs, age-ups
    army_w: dict = field(default_factory=dict)  # wallet for military
    foragers: int = 0
    builders: int = 0  # foragers busy building (no income)
    pop_cap: int = 5
    army: dict = field(default_factory=dict)
    army_spent: float = 0.0
    techs: set = field(default_factory=set)
    buildings: dict = field(default_factory=dict)
    jobs: list = field(default_factory=list)  # [name, seconds_left, kind]  kind: build/tech/train
    home_busy: int = 0  # seconds the Home Tree is busy (training or researching)
    assign: dict = field(default_factory=lambda: {r: 0 for r in RES})
    sources: dict = field(default_factory=dict)
    events: list = field(default_factory=list)
    log: list = field(default_factory=list)

    def __post_init__(self) -> None:
        m = B["match"]
        self.eco = cost(m["start_resources"])
        self.army_w = {r: 0.0 for r in RES}
        self.foragers = m["start_units"]["forager"]
        self.buildings = {"home_tree": 1}
        for r in RES:
            self.sources[r] = [
                Source(
                    s["kind"],
                    s["amount"],
                    s["dist_m"],
                    s["dist_cache_m"],
                    s["amount"] < 0,
                    s["slots"],
                )
                for s in B["map_resources_per_player"][r]
            ]
        self.assign = {"food": 3, "wood": 1, "stone": 0, "ochre": 0}

    # ---- economy -------------------------------------------------------------
    def allowed(self, kind: str) -> bool:
        need = B["gather"]["need_tech"].get(kind)
        if need is None:
            return True
        return self.age >= int(need[-1])

    def active_source(self, r: str) -> Source | None:
        for s in self.sources[r]:
            if (s.renewable or s.left >= 20) and self.allowed(s.kind):
                if s.kind == "fish_weir" and self.buildings.get("fish_weir", 0) == 0:
                    continue
                return s
        return None

    def mult(self, kind: str) -> float:
        m = 1.0
        for tname in self.techs:
            t = B["techs"].get(tname, {})
            m *= t.get("effect", {}).get("gather_mult", {}).get(kind, 1.0)
        return m

    def carry(self) -> float:
        c = B["gather"]["carry"]
        for tname in self.techs:
            c += B["techs"].get(tname, {}).get("effect", {}).get("carry_add", 0)
        return c

    def eff_rate(self, s: Source) -> float:
        g = B["gather"]
        rate = g["rates"][s.kind] * self.mult(s.kind)
        d = s.dist_cache if s.cached else s.dist
        speed = B["units"]["forager"]["speed"]
        c = self.carry()
        return c / (c / rate + 2 * d / speed + g["drop_s"])

    def gather_tick(self) -> None:
        working = self.foragers - self.builders
        total_assigned = sum(self.assign.values())
        scale = min(1.0, working / total_assigned) if total_assigned else 0.0
        scale *= 1.0 - self.prof["idle_frac"]
        split = self.split()
        for r in RES:
            n = self.assign[r] * scale
            # fill sources nearest first, up to their worker slots (a source under 20 units counts as empty)
            for src in self.sources[r]:
                if n <= 0:
                    break
                if not self.allowed(src.kind) or (not src.renewable and src.left < 20):
                    continue
                cap = self.buildings.get("fish_weir", 0) if src.kind == "fish_weir" else src.slots
                k = min(n, cap)
                if k <= 0:
                    continue
                n -= k
                amt = k * self.eff_rate(src)
                if not src.renewable:
                    amt = min(amt, src.left)
                    src.left -= amt
                self.eco[r] += amt * (1 - split)
                self.army_w[r] += amt * split
        # fig trees regrow
        fruit = self.sources["food"][0]
        fruit.left = min(600.0, fruit.left + 6 * B["fruit_regrow_per_s_per_tree"])

    def split(self) -> float:
        """Share of income that goes to the army wallet."""
        f = self.prof["army_frac"]
        if self.age >= 2:
            return f[self.age - 1]
        if self.t >= 240:
            return f[0]  # small age-1 defence force
        return 0.0

    # ---- decisions -----------------------------------------------------------
    def next_goal(self) -> dict:
        """Everything still to buy this age (buildings, techs, age-up, houses) plus a few army units."""
        need: dict = {r: 0.0 for r in RES}

        def add(c: dict, k: float = 1.0) -> None:
            for r in RES:
                need[r] += c.get(r, 0) * k

        if self.age == 1:
            for b in AGE1_BUILDS[:2]:
                if not self.buildings.get(b):
                    add(B["buildings"][b]["cost"])
            todo = ["stone_that_cuts", *ECO_TECHS[1], "age_2_fire"]
        elif self.age == 2:
            for b in AGE2_BUILDS:
                if not self.buildings.get(b):
                    add(B["buildings"][b]["cost"])
            todo = [*ECO_TECHS[2], "age_3_words"]
        else:
            add(B["buildings"]["story_circle"]["cost"])
            add(B["buildings"]["fish_weir"]["cost"], 4)
            todo = ECO_TECHS[3]
        for t in todo:
            if t not in self.techs:
                add(B["techs"][t]["cost"])
        add({"wood": 60})  # houses
        self.raw_need = dict(need)
        eco_need = {r: max(need[r] - self.eco[r], 0.0) for r in RES}
        army_need = {r: 0.0 for r in RES}
        if self.split() > 0:
            for u in self.army_mix():
                for r, v in B["units"][u]["cost"].items():
                    army_need[r] += v * 3
        return {r: eco_need[r] + max(army_need[r] - self.army_w[r], 0.0) for r in RES}

    def army_mix(self) -> list:
        mix = {
            1: ["bruiser", "stone_thrower"],
            2: ["spear_bearer", "stone_thrower", "runner", "bruiser"],
            3: ["stone_thrower", "spear_bearer", "bruiser", "runner", "torch_bearer"],
        }[self.age]
        return [
            n
            for n in mix
            if B["units"][n]["from"] == "home_tree" or self.buildings.get(B["units"][n]["from"], 0)
        ]

    def reassign(self) -> None:
        """Greedy: each forager goes where (missing resource) / (rate) is largest."""
        self.next_goal()  # refreshes raw_need for the wallet rebalance
        n = self.foragers
        sp = self.prof["gather_split"][self.age - 1]
        new = {r: int(n * sp[r]) for r in RES}
        rest = n - sum(new.values())
        for r in sorted(RES, key=lambda r: -(n * sp[r] - int(n * sp[r])))[:rest]:
            new[r] += 1
        self.assign = new
        if self.prof["uses_caches"]:
            # a Cache goes beside any source with 3+ foragers that is far from a drop site
            for r in RES:
                n = new[r]
                for i, src in enumerate(self.sources[r]):
                    if n <= 0:
                        break
                    if not self.allowed(src.kind) or (not src.renewable and src.left < 20):
                        continue
                    k = min(n, src.slots)
                    n -= k
                    caches = self.buildings.get("cache", 0) + sum(
                        1 for j in self.jobs if j[0] == "cache"
                    )
                    if (
                        k >= 3
                        and not src.cached
                        and src.dist > src.dist_cache + 5
                        and caches < 8
                        and r != "ochre"
                    ):
                        self.start_build("cache", tag=f"{r}:{i}")

    def start_build(self, name: str, tag: str | None = None) -> bool:
        if any(j[0] == name and j[2] == "build" and j[3] == tag for j in self.jobs):
            return False
        b = B["buildings"][name]
        c = cost(b.get("cost", {}))
        if not can_pay(self.eco, c):
            return False
        pay(self.eco, c)
        nb = 2 if b["build_s"] >= 60 else 1
        self.builders += nb
        self.jobs.append([name, b["build_s"] // nb + 8, "build", tag, nb])
        return True

    def start_tech(self, name: str) -> bool:
        t = B["techs"].get(name) or B["line_upgrades"][name]
        if name in self.techs or any(j[0] == name for j in self.jobs):
            return False
        if self.buildings.get(t["at"], 0) == 0:
            return False
        if t["at"] == "home_tree" and self.home_busy > 0:
            return False
        c = cost(t["cost"])
        if not can_pay(self.eco, c):
            return False
        pay(self.eco, c)
        self.jobs.append([name, t["time_s"], "tech", None, 0])
        if t["at"] == "home_tree":
            self.home_busy = t["time_s"]
        self.events.append((self.t, f"start {name}"))
        return True

    def decide(self) -> None:
        p = self.prof
        pop = self.foragers + sum(self.army.values()) + sum(1 for j in self.jobs if j[2] == "train")
        # houses
        houses_building = sum(1 for j in self.jobs if j[0] in ("nest_grove", "windbreak"))
        if (
            self.pop_cap - pop <= 2 + 2 * houses_building
            and self.pop_cap < B["match"]["pop_cap_max"]
            and houses_building < 2
        ):
            self.start_build("nest_grove" if self.age == 1 else "windbreak", tag=str(self.t))
        # foragers
        target = p["forager_target"][self.age - 1]
        if self.home_busy == 0 and self.foragers < target and pop < self.pop_cap:
            c = cost(B["units"]["forager"]["cost"])
            if can_pay(self.eco, c):
                pay(self.eco, c)
                tr = B["units"]["forager"]["train_s"]
                if "shared_names" in self.techs:
                    tr = int(tr * 0.85)
                self.jobs.append(["forager", tr, "train", None, 0])
                self.home_busy = tr
        # buildings and techs on the road to the next age
        if self.age == 1:
            for b in AGE1_BUILDS[:2]:
                if self.buildings.get(b, 0) == 0 and self.t > 90:
                    self.start_build(b)
                    break
            for tn in ECO_TECHS[1]:
                if self.t > 200:
                    self.start_tech(tn)
            if self.t > 120:
                self.start_tech("stone_that_cuts")
            built1 = sum(self.buildings.get(b, 0) for b in AGE1_BUILDS)
            if (
                "stone_that_cuts" in self.techs
                and built1 >= 2
                and self.t >= p["age2_click_min"] * 60
                and self.foragers >= target - 1
            ):
                self.start_tech("age_2_fire")
        elif self.age == 2:
            for b in AGE2_BUILDS:
                if self.buildings.get(b, 0) == 0:
                    self.start_build(b)
                    break
            for tn in ECO_TECHS[2]:
                self.start_tech(tn)
            built2 = sum(self.buildings.get(b, 0) for b in AGE2_BUILDS)
            if built2 >= 2 and self.t >= p["age3_click_min"] * 60 and self.foragers >= target - 2:
                self.start_tech("age_3_words")
        else:
            if self.buildings.get("story_circle", 0) == 0:
                self.start_build("story_circle")
            if self.buildings.get("fish_weir", 0) < 4 and self.sources["food"][4].left < 300:
                self.start_build("fish_weir", tag=str(self.buildings.get("fish_weir", 0)))
            for tn in ECO_TECHS[3]:
                self.start_tech(tn)
        self.train_army()

    def train_army(self) -> None:
        """Spend the army wallet on the age's main units (counter-pick off: fixed mix)."""
        if sum(self.army.values()) >= self.prof["max_army"]:
            return
        pop = self.foragers + sum(self.army.values()) + sum(1 for j in self.jobs if j[2] == "train")
        if pop >= self.pop_cap:
            return
        queued = sum(1 for j in self.jobs if j[2] == "train" and j[0] != "forager")
        slots = 2 if self.age == 1 else 3
        if queued >= slots:
            return
        mix = [n for n in self.army_mix() if can_pay(self.army_w, cost(B["units"][n]["cost"]))]
        if not mix:
            return
        u = min(mix, key=lambda n: self.army.get(n, 0))
        ud = B["units"][u]
        c = cost(ud["cost"])
        if can_pay(self.army_w, c):
            pay(self.army_w, c)
            self.army_spent += sum(c.values())
            self.jobs.append([u, ud["train_s"], "train", None, 0])

    # ---- clock ---------------------------------------------------------------
    def rebalance(self) -> None:
        """Save for the next eco goal, spend the rest: eco surplus flows to the army wallet and back."""
        if self.split() <= 0:
            return
        for r in RES:
            extra = self.eco[r] - self.raw_need.get(r, 0.0)
            if extra > 0:
                self.eco[r] -= extra
                self.army_w[r] += extra
            # the army keeps at most two of its dearest unit's cost of each resource
            cap = 2 * max((B["units"][u]["cost"].get(r, 0) for u in self.army_mix()), default=0)
            if self.army_w[r] > cap:
                self.eco[r] += self.army_w[r] - cap
                self.army_w[r] = cap

    def tick(self) -> None:
        if self.t % 20 == 0:
            self.reassign()
            self.rebalance()
        self.decide()
        self.gather_tick()
        if self.home_busy > 0:
            self.home_busy -= 1
        done = []
        for j in self.jobs:
            j[1] -= 1
            if j[1] <= 0:
                done.append(j)
        for j in done:
            self.jobs.remove(j)
            name, _, kind, tag, nb = j
            if kind == "build":
                self.builders -= nb
                self.buildings[name] = self.buildings.get(name, 0) + 1
                self.pop_cap = min(
                    B["match"]["pop_cap_max"], self.pop_cap + B["buildings"][name].get("pop", 0)
                )
                if name == "cache" and tag:
                    r, i = tag.split(":")
                    self.sources[r][int(i)].cached = True
                    self.events.append((self.t, f"built cache at {self.sources[r][int(i)].kind}"))
                if name == "ochre_cache":
                    for src in self.sources["ochre"]:
                        src.cached = True
                if name in AGE1_BUILDS + AGE2_BUILDS + ["story_circle"]:
                    self.events.append((self.t, f"built {name}"))
            elif kind == "tech":
                self.techs.add(name)
                self.events.append((self.t, f"done {name}"))
                if name == "age_2_fire":
                    self.age = 2
                    if self.prof["uses_caches"]:
                        self.start_build(
                            "cache", tag="food:3"
                        )  # build order: Cache at the antelope herd on arrival
                if name == "age_3_words":
                    self.age = 3
            else:
                if name == "forager":
                    self.foragers += 1
                else:
                    self.army[name] = self.army.get(name, 0) + 1
        if self.t % 60 == 0:
            self.log.append(
                (
                    self.t // 60,
                    self.age,
                    self.foragers,
                    sum(self.army.values()),
                    self.pop_cap,
                    {r: int(self.eco[r]) for r in RES},
                    dict(self.assign),
                )
            )
        self.t += 1


def run(name: str) -> Side:
    s = Side(B["ai_profiles"][name], name)
    while s.t <= SIM_END_S:
        s.tick()
    return s


def when(s: Side, label: str) -> float | None:
    for t, e in s.events:
        if e == label:
            return t / 60
    return None


# ---- counter check -------------------------------------------------------------
def unit_dmg(a: dict, t: dict, tclass: str) -> float:
    mult = B["counters"].get(a["class"], {}).get(tclass, 1.0)
    arm = t["armour"][1] if a["range_m"] > 0 else t["armour"][0]
    return max(1.0, a["atk"] * mult - arm)


def fight(an: str, bn: str, budget: float = 600.0) -> tuple[str, int, int, int, int]:
    """Equal-cost brawl, focus fire, ranged side gets free volleys while melee closes the gap."""
    A, Bu = B["units"][an], B["units"][bn]
    na = int(budget // sum(A["cost"].values()))
    nb = int(budget // sum(Bu["cost"].values()))
    ha = [float(A["hp"])] * na
    hb = [float(Bu["hp"])] * nb
    start_a, start_b = na, nb
    gap = max(A["range_m"], Bu["range_m"]) - min(A["range_m"], Bu["range_m"])
    closing = 0.0
    if gap > 0:
        closer = A if A["range_m"] < Bu["range_m"] else Bu
        closing = gap / closer["speed"]
    t = 0.0
    dt = 0.1
    while ha and hb and t < 300:
        # melee crowding: at most 6 melee attackers reach one target group per side front
        def dps(side, n, other, oclass, ranged_ok):
            if not ranged_ok:
                return 0.0
            reach = n if side["range_m"] > 0 else min(n, 6 + n // 3)
            return reach * unit_dmg(side, other, oclass) / side["rof_s"]

        a_ok = t >= closing or A["range_m"] >= Bu["range_m"]
        b_ok = t >= closing or Bu["range_m"] >= A["range_m"]
        da = dps(A, len(ha), Bu, Bu["class"], a_ok) * dt
        db = dps(Bu, len(hb), A, A["class"], b_ok) * dt
        hb[0] -= da
        ha[0] -= db
        if hb[0] <= 0:
            hb.pop(0)
        if ha[0] <= 0:
            ha.pop(0)
        t += dt
    win = an if ha and not hb else bn if hb and not ha else "draw"
    return win, start_a, len(ha), start_b, len(hb)


def main() -> None:
    if len(sys.argv) == 3 and sys.argv[1] == "--trace":
        s = run(sys.argv[2])
        print("min age foragers army cap  eco_wallet  assign")
        for row in s.log:
            print(*row)
        for t, e in s.events:
            print(f"{t // 60:02d}:{t % 60:02d} {e}")
        return

    print("ECONOMY PACING (undisturbed band, same income rules for every profile)")
    print(
        f"{'profile':8} {'cuts':>6} {'age2 go':>8} {'age2':>6} {'age3 go':>8} {'age3':>6} {'forag@10':>9} {'army@15':>8} {'army@20':>8} {'army res@20':>12}  verdict"
    )
    ok_all = True
    army20 = {}
    for name in ("easy", "normal", "hard"):
        s = run(name)
        cuts = when(s, "done stone_that_cuts")
        a2g, a2 = when(s, "start age_2_fire"), when(s, "done age_2_fire")
        a3g, a3 = when(s, "start age_3_words"), when(s, "done age_3_words")
        f10 = s.log[10][2]
        army15, army20[name] = s.log[15][3], s.log[20][3]
        tg = TARGETS[name]
        ok = (
            a2 is not None
            and a3 is not None
            and tg["age2"][0] <= a2 <= tg["age2"][1]
            and tg["age3"][0] <= a3 <= tg["age3"][1]
        )
        ok_all &= ok

        def f(x):
            return f"{x:6.1f}" if x is not None else "   n/a"

        # army resources at 20 min (approx: spent so far)
        print(
            f"{name:8} {f(cuts)} {f(a2g):>8} {f(a2)} {f(a3g):>8} {f(a3)} {f10:9d} {army15:8d} {army20[name]:8d} {int(s.army_spent):12d}  {'PASS' if ok else 'FAIL'} (target age2 {tg['age2']}, age3 {tg['age3']})"
        )

    order_ok = army20["easy"] < army20["normal"] < army20["hard"]
    ok_all &= order_ok
    print(
        f"army at 20 min rises with difficulty (easy < normal < hard): {'PASS' if order_ok else 'FAIL'}"
    )
    print()
    print("COUNTER CHECK (equal 600-resource armies, no upgrades, focus fire)")
    pairs = [
        ("stone_thrower", "bruiser"),
        ("runner", "stone_thrower"),
        ("spear_bearer", "runner"),
        ("bruiser", "spear_bearer"),
        ("bruiser", "runner"),
        ("stone_thrower", "spear_bearer"),
    ]
    for a, b in pairs:
        win, na, la, nb, lb = fight(a, b)
        expect = a
        good = win == expect
        ok_all &= good
        print(
            f"{a:14} ({na:2d}) vs {b:14} ({nb:2d}) -> winner {win:14} survivors {la}/{na} vs {lb}/{nb}  {'PASS' if good else 'FAIL'}"
        )
    print()
    print("ALL PASS" if ok_all else "SOME FAIL")


if __name__ == "__main__":
    main()
