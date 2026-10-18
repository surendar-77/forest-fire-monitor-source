# Machine learning

## Fire danger (stage 1)

Daily probability that weather at a node matches fire days.

- **Data:** UCI Algerian Forest Fires dataset (243 days from 2 regions, summer
  2012, labelled fire / not fire), CC BY 4.0. Stored in `data/`.
- **Features:** noon temperature, rain over the previous 24 h, and ISI
  (Initial Spread Index). FFMC and ISI are recomputed from the dataset's own
  weather with `fwi.py`, exactly as the backend computes them at runtime.
  The dataset's recorded FFMC/ISI can't be reproduced from its weather and
  inflate accuracy to ~99%, so they are not used.
- **Model:** gradient-boosted trees (80 trees, depth 2), exported to
  `worker/src/models/fireDanger.json` and run by the Cloudflare Worker each
  hour with Open-Meteo weather for the node's location.
- **Accuracy:** 91% cross-validated (AUC 0.96); 87% / 90% when trained on one
  region and tested on the other. Not yet validated on Indian fire data.

```sh
python -m venv .venv && .venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python compare_fire_danger.py   # model comparison
.venv\Scripts\python train_fire_danger.py     # train + export
cd ../worker && npm test && npx wrangler deploy
```
