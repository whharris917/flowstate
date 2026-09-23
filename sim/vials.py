"""The filling line: vials as countable things, and the parts that move,
fill, weigh and cap them (director, 2026-09-22: "build a vial filler from
individual parts, rather than have an all-in-one object").

Liquids move as flows; a filling line moves items. A vial is a record of
its own -- its size, what is in it, whether it is capped -- carried by a
track or a star wheel at a position along it, and handed from one
carrier to the next across an item wire, once a scan, when the upstream
one offers it and the downstream one has room (``Simulation._transfer_items``).
Vials are conserved like litres: they enter at a magazine, are held on
carriers, and leave at an outfeed table.

Everything that acts on a vial sits at a point along a carrier: a stop
gate that holds it, a photo-eye that sees it, a load cell that weighs it,
a fill needle whose stream it catches, a capper that caps it. The plant
works out which carrier and where from where the player placed them; the
kernel is one-dimensional along each carrier (``mount``).

  VialMagazine  where empty vials enter, at the rate the line takes them
  VialTrack     a motor-driven belt; vials queue nose to tail when held
  StarWheel     an indexing rotary transfer, one pocket per pulse
  StopGate      a spring pin that holds vials until its coil releases it
  PhotoEye      a discrete "vial here" signal
  LoadCell      weighs the vial on its pan; a setpoint contact at target
  FillNeedle    an open end pointing down: what falls, the vial catches
  Capper        caps the vial under it on command
  VialTable     the outfeed: where vials leave, and the batch record
"""
from __future__ import annotations

from typing import Optional

from sim.core import Component, PortKind
from sim.hydraulics import ControlResistance, static_head_pa
from sim.library import Equation, EquipmentSpec, Param
from sim.stream import Stream

# Standard tubular vials: nominal mL -> (outer diameter m, height m,
# brimful mL, glass mass g). ISO 8362 R-sizes, rounded.
VIAL_SIZES: dict[int, tuple[float, float, float, float]] = {
    2: (0.016, 0.035, 4.0, 3.5),
    10: (0.024, 0.045, 13.5, 8.0),
    20: (0.030, 0.055, 26.0, 13.0),
    50: (0.042, 0.073, 62.0, 30.0),
}


def vial_size(nominal_ml: float) -> int:
    """The standard size nearest a nominal volume."""
    return min(VIAL_SIZES, key=lambda k: abs(k - nominal_ml))


class Vial:
    """One vial: glass of a standard size and whatever has been put in
    it. Pure data; the carrier holding it decides where it is."""

    def __init__(self, serial: str, nominal_ml: int = 10) -> None:
        nominal_ml = vial_size(nominal_ml)
        d, h, brim_ml, tare_g = VIAL_SIZES[nominal_ml]
        self.serial = serial
        self.nominal_ml = nominal_ml
        self.diameter_m = d
        self.height_m = h
        self.brim_l = brim_ml / 1000.0
        self.tare_g = tare_g
        self.contents = Stream.empty()   # its flow_lps field holds the volume, L
        self.capped = False

    @property
    def volume_l(self) -> float:
        return self.contents.flow_lps

    @property
    def room_l(self) -> float:
        return max(self.brim_l - self.volume_l, 0.0)

    @property
    def mass_g(self) -> float:
        """Glass plus liquid, on the 1 kg/L basis the species table uses."""
        return self.tare_g + self.volume_l * 1000.0

    def add(self, stream: Stream, litres: float) -> float:
        """Pour ``litres`` of that stream in; returns what ran over the lip."""
        taken = min(max(litres, 0.0), self.room_l)
        if taken > 0.0:
            self.contents = Stream.mix(self.contents, stream.with_flow(taken))
        return max(litres, 0.0) - taken

    def state_dict(self) -> dict:
        c = self.contents
        return {"serial": self.serial, "ml": self.nominal_ml, "capped": self.capped,
                "volume_l": c.flow_lps, "temp_c": c.temp_c, "comp": dict(c.comp)}

    @staticmethod
    def from_dict(state: dict) -> "Vial":
        v = Vial(str(state.get("serial", "")), int(state.get("ml", 10)))
        v.capped = bool(state.get("capped", False))
        vol = float(state.get("volume_l", 0.0))
        if vol > 0.0:
            v.contents = Stream(vol, float(state.get("temp_c", 20.0)), dict(state.get("comp", {})))
        return v


class _Mounted(Component):
    """Something that acts at one point along a carrier. ``s_m`` is that
    point: metres along a track, a station number on a star wheel. The
    carrier calls ``sense`` after it has moved its vials each scan."""

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.s_m = 0.0
        self.host = ""

    def sense(self, carrier: "_Carrier") -> None:
        pass


class _Carrier(Component):
    """Holds vials at positions and hands them on."""

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.mounts: list[_Mounted] = []
        self.add_observable("held_l", "held_l")
        self.add_observable("vials_on", "vials_on")

    def mount(self, device: _Mounted, s_m: float) -> None:
        if device not in self.mounts:
            self.mounts.append(device)
        device.s_m = float(s_m)
        device.host = self.name

    def unmount(self, device: _Mounted) -> None:
        if device in self.mounts:
            self.mounts.remove(device)
        device.host = ""

    def vials(self) -> list[tuple[Vial, float]]:
        """Every vial it holds, with its position."""
        return []

    def vial_near(self, s: float, tol: float) -> Optional[Vial]:
        return None

    @property
    def held_l(self) -> float:
        return sum(v.volume_l for v, _ in self.vials())

    @property
    def vials_on(self) -> int:
        return len(self.vials())

    def _sense_mounts(self) -> None:
        for device in self.mounts:
            device.sense(self)


def _powered(port) -> bool:
    return float(port.value) > 0.5


class VialMagazine(Component):
    """A tray of empty vials tilted toward the line: it lets one onto the
    track whenever the track has room, no faster than its escapement
    allows. Where vials enter the plant, as a header is where liquid
    does. No power: gravity and a spring escapement."""

    def __init__(self, name: str, vial_ml: int = 10, rate_per_min: float = 60.0) -> None:
        super().__init__(name)
        if rate_per_min <= 0.0:
            raise ValueError("rate_per_min must be positive")
        self.vial_ml = vial_size(vial_ml)
        self.rate_per_min = rate_per_min
        self.is_on = True
        self.supplied = 0
        self._cooldown = 0.0
        self.outfeed = self.add_output("outfeed", PortKind.ITEM)
        self.add_observable("supplied", "supplied")

    def item_offer(self, port_name: str):
        if not self.is_on or self._cooldown > 0.0:
            return None
        return Vial(f"{self.name}#{self.supplied + 1}", self.vial_ml)

    def item_take(self, port_name: str):
        vial = self.item_offer(port_name)
        if vial is not None:
            self.supplied += 1
            self._cooldown = 60.0 / self.rate_per_min
        return vial

    def tick(self, dt: float) -> None:
        self._cooldown = max(self._cooldown - dt, 0.0)

    def state_dict(self) -> dict:
        return {"is_on": self.is_on, "supplied": self.supplied, "cooldown": self._cooldown}

    def apply_state(self, state: dict) -> None:
        self.is_on = bool(state.get("is_on", self.is_on))
        self.supplied = int(state.get("supplied", self.supplied))
        self._cooldown = float(state.get("cooldown", 0.0))


class VialTrack(_Carrier):
    """A motor-driven belt between guide rails. Every vial rides the belt
    at its speed until something holds it: the vial ahead (they queue
    nose to tail), a stop gate's pin, or the end of the track while
    nothing downstream takes it. Held vials stand while the belt slides
    under them, as on a real accumulation conveyor."""

    def __init__(self, name: str, length_m: float = 2.0, speed_mps: float = 0.1) -> None:
        super().__init__(name)
        if length_m <= 0.0 or speed_mps <= 0.0:
            raise ValueError("length_m and speed_mps must be positive")
        self.length_m = length_m
        self.speed_mps = speed_mps
        self.hand_on = False
        self.running = False
        self._vials: list[list] = []   # [vial, s], front (largest s) first
        self.infeed = self.add_input("infeed", PortKind.ITEM)
        self.outfeed = self.add_output("outfeed", PortKind.ITEM)
        self.run = self.add_input("run", PortKind.SIGNAL_DISCRETE)
        self.power = self.add_input("power", PortKind.POWER, "24VDC")
        self.add_observable("running", "running")

    def vials(self) -> list[tuple[Vial, float]]:
        return [(v, s) for v, s in self._vials]

    def vial_near(self, s: float, tol: float) -> Optional[Vial]:
        best = None
        for v, sv in self._vials:
            if abs(sv - s) <= tol and (best is None or abs(sv - s) < abs(best[1] - s)):
                best = (v, sv)
        return best[0] if best else None

    def _commanded(self) -> bool:
        return bool(self.run.value) if self.run.wire_count > 0 else self.hand_on

    def item_offer(self, port_name: str):
        if not self._vials:
            return None
        v, s = self._vials[0]
        return v if s >= self.length_m - v.diameter_m / 2.0 - 1e-6 else None

    def item_take(self, port_name: str):
        vial = self.item_offer(port_name)
        if vial is not None:
            self._vials.pop(0)
        return vial

    def item_accepts(self, port_name: str, item) -> bool:
        if not self._vials:
            return True
        v, s = self._vials[-1]
        return s - v.diameter_m / 2.0 >= item.diameter_m - 1e-9

    def item_put(self, port_name: str, item) -> None:
        self._vials.append([item, item.diameter_m / 2.0])

    def tick(self, dt: float) -> None:
        self.running = _powered(self.power) and self._commanded()
        step = self.speed_mps * dt if self.running else 0.0
        gates = [g.s_m for g in self.mounts if isinstance(g, StopGate) and g.blocking]
        ahead = None
        for entry in self._vials:
            v, s = entry
            half = v.diameter_m / 2.0
            limit = self.length_m - half if ahead is None \
                else ahead[1] - ahead[0].diameter_m / 2.0 - half
            for g in gates:
                if s + half <= g + 1e-6:
                    limit = min(limit, g - half)
            entry[1] = max(s, min(s + step, limit))
            ahead = entry
        self._sense_mounts()

    def state_dict(self) -> dict:
        return {"hand_on": self.hand_on,
                "vials": [[v.state_dict(), s] for v, s in self._vials]}

    def apply_state(self, state: dict) -> None:
        self.hand_on = bool(state.get("hand_on", self.hand_on))
        self._vials = [[Vial.from_dict(v), float(s)] for v, s in state.get("vials", [])]


class StarWheel(_Carrier):
    """An indexing rotary transfer: a wheel with pockets round its rim,
    turned one pocket per pulse on its index input. A vial arriving at
    the infeed station drops into the pocket there; a pocket arriving at
    the outfeed station offers its vial on. Stations between are where a
    needle or a capper can stand, and they see the pocket only while the
    wheel is at rest."""

    def __init__(self, name: str, pockets: int = 6, pitch_radius_m: float = 0.12,
                 index_s: float = 0.4, out_station: int = 3) -> None:
        super().__init__(name)
        if pockets < 2:
            raise ValueError("a star wheel needs at least two pockets")
        self.pockets = pockets
        self.pitch_radius_m = pitch_radius_m
        self.index_s = index_s
        self.out_station = out_station % pockets
        self.offset = 0          # indexes completed, mod pockets
        self.progress = 0.0      # 0..1 through the current index, 0 at rest
        self.moving = False
        self.indexes = 0
        self._pocket: list[Optional[Vial]] = [None] * pockets
        self._was_index = False
        self._hand_pulse = False
        self.infeed = self.add_input("infeed", PortKind.ITEM)
        self.outfeed = self.add_output("outfeed", PortKind.ITEM)
        self.index = self.add_input("index", PortKind.SIGNAL_DISCRETE)
        self.power = self.add_input("power", PortKind.POWER, "24VDC")
        self.home = self.add_output("home", PortKind.SIGNAL_DISCRETE)
        self.add_observable("indexes", "indexes")

    def pocket_at(self, station: int) -> int:
        return (station - self.offset) % self.pockets

    def vials(self) -> list[tuple[Vial, float]]:
        out = []
        for p, v in enumerate(self._pocket):
            if v is not None:
                out.append((v, float((p + self.offset) % self.pockets) + self.progress))
        return out

    def vial_near(self, s: float, tol: float) -> Optional[Vial]:
        if self.moving:
            return None
        station = round(s)
        if abs(s - station) > tol:
            return None
        return self._pocket[self.pocket_at(station % self.pockets)]

    def hand_index(self) -> None:
        """E: one index by hand, when nothing is wired to index."""
        self._hand_pulse = True

    def item_accepts(self, port_name: str, item) -> bool:
        return not self.moving and self._pocket[self.pocket_at(0)] is None

    def item_put(self, port_name: str, item) -> None:
        self._pocket[self.pocket_at(0)] = item

    def item_offer(self, port_name: str):
        if self.moving:
            return None
        return self._pocket[self.pocket_at(self.out_station)]

    def item_take(self, port_name: str):
        vial = self.item_offer(port_name)
        if vial is not None:
            self._pocket[self.pocket_at(self.out_station)] = None
        return vial

    def tick(self, dt: float) -> None:
        pulse = bool(self.index.value) if self.index.wire_count > 0 else self._hand_pulse
        self._hand_pulse = False
        edge = pulse and not self._was_index
        self._was_index = pulse
        if self.moving:
            self.progress += dt / self.index_s
            if self.progress >= 1.0:
                self.progress = 0.0
                self.moving = False
                self.offset = (self.offset + 1) % self.pockets
        elif edge and _powered(self.power):
            self.moving = True
            self.progress = 0.0
            self.indexes += 1
        self.home.value = not self.moving
        self._sense_mounts()

    def state_dict(self) -> dict:
        return {"offset": self.offset, "progress": self.progress, "moving": self.moving,
                "indexes": self.indexes,
                "pockets": [v.state_dict() if v else None for v in self._pocket]}

    def apply_state(self, state: dict) -> None:
        self.offset = int(state.get("offset", 0)) % self.pockets
        self.progress = float(state.get("progress", 0.0))
        self.moving = bool(state.get("moving", False))
        self.indexes = int(state.get("indexes", self.indexes))
        saved = state.get("pockets", [])
        self._pocket = [Vial.from_dict(v) if v else None for v in saved][:self.pockets]
        self._pocket += [None] * (self.pockets - len(self._pocket))


class StopGate(_Mounted):
    """A pin across the track, spring-extended: it holds every vial that
    reaches it until its coil is energized, which pulls the pin clear.
    A lost signal is a held line."""

    def __init__(self, name: str, stroke_s: float = 0.1) -> None:
        super().__init__(name)
        self.stroke_s = stroke_s
        self.retracted = 0.0     # 0 = pin across the track, 100 = clear
        self.release = self.add_input("release", PortKind.SIGNAL_DISCRETE)
        self.add_observable("retracted", "retracted")

    @property
    def blocking(self) -> bool:
        return self.retracted < 50.0

    def tick(self, dt: float) -> None:
        target = 100.0 if bool(self.release.value) else 0.0
        step = 100.0 * dt / self.stroke_s
        self.retracted = min(self.retracted + step, target) if self.retracted < target \
            else max(self.retracted - step, target)

    def state_dict(self) -> dict:
        return {"retracted": self.retracted}

    def apply_state(self, state: dict) -> None:
        self.retracted = float(state.get("retracted", self.retracted))


class PhotoEye(_Mounted):
    """A through-beam across the track: its contact makes while a vial
    breaks the beam."""

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.seen = False
        self.present = self.add_output("present", PortKind.SIGNAL_DISCRETE)

    def sense(self, carrier: _Carrier) -> None:
        self.seen = any(abs(s - self.s_m) < v.diameter_m / 2.0 for v, s in carrier.vials()) \
            if isinstance(carrier, VialTrack) else carrier.vial_near(self.s_m, 0.3) is not None

    def tick(self, dt: float) -> None:
        self.present.value = self.seen


class LoadCell(_Mounted):
    """A weighing pan under one spot on the track, with its indicator.
    The indicator tares each vial as it settles, so it reads the net
    fill; its analog output is that weight and its setpoint contact
    makes when the fill reaches the target."""

    def __init__(self, name: str, range_g: float = 100.0, target_g: float = 10.0) -> None:
        super().__init__(name)
        if range_g <= 0.0:
            raise ValueError("range_g must be positive")
        self.range_g = range_g
        self.target_g = target_g
        self.net_g = 0.0
        self._on_pan = False
        self.weight = self.add_output("weight", PortKind.SIGNAL_ANALOG)
        self.at_target = self.add_output("at_target", PortKind.SIGNAL_DISCRETE)
        self.add_observable("net_g", "net_g")

    def sense(self, carrier: _Carrier) -> None:
        vial = carrier.vial_near(self.s_m, 0.004 if isinstance(carrier, VialTrack) else 0.3)
        self.net_g = min(vial.volume_l * 1000.0, self.range_g) if vial is not None else 0.0
        self._on_pan = vial is not None

    def tick(self, dt: float) -> None:
        self.weight.value = self.net_g
        self.at_target.value = self._on_pan and self.net_g >= self.target_g


class FillNeedle(_Mounted):
    """An open end pointing straight down: a filling needle on its stand.
    Its node vents to the air at the tip's height, one way, and what
    leaves falls into the vial under it -- or, with no vial there or the
    vial brimful, onto the track and is counted as spilled. The valve
    upstream is the dose control; the needle only has a bore."""

    def __init__(self, name: str, cv_lps: float = 0.05, elevation_m: float = 1.0) -> None:
        super().__init__(name)
        if cv_lps <= 0.0:
            raise ValueError("cv_lps must be positive")
        self.cv_lps = cv_lps
        self.elevation_m = float(elevation_m)
        self.delivered_l = 0.0
        self.spilled_l = 0.0
        self.catch_vial: Optional[Vial] = None
        self.catch = None       # an open vessel under the tip, named by the plant
        self._vent = None
        self._air = -1
        self.inlet = self.add_input("inlet", PortKind.PROCESS_MATERIAL)
        self.add_observable("delivered_l", "delivered_l")
        self.add_observable("spilled_l", "spilled_l")
        self.add_observable("flow_lps", "flow_lps")

    @property
    def flow_lps(self) -> float:
        return max(self._vent.flow_lps, 0.0) if self._vent is not None else 0.0

    def build_hydraulics(self, net, node: dict[str, int]) -> None:
        self._air = net.add_node(static_head_pa(self.elevation_m), fixed=True)
        self._vent = net.add_branch(ControlResistance(
            node["inlet"], self._air, self.cv_lps, self.name, one_way=True))

    def update_hydraulics(self, net, node: dict[str, int]) -> None:
        net.set_pressure(self._air, static_head_pa(self.elevation_m), fixed=True)
        self._vent.cv_lps = self.cv_lps
        self._vent.opening = 1.0

    def sense(self, carrier: _Carrier) -> None:
        # The stream falls into a vial's mouth only: its neck is about
        # half its width, so the vial must stand within a quarter of its
        # diameter of the tip.
        found = None
        for v, s in carrier.vials():
            tol = v.diameter_m * 0.25 if isinstance(carrier, VialTrack) else 0.3
            if abs(s - self.s_m) <= tol and not v.capped:
                found = v
        if isinstance(carrier, StarWheel) and carrier.moving:
            found = None
        self.catch_vial = found

    def tick(self, dt: float) -> None:
        q = self.flow_lps
        if q <= 0.0:
            return
        litres = q * dt
        stream = self.inlet.stream
        if self.catch_vial is not None:
            over = self.catch_vial.add(stream, litres)
            self.delivered_l += litres - over
            self.spilled_l += over
        elif self.catch is not None and getattr(self.catch, "open_top", False):
            self.catch.receive(stream.with_flow(q))
            self.delivered_l += litres
        else:
            self.spilled_l += litres

    def state_dict(self) -> dict:
        return {"delivered_l": self.delivered_l, "spilled_l": self.spilled_l,
                "elevation_m": self.elevation_m}

    def apply_state(self, state: dict) -> None:
        self.delivered_l = float(state.get("delivered_l", self.delivered_l))
        self.spilled_l = float(state.get("spilled_l", self.spilled_l))
        self.elevation_m = float(state.get("elevation_m", self.elevation_m))


class Capper(_Mounted):
    """A capping head over one spot: while its command is on and an
    uncapped vial stands under it, it takes a cap from its chute and
    crimps it on over ``cap_s``. Its contact makes while the vial under
    it is capped."""

    def __init__(self, name: str, cap_s: float = 0.8) -> None:
        super().__init__(name)
        if cap_s <= 0.0:
            raise ValueError("cap_s must be positive")
        self.cap_s = cap_s
        self.progress = 0.0
        self.caps_used = 0
        self._vial: Optional[Vial] = None
        self.command = self.add_input("cap", PortKind.SIGNAL_DISCRETE)
        self.power = self.add_input("power", PortKind.POWER, "24VDC")
        self.capped = self.add_output("capped", PortKind.SIGNAL_DISCRETE)
        self.add_observable("caps_used", "caps_used")

    def sense(self, carrier: _Carrier) -> None:
        tol = 0.004 if isinstance(carrier, VialTrack) else 0.3
        vial = carrier.vial_near(self.s_m, tol)
        if vial is not self._vial:
            self.progress = 0.0
        self._vial = vial

    def tick(self, dt: float) -> None:
        vial = self._vial
        working = vial is not None and not vial.capped and bool(self.command.value) \
            and _powered(self.power)
        if working:
            self.progress += dt / self.cap_s
            if self.progress >= 1.0:
                vial.capped = True
                self.caps_used += 1
                self.progress = 0.0
        self.capped.value = vial is not None and vial.capped

    def state_dict(self) -> dict:
        return {"caps_used": self.caps_used}

    def apply_state(self, state: dict) -> None:
        self.caps_used = int(state.get("caps_used", self.caps_used))


class VialTable(Component):
    """The outfeed: a turntable that gathers finished vials. Where vials
    leave the plant, and the batch record of what was in them -- how
    many, how full, how pure, how many went out uncapped."""

    KEEP = 60   # the last vials, for whoever wants to look at them

    def __init__(self, name: str) -> None:
        super().__init__(name)
        self.count = 0
        self.capped_count = 0
        self.out_l = 0.0
        self.product_l = 0.0
        self.min_ml = 0.0
        self.max_ml = 0.0
        self.recent: list[Vial] = []
        self.infeed = self.add_input("infeed", PortKind.ITEM)
        self.add_observable("count", "count")
        self.add_observable("capped_count", "capped_count")
        self.add_observable("out_l", "out_l")
        self.add_observable("mean_ml", "mean_ml")

    @property
    def mean_ml(self) -> float:
        return self.out_l * 1000.0 / self.count if self.count else 0.0

    def item_accepts(self, port_name: str, item) -> bool:
        return True

    def item_put(self, port_name: str, item) -> None:
        ml = item.volume_l * 1000.0
        self.min_ml = ml if self.count == 0 else min(self.min_ml, ml)
        self.max_ml = ml if self.count == 0 else max(self.max_ml, ml)
        self.count += 1
        self.capped_count += 1 if item.capped else 0
        self.out_l += item.volume_l
        self.product_l += item.volume_l * item.contents.frac("product")
        self.recent.append(item)
        self.recent = self.recent[-self.KEEP:]

    def tick(self, dt: float) -> None:
        pass

    def state_dict(self) -> dict:
        return {"count": self.count, "capped_count": self.capped_count, "out_l": self.out_l,
                "product_l": self.product_l, "min_ml": self.min_ml, "max_ml": self.max_ml,
                "recent": [v.state_dict() for v in self.recent]}

    def apply_state(self, state: dict) -> None:
        self.count = int(state.get("count", self.count))
        self.capped_count = int(state.get("capped_count", self.capped_count))
        self.out_l = float(state.get("out_l", self.out_l))
        self.product_l = float(state.get("product_l", self.product_l))
        self.min_ml = float(state.get("min_ml", self.min_ml))
        self.max_ml = float(state.get("max_ml", self.max_ml))
        self.recent = [Vial.from_dict(v) for v in state.get("recent", [])]


# ---- library pages (Python-side documentation) --------------------------

VialMagazine.SPEC = EquipmentSpec(
    key="vial_magazine", title="Vial Magazine", tier="utility",
    summary=("A tilted tray of empty vials with a spring escapement: it lets one "
             "onto the track whenever the track has room, no faster than its rate. "
             "Where vials enter the plant."),
    ports={"outfeed": "Where each empty vial leaves for the track."},
    equations=(Equation("interval = 60 / rate", "Seconds between vials at most."),),
    params=(Param("vial_ml", "mL", "The vial size it holds: 2, 10, 20 or 50 mL."),
            Param("rate_per_min", "vials/min", "The escapement's fastest rate.")),
    assumptions=("It never runs out of vials.", "Every vial is clean, whole and empty."),
)

VialTrack.SPEC = EquipmentSpec(
    key="vial_track", title="Vial Track", tier="utility",
    summary=("A belt between guide rails. Vials ride it at its speed until something "
             "holds them -- the vial ahead, a stop gate, or the end while nothing "
             "downstream takes them -- and then stand while the belt slides under them."),
    ports={"infeed": "Where vials arrive.", "outfeed": "Where vials leave at the far end.",
           "run": "Runs the belt while on; with nothing wired, E switches it.",
           "power": "24 V DC for the drive."},
    equations=(Equation("s' = min(s + v dt, limit)", "Each vial advances to the nearest hold."),
               Equation("limit = s_ahead - (d_ahead + d)/2", "Vials queue nose to tail.")),
    params=(Param("length_m", "m", "The track's length."),
            Param("speed_mps", "m/s", "The belt speed.")),
    assumptions=("Vials never tip, jam or slip.", "Every vial on the belt moves at belt speed."),
)

StarWheel.SPEC = EquipmentSpec(
    key="star_wheel", title="Star Wheel", tier="utility",
    summary=("An indexing rotary transfer: pockets round a wheel, turned one pocket "
             "per pulse. A vial drops into the pocket at the infeed station and is "
             "offered on at the outfeed station."),
    ports={"infeed": "The infeed station's pocket.", "outfeed": "The outfeed station's pocket.",
           "index": "A rising edge turns the wheel one pocket; with nothing wired, E does.",
           "power": "24 V DC for the indexer.", "home": "On while the wheel is at rest."},
    equations=(Equation("station = (pocket + offset) mod N", "Where each pocket stands."),),
    params=(Param("pockets", "", "How many pockets round the rim."),
            Param("pitch_radius_m", "m", "Radius of the pocket circle."),
            Param("index_s", "s", "Time for one index."),
            Param("out_station", "", "The station the outfeed stands at.")),
    assumptions=("A vial is taken or offered only at rest.", "Indexing never misses."),
)

StopGate.SPEC = EquipmentSpec(
    key="stop_gate", title="Stop Gate", tier="control",
    summary=("A spring pin across the track: it holds every vial that reaches it "
             "until its coil pulls it clear. A lost signal is a held line."),
    ports={"release": "Energized, the pin retracts and vials pass."},
    equations=(Equation("x -> 100 in stroke_s energized, -> 0 not", "The pin's travel."),),
    params=(Param("stroke_s", "s", "The pin's travel time."),),
    assumptions=("A pin coming down onto a vial drops behind it.",),
)

PhotoEye.SPEC = EquipmentSpec(
    key="photo_eye", title="Photo-Eye", tier="control",
    summary="A through-beam across the track: its contact makes while a vial breaks it.",
    ports={"present": "On while a vial is in the beam."},
    equations=(Equation("present = |s_vial - s| < d/2", "The beam sees the vial's body."),),
    params=(),
    assumptions=("No supply wiring is modelled.", "It never misses a clear vial."),
)

LoadCell.SPEC = EquipmentSpec(
    key="load_cell", title="Load Cell", tier="control",
    summary=("A weighing pan under one spot on the track with its indicator, which "
             "tares each vial as it settles and reads the net fill."),
    ports={"weight": "The net fill, grams.",
           "at_target": "The setpoint contact: on once the fill reaches the target."},
    equations=(Equation("net = 1000 * V", "Grams of fill, on the 1 kg/L basis."),),
    params=(Param("range_g", "g", "The pan's range."),
            Param("target_g", "g", "Where the setpoint contact makes.")),
    assumptions=("The tare is exact.", "No settling time, no vibration."),
)

FillNeedle.SPEC = EquipmentSpec(
    key="fill_needle", title="Fill Needle", tier="utility",
    summary=("An open end pointing straight down. What leaves it falls into the vial "
             "under it, or onto the track, counted as spilled."),
    ports={"inlet": "The line from the dosing valve."},
    equations=(Equation("Q = Cv * sqrt(dP / 100 kPa)", "Out to the air at the tip's height, one way."),),
    params=(Param("cv_lps", "L/s at 1 bar", "The needle bore's flow at the reference drop."),
            Param("elevation_m", "m", "The tip's height, from where it stands.")),
    assumptions=("A vial catches within a quarter of its width of the tip.",
                 "No drip after the valve shuts: the line stops when the pressure does."),
)

Capper.SPEC = EquipmentSpec(
    key="capper", title="Capper", tier="utility",
    summary="A capping head: while commanded, it caps the uncapped vial under it.",
    ports={"cap": "Caps the vial under it while on.", "power": "24 V DC for the head.",
           "capped": "On while the vial under it is capped."},
    equations=(Equation("capped after cap_s of command", "One crimp per vial."),),
    params=(Param("cap_s", "s", "Time to cap a vial."),),
    assumptions=("It never runs out of caps.", "Every crimp seals."),
)

VialTable.SPEC = EquipmentSpec(
    key="vial_table", title="Vial Table", tier="utility",
    summary=("The outfeed turntable: where finished vials leave the plant, and the "
             "batch record of them."),
    ports={"infeed": "Where vials arrive."},
    equations=(Equation("mean = sum(V) / n", "The batch's mean fill."),),
    params=(),
    assumptions=("It never fills up.",),
)
