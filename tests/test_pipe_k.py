"""A pipe's resistance follows its length and size, so cutting a device
into a line leaves the line's resistance as it was and moving equipment
changes it."""
from __future__ import annotations

import pytest

from sim.hydraulics import pipe_k


class TestPipeK:
    def test_it_is_proportional_to_length(self) -> None:
        assert pipe_k(20.0, 50) == pytest.approx(2.0 * pipe_k(10.0, 50))

    def test_two_pieces_are_the_whole(self) -> None:
        # A line cut in two is the same line: the pieces' resistances add
        # up to the whole's (friction only; bends go with whichever piece
        # has them).
        assert pipe_k(3.0, 50) + pipe_k(7.0, 50) == pytest.approx(pipe_k(10.0, 50))

    def test_it_falls_with_the_fifth_power_of_the_bore(self) -> None:
        assert pipe_k(10.0, 25) == pytest.approx(32.0 * pipe_k(10.0, 50))

    def test_a_bend_costs_about_a_metre_and_a_half_of_straight(self) -> None:
        bend = pipe_k(0.0, 50, 1.0)
        per_m = pipe_k(1.0, 50)
        assert 0.5 < bend / per_m < 1.5

    def test_the_magnitude_is_real_pipe(self) -> None:
        # DN50 at 3 L/s is 1.5 m/s: about 0.5 kPa a metre, a textbook
        # figure for water in 2-inch pipe.
        dp_per_m = pipe_k(1.0, 50) * 3.0 ** 2
        assert 350.0 < dp_per_m < 650.0
