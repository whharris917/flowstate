"""Process historian: every tag, every scan, no exceptions.

The historian is the single source of truth for anything displayed to a
human. Displays read historized samples (trends) or live sim state
(faceplates); they never compute, smooth, or invent data. What you see
on a trend is exactly what the kernel computed, tick by tick — the same
contract as a plant historian.
"""
from __future__ import annotations

from typing import Callable


class Historian:
    """Records named tags as parallel time series, one sample per scan."""

    def __init__(self) -> None:
        self.time: list[float] = []
        self.data: dict[str, list[float]] = {}
        self._readers: dict[str, Callable[[], float]] = {}

    @property
    def tags(self) -> list[str]:
        return list(self._readers)

    def __len__(self) -> int:
        return len(self.time)

    def register(self, tag: str, read: Callable[[], float]) -> None:
        if tag in self._readers:
            raise ValueError(f"duplicate tag {tag!r}")
        if self.time:
            raise ValueError("register all tags before sampling begins")
        self._readers[tag] = read
        self.data[tag] = []

    def sample(self, t: float) -> None:
        self.time.append(t)
        for tag, read in self._readers.items():
            self.data[tag].append(float(read()))

    def series(self, tag: str) -> list[float]:
        return self.data[tag]

    def to_csv_text(self) -> str:
        """Full record as CSV, time first — the export a historian owes you."""
        tags = self.tags
        lines = ["time_s," + ",".join(tags)]
        for i, t in enumerate(self.time):
            row = ",".join(f"{self.data[tag][i]:.6g}" for tag in tags)
            lines.append(f"{t:.6g},{row}")
        return "\n".join(lines) + "\n"

    def to_csv(self, path: str) -> None:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(self.to_csv_text())
