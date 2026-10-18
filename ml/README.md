# Machine learning

## Fire danger (stage 1), trained on Indian data

Daily chance of a satellite-detected vegetation fire within 10 km of a node,
from that day's noon weather and the month.

- **Labels:** NASA FIRMS VIIRS S-NPP (375 m) active fires for India,
  2022-2024. Uses presumed vegetation fires with nominal or high confidence.
  A day counts as a fire day when a detection falls within 10 km between
  06:00 and 06:00 the next day IST, i.e. after the noon rating.
- **Weather:** ERA5 via the Open-Meteo archive, hourly, in IST. Features
  are computed exactly as the Worker computes them at runtime:
  - noon temperature, humidity and wind
  - rain in the previous 24 h
  - FFMC spun up over the previous 14 noons, and ISI (`fwi.py`)
  - month, encoded as sin/cos
- **Locations:** 45 forest areas in 23 states (`india_dataset.py`), covering:
  - dry and moist deciduous forest
  - chir pine
  - evergreen
  - thorn forest
  - north-east bamboo/jhum

  Cropland-burning areas are excluded. That gives 49,320 location-days, 4.2%
  of them fire days.
- **Model:** gradient-boosted trees (150 trees, depth 3), exported to
  `worker/src/models/fireDanger.json`. The Cloudflare Worker runs it each
  hour with Open-Meteo weather for the node.

### Results (data the model never trained on)

| | ROC AUC | PR AUC | Brier | Fire-day rate in top 10% vs average |
|---|---|---|---|---|
| Leave-states-out (5 folds of whole states) | 0.848 | 0.176 | 0.037 | 4.6× |
| Train 2022-23, test 2024 | 0.879 | 0.220 | 0.036 | 4.9× |
| Previous Algerian model applied to India | 0.791 | 0.120 | 0.319 | 2.9× |

- **Calibration:** the probabilities are calibrated up to ~30% (for example,
  predicted 14% gives 14% observed). Above that they run high: 38% predicted
  is ~24% observed.
- **Algerian model:** it ranks Indian days reasonably, but its probabilities
  are badly off (Brier 0.32), so it rates far too many days as dangerous.

### Turning the chance into Low / Medium / High

The raw chance is mapped to a 0-100 danger index with the breakpoints below
(set in `LEVELS`). The rest of the system keeps 1/3 = Medium and 2/3 = High.

| Raw chance | Index | Level | Share of days | Fire-day rate |
|---|---|---|---|---|
| < 8% | < 33 | LOW | 83% | 1.8% |
| 8-20% | 33-67 | MEDIUM | 12% | 13.4% |
| > 20% | > 67 | HIGH | 5% | 22.8% |

The share-of-days and fire-day-rate columns come from the leave-states-out
predictions. Terrain factors multiply the odds of the raw chance before it is
mapped to the index (`worker/src/terrain.ts`).

### Terrain check

These are fire odds beyond what the weather explains, by forest type,
relative to the average site:

| Forest type | Odds | Locations |
|---|---|---|
| Chir pine | 2.8× | 4 |
| Evergreen | 2.5× | 2 |
| Bamboo/jhum | 2.0× | 4 |
| Moist deciduous | 1.5× | 19 |
| Dry deciduous | 0.75× | 14 |
| Thorn | 0.06× | 2 |

- The pine and thorn results agree with the expert terrain factors.
- The evergreen result rests on two sites, and is probably surrounding jhum
  and grassland fires.
- Human ignition confounds fuel throughout, so the factors stay expert-set.

### Limits

- **What the label measures:** "satellite saw a fire nearby", not "fire
  started at the node". Small or under-canopy fires are missed, and most
  Indian forest fires are lit by people. The model rates conditions, not
  ignitions.
- **Training vs runtime weather:** the model trains on ERA5 reanalysis but
  runs on the Open-Meteo forecast, so there's a small shift between the two.

```sh
python -m venv .venv && .venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python india_dataset.py             # downloads FIRMS CSVs first, see below
.venv\Scripts\python compare_fire_danger_india.py # model / feature comparison
.venv\Scripts\python train_fire_danger_india.py   # train + export
cd ../worker && npm test && npx wrangler deploy
```

The FIRMS yearly country files need no key. Save them in `data/india/` (it
is gitignored):

`https://firms.modaps.eosdis.nasa.gov/data/country/viirs-snpp/{year}/viirs-snpp_{year}_India.csv`
→ `data/india/viirs_{year}_India.csv`

### Previous model (Algerian dataset)

`train_fire_danger.py` trains on the UCI Algerian Forest Fires dataset
(243 days, 2012). It reached 91% cross-validated accuracy there. It is kept
for comparison in `models/fire_danger_algeria.json` and is no longer deployed.
