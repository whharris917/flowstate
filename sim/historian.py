"""Process historian: every tag, every scan, no exceptions.

The historian is the single source of truth for anything displayed to a
human. Displays read historized samples (trends) or live sim state
(faceplates); they never compute, smooth, or invent data.

Tags may be registered mid-run (the player just installed the
instrument — its record starts now) and retired (the instrument was
removed — its history is kept, it just stops growing). A tag's series
aligns with the shared time axis via its start index.
"""
from __future__ import annotations

from typing import Callable


class Historian:
    """Records named tags as parallel time series, one sample per scan."""

    def __init__(self) -> None:
        self.time: list[float] = []
        self.data: dict[str, list[float]] = {}
        self._starts: dict[str, int] = {}
        self._readers: dict[str, Callable[[], float]] = {}

    @property
    def tags(self) -> list[str]:
        """Every tag ever recorded, including retired ones."""
        return list(self.data)

    @property
    def active_tags(self) -> list[str]:
        return list(self._readers)

    def __len__(self) -> int:
        return len(self.time)

    def register(self, tag: str, read: Callable[[], float]) -> None:
        if tag in self.data:
            raise ValueError(f"duplicate tag {tag!r}")
        self._readers[tag] = read
        self._starts[tag] = len(self.time)
        self.data[tag] = []

    def retire(self, tag: str) -> None:
        """Stop sampling a tag; its recorded history remains."""
        if tag not in self._readers:
            raise ValueError(f"tag {tag!r} is not active")
        del self._readers[tag]

    def start_index(self, tag: str) -> int:
        return self._starts[tag]

    def sample(self, t: float) -> None:
        self.time.append(t)
        for tag, read in self._readers.items():
            self.data[tag].append(float(read()))

    def series(self, tag: str) -> list[float]:
        return self.data[tag]

    def value_at(self, tag: str, index: int) -> float | None:
        """Value of a tag at a global sample index, or None if the tag
        did not exist (or was retired) at that time."""
        local = index - self._starts[tag]
        if 0 <= local < len(self.data[tag]):
            return self.data[tag][local]
        return None

    def to_csv_text(self) -> str:
        """Full record as CSV, time first. Cells are empty where a tag
        did not exist yet or had been retired — the honest gap."""
        tags = self.tags
        lines = ["time_s," + ",".join(tags)]
        for i, t in enumerate(self.time):
            cells = []
            for tag in tags:
                value = self.value_at(tag, i)
                cells.append("" if value is None else f"{value:.6g}")
            lines.append(f"{t:.6g}," + ",".join(cells))
        return "\n".join(lines) + "\n"

    def to_csv(self, path: str) -> None:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(self.to_csv_text())
