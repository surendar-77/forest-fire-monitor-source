"""Trains the production fire-danger model on Indian data and exports it.

  python india_dataset.py             # once: builds data/india/dataset.csv
  python compare_fire_danger_india.py # optional: model / feature comparison
  python train_fire_danger_india.py   # train, validate, export

Target: probability that NASA VIIRS detects a vegetation fire within 10 km
of a forest location today (see india_dataset.py), from today's noon
weather and the month. 45 forest locations in 23 states, 2022-2024.

Features (all computed by the Worker at runtime from Open-Meteo):
noon temperature, humidity, wind, rain in the previous 24 h, FFMC, ISI, and
the month as a cycle (sin/cos), since India's fire season (Feb-June) is a
strong signal beyond the day's weather. Rain over 14 days and dry-day count
added nothing in comparison and are left out.

The raw probability is calibrated (predicted vs observed agree up to ~30%)
but small: 4% of location-days are fire days. For Low/Medium/High it's
mapped to a 0-1 danger index with breakpoints from the data (LEVELS), so
the rest of the system keeps its 1/3 and 2/3 level boundaries.

Exported to worker/src/models/fireDanger.json.
"""

from __future__ import annotations

import json
import warnings
from datetime import date
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import GroupKFold

from compare_fire_danger_india import algerian_baseline, load, scores
from train_fire_danger import export_trees

warnings.filterwarnings("ignore")

FEATURES = ["Temperature", "RH", "Wind", "Rain", "FFMC", "ISI", "MonthSin", "MonthCos"]
UNITS = ["°C (noon)", "% (noon)", "km/h (noon, 10 m)", "mm in previous 24 h",
         "Fine Fuel Moisture Code", "Initial Spread Index", "sin(2π(month-1)/12)", "cos(2π(month-1)/12)"]
OUT = Path(__file__).parent.parent / "worker" / "src" / "models" / "fireDanger.json"
MODEL_ID = "fire-danger-india-gbm-v2"

# Raw probability at which the danger index reaches 1/3 (MEDIUM), 2/3 (HIGH)
# and 1. Fire-day rate at 0.08 is ~2.5x the average day, at 0.20 ~5x.
LEVELS = {"medium": 0.08, "high": 0.20, "max": 0.40}


def make_model() -> GradientBoostingClassifier:
    return GradientBoostingClassifier(
        n_estimators=150, max_depth=3, learning_rate=0.05, subsample=0.8, random_state=0
    )


def danger_index(p: np.ndarray) -> np.ndarray:
    xs = [0.0, LEVELS["medium"], LEVELS["high"], LEVELS["max"]]
    return np.interp(p, xs, [0.0, 1 / 3, 2 / 3, 1.0])


def evaluate(df: pd.DataFrame) -> dict:
    X, y = df[FEATURES].to_numpy(), df["fire"].to_numpy()

    oof = np.zeros(len(df))
    for train, test in GroupKFold(n_splits=5).split(X, y, df["state"]):
        oof[test] = make_model().fit(X[train], y[train]).predict_proba(X[test])[:, 1]

    tr, te = (df["year"] < 2024).to_numpy(), (df["year"] == 2024).to_numpy()
    temporal_p = make_model().fit(X[tr], y[tr]).predict_proba(X[te])[:, 1]

    index = danger_index(oof)
    levels = {}
    for name, lo, hi in (("LOW", 0, 1 / 3), ("MEDIUM", 1 / 3, 2 / 3), ("HIGH", 2 / 3, 1.01)):
        m = (index >= lo) & (index < hi)
        levels[name] = {"share_of_days": round(float(m.mean()), 3),
                        "fire_day_rate": round(float(y[m].mean()), 3)}

    calibration = []
    for lo, hi in ((0, 0.02), (0.02, 0.05), (0.05, 0.1), (0.1, 0.2), (0.2, 0.3), (0.3, 1)):
        m = (oof >= lo) & (oof < hi)
        calibration.append({"predicted": f"{lo:.2f}-{hi:.2f}", "days": int(m.sum()),
                            "mean_predicted": round(float(oof[m].mean()), 3),
                            "observed": round(float(y[m].mean()), 3)})

    return {
        "fire_day_rate": round(float(y.mean()), 4),
        "leave_states_out": scores(y, oof),
        "train_2022_23_test_2024": scores(y[te], temporal_p),
        "algerian_model_on_india": algerian_baseline(df),
        "levels_leave_states_out": levels,
        "calibration_leave_states_out": calibration,
    }


def main() -> None:
    df = load()
    metrics = evaluate(df)
    print(json.dumps(metrics, indent=2))

    X, y = df[FEATURES].to_numpy(), df["fire"].to_numpy()
    model = make_model().fit(X, y)
    prior = float(y.mean())

    fixtures = [
        {"input": [round(float(v), 4) for v in row],
         "probability": round(float(model.predict_proba([row])[0, 1]), 6)}
        for row in df.sample(10, random_state=3)[FEATURES].to_numpy()
    ]

    OUT.write_text(
        json.dumps(
            {
                "id": MODEL_ID,
                "trained": date.today().isoformat(),
                "description": "Probability of a NASA VIIRS vegetation-fire detection within 10 km "
                "today, from noon weather and month. Trained on 45 forest locations in 23 Indian "
                "states, 2022-2024 (ERA5 weather via Open-Meteo, FIRMS VIIRS S-NPP fires).",
                "features": FEATURES,
                "featureUnits": UNITS,
                "init": float(np.log(prior / (1 - prior))),
                "learningRate": model.learning_rate,
                "levels": LEVELS,
                "baseRate": round(prior, 4),
                "trees": export_trees(model),
                "metrics": metrics,
                "fixtures": fixtures,
            },
            indent=1,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"Exported {len(model.estimators_)} trees to {OUT}")


if __name__ == "__main__":
    main()
