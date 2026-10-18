"""Trains the fire-danger model and exports it for the backend.

  python train_fire_danger.py

Data: UCI Algerian Forest Fires dataset (243 days, two regions, fire / not
fire). FFMC and ISI are recomputed from the dataset's own weather columns
with fwi.py, exactly as the backend computes them at runtime from weather
data, rather than taken from the dataset's recorded codes (which can't be
reproduced from its weather and made accuracy look far better than it is
in deployment).

Model: gradient-boosted decision stumps/trees on Temperature, 24 h Rain and
ISI, chosen as the most robust when trained on one region and tested on
the other. Exported as JSON trees to worker/src/models/fireDanger.json.
"""

from __future__ import annotations

import json
import warnings
from datetime import date
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.metrics import accuracy_score, f1_score, roc_auc_score
from sklearn.model_selection import RepeatedStratifiedKFold, cross_validate

from fire_danger_data import load
from fwi import ffmc_series, isi

warnings.filterwarnings("ignore")

FEATURES = ["Temperature", "Rain", "ISI"]
OUT = Path(__file__).parent.parent / "worker" / "src" / "models" / "fireDanger.json"
MODEL_ID = "fire-danger-gbm-v1"


def make_model() -> GradientBoostingClassifier:
    return GradientBoostingClassifier(n_estimators=80, max_depth=2, learning_rate=0.1, random_state=0)


def dataset() -> pd.DataFrame:
    parts = []
    for _, g in load().groupby("region", sort=False):
        g = g.sort_values(["month", "day"]).copy()
        g["FFMC"] = ffmc_series(list(zip(g.Temperature, g.RH, g.Ws, g.Rain)))
        g["ISI"] = [isi(f, w) for f, w in zip(g.FFMC, g.Ws)]
        parts.append(g)
    return pd.concat(parts, ignore_index=True)


def evaluate(df: pd.DataFrame) -> dict:
    X, y = df[FEATURES].to_numpy(), df["fire"].to_numpy()
    cv = RepeatedStratifiedKFold(n_splits=5, n_repeats=10, random_state=0)
    scores = cross_validate(make_model(), X, y, cv=cv, scoring=["accuracy", "f1", "roc_auc"])

    cross = {}
    for train, test in (("Bejaia", "Sidi-Bel Abbes"), ("Sidi-Bel Abbes", "Bejaia")):
        tr, te = df["region"] == train, df["region"] == test
        model = make_model().fit(X[tr], y[tr])
        p = model.predict_proba(X[te])[:, 1]
        cross[f"{train} -> {test}"] = {
            "accuracy": round(float(accuracy_score(y[te], p >= 0.5)), 3),
            "f1": round(float(f1_score(y[te], p >= 0.5)), 3),
            "auc": round(float(roc_auc_score(y[te], p)), 3),
        }

    return {
        "cv_accuracy": round(float(scores["test_accuracy"].mean()), 3),
        "cv_f1": round(float(scores["test_f1"].mean()), 3),
        "cv_auc": round(float(scores["test_roc_auc"].mean()), 3),
        "cross_region": cross,
    }


def export_trees(model: GradientBoostingClassifier) -> list[dict]:
    """Each regression tree as flat arrays; leaves have feature = -1."""
    trees = []
    for estimator in model.estimators_[:, 0]:
        t = estimator.tree_
        trees.append(
            {
                "feature": t.feature.tolist(),
                "threshold": [round(float(v), 6) for v in t.threshold],
                "left": t.children_left.tolist(),
                "right": t.children_right.tolist(),
                "value": [round(float(v), 8) for v in t.value[:, 0, 0]],
            }
        )
    return trees


def main() -> None:
    df = dataset()
    metrics = evaluate(df)
    print(json.dumps(metrics, indent=2))

    model = make_model().fit(df[FEATURES].to_numpy(), df["fire"].to_numpy())

    # Prior log-odds the boosting starts from (sklearn's "init" estimator).
    prior = float(df["fire"].mean())
    init = float(np.log(prior / (1 - prior)))

    # A few input -> probability pairs so the TypeScript port can be checked
    # against scikit-learn.
    samples = df.sample(8, random_state=3)[FEATURES].to_numpy()
    fixtures = [
        {"input": [round(float(v), 4) for v in row],
         "probability": round(float(model.predict_proba([row])[0, 1]), 6)}
        for row in samples
    ]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps(
            {
                "id": MODEL_ID,
                "trained": date.today().isoformat(),
                "description": "Probability that weather conditions match fire days "
                "(UCI Algerian Forest Fires dataset, 2012).",
                "features": FEATURES,
                "featureUnits": ["°C (noon)", "mm in previous 24 h", "Initial Spread Index"],
                "init": init,
                "learningRate": model.learning_rate,
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
