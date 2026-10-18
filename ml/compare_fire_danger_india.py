"""Compares fire-danger models on the Indian dataset (india_dataset.py).

  python compare_fire_danger_india.py

Two honest splits, both unseen by training:
- spatial: leave-states-out (5 folds of whole states), i.e. a node in a
  state the model never saw;
- temporal: train 2022-2023, test 2024.

Metrics: ROC AUC, PR AUC (average precision; compare with the fire-day
base rate), Brier score, and lift = fire-day rate among the top 10% most
dangerous days / overall rate.
"""

from __future__ import annotations

import json
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, brier_score_loss, roc_auc_score
from sklearn.model_selection import GroupKFold
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

warnings.filterwarnings("ignore")

DATA = Path(__file__).parent / "data" / "india" / "dataset.csv"
ALGERIAN = Path(__file__).parent / "models" / "fire_danger_algeria.json"

FEATURE_SETS = {
    "T+Rain+ISI (current)": ["Temperature", "Rain", "ISI"],
    "+RH+Wind+FFMC": ["Temperature", "RH", "Wind", "Rain", "FFMC", "ISI"],
    "+Rain14+DryDays": ["Temperature", "RH", "Wind", "Rain", "FFMC", "ISI", "Rain14", "DryDays"],
    "+season": ["Temperature", "RH", "Wind", "Rain", "FFMC", "ISI", "Rain14", "DryDays", "MonthSin", "MonthCos"],
}


def load() -> pd.DataFrame:
    df = pd.read_csv(DATA)
    angle = 2 * np.pi * (df["month"] - 1) / 12
    df["MonthSin"], df["MonthCos"] = np.sin(angle), np.cos(angle)
    df["year"] = df["date"].str[:4].astype(int)
    return df


def models() -> dict:
    return {
        "logistic": lambda: make_pipeline(StandardScaler(), LogisticRegression(max_iter=2000)),
        "gbm d2x80": lambda: GradientBoostingClassifier(n_estimators=80, max_depth=2, random_state=0),
        "gbm d3x150": lambda: GradientBoostingClassifier(
            n_estimators=150, max_depth=3, learning_rate=0.05, subsample=0.8, random_state=0
        ),
    }


def scores(y: np.ndarray, p: np.ndarray) -> dict:
    top = p >= np.quantile(p, 0.9)
    return {
        "auc": round(float(roc_auc_score(y, p)), 3),
        "pr_auc": round(float(average_precision_score(y, p)), 3),
        "brier": round(float(brier_score_loss(y, p)), 4),
        "lift@10%": round(float(y[top].mean() / y.mean()), 2),
    }


def spatial(df: pd.DataFrame, features: list[str], make) -> dict:
    X, y = df[features].to_numpy(), df["fire"].to_numpy()
    p = np.zeros(len(df))
    for train, test in GroupKFold(n_splits=5).split(X, y, df["state"]):
        p[test] = make().fit(X[train], y[train]).predict_proba(X[test])[:, 1]
    return scores(y, p)


def temporal(df: pd.DataFrame, features: list[str], make) -> dict:
    tr, te = df["year"] < 2024, df["year"] == 2024
    model = make().fit(df.loc[tr, features].to_numpy(), df.loc[tr, "fire"].to_numpy())
    return scores(df.loc[te, "fire"].to_numpy(), model.predict_proba(df.loc[te, features].to_numpy())[:, 1])


def algerian_baseline(df: pd.DataFrame) -> dict:
    """The current production model (Algerian data), applied as-is."""
    m = json.loads(ALGERIAN.read_text(encoding="utf-8"))
    X = df[m["features"]].to_numpy()
    score = np.full(len(df), m["init"])
    for t in m["trees"]:
        node = np.zeros(len(df), dtype=int)
        for _ in range(16):
            f = np.array(t["feature"])[node]
            leaf = f < 0
            if leaf.all():
                break
            go_left = X[np.arange(len(df)), np.where(leaf, 0, f)] <= np.array(t["threshold"])[node]
            nxt = np.where(go_left, np.array(t["left"])[node], np.array(t["right"])[node])
            node = np.where(leaf, node, nxt)
        score += m["learningRate"] * np.array(t["value"])[node]
    p = 1 / (1 + np.exp(-score))
    return scores(df["fire"].to_numpy(), p)


def main() -> None:
    df = load()
    print(f"{len(df):,} location-days, {df['state'].nunique()} states, "
          f"fire-day rate {df['fire'].mean():.3f}\n")
    print("Algerian model as deployed:", algerian_baseline(df), "\n")

    print(f"{'features':<22} {'model':<11} {'split':<9} auc    pr_auc brier  lift@10%")
    for name, features in FEATURE_SETS.items():
        for model_name, make in models().items():
            for split, fn in (("spatial", spatial), ("temporal", temporal)):
                s = fn(df, features, make)
                print(f"{name:<22} {model_name:<11} {split:<9} {s['auc']:<6} {s['pr_auc']:<6} "
                      f"{s['brier']:<6} {s['lift@10%']}")


if __name__ == "__main__":
    main()
