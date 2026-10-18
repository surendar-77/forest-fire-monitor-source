"""Loads the UCI Algerian Forest Fires dataset (id 547) into one clean table.

The CSV holds two regions one after the other, each with its own header
line, and has stray spaces and one malformed row. Columns used:
  Temperature (noon max, °C), RH (%), Ws (wind, km/h), Rain (mm),
  FFMC, ISI (Canadian Fire Weather Index codes), Classes (fire / not fire).
"""

from __future__ import annotations

import io
from pathlib import Path

import pandas as pd

DATA = Path(__file__).parent / "data" / "Algerian_forest_fires_dataset_UPDATE.csv"
URL = "https://archive.ics.uci.edu/static/public/547/algerian+forest+fires+dataset.zip"


def load() -> pd.DataFrame:
    text = DATA.read_text(encoding="utf-8")
    frames = []
    region = None
    block: list[str] = []

    def flush():
        if region is not None and block:
            df = pd.read_csv(io.StringIO("\n".join(block)), skipinitialspace=True)
            df["region"] = region
            frames.append(df)

    for line in text.splitlines():
        if "Region Dataset" in line:
            flush()
            region = "Bejaia" if "Bejaia" in line else "Sidi-Bel Abbes"
            block = []
        elif line.strip():
            block.append(line)
    flush()

    df = pd.concat(frames, ignore_index=True)
    df.columns = [c.strip() for c in df.columns]
    df["Classes"] = df["Classes"].astype(str).str.strip().str.lower()
    df = df[df["Classes"].isin(["fire", "not fire"])].copy()

    numeric = ["Temperature", "RH", "Ws", "Rain", "FFMC", "DMC", "DC", "ISI", "BUI", "FWI"]
    for col in numeric:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    df = df.dropna(subset=numeric)

    df["fire"] = (df["Classes"] == "fire").astype(int)
    return df.reset_index(drop=True)


if __name__ == "__main__":
    df = load()
    print(df.groupby("region")["fire"].agg(["count", "sum"]))
    print(df.describe().T[["mean", "min", "max"]])
