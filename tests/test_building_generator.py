"""The building generator and its validator (tools/building/): the test
house is clean, bad parameters are refused, and each kind of fault a
building can have is found."""
import copy
import json
import os
import sys

import pytest

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "tools", "building"))

import arch  # noqa: E402
from validate import Validator  # noqa: E402

with open(os.path.join(HERE, "..", "tools", "building", "examples", "cottage.json"), encoding="utf-8") as f:
    COTTAGE = json.load(f)


def checks(data: dict) -> set:
    m = arch.Model(data).generate()
    v = Validator(m)
    v.run()
    return {f.check for f in v.findings}


def mutate(fn) -> dict:
    d = copy.deepcopy(COTTAGE)
    fn(d)
    return d


def test_the_test_house_is_a_building():
    assert checks(COTTAGE) == set()


def test_a_window_into_the_roof_is_found():
    def f(d):
        d["openings"].append({"at": [20, 0], "w": 3.0, "sill": 12.5, "head": 19.5})
    assert checks(mutate(f)) & {"openings", "overlap", "fitted"}


def test_walls_with_no_roof_over_them_are_found():
    def f(d):
        d["roofs"] = [r for r in d["roofs"] if r["id"] != "wing"]
        d["openings"] = [o for o in d["openings"] if o["at"][0] != 60]
    found = checks(mutate(f))
    assert "generation" in found and "sealed" in found


def test_a_short_chimney_is_found():
    def f(d):
        d["chimneys"][0]["top"] = 33.0
    assert "chimneys" in checks(mutate(f))


def test_a_porch_over_a_room_is_found():
    def f(d):
        d["spaces"][-1]["poly"] = {"rect": [10, 26, 30, 38]}
    assert "overlap" in checks(mutate(f))


@pytest.mark.parametrize("change", [
    lambda d: d["roofs"][0].update(footprint=[[0, 0], [40, 0], [40, 30], [20, 15], [0, 30]]),
    lambda d: d["roofs"][0].update(pitch=45.0),
    lambda d: d["roofs"][2].update(plate=40.0),
    lambda d: d["openings"].append({"at": [15, 15], "w": 3.0, "sill": 3.0, "head": 8.0}),
    lambda d: d["roofs"][1].update(sides={"x1": {"kind": "gable", "rake": 12.0}}),
])
def test_bad_parameters_are_refused(change):
    with pytest.raises(arch.GenError):
        arch.Model(mutate(change)).generate()
