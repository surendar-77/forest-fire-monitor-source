"""Compares candidate fire-danger models on the Algerian dataset.

Feature sets are limited to what the backend can compute at runtime:
  raw:   Temperature, RH, Ws, Rain         (node sensors + free weather API)
  ffmc:  raw + FFMC + ISI                  (FFMC/ISI computed daily from the
                                            same weather, Van Wagner 1987)

Two evaluations:
  * stratified 5-fold cross-validation, repeated, on both regions together
  * cross-region: train on one region, test on the other (closest to
    deploying in a new place)
"""

from __future__ import annotations

import warnings

import numpy as np
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import f1_score, roc_auc_score
from sklearn.model_selection import RepeatedStratifiedKFold, cross_validate
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.tree import DecisionTreeClassifier

from fire_danger_data import load

warnings.filterwarnings("ignore")

FEATURES = {
    "raw": ["Temperature", "RH", "Ws", "Rain"],
    "ffmc": ["Temperature", "RH", "Ws", "Rain", "FFMC", "ISI"],
}

MODELS = {
    "logistic": lambda: make_pipeline(StandardScaler(), LogisticRegression(C=1.0, max_iter=1000)),
    "tree(d3)": lambda: DecisionTreeClassifier(max_depth=3, random_state=0),
    "forest": lambda: RandomForestClassifier(n_estimators=200, max_depth=4, random_state=0),
    "boosting": lambda: GradientBoostingClassifier(n_estimators=100, max_depth=2, random_state=0),
}


def main() -> None:
    df = load()
    y = df["fire"].to_numpy()
    print(f"{len(df)} days, {y.sum()} fire / {len(y) - y.sum()} not fire\n")

    cv = RepeatedStratifiedKFold(n_splits=5, n_repeats=5, random_state=0)
    print(f"{'features':<6} {'model':<10} {'CV acc':>8} {'CV F1':>7} {'CV AUC':>7} "
          f"{'B->S acc':>9} {'S->B acc':>9}")

    for fname, cols in FEATURES.items():
        X = df[cols].to_numpy()
        for mname, make in MODELS.items():
            scores = cross_validate(make(), X, y, cv=cv, scoring=["accuracy", "f1", "roc_auc"])

            cross = []
            for train_region, test_region in (("Bejaia", "Sidi-Bel Abbes"), ("Sidi-Bel Abbes", "Bejaia")):
                tr = df["region"] == train_region
                te = df["region"] == test_region
                model = make().fit(X[tr], y[tr])
                cross.append((model.predict(X[te]) == y[te]).mean())

            print(f"{fname:<6} {mname:<10} {scores['test_accuracy'].mean():8.3f} "
                  f"{scores['test_f1'].mean():7.3f} {scores['test_roc_auc'].mean():7.3f} "
                  f"{cross[0]:9.3f} {cross[1]:9.3f}")


if __name__ == "__main__":
    main()
