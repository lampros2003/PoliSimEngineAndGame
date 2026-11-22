"""Stage S15.2: groups by belief, work and place; stances; twelve policies; twelve statistics
(docs/S15-PLAN.md; models/uk/politics/README.md, "Beliefs, work and places";
models/uk/POLICIES.md, "Stage S15.2"). Each test says in its name what it checks."""

from __future__ import annotations

import functools
import sys
import tomllib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))

from engine import Simulation, load_model  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
UK = ROOT / "models" / "uk"
SEED = 2025
SCENARIO = tomllib.loads((UK / "scenarios" / "2025.toml").read_text(encoding="utf-8"))
PARAMS = SCENARIO["params"]
NEW_GROUPS = ["socialists", "capitalists", "liberals", "conservatives", "environmentalists", "patriots",
              "public_sector", "trade_unionists", "farmers", "town", "countryside"]
STANCES = ["state", "order", "green", "nation"]
NEW_POLICIES = ["net_wealth_tax", "farm_support", "rail_ownership", "congestion_charge", "rd_grants", "onshore_wind",
                "free_childcare", "energy_bill_help", "identity_cards", "strike_limits"]
IN_FORCE = {"trade_union_law": 1, "public_pay_settlement": 0.0}
# Each statistic and its published 2024 level in the base month (money in pence).
LEVELS = {"inequality": 0.35, "rents": 132700.0, "house_prices": 26800000.0, "energy_bills": 173800.0,
          "strike_days": 600000.0, "business_confidence": 39.0, "farm_incomes": 770000000000.0, "congestion": 62.0,
          "air_pollution": 7.5, "research_development": 0.0271}


@functools.lru_cache(maxsize=None)
def model():
    return load_model(UK)


def default(name):
    return model().symbols[name].spec["default"]


@functools.lru_cache(maxsize=None)
def run(changes: tuple = (), steps: int = 13):
    """Every month's row and the simulation, with `changes` ((name, value), ...) from the second month."""
    sim = Simulation(model(), seed=SEED, params=PARAMS, commands={1: dict(changes)} if changes else None)
    return sim, sim.run(steps)


def approval(changes, group, steps=13):
    return run(changes, steps)[1][-1][f"approval_{group}"] - run((), steps)[1][-1][f"approval_{group}"]


class Groups(unittest.TestCase):
    def test_every_new_group_has_a_plausible_share(self):
        row = run(steps=1)[1][0]
        shares = {g: row[f"share_{g}"] for g in NEW_GROUPS}
        # Stage S16.2: the belief groups from More in Common's segments (tools/uk/segments.toml).
        self.assertAlmostEqual(shares["socialists"], 0.234, places=2)
        self.assertAlmostEqual(shares["liberals"], 0.264, places=2)
        self.assertAlmostEqual(shares["public_sector"], 6.14e6 / 53.5e6, places=2)
        self.assertAlmostEqual(shares["trade_unionists"], 6.4e6 / 53.5e6, places=2)
        self.assertLess(shares["farmers"], 0.02)
        self.assertAlmostEqual(shares["town"] + shares["countryside"], 1.0, places=12)
        self.assertGreater(shares["countryside"], 0.15)
        self.assertLess(shares["countryside"], 0.22)

    def test_london_has_no_countryside_and_more_liberals(self):
        sim, _ = run(steps=1)
        voters, member, region = sim.column("voters"), sim.column("group_member"), sim.column("type_region")
        groups = model().dims["group"].members
        n = len(groups)

        def share(key, r):
            g = groups.index(key)
            ts = [t for t in range(len(voters)) if region[t] == r]
            return sum(voters[t] * member[t * n + g] for t in ts) / sum(voters[t] for t in ts)
        self.assertEqual(share("countryside", 6), 0.0)
        self.assertGreater(share("liberals", 6), share("liberals", 2))

    def test_the_regions_and_smokers_leave_the_ring_but_stay_in_the_model(self):
        ring = [g["key"] for g in SCENARIO["play"]["web"]["groups"]]
        for key in ("scotland", "wales", "london", "north", "smokers"):
            self.assertNotIn(key, ring)
            self.assertIn(f"approval_{key}", run(steps=1)[1][0])
        for key in NEW_GROUPS:
            self.assertIn(key, ring)


class Segments(unittest.TestCase):
    """Stage S16.2: each belief group is a stated mix of More in Common's seven segments, whose
    sizes are published; the groups' national shares are the mix's arithmetic."""

    def test_the_six_groups_national_shares_equal_the_mappings_arithmetic(self):
        sys.path.insert(0, str(ROOT / "tools" / "uk"))
        import voters
        table = tomllib.loads((ROOT / "tools" / "uk" / "segments.toml").read_text(encoding="utf-8"))
        self.assertAlmostEqual(sum(v["size"] for v in table["segments"].values()), 1.0, places=12)
        expected = {g: sum(w * table["segments"][k]["size"] for k, w in mix.items() if k in table["segments"])
                    for g, mix in table["groups"].items()}
        self.assertEqual(expected, voters.segment_shares())
        # The membership written for the model (politics/estimated_groups.csv) holds them over
        # the base year's adults, by voter type.
        base = voters.base_voters(UK / "households" / "households.csv")
        members = voters.segment_members(base)
        for group, share in expected.items():
            got = sum(n * m for n, m in zip(base, members[group])) / sum(base)
            self.assertAlmostEqual(got, share, places=9, msg=group)
        self.assertAlmostEqual(expected["socialists"], 0.12 + 0.4 * 0.21 + 0.15 * 0.20, places=12)
        self.assertAlmostEqual(expected["patriots"], 0.8 * 0.20 + 0.8 * 0.08 + 0.4 * 0.20, places=12)

    def test_patriots_rise_with_age_as_yougov_found(self):
        sim, _ = run(steps=1)
        voters, member, age = sim.column("voters"), sim.column("group_member"), sim.column("type_age")
        groups = model().dims["group"].members
        n, g = len(groups), groups.index("patriots")

        def share(band):
            ts = [t for t in range(len(voters)) if age[t] == band]
            return sum(voters[t] * member[t * n + g] for t in ts) / sum(voters[t] for t in ts)
        self.assertGreater(share(4), 2.0 * share(0))


class Stances(unittest.TestCase):
    def test_the_stances_and_the_new_reactions_are_nil_at_the_2024_settings(self):
        sim, rows = run(steps=2)
        for s in STANCES:
            self.assertEqual(rows[0][f"stance_{s}"], 0.0, s)
        self.assertEqual(set(sim.column("belief_standing")), {0.0})

    def test_tax_and_spend_pleases_socialists_and_angers_capitalists_and_the_country_barely_moves(self):
        move = (("basic_rate", 0.25), ("spending_health", round(default("spending_health") * 1.1)))
        self.assertAlmostEqual(run(move)[1][-1]["stance_state"], 2.0, places=6)
        self.assertGreater(approval(move, "socialists") - approval(move, "capitalists"), 0.01)
        self.assertGreater(approval(move, "socialists"), 0.0)
        self.assertLess(abs(run(move)[1][-1]["government_support"] - run()[1][-1]["government_support"]), 0.01)

    def test_law_and_order_pleases_conservatives_and_angers_liberals(self):
        move = (("sentencing", 3), ("visa_threshold", 43700))
        self.assertGreater(approval(move, "conservatives"), 0.01)
        self.assertLess(approval(move, "liberals"), -0.01)
        self.assertLess(abs(run(move)[1][-1]["government_support"] - run()[1][-1]["government_support"]), 0.01)

    def test_green_and_national_moves_split_their_groups(self):
        green = (("carbon_price", 50), ("onshore_wind", 100_000_000))
        self.assertGreater(approval(green, "environmentalists"), approval(green, "motorists") + 0.005)
        nation = (("trade_barrier_eu", 0.05), ("spending_defence", round(default("spending_defence") * 1.1)))
        self.assertGreater(approval(nation, "patriots"), approval(nation, "liberals") + 0.01)


    def test_a_stance_move_leaves_the_electorates_mean_reaction_nil(self):
        # Each side counts by membership over its share of adults, and town and countryside by
        # membership less share, so the mean over the electorate is nil whatever the move.
        for move in ((("sentencing", 4), ("visa_threshold", 50000)), (("basic_rate", 0.3), ("fuel_duty", 70.0)),
                     (("carbon_price", 100), ("planning_rules", 4), ("trade_barrier_eu", 0.2))):
            sim, _ = run(move)
            voters, belief = sim.column("voters"), sim.column("belief_standing")
            self.assertNotEqual(max(abs(b) for b in belief), 0.0)
            mean = sum(v * b for v, b in zip(voters, belief)) / sum(voters)
            self.assertLess(abs(mean), 1e-12, move)


class Strategies(unittest.TestCase):
    def test_the_reformer_does_not_lose_to_doing_nothing(self):
        sys.path.insert(0, str(ROOT / "tools" / "uk"))
        import strategies
        scenario = strategies.load_scenario(strategies.SCENARIO)
        seats = {k: strategies.play(scenario, k)["election"][1][0] for k in ("a", "e")}
        self.assertGreaterEqual(seats["e"], seats["a"])


class Policies(unittest.TestCase):
    def test_the_new_policies_start_not_in_force_and_two_are_in_force(self):
        for name in NEW_POLICIES:
            self.assertEqual(default(name), 0, name)
        for name, value in IN_FORCE.items():
            self.assertEqual(default(name), value, name)
        offs = {p["levers"][0] for a in SCENARIO["play"]["web"]["areas"] for p in a["policies"] if "off" in p}
        self.assertTrue(set(NEW_POLICIES) <= offs)

    def test_every_new_policy_has_a_stance_and_a_capital_weight(self):
        sys.path.insert(0, str(ROOT / "tools" / "uk"))
        import beliefs
        for name in NEW_POLICIES + list(IN_FORCE):
            self.assertIn(name, beliefs.STANCES, name)
            self.assertIn("capital_weight", model().symbols[name].spec, name)

    def test_the_wealth_tax_raises_receipts_and_the_rich_dislike_it(self):
        sim, rows = run((("net_wealth_tax", 0.01),))
        self.assertGreater(rows[-1]["tax_burden"], run()[1][-1]["tax_burden"])
        self.assertLess(rows[-1]["inequality"], run()[1][-1]["inequality"])
        self.assertLess(approval((("net_wealth_tax", 0.01),), "high_income"), approval((("net_wealth_tax", 0.01),), "low_income"))

    def test_farm_support_raises_farm_incomes_and_farmers_like_it(self):
        move = (("farm_support", 100_000_000),)
        self.assertGreater(run(move)[1][-1]["farm_incomes"], run()[1][-1]["farm_incomes"] * 1.1)
        self.assertGreater(approval(move, "farmers"), approval(move, "town"))

    def test_rail_ownership_and_congestion_charging_cut_congestion(self):
        for move in ((("rail_ownership", 1),), (("congestion_charge", 5.0),)):
            self.assertLess(run(move)[1][-1]["congestion"], run()[1][-1]["congestion"], move)
        self.assertLess(approval((("congestion_charge", 5.0),), "motorists"), approval((("congestion_charge", 5.0),), "town"))

    def test_research_grants_raise_research_and_onshore_wind_lowers_bills(self):
        self.assertGreater(run((("rd_grants", 200_000_000),))[1][-1]["research_development"],
                           run()[1][-1]["research_development"] + 0.001)
        wind = (("onshore_wind", 200_000_000),)
        self.assertLess(run(wind, 25)[1][-1]["energy_bills"], run((), 25)[1][-1]["energy_bills"])
        self.assertLess(approval(wind, "countryside"), approval(wind, "town"))

    def test_childcare_help_with_bills_and_identity_cards_reach_their_groups(self):
        self.assertGreater(approval((("free_childcare", 1),), "parents"), approval((("free_childcare", 1),), "pensioners"))
        help_ = (("energy_bill_help", 300),)
        self.assertLess(run(help_)[1][-1]["energy_bills"], run()[1][-1]["energy_bills"] - 25000)
        self.assertGreater(approval(help_, "low_income"), approval(help_, "high_income"))
        cards = (("identity_cards", 1),)
        self.assertGreater(approval(cards, "pensioners"), approval(cards, "young"))
        self.assertLess(run(cards)[1][-1]["crime_incidents"], run()[1][-1]["crime_incidents"])

    def test_strike_law_and_public_pay_move_strikes_and_the_unions(self):
        base = run()[1][-1]["strike_days"]
        self.assertLess(run((("strike_limits", 1),))[1][-1]["strike_days"], base * 0.9)
        self.assertGreater(run((("trade_union_law", 0),))[1][-1]["strike_days"], base * 1.2)
        self.assertLess(approval((("strike_limits", 1),), "trade_unionists"), approval((("strike_limits", 1),), "pensioners"))
        pay = (("public_pay_settlement", 0.02),)
        self.assertLess(run(pay)[1][-1]["strike_days"], base)
        self.assertGreater(approval(pay, "public_sector"), approval(pay, "capitalists"))
        self.assertGreater(run(pay)[1][-1]["public_pay"], run()[1][-1]["public_pay"] * 1.01)


class Statistics(unittest.TestCase):
    def test_each_new_statistic_starts_at_its_published_2024_level(self):
        row = run(steps=1)[1][0]
        for name, level in LEVELS.items():
            self.assertAlmostEqual(row[name], level, places=6, msg=name)
        self.assertAlmostEqual(row["tax_burden"], 1121.3 / 2904.9, places=3)
        self.assertAlmostEqual(row["trade_balance"] * 12 / 100 / 1e9, 882.4 - 903.5, delta=0.5)

    def test_the_gini_comes_from_the_households(self):
        sim, rows = run(steps=1)
        self.assertGreater(rows[0]["gini_households"], 0.25)
        self.assertLess(rows[0]["gini_households"], 0.45)
        # A higher Universal Credit and a higher top rate narrow it.
        more = run((("uc_single", round(default("uc_single") * 1.3, 2)), ("additional_rate", 0.5)))[1][-1]["inequality"]
        self.assertLess(more, run()[1][-1]["inequality"])

    def test_rent_controls_slow_rents_and_mortgage_rates_move_house_prices(self):
        self.assertLess(run((("rent_controls", 2),), 25)[1][-1]["rents"], run((), 25)[1][-1]["rents"])
        dear = run((("gilt_yield_shift", 0.02),), 25)[1][-1]["house_prices"]
        self.assertLess(dear, run((), 25)[1][-1]["house_prices"] * 0.99)

    def test_air_pollution_feeds_healthy_life_and_research_feeds_productivity(self):
        charge = run((("congestion_charge", 10.0),), 25)[1][-1]
        base = run((), 25)[1][-1]
        self.assertLess(charge["air_pollution"], base["air_pollution"])
        self.assertGreater(charge["healthy_life_expectancy"], base["healthy_life_expectancy"])
        grants = run((("rd_grants", 400_000_000),), 25)[1][-1]
        self.assertGreater(grants["productivity"], base["productivity"])

    def test_corporation_tax_lowers_business_confidence(self):
        self.assertLess(run((("corporation_tax_rate", 0.30),))[1][-1]["business_confidence"],
                        run()[1][-1]["business_confidence"] - 3.0)

    def test_situations_name_the_statistic_that_sets_them_off(self):
        mapping = SCENARIO["play"]["web"]["situations"]
        names = [d.name for d in model().symbols.values() if d.spec.get("situation")]
        rows = run(steps=1)[1][0]
        for n in names:
            self.assertIn(n, mapping, n)
            self.assertIn(mapping[n], rows, n)

    def test_a_squeeze_on_public_pay_brings_a_wave_of_strikes(self):
        _, rows = run((("public_pay_settlement", -0.02),), 37)
        self.assertTrue(any(r["strike_wave"] for r in rows))


class Board(unittest.TestCase):
    def test_about_eighty_nodes_in_force(self):
        web = SCENARIO["play"]["web"]
        indicators = sum(len(a["indicators"]) for a in web["areas"])
        in_force = 0
        for a in web["areas"]:
            for p in a["policies"]:
                lever = p["levers"][0]
                if "off" not in p or default(lever) != p["off"] and not (isinstance(default(lever), int) and model().symbols[lever].money and default(lever) == round(p["off"])):
                    in_force += 1
        self.assertEqual(indicators, 41)
        self.assertEqual(in_force, 40)

    def test_every_board_row_exists(self):
        row = run(steps=1)[1][0]
        for a in SCENARIO["play"]["web"]["areas"]:
            for i in a["indicators"]:
                self.assertIn(i["row"], row, i["row"])


if __name__ == "__main__":
    unittest.main()
