"""The hydraulic network: pressure drives flow.

Before this existed, flow was *asserted*. A pump moved 2 L/s because it
was labelled a 2 L/s pump, a valve passed a linear fraction of its Cv
regardless of what was across it, and every consumer had to announce
what it took on a ``draw`` wire so the supplier could decrement its
inventory. That draw wire was double-entry bookkeeping wearing the
costume of a pipe, and it showed: a supply header, which physically has
no inlet at all, carried one.

Here flow is *solved*. The plant's material connections form a network
of nodes at some pressure, joined by branches with a hydraulic
character. Headers and vessels set boundary pressures; pumps add head;
valves and pipe runs resist. What flows is whatever satisfies all of
them at once.

Three things fall out of this that no amount of bookkeeping would give:

  * A tee is not a component. A node where three branches meet splits
    flow by their resistances, because that is what a node *is*.
  * A pump has a curve, so it dead-heads against too much discharge
    pressure and two in parallel do not double the flow.
  * "Why is my flow low?" has an answer you can trace, which the game
    needs as a verb.

Method: nodal Newton-Raphson. Each free node carries one unknown
pressure and one equation -- that the flows into it sum to zero. Every
branch can state its flow given the pressure across it, and the slope of
that relation, which is all Newton needs. Warm-started from the previous
tick the state barely moves between scans, so it converges in two or
three iterations.

Units throughout: pressure in Pa gauge, flow in L/s, and one density for
everything (see ``RHO``), consistent with the kernel's 1 L = 1 kg basis.
"""
from __future__ import annotations

import math

# One density for every liquid, matching the kernel's aqueous basis.
# Carrying a real density per species would mean the mass and volume
# bookkeeping everywhere else stopped agreeing, for very little.
RHO_KG_PER_M3 = 1000.0
G = 9.81

# Pa of static head per metre of liquid: 9810, near enough 9.8 kPa/m.
HEAD_PA_PER_M = RHO_KG_PER_M3 * G

ATMOSPHERIC_PA = 0.0          # gauge
# Nothing may be pulled below a hard vacuum. A branch demanding more
# than the system can deliver pins its suction node here, which is what
# a component should read as cavitation.
MIN_PRESSURE_PA = -101_300.0

# Below this pressure difference a branch is treated as linear, so the
# Jacobian of a square-law element stays finite through zero flow.
_DP_FLOOR_PA = 1.0
_EPS = 1e-12


class Branch:
    """One flow path between two nodes.

    Sign convention everywhere: ``dp`` is P(node_a) - P(node_b), and a
    positive flow runs from a to b.
    """

    def __init__(self, node_a: int, node_b: int, name: str = "") -> None:
        self.node_a = node_a
        self.node_b = node_b
        self.name = name
        self.flow_lps = 0.0     # filled in by the solve

    def flow(self, dp: float) -> float:
        raise NotImplementedError

    def conductance(self, dp: float) -> float:
        """dQ/d(dp). Newton needs the slope, not an exact derivative:
        an approximate one costs an iteration, never correctness."""
        raise NotImplementedError


class Resistance(Branch):
    """A pipe run, a fitting, an open drain — anything that turns
    pressure into nothing but noise and heat.

        Q = sign(dp) * sqrt(|dp| / k)

    ``k`` is in Pa per (L/s)^2, so k = 1000 means one litre a second
    costs a kilopascal. Square law, as turbulent flow is.
    """

    def __init__(self, node_a: int, node_b: int, k_pa_per_lps2: float,
                 name: str = "") -> None:
        super().__init__(node_a, node_b, name)
        self.k = max(k_pa_per_lps2, _EPS)

    def flow(self, dp: float) -> float:
        return math.copysign(math.sqrt(abs(dp) / self.k), dp)

    def conductance(self, dp: float) -> float:
        return 1.0 / (2.0 * math.sqrt(self.k * max(abs(dp), _DP_FLOOR_PA)))


class ControlResistance(Resistance):
    """A valve: the same square law, but the coefficient opens and
    closes.

        Q = Cv * f(x) * sqrt(dp)

    ``cv_lps`` is the flow at full open across the reference drop, so
    the number a player sizes stays the familiar one. Shut, it passes
    nothing at all rather than a very large resistance, so a closed
    valve is genuinely closed.
    """

    REF_DROP_PA = 100_000.0     # 1 bar, the usual sizing basis

    def __init__(self, node_a: int, node_b: int, cv_lps: float,
                 name: str = "") -> None:
        # k such that Q = cv_lps at the reference drop.
        super().__init__(node_a, node_b, self.REF_DROP_PA / max(cv_lps, _EPS) ** 2, name)
        self.cv_lps = cv_lps
        self.opening = 0.0      # 0..1, set from the positioner each tick

    def _k_now(self) -> float:
        effective = self.cv_lps * self.opening
        return self.REF_DROP_PA / max(effective, _EPS) ** 2

    def flow(self, dp: float) -> float:
        if self.opening <= 1e-4:
            return 0.0
        return math.copysign(math.sqrt(abs(dp) / self._k_now()), dp)

    def conductance(self, dp: float) -> float:
        if self.opening <= 1e-4:
            return 0.0
        return 1.0 / (2.0 * math.sqrt(self._k_now() * max(abs(dp), _DP_FLOOR_PA)))


class PumpCurve(Branch):
    """A centrifugal pump, with the curve that makes it one.

        H(Q) = H0 * (1 - (Q / Qmax)^2)

    Head is highest at shutoff and falls away as flow rises, so the
    pump finds its own operating point against whatever the system
    puts in front of it. Ask it to lift more than H0 and it dead-heads:
    the motor spins, the flow is zero, and nothing you do at the
    control valve changes that. A check valve stops it running
    backwards.
    """

    #: Flow past which the curve is treated as flat, as a multiple of
    #: the rating.
    RUNOUT_FACTOR = 1.35

    def __init__(self, node_a: int, node_b: int, head_pa: float,
                 max_lps: float, name: str = "") -> None:
        super().__init__(node_a, node_b, name)
        self.head_pa = max(head_pa, _EPS)
        self.max_lps = max(max_lps, _EPS)
        self.running = False

    def flow(self, dp: float) -> float:
        if not self.running:
            return 0.0
        # dp is suction minus discharge, so the rise the pump must make
        # is -dp. Q = Qmax * sqrt(1 - rise/H0).
        rise = -dp
        if rise >= self.head_pa:
            return 0.0          # dead-headed
        # Past the end of the curve a centrifugal pump stops being a
        # pump and is only a fitting, so cap the runout rather than
        # letting a high-pressure header drive it to silly flows.
        return min(self.max_lps * math.sqrt(1.0 - rise / self.head_pa),
                   self.max_lps * self.RUNOUT_FACTOR)

    def conductance(self, dp: float) -> float:
        if not self.running:
            return 0.0
        rise = -dp
        if rise >= self.head_pa:
            return 0.0
        return self.max_lps / (2.0 * self.head_pa
                               * math.sqrt(max(1.0 - rise / self.head_pa, 1e-6)))


class FixedFlow(Branch):
    """A machine that sets its own throughput: a metering pump, or a
    unit with its own feed pump inside it. It takes what it takes and
    the network works around it, which is what a positive-displacement
    machine does until something cavitates."""

    def __init__(self, node_a: int, node_b: int, lps: float = 0.0,
                 name: str = "") -> None:
        super().__init__(node_a, node_b, name)
        self.lps = lps

    def flow(self, dp: float) -> float:
        return self.lps

    def conductance(self, dp: float) -> float:
        return 0.0


class Network:
    """Nodes, branches, and the solve that reconciles them."""

    MAX_ITERATIONS = 60
    TOLERANCE_LPS = 1e-6
    # Newton on a square-law branch is badly behaved far from the
    # answer: the slope of sqrt goes flat, so an undamped step can
    # overshoot by a factor of ten and sit there oscillating. Capping
    # how far a node may move in one iteration costs a few iterations
    # on the first solve and nothing at all afterwards, because a warm
    # start is already within a few hundred pascals.
    MAX_STEP_PA = 150_000.0
    #: How many times to halve a step that is not helping before giving
    #: up on it and re-linearising.
    MAX_HALVINGS = 12

    def __init__(self) -> None:
        self.pressures: list[float] = []
        self.fixed: list[bool] = []
        self.branches: list[Branch] = []
        self.iterations = 0
        self.residual_lps = 0.0
        self._solved_once = False

    def add_node(self, pressure_pa: float = ATMOSPHERIC_PA,
                 fixed: bool = False) -> int:
        self.pressures.append(pressure_pa)
        self.fixed.append(fixed)
        return len(self.pressures) - 1

    def set_pressure(self, node: int, pressure_pa: float,
                     fixed: bool = True) -> None:
        self.pressures[node] = pressure_pa
        self.fixed[node] = fixed

    def add_branch(self, branch: Branch) -> Branch:
        self.branches.append(branch)
        return branch

    # -- the solve ----------------------------------------------------

    def solve(self) -> None:
        """Find node pressures that balance every node, then record the
        flow in each branch.

        Warm-started: pressures keep whatever the previous tick left
        them at, which is nearly the answer already.
        """
        free = [i for i, is_fixed in enumerate(self.fixed) if not is_fixed]
        index_of = {node: slot for slot, node in enumerate(free)}
        n = len(free)
        self.iterations = 0
        if n == 0:
            self._record_flows()
            return

        # Cold start: put the free nodes somewhere plausible rather than
        # at zero, which may be a long way from any pressure in the
        # plant. Every scan after the first is warm-started from the
        # last answer and this does not run.
        if not self._solved_once:
            known = [self.pressures[i] for i, f in enumerate(self.fixed) if f]
            if known:
                seed = sum(known) / len(known)
                for node in free:
                    self.pressures[node] = seed
            self._solved_once = True

        for _ in range(self.MAX_ITERATIONS):
            self.iterations += 1
            residual = self._residuals(index_of, n)
            worst = max((abs(r) for r in residual), default=0.0)
            if worst < self.TOLERANCE_LPS:
                break

            jacobian = [[0.0] * n for _ in range(n)]
            for branch in self.branches:
                a, b = branch.node_a, branch.node_b
                g = branch.conductance(self.pressures[a] - self.pressures[b])
                if a in index_of:
                    ia = index_of[a]
                    jacobian[ia][ia] -= g
                    if b in index_of:
                        jacobian[ia][index_of[b]] += g
                if b in index_of:
                    ib = index_of[b]
                    jacobian[ib][ib] -= g
                    if a in index_of:
                        jacobian[ib][index_of[a]] += g

            # A node with no pressure-sensitive branch on it (only fixed
            # flows) leaves a zero row; pin it so the system stays
            # solvable rather than blowing up.
            for i in range(n):
                if abs(jacobian[i][i]) < 1e-12:
                    jacobian[i][i] = -1e-9

            step = _solve_dense(jacobian, [-r for r in residual])
            if step is None:
                break

            # Damped step. An undamped Newton step on a square law will
            # happily leap clean over the answer and land the same
            # distance the other side, then leap back, forever -- which
            # is exactly what a dead-ended drain does at zero flow. Try
            # the full step, and keep halving until the imbalance
            # actually improves.
            before = _norm(residual)
            saved = [self.pressures[node] for node in free]
            scale = 1.0
            for _attempt in range(self.MAX_HALVINGS):
                for slot, node in enumerate(free):
                    move = step[slot] * scale
                    move = max(-self.MAX_STEP_PA, min(self.MAX_STEP_PA, move))
                    self.pressures[node] = max(saved[slot] + move, MIN_PRESSURE_PA)
                if _norm(self._residuals(index_of, n)) < before:
                    break
                scale *= 0.5

        self._record_flows()
        self.residual_lps = self._worst_imbalance(index_of, len(free))

    def _residuals(self, index_of: dict[int, int], n: int) -> list[float]:
        """Net flow into each free node. Zero everywhere is the answer."""
        residual = [0.0] * n
        for branch in self.branches:
            a, b = branch.node_a, branch.node_b
            q = branch.flow(self.pressures[a] - self.pressures[b])
            if a in index_of:
                residual[index_of[a]] -= q
            if b in index_of:
                residual[index_of[b]] += q
        return residual

    def _record_flows(self) -> None:
        for branch in self.branches:
            dp = self.pressures[branch.node_a] - self.pressures[branch.node_b]
            branch.flow_lps = branch.flow(dp)

    def _worst_imbalance(self, index_of: dict[int, int], n: int) -> float:
        """The largest flow imbalance left at any free node, reported
        after the last update rather than before it, so a caller can
        trust it as a measure of the answer it actually got."""
        if n == 0:
            return 0.0
        totals = [0.0] * n
        for branch in self.branches:
            if branch.node_a in index_of:
                totals[index_of[branch.node_a]] -= branch.flow_lps
            if branch.node_b in index_of:
                totals[index_of[branch.node_b]] += branch.flow_lps
        return max(abs(t) for t in totals)


def _norm(values: list[float]) -> float:
    return math.sqrt(sum(v * v for v in values))


def _solve_dense(matrix: list[list[float]], rhs: list[float]) -> list[float] | None:
    """Gaussian elimination with partial pivoting.

    Plant networks are tens of nodes, so a dense solve costs nothing and
    saves a dependency. Returns None if the system is singular, which
    the caller treats as "keep last tick's answer" rather than crashing
    the plant.
    """
    n = len(rhs)
    a = [row[:] + [rhs[i]] for i, row in enumerate(matrix)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(a[r][col]))
        if abs(a[pivot][col]) < 1e-14:
            return None
        a[col], a[pivot] = a[pivot], a[col]
        inv = 1.0 / a[col][col]
        for row in range(col + 1, n):
            factor = a[row][col] * inv
            if factor == 0.0:
                continue
            for k in range(col, n + 1):
                a[row][k] -= factor * a[col][k]
    out = [0.0] * n
    for row in range(n - 1, -1, -1):
        total = a[row][n]
        for k in range(row + 1, n):
            total -= a[row][k] * out[k]
        out[row] = total / a[row][row]
    return out


def static_head_pa(depth_m: float) -> float:
    """Pressure at the bottom of a column of liquid this deep."""
    return HEAD_PA_PER_M * max(depth_m, 0.0)
