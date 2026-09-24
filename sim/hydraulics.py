"""The hydraulic network: pressure drives flow.

Flow is *solved*, never asserted: no consumer announces what it takes
on a ``draw`` wire so a supplier can decrement its inventory. The plant's material connections form a network
of nodes at some pressure, joined by branches with a hydraulic
character. Headers and vessels set boundary pressures; pumps add head;
valves and pipe runs resist. What flows is whatever satisfies all of
them at once.

Three things fall out of this:

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
# Below this a branch is treated as carrying nothing, for the purpose of
# working out what is connected to what.
_CONDUCTING_EPS = 1e-12


def _square_law_flow(dp: float, k: float) -> float:
    """Q for a square-law element, linearised through zero.

    Below the floor the square law is replaced by the straight line that
    meets it at the floor. The linearisation has to be applied to the
    *flow* as well as to the slope: regularising only the slope leaves
    Newton chasing a target its own derivative disagrees with, and it
    grinds against the iteration cap forever without ever landing.
    """
    if abs(dp) >= _DP_FLOOR_PA:
        return math.copysign(math.sqrt(abs(dp) / k), dp)
    return dp * math.sqrt(_DP_FLOOR_PA / k) / _DP_FLOOR_PA


def _drop_for(q: float, k: float) -> float:
    """The pressure drop at which a square-law element passes |q|: the
    inverse of ``_square_law_flow``, linear part included. A plateau step
    aims exactly there -- a fixed margin of a pascal through a wide open
    end is a flow a thousand times a drip's, and the step overshoots."""
    q = abs(q)
    dp = k * q * q
    if dp >= _DP_FLOOR_PA:
        return dp
    return q * math.sqrt(k * _DP_FLOOR_PA)


def _square_law_slope(dp: float, k: float) -> float:
    if abs(dp) >= _DP_FLOOR_PA:
        return 1.0 / (2.0 * math.sqrt(k * abs(dp)))
    return math.sqrt(_DP_FLOOR_PA / k) / _DP_FLOOR_PA


class Branch:
    """One flow path between two nodes.

    Sign convention everywhere: ``dp`` is P(node_a) - P(node_b), and a
    positive flow runs from a to b.
    """

    #: Whether the flow depends on the two end pressures differently.
    #: A pipe or a valve answers to the difference alone, so one slope
    #: serves both ends of it. A regulator, whose opening follows its
    #: downstream pressure, is far stiffer on the b side than the a
    #: side, and the Jacobian must know or Newton steps the inlet as if
    #: it were the outlet and never lands.
    two_sided = False
    #: A branch that can stand closed as a one-way wall -- a check, a
    #: vessel nozzle, a one-way valve -- and report the open side's slope
    #: while it does (see Network._jacobian).
    wall = False

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

    def is_conducting(self, dp: float) -> bool:
        """Whether material can actually cross this branch right now.

        Kept separate from ``conductance`` because the two answer
        different questions. Connectivity asks "is there a path?", and a
        shut valve is a wall whatever slope it reports. Newton asks
        "which way should I step?", and near a kink the useful slope is
        the one on the far side of it.
        """
        return self.conductance(dp) > _CONDUCTING_EPS

    # Most branches care only about the difference across them. A pump
    # is the exception: it also cares how close its suction is to a
    # vacuum, because that is what decides whether it is pumping or
    # cavitating. These two hand the absolute pressures over so it can
    # ask, and cost nothing for everything else.

    def flow_at(self, pa: float, pb: float) -> float:
        return self.flow(pa - pb)

    def conductance_at(self, pa: float, pb: float) -> float:
        return self.conductance(pa - pb)

    def conductance_b_at(self, pa: float, pb: float) -> float:
        """-dQ/dP_b: the slope on the b side, for a two-sided branch.
        Positive, like the a side: flow falls as the outlet rises."""
        return self.conductance_at(pa, pb)

    def is_conducting_at(self, pa: float, pb: float) -> bool:
        return self.is_conducting(pa - pb)

    def crack_target(self, node: int, pa: float, pb: float,
                     push: float, passing: bool = True) -> float | None:
        """Where ``node`` must stand for this branch, a one-way wall shut
        against it, to pass ``push`` L/s (positive: net inflow, so the
        node must rise; negative: it must fall), or None when the branch
        is not such a wall. With ``passing`` False, the crack itself: the
        wall reached at rest, for flow that will not last. The solver's way off a plateau:
        between a node and a shut check or a dry nozzle nothing flows
        until the crack, so Newton's local slope climbs a 10 kPa gap in
        steps of a few hundred pascals while the flow arriving stays
        unbalanced."""
        return None


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
        return _square_law_flow(dp, self.k)

    def conductance(self, dp: float) -> float:
        return _square_law_slope(dp, self.k)


class ControlResistance(Resistance):
    """A valve: the same square law, but the coefficient opens and
    closes.

        Q = Cv * f(x) * sqrt(dp)

    ``cv_lps`` is the flow at full open across the reference drop, so
    the number a player sizes stays the familiar one. Shut, it passes
    nothing at all rather than a very large resistance, so a closed
    valve is genuinely closed.

    ``one_way`` passes from a to b only: an open drain to an
    atmospheric sewer, which under suction draws air, never sewer water.
    Backwards it passes nothing and joins nothing, but reports the open
    side's slope, as ``CheckResistance`` does, so Newton knows where the
    wall is.
    """

    REF_DROP_PA = 100_000.0     # 1 bar, the usual sizing basis

    def __init__(self, node_a: int, node_b: int, cv_lps: float,
                 name: str = "", one_way: bool = False) -> None:
        # k such that Q = cv_lps at the reference drop.
        super().__init__(node_a, node_b, self.REF_DROP_PA / max(cv_lps, _EPS) ** 2, name)
        self.cv_lps = cv_lps
        self.opening = 0.0      # 0..1, set from the positioner each tick
        self.one_way = one_way

    def _k_now(self) -> float:
        effective = self.cv_lps * self.opening
        return self.REF_DROP_PA / max(effective, _EPS) ** 2

    def flow(self, dp: float) -> float:
        if self.opening <= 1e-4 or (self.one_way and dp <= 0.0):
            return 0.0
        return _square_law_flow(dp, self._k_now())

    def conductance(self, dp: float) -> float:
        if self.opening <= 1e-4:
            return 0.0
        return _square_law_slope(dp, self._k_now())

    def is_conducting(self, dp: float) -> bool:
        if self.one_way and dp <= 0.0:
            return False
        return super().is_conducting(dp)

    @property
    def wall(self) -> bool:
        return self.one_way

    def crack_target(self, node: int, pa: float, pb: float,
                     push: float, passing: bool = True) -> float | None:
        if not self.one_way or self.opening <= 1e-4 or pa > pb:
            return None
        drop = _drop_for(push, self._k_now()) if passing else 0.0
        if node == self.node_a and push < 0.0:
            return MIN_PRESSURE_PA    # a sewer supplies nothing: the suction runs out
        if node == self.node_a and push > 0.0:
            return pb + drop
        if node == self.node_b and push < 0.0:
            return pa - drop
        return None


class CheckResistance(Resistance):
    """A resistance with a check valve in it: flow from a to b only.

    A top-entry nozzle is one of these. The line discharges above the
    liquid, so material can fall in and nothing can come back out --
    which is not a detail, because without it an empty vessel will
    happily supply liquid it does not have through the nozzle at its
    roof.

    The flow is one-way. The *slope* is not, and that distinction is
    load-bearing. A shut check reporting zero slope tells Newton the
    node is insensitive, so it takes a step sized by the pipe alone and
    sails clean past the pressure at which the valve cracks -- then
    back, then forwards, until the iteration cap. Reporting the
    open-side slope instead says "there is a wall a few hundred pascals
    away", and it lands on the crack point in two steps. The flow it
    passes while shut is still exactly zero, so nothing is invented;
    only the step length changes. ``is_conducting`` keeps connectivity
    honest, because for working out what is joined to what a shut check
    really is a wall.
    """

    def flow(self, dp: float) -> float:
        return super().flow(dp) if dp > 0.0 else 0.0

    def conductance(self, dp: float) -> float:
        return super().conductance(dp)

    def is_conducting(self, dp: float) -> bool:
        return dp > 0.0 and super().is_conducting(dp)

    wall = True

    def crack_target(self, node: int, pa: float, pb: float,
                     push: float, passing: bool = True) -> float | None:
        if pa > pb:
            return None
        drop = _drop_for(push, self.k) if passing else 0.0
        if node == self.node_a and push > 0.0:
            return pb + drop
        if node == self.node_b and push < 0.0:
            return pa - drop
        return None


class NozzleResistance(Resistance):
    """A vessel nozzle: node_a is the vessel side, node_b the line, so
    a positive flow leaves the vessel.

    What a nozzle passes depends on where it stands relative to the
    liquid. Inflow is always free: a line can discharge
    into a vessel through a nozzle above the liquid or under it. Outflow
    needs liquid standing over the nozzle, and ``submergence`` (0..1)
    is how much of it does: 1 well under the surface, 0 once the level
    has fallen past it, the ramp between them 3 cm, so an emptying
    vessel does not chatter shut.

    Dry, it is a check valve seen from the vessel's side, and reports
    as one does: no flow out, but the *slope* reported is
    the open side's, so Newton lands on the crack point instead of
    stepping past it for ever. Connectivity still sees a wall.
    """

    REF_DROP_PA = ControlResistance.REF_DROP_PA

    def __init__(self, node_a: int, node_b: int, cv_lps: float,
                 name: str = "") -> None:
        super().__init__(node_a, node_b, self.REF_DROP_PA / max(cv_lps, _EPS) ** 2, name)
        self.cv_lps = cv_lps
        self.submergence = 0.0

    def set_cv(self, cv_lps: float) -> None:
        """Size the nozzle: the flow it passes wide open across the
        reference drop. A nozzle takes the size of the line on it."""
        self.cv_lps = cv_lps
        self.k = self.REF_DROP_PA / max(cv_lps, _EPS) ** 2

    def _k_out(self) -> float:
        effective = self.cv_lps * self.submergence
        return self.REF_DROP_PA / max(effective, _EPS) ** 2

    def flow(self, dp: float) -> float:
        if dp > 0.0:
            if self.submergence <= 1e-4:
                return 0.0
            return _square_law_flow(dp, self._k_out())
        return _square_law_flow(dp, self.k)

    def conductance(self, dp: float) -> float:
        if dp > 0.0 and self.submergence > 1e-4:
            return _square_law_slope(dp, self._k_out())
        # The inflow slope: the branch in force for inflow, and the
        # open side's slope while the nozzle stands dry.
        return _square_law_slope(dp, self.k)

    def is_conducting(self, dp: float) -> bool:
        if dp > 0.0:
            return self.submergence > 1e-4
        return True

    wall = True

    def crack_target(self, node: int, pa: float, pb: float,
                     push: float, passing: bool = True) -> float | None:
        # Dry, nothing leaves the vessel: a line node standing below the
        # vessel side with liquid arriving must rise past it to pass it in;
        # one pulled on (a pump drawing from a vessel gone dry) can get
        # nothing from it and falls to where whatever pulls runs out of
        # suction, the hard-vacuum floor.
        if node == self.node_b and pb < pa and self.submergence <= 1e-4:
            if push > 0.0:
                return pa + (_drop_for(push, self.k) if passing else 0.0)
            return MIN_PRESSURE_PA
        return None


class RegulatorResistance(ControlResistance):
    """A self-acting pressure regulator: a valve whose opening is a
    function of its own downstream pressure, solved with the network
    rather than a scan behind it.

        x = clamp((P_set - P_b) / P_band, 0, 1)
        Q = Cv * x * sqrt(dp / dp_ref)

    Why a branch and not a component adjusting a valve each scan: the
    downstream side of a regulator is stiff (an orifice, a shut line),
    so a proportional opening set from last scan's pressure swings from
    shut to full open and back every scan and never settles. Solved
    simultaneously it is one equilibrium, found in a few iterations.
    The slope reported to Newton carries the opening's own dependence
    on the downstream pressure, so a step lands rather than under-shoots.
    """

    def __init__(self, node_a: int, node_b: int, cv_lps: float, set_pa: float,
                 band_pa: float, name: str = "") -> None:
        super().__init__(node_a, node_b, cv_lps, name)
        self.set_pa = set_pa
        self.band_pa = max(band_pa, 1.0)
        self.opening = 1.0

    def opening_at(self, pb: float) -> float:
        return min(max((self.set_pa - pb) / self.band_pa, 0.0), 1.0)

    def flow_at(self, pa: float, pb: float) -> float:
        self.opening = self.opening_at(pb)
        return self.flow(pa - pb)

    two_sided = True

    def conductance_at(self, pa: float, pb: float) -> float:
        # The a side: the seat as it stands, the square law through it.
        self.opening = self.opening_at(pb)
        return self.conductance(pa - pb)

    def conductance_b_at(self, pa: float, pb: float) -> float:
        # The b side: the square law, and the seat closing as the
        # outlet rises (dQ/dx * dx/dP_b), which is the stiff part.
        x = self.opening_at(pb)
        self.opening = x
        g = self.conductance(pa - pb)
        if 0.0 < x < 1.0:
            g += abs(self.flow(pa - pb)) / (x * self.band_pa)
        return g

    def is_conducting_at(self, pa: float, pb: float) -> bool:
        return self.opening_at(pb) > 1e-4


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
    #: How far above a hard vacuum the suction has to stay for the pump
    #: to make its full curve. Inside this band it is losing prime, and
    #: at the bottom of it it is moving nothing at all.
    #:
    #: This is what stops a pump on an empty vessel dragging its suction
    #: line to vacuum and demanding material anyway. Without it the
    #: suction pins at the floor, the imbalance can never be driven to
    #: zero because the node cannot go any lower, and the solve grinds
    #: against the iteration cap for the rest of the run. A taper rather
    #: than a cut-off, because Newton cannot follow a cliff.
    CAVITATION_BAND_PA = 20_000.0

    def __init__(self, node_a: int, node_b: int, head_pa: float,
                 max_lps: float, name: str = "", exponent: float = 2.0) -> None:
        super().__init__(node_a, node_b, name)
        self.head_pa = max(head_pa, _EPS)
        self.max_lps = max(max_lps, _EPS)
        self.running = False
        # The curve's steepness: H = H0 * (1 - (Q/Qmax)^n). Two is a
        # centrifugal pump. A positive-displacement machine (a metering
        # pump) is nearly vertical -- its flow barely moves with the
        # head until the head runs out -- and a high exponent is that
        # curve without a cliff Newton cannot follow.
        self.exponent = max(exponent, 1.0)
        # The pump's own height as static head, rho*g*z. Node pressures
        # are piezometric (P + rho*g*z), so the pressure a gauge on the
        # suction would read -- the one that decides whether the pump
        # has prime -- is the node's less this. A pump at the top of a
        # rise sees a lower static suction than one at the bottom, and
        # can lose prime where the other does not.
        self.datum_pa = 0.0

    def prime(self, suction_pa: float) -> float:
        """How much of its curve it is making, 0 to 1. One whenever
        there is real pressure on the suction, tapering to nothing as
        the *static* suction approaches a hard vacuum."""
        headroom = suction_pa - self.datum_pa - MIN_PRESSURE_PA
        return min(max(headroom / self.CAVITATION_BAND_PA, 0.0), 1.0)

    def flow_at(self, pa: float, pb: float) -> float:
        return self.flow(pa - pb) * self.prime(pa)

    def conductance_at(self, pa: float, pb: float) -> float:
        # Inside the band the suction pressure moves the flow twice
        # over: along the curve, and by how much prime the pump has.
        # Newton needs both terms or it under-steps and grinds -- the
        # same trap as regularising a slope without its flow.
        prime = self.prime(pa)
        g = self.conductance(pa - pb) * prime
        if 0.0 < prime < 1.0:
            g += self.flow(pa - pb) / self.CAVITATION_BAND_PA
        return g

    def is_conducting_at(self, pa: float, pb: float) -> bool:
        return self.is_conducting(pa - pb) and self.prime(pa) > 0.0

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
        return min(self.max_lps * (1.0 - rise / self.head_pa) ** (1.0 / self.exponent),
                   self.max_lps * self.RUNOUT_FACTOR)

    def conductance(self, dp: float) -> float:
        if not self.running:
            return 0.0
        rise = -dp
        if rise >= self.head_pa:
            return 0.0
        n = self.exponent
        left = max(1.0 - rise / self.head_pa, 1e-6)
        return self.max_lps / (n * self.head_pa) * left ** (1.0 / n - 1.0)


class FixedFlow(Branch):
    """A machine that sets its own throughput: a metering pump, or a
    unit with its own feed pump inside it. It takes what it takes and
    the network works around it, which is what a positive-displacement
    machine does until something cavitates.

    Its conductance is zero -- pressure does not change what it does --
    but it is emphatically *conducting*. Material crosses it, so
    whatever it discharges into has a pressure to find rather than being
    hydraulically adrift. Read its flat slope as a wall and a receiving
    nozzle behind a check that has not cracked yet looks unreachable,
    and the two ends wait for each other for ever.

    What it draws, though, has to be there: drawing from a line nothing
    supplies, it starves as its suction nears a hard vacuum, the pump's
    taper over the same band. Imposed regardless, a draw from a vessel
    whose outlet stands above the liquid is an imbalance the solve can
    never close. A machine drawing from its own fixed bowl or drum never
    nears vacuum and is unaffected. The flow depends on the suction alone, so the
    branch is two-sided: all of its slope on the a side, none on the b.
    """

    STARVE_BAND_PA = PumpCurve.CAVITATION_BAND_PA
    two_sided = True

    def __init__(self, node_a: int, node_b: int, lps: float = 0.0,
                 name: str = "") -> None:
        super().__init__(node_a, node_b, name)
        self.lps = lps

    def supply(self, suction_pa: float) -> float:
        """How much of its rate the suction lets it draw, 0 to 1."""
        return min(max((suction_pa - MIN_PRESSURE_PA) / self.STARVE_BAND_PA, 0.0), 1.0)

    def flow(self, dp: float) -> float:
        return self.lps

    def conductance(self, dp: float) -> float:
        return 0.0

    def flow_at(self, pa: float, pb: float) -> float:
        return self.lps * self.supply(pa)

    def conductance_at(self, pa: float, pb: float) -> float:
        s = self.supply(pa)
        return self.lps / self.STARVE_BAND_PA if 0.0 < s < 1.0 else 0.0

    def conductance_b_at(self, pa: float, pb: float) -> float:
        return 0.0

    def is_conducting(self, dp: float) -> bool:
        return True


class Network:
    """Nodes, branches, and the solve that reconciles them."""

    MAX_ITERATIONS = 20
    # A cold solve starts from a seed, not from last scan's answer, so it
    # may take longer to land: three times the budget, once, when new
    # nodes appear. Any flat seed leaves some block far from its answer
    # (a drip line behind a shut regulator, a gravity drain started at
    # the sewer's level), and such a block takes about twenty iterations.
    COLD_ITERATIONS = 60
    #: A node is converged when its imbalance is below this, or below a
    #: thousandth of what passes through it, whichever is smaller: a
    #: drip line moving a tenth of a millilitre a second cannot be
    #: judged by an absolute tenth of a millilitre. Never looser than
    #: the absolute figure, never tighter than the floor.
    TOLERANCE_LPS = 1e-4
    TOLERANCE_REL = 1e-3
    TOLERANCE_FLOOR_LPS = 1e-8
    # Newton on a square-law branch is badly behaved far from the
    # answer: the slope of sqrt goes flat, so an undamped step can
    # overshoot by a factor of ten and sit there oscillating. Capping
    # how far a node may move in one iteration costs a few iterations
    # on the first solve and nothing at all afterwards, because a warm
    # start is already within a few hundred pascals.
    MAX_STEP_PA = 150_000.0
    #: How many times to halve a step that is not helping before giving
    #: up on it and re-linearising.
    MAX_HALVINGS = 8
    #: Scales tried when no halving helps: a step that stopped short
    #: of a plateau's edge (a dry nozzle, a shut check) is lengthened
    #: before the solve gives up.
    LENGTHENINGS = (1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0)

    def __init__(self) -> None:
        self.pressures: list[float] = []
        self.fixed: list[bool] = []
        self.branches: list[Branch] = []
        self.iterations = 0
        self.residual_lps = 0.0
        #: Whether the last solve landed: every node joined to a fixed
        #: pressure within its tolerance. A solve that stops
        #: short records flows that do not balance, and inside a machine
        #: that passes material through that is material made or lost.
        self.converged = True
        #: An observer for studying a solve (tools/replay_network.py):
        #: called as trace(event, **fields) at each iteration and step
        #: decision. None in the running plant.
        self.trace = None
        self._solved_once = False
        # Nodes whose pressure a rebuild carried over from the network it
        # replaced: warm already, so the cold start leaves them alone.
        self.warm: set[int] = set()
        self._loose: set[int] = set()
        self._islanded: set[int] = set()

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
        self.converged = True
        if n == 0:
            self._record_flows()
            return
        self.converged = False

        # The plant is many independent problems, one per block of free
        # nodes joined by branches, divided by the vessels and headers
        # that fix pressures between them; each block gets its own step
        # length, judged on its own imbalance, and a block that stalls
        # stops alone. One step length judged on the whole plant lets one
        # block swing (a steam line across its drum pressure) while
        # another improves enough to carry it, and a stall in one stops
        # them all.
        blocks = self._blocks(free, index_of)
        # Cold start: put the free nodes somewhere plausible rather than
        # at zero, which may be a long way from any pressure in the
        # plant. Every scan after the first is warm-started from the
        # last answer and this does not run, and a
        # rebuild carries every existing nozzle's pressure over, so only
        # new nodes are seeded.
        cold = not self._solved_once
        if cold:
            self._seed_blocks(blocks, free)
            self._solved_once = True
        stalled = [False] * len(blocks)
        # Failed steps in a row: a block stops after two. One failure is
        # often a wall or a regulator that has just changed state, and the
        # next linearisation, from the nudge the failure leaves, is what
        # it needs (a regulator can crack open on the step that failed);
        # a trickle that no step can
        # help still stops at the second, rather than grind out the cap.
        failures = [0] * len(blocks)
        crossed = [False] * len(blocks)
        for _ in range(self.COLD_ITERATIONS if cold else self.MAX_ITERATIONS):
            self.iterations += 1
            # What is actually connected decides which nodes have an
            # equation to satisfy fully; every node counts for
            # convergence (see _drop_dead).
            reachable, conducting = self._reachable_from_fixed(index_of)
            residual = self._residuals(index_of, n)
            throughput = self._throughput(index_of, n)
            if self.trace is not None:
                self.trace("iteration", iteration=self.iterations, residual=residual,
                           free=free, pressures=list(self.pressures))
            within = [abs(r) < self._tolerance_at(throughput[i])
                      for i, r in enumerate(residual)]
            if all(within):
                self.converged = True
                break
            active = [b for b, block in enumerate(blocks)
                      if not stalled[b] and not all(within[slot] for slot in block)]
            if not active:
                break

            jacobian = self._jacobian(index_of, n, residual)
            rhs = [-r for r in residual]
            self._drop_dead(jacobian, rhs, reachable, self._loose)
            step = _solve_dense(jacobian, rhs)
            if step is None:
                break
            saved = [self.pressures[node] for node in free]
            for b in active:
                if self._block_step(blocks[b], step, saved, residual, reachable,
                                    throughput, free, index_of, n, crossed, b):
                    failures[b] = 0
                else:
                    failures[b] += 1
                    stalled[b] = failures[b] >= 2

        if self.converged and self.iterations > 1:
            self._polish(free, index_of, n)
        if not self.converged:
            # The loop left without checking: at the cap, or on a step
            # that helped nothing. Judge where it stopped.
            reachable, _ = self._reachable_from_fixed(index_of)
            residual = self._residuals(index_of, n)
            throughput = self._throughput(index_of, n)
            self.converged = all(abs(r) < self._tolerance_at(throughput[i])
                                 for i, r in enumerate(residual))

        # Flows are what the converged pressures say, recorded BEFORE
        # any island is settled: settling averages stale pressures, and
        # reading a check valve at the average can open it on paper and
        # push material into a vessel from nowhere.
        self._record_flows()
        self._settle_islands(free, index_of, n)
        self.residual_lps = self._worst_imbalance(index_of, len(free))

    def _seed_blocks(self, blocks: list[list[int]], free: list[int]) -> None:
        """The cold-start pressure of every node that has none of its own:
        the mean of the plant's fixed pressures. A node a rebuild carried
        over (``warm``) keeps the answer it had. Local seeds do worse: the
        mean of the fixed pressures a block touches can start a dead leg
        behind a barely-open valve flipping across its square law for the
        rest of the solve (a latent weakness, recorded with its network in
        tests/data), and a unit-conductance linear solve can start a node
        fed through a tight orifice below a one-way drain's crack."""
        known = [self.pressures[i] for i, f in enumerate(self.fixed) if f]
        plant_mean = sum(known) / len(known) if known else 0.0
        for block in blocks:
            for slot in block:
                if free[slot] not in self.warm:
                    self.pressures[free[slot]] = plant_mean

    def _settle_islands(self, free: list[int], index_of: dict[int, int],
                        n: int) -> None:
        """Anything cut off from every fixed pressure settles to one
        common value and stops flowing.

        Run once, after the iteration: moving pressures behind Newton's
        back mid-solve stops it converging at all.

        Follow only branches that conduct. Averaging across a stopped
        pump would drag the island toward the header it is isolated
        from, and the difference that leaves behind keeps pushing
        material through the pipe between them — material nothing
        supplied.
        """
        reachable, conducting = self._reachable_from_fixed(index_of)
        settled: set[int] = set()
        for slot in range(n):
            if reachable[slot]:
                continue
            start = free[slot]
            if start in settled:
                continue
            island = [start]
            settled.add(start)
            queue = [start]
            while queue:
                node = queue.pop()
                for neighbour in conducting.get(node, ()):
                    if neighbour in settled or neighbour not in index_of:
                        continue
                    if reachable[index_of[neighbour]]:
                        continue
                    settled.add(neighbour)
                    island.append(neighbour)
                    queue.append(neighbour)
            common = sum(self.pressures[x] for x in island) / len(island)
            for node in island:
                self.pressures[node] = common
        self._islanded = settled
        # Nothing inside an island can be flowing. An island is cut off
        # from every fixed pressure, so there is nowhere for material to
        # come from or go to -- and settling it to one common pressure
        # leaves a *running* pump reading its shutoff flow, which is a
        # litre a second of nothing arriving from nowhere.
        for branch in self.branches:
            if branch.node_a in settled and branch.node_b in settled:
                branch.flow_lps = 0.0

    def _reachable_from_fixed(self, index_of: dict[int, int]):
        """Which free nodes can actually feel a fixed pressure, through
        branches that are currently conducting.

        A shut valve or a blocked check valve is a wall: whatever is
        behind it is hydraulically adrift and has nothing to solve.
        """
        adjacency: dict[int, list[int]] = {}
        for branch in self.branches:
            a, b = branch.node_a, branch.node_b
            if not branch.is_conducting_at(self.pressures[a], self.pressures[b]):
                continue
            adjacency.setdefault(a, []).append(b)
            adjacency.setdefault(b, []).append(a)
        seen: set[int] = set()
        frontier = [i for i, is_fixed in enumerate(self.fixed) if is_fixed]
        seen.update(frontier)
        while frontier:
            node = frontier.pop()
            for neighbour in adjacency.get(node, ()):
                if neighbour not in seen:
                    seen.add(neighbour)
                    frontier.append(neighbour)
        reachable = [False] * len(index_of)
        for node, slot in index_of.items():
            reachable[slot] = node in seen
        return reachable, adjacency

    def _tolerance_at(self, throughput: float) -> float:
        """The imbalance a free node may keep: relative to what it passes."""
        return min(self.TOLERANCE_LPS,
                   max(self.TOLERANCE_FLOOR_LPS, self.TOLERANCE_REL * throughput))

    def _throughput(self, index_of: dict[int, int], n: int) -> list[float]:
        """What passes through each free node: the sum of |Q| on it."""
        through = [0.0] * n
        for branch in self.branches:
            a, b = branch.node_a, branch.node_b
            q = abs(branch.flow_at(self.pressures[a], self.pressures[b]))
            if a in index_of:
                through[index_of[a]] += q
            if b in index_of:
                through[index_of[b]] += q
        return through

    def _jacobian(self, index_of: dict[int, int], n: int,
                  residual: list[float] | None = None) -> list[list[float]]:
        """dQ/dP at the current pressures: every branch's slope lands on
        both its end nodes.

        A closed wall (a shut check, a dry nozzle, a one-way valve shut
        backwards) reports the open side's slope so Newton knows a crack
        is near when flow pushes at it (see CheckResistance). Pulled
        away from, it passes nothing whatever the pressure and anchors
        nothing, and its slope -- enormous near the crack -- would tell
        Newton otherwise: a line at rest between two dry nozzles would sit
        with each end pinned at its own nozzle's crack and a valve between
        them passing a litre a second that could go nowhere. So
        given the imbalances, a closed wall's slope is dropped from a
        node's row while that node's imbalance drives it away from the
        crack; the row may then lose its only anchor, and _drop_dead ties
        it as it ties an island."""
        jacobian = [[0.0] * n for _ in range(n)]
        # Rows that lost a wall's slope may have lost their only anchor;
        # _drop_dead ties them as it ties an island.
        self._loose = set()
        for branch in self.branches:
            a, b = branch.node_a, branch.node_b
            pa, pb = self.pressures[a], self.pressures[b]
            g = branch.conductance_at(pa, pb)
            gb = branch.conductance_b_at(pa, pb) if branch.two_sided else g
            # Closed by more than the linear stretch at the crack: within
            # a pascal of it the law is smooth on purpose, and dropping
            # the slope there as the imbalance flips sign each iteration
            # leaves a trickle converging by a quarter an iteration.
            closed = (residual is not None and branch.wall
                      and not branch.is_conducting_at(pa, pb)
                      and abs(pa - pb) > _DP_FLOOR_PA)
            if a in index_of:
                ia = index_of[a]
                if not closed or not _pulled_away(branch, a, pa, pb, residual[ia]):
                    jacobian[ia][ia] -= g
                    if b in index_of:
                        jacobian[ia][index_of[b]] += gb
                else:
                    self._loose.add(ia)
            if b in index_of:
                ib = index_of[b]
                if not closed or not _pulled_away(branch, b, pa, pb, residual[ib]):
                    jacobian[ib][ib] -= gb
                    if a in index_of:
                        jacobian[ib][index_of[a]] += g
                else:
                    self._loose.add(ib)
        return jacobian

    @staticmethod
    def _drop_dead(jacobian: list[list[float]], rhs: list[float],
                   reachable: list[bool], loose: set[int] | frozenset = frozenset()) -> None:
        """A node with no slope at all has no equation: its row and column
        become a bare -1.

        A node cut off from every fixed pressure keeps its equation, with
        a slight tie to where it stands so the island's common level is
        still determined. Frozen, a false island stays false: a line
        stranded between a regulator shut above its set point and a
        one-way open end shut below the air, with liquid still pushing
        through it, never moves. Kept live, the liquid inside it moves its
        pressures, a wall reopens, and the line is solved; a real dead leg
        simply comes to one pressure. So every node counts for
        convergence."""
        n = len(rhs)
        for i in range(n):
            if abs(jacobian[i][i]) < 1e-12:
                for j in range(n):
                    jacobian[i][j] = 0.0
                    jacobian[j][i] = 0.0
                jacobian[i][i] = -1.0
                rhs[i] = 0.0
            elif not reachable[i] or i in loose:
                jacobian[i][i] -= ISLAND_TIE * abs(jacobian[i][i])

    def _polish(self, free: list[int], index_of: dict[int, int], n: int) -> None:
        """One more full Newton step after the solve has landed, kept
        only if it improves the balance. Converged means every node within
        its tolerance, up to a tenth of a millilitre a second, and at a
        node inside a machine that passes material through, what is left
        is material made or lost -- a third of a litre an hour at worst;
        near the answer Newton converges quadratically, so one step takes
        it to rounding."""
        residual = self._residuals(index_of, n)
        before = _norm(residual)
        if before == 0.0:
            return
        reachable, _ = self._reachable_from_fixed(index_of)
        jacobian = self._jacobian(index_of, n, residual)
        rhs = [-r for r in residual]
        self._drop_dead(jacobian, rhs, reachable, self._loose)
        step = _solve_dense(jacobian, rhs)
        if step is None:
            return
        saved = [self.pressures[node] for node in free]
        for slot, node in enumerate(free):
            move = max(-self.MAX_STEP_PA, min(self.MAX_STEP_PA, step[slot]))
            self.pressures[node] = max(saved[slot] + move, MIN_PRESSURE_PA)
        if _norm(self._residuals(index_of, n)) >= before:
            for slot, node in enumerate(free):
                self.pressures[node] = saved[slot]

    def _blocks(self, free: list[int], index_of: dict[int, int]) -> list[list[int]]:
        """The free nodes in independent blocks: joined by any branch with
        both ends free, divided wherever a fixed pressure stands between.
        Each is a problem of its own (slots, in order)."""
        parent = list(range(len(free)))

        def root(x: int) -> int:
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        for branch in self.branches:
            ia = index_of.get(branch.node_a)
            ib = index_of.get(branch.node_b)
            if ia is not None and ib is not None:
                ra, rb = root(ia), root(ib)
                if ra != rb:
                    parent[ra] = rb
        groups: dict[int, list[int]] = {}
        for slot in range(len(free)):
            groups.setdefault(root(slot), []).append(slot)
        return list(groups.values())

    def _block_step(self, block: list[int], step: list[float], saved: list[float],
                    residual: list[float], reachable: list[bool], throughput: list[float],
                    free: list[int], index_of: dict[int, int], n: int,
                    crossed: list[bool], b: int) -> bool:
        """One block's damped Newton step, judged on the block's own
        imbalance: the full step, then halvings, then lengthenings, then
        the plateau step (forced once a solve where Newton failed). False
        when no scale helps: the block is left at the shortest step tried
        and stops for this solve.

        An undamped Newton step on a square law leaps clean over the
        answer and lands the same distance the other side, then leaps
        back, forever -- which is what a dead-ended drain does at zero
        flow -- so the step is halved until the imbalance improves. A
        node on a plateau (liquid arriving at a dry nozzle or a shut
        check, whose flow is flat until the crack) gets a step sized by
        the open side's slope, which reaches the crack only when the flow
        to push is large against the gap, so a longer step is tried
        before the plateau step; the ladder climbs by 1.5 and 2 in turn because the
        window of scales that improves the norm opens at the crack and
        closes where the open side overshoots."""
        before = _norm([residual[slot] for slot in block])
        if max(abs(step[slot]) for slot in block) < 1e-9:
            return False

        def place(scale: float) -> None:
            for slot in block:
                move = max(-self.MAX_STEP_PA, min(self.MAX_STEP_PA, step[slot] * scale))
                self.pressures[free[slot]] = max(saved[slot] + move, MIN_PRESSURE_PA)

        def block_norm() -> float:
            r = self._residuals(index_of, n)
            return _norm([r[slot] for slot in block])

        scale = 1.0
        shortest = scale
        improved = False
        for _attempt in range(self.MAX_HALVINGS):
            shortest = scale
            place(scale)
            if _improves(block_norm(), before, scale):
                improved = True
                break
            scale *= 0.5
        if not improved:
            longest = max(abs(step[slot]) for slot in block)
            for scale in self.LENGTHENINGS:
                if longest * scale > 2.0 * self.MAX_STEP_PA:
                    break
                place(scale)
                if _improves(block_norm(), before, scale):
                    improved = True
                    break
        # A node stranded below a closed one-way wall with flow pushing
        # at it: step it to the wall's crack, and keep that instead when
        # it leaves less imbalance than Newton's step.
        # Newton's own step can keep improving a little and run out the
        # iteration cap crawling up the gap.
        newton_at = [self.pressures[free[slot]] for slot in block]
        newton_norm = block_norm() if improved else before
        if self._plateau_step(free, index_of, n, residual, reachable, throughput,
                              saved, newton_norm, block=block):
            return True
        if (not improved and not crossed[b]
                and self._plateau_step(free, index_of, n, residual, reachable, throughput,
                                       saved, math.inf, cracks_only=True, block=block)):
            # Newton's own step failed and a wall stands in the way: cross
            # it anyway, once a solve. Judged where it lands, the step
            # looks worse -- the node rose, so what feeds it pushes harder
            # for a moment -- but from the open side the next iteration
            # settles.
            crossed[b] = True
            return True
        for i, slot in enumerate(block):
            self.pressures[free[slot]] = newton_at[i]
        if improved:
            return True
        # No scale of this step helps, so re-linearising will not either:
        # a trickle into a shut check valve, whose crack point is tens of
        # kPa away and whose slope says otherwise. The block stops -- at
        # the shortest step tried, not back at the start: that nudge is
        # what lets the next scan leave a plateau whose slope reads zero
        # (a regulator shut a hair above its setpoint).
        place(shortest)
        return False

    def _plateau_step(self, free: list[int], index_of: dict[int, int], n: int,
                      residual: list[float], reachable: list[bool],
                      throughput: list[float], saved: list[float],
                      before: float, cracks_only: bool = False,
                      block: list[int] | None = None) -> bool:
        """Step every node stranded below a closed one-way wall -- a dry
        nozzle, a shut check, a one-way drain -- with flow pushing at it
        to the pressure at which the wall passes that flow, and let the
        rest of the network follow by the linear solve with those nodes
        held. Kept only if it leaves less imbalance than ``before``; the
        caller puts its own step back otherwise.

        Why: a valve opening onto a dry roof nozzle 10 kPa above the line
        passes nothing until the crack, so the local slope sizes Newton's
        step at a few hundred pascals, and the line would crawl up the gap
        over twenty scans with the valve's whole flow unbalanced."""
        slots = block if block is not None else list(range(n))
        in_block = set(slots)
        for slot in slots:
            self.pressures[free[slot]] = saved[slot]
        # Two honest landings at a wall: the crack with the flow pushing
        # at it passing (a sustained feed, XV-401 into T-402), and the
        # crack at rest (flow that is only the network settling: a cold
        # boiler's line, drum and sewer both at zero, whose trickle into a
        # one-way drain dies as the line comes up and leaves the passing
        # landing always a trickle short). Both are tried and
        # the better kept.
        jacobian0 = self._jacobian(index_of, n, residual)
        rhs0 = [-r for r in residual]
        self._drop_dead(jacobian0, rhs0, reachable, self._loose)
        best: tuple[float, list[float]] | None = None
        for passing in (True, False):
            targets = self._crack_targets(index_of, residual, throughput, in_block,
                                          cracks_only, passing)
            if not targets:
                continue
            jacobian = [row[:] for row in jacobian0]
            rhs = rhs0[:]
            for slot, target in targets.items():
                jacobian[slot] = [0.0] * n
                jacobian[slot][slot] = 1.0
                rhs[slot] = target - self.pressures[free[slot]]
            step = _solve_dense(jacobian, rhs)
            if step is None:
                continue
            for slot in slots:
                move = max(-self.MAX_STEP_PA, min(self.MAX_STEP_PA, step[slot]))
                self.pressures[free[slot]] = max(saved[slot] + move, MIN_PRESSURE_PA)
            after = self._residuals(index_of, n)
            landed = _norm([after[slot] for slot in slots])
            if best is None or landed < best[0]:
                best = (landed, [self.pressures[free[slot]] for slot in slots])
            for slot in slots:
                self.pressures[free[slot]] = saved[slot]
        if best is None:
            return False
        for i, slot in enumerate(slots):
            self.pressures[free[slot]] = best[1][i]
        return _improves(best[0], before)

    def _crack_targets(self, index_of: dict[int, int], residual: list[float],
                       throughput: list[float], in_block: set[int], cracks_only: bool,
                       passing: bool) -> dict[int, float]:
        """Each stranded node's landing at the nearest wall it is pushed
        toward (see _plateau_step)."""
        targets: dict[int, float] = {}
        for branch in self.branches:
            pa = self.pressures[branch.node_a]
            pb = self.pressures[branch.node_b]
            for node in (branch.node_a, branch.node_b):
                slot = index_of.get(node)
                if slot is None or slot not in in_block:
                    continue
                push = residual[slot]
                if abs(push) < self._tolerance_at(throughput[slot]):
                    continue
                target = branch.crack_target(node, pa, pb, push, passing)
                if target is None:
                    continue
                # Forced, only a real crack: the vacuum floor suits a pump
                # pulling, but a gravity line pulled against a dry nozzle
                # simply stops, and the floor would be wrong.
                if cracks_only and target <= MIN_PRESSURE_PA:
                    continue
                # The nearest wall opens first.
                if slot not in targets:
                    targets[slot] = target
                elif push > 0.0:
                    targets[slot] = min(targets[slot], target)
                else:
                    targets[slot] = max(targets[slot], target)
        return targets

    def _residuals(self, index_of: dict[int, int], n: int) -> list[float]:
        """Net flow into each free node. Zero everywhere is the answer."""
        residual = [0.0] * n
        for branch in self.branches:
            a, b = branch.node_a, branch.node_b
            q = branch.flow_at(self.pressures[a], self.pressures[b])
            if a in index_of:
                residual[index_of[a]] -= q
            if b in index_of:
                residual[index_of[b]] += q
        return residual

    def _record_flows(self) -> None:
        """Every branch's flow at the current pressures. Called before
        islands are settled, so a shut check valve stays shut in the
        record."""
        for branch in self.branches:
            branch.flow_lps = branch.flow_at(
                self.pressures[branch.node_a], self.pressures[branch.node_b])

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


def _pulled_away(branch: Branch, node: int, pa: float, pb: float, push: float) -> bool:
    """Whether ``push`` drives the node away from a closed wall's crack:
    the crack lies the other way. With no push, or a push toward the
    crack, the wall's slope stands (a line whose flow has not arrived yet
    still has its outlet)."""
    if push == 0.0:
        return False
    toward = branch.crack_target(node, pa, pb, push)
    if toward is not None and toward > MIN_PRESSURE_PA:
        return False
    other = branch.crack_target(node, pa, pb, -push)
    return other is not None and other > MIN_PRESSURE_PA


def _improves(after: float, before: float, scale: float = 1.0) -> bool:
    """Whether a step cut the imbalance enough for its length (the
    Armijo condition): by a ten-thousandth of it per unit of step. A
    Newton step on a square law lands near the mirror image of where it
    started, nearly the same imbalance the other side; a bare "less than"
    accepts it for a hair of improvement, and a stopped pump's suction
    flips between the two. Refused,
    the first halving lands on the answer."""
    return after < before * (1.0 - 1e-4 * scale)


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


#: How strongly a node cut off from every fixed pressure is tied to
#: where it stands, relative to its own slope: enough to fix an island's
#: common level, too little to hold its liquid still.
ISLAND_TIE = 1e-6

#: Darcy friction factor for clean commercial pipe in turbulent flow.
FRICTION_FACTOR = 0.02
#: Loss coefficient of one long-radius 90-degree bend.
BEND_K = 0.3


def pipe_k(length_m: float, dn: int, bend_quarters: float = 0.0) -> float:
    """A pipe's resistance follows its length and size: Darcy-Weisbach with one friction factor, plus a loss
    coefficient per quarter-turn of bend,
    dP = (f*L/D + K*bends) * rho*v^2/2, in Pa per (L/s)^2. The bore is
    the nominal size in millimetres. The kernel stays geometry-free:
    whoever lays the run measures it and asks this."""
    d = dn / 1000.0
    area = math.pi * d * d / 4.0
    v_per_lps = 0.001 / area
    dynamic = RHO_KG_PER_M3 / 2.0 * v_per_lps * v_per_lps
    k = (FRICTION_FACTOR * max(length_m, 0.0) / d + BEND_K * max(bend_quarters, 0.0)) * dynamic
    return max(k, 1e-6)
