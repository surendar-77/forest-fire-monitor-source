"""Builds the Indian fire-danger training set.

  python india_dataset.py        # writes data/india/dataset.csv

One row per forest location per day, 2022-2024:

- Weather: ERA5 reanalysis from the Open-Meteo archive (free, no key),
  hourly 2 m temperature and humidity, 10 m wind and precipitation, in IST.
  Features are computed exactly as the Worker computes them at runtime from
  the Open-Meteo forecast: noon values, rain in the 24 h up to noon, and
  FFMC spun up from 85 over the previous 14 noons (the forecast API gives
  14 past days).
- Label: NASA FIRMS VIIRS (S-NPP, 375 m) active-fire detections for India,
  presumed vegetation fires with nominal/high confidence. A day is a fire
  day when a detection falls within RADIUS_KM of the location between 06:00
  that day and 06:00 the next day IST, i.e. after the noon rating is issued
  (covers the ~13:30 day and ~01:30 night overpasses).

Locations are forest areas (mostly tiger reserves and forest divisions)
across 23 states, chosen to cover India's forest types: dry and moist
deciduous, Himalayan pine, evergreen, thorn and north-east hill forests.
Cropland-burning areas (Punjab/Haryana) are deliberately excluded.
"""

from __future__ import annotations

import time
from pathlib import Path

import numpy as np
import pandas as pd
import requests

from fwi import FFMC_START, ffmc, isi

DATA = Path(__file__).parent / "data" / "india"
WEATHER = DATA / "weather"
YEARS = (2022, 2023, 2024)
RADIUS_KM = 10.0
SPINUP_DAYS = 14  # past noons the runtime has (Open-Meteo past_days=14)

# (name, state, forest type, latitude, longitude)
LOCATIONS = [
    ("Similipal", "Odisha", "moist deciduous", 21.85, 86.35),
    ("Satkosia", "Odisha", "dry deciduous", 20.60, 84.85),
    ("Kandhamal", "Odisha", "moist deciduous", 20.20, 84.10),
    ("Koraput", "Odisha", "moist deciduous", 18.80, 82.70),
    ("Achanakmar", "Chhattisgarh", "moist deciduous", 22.50, 81.80),
    ("Indravati", "Chhattisgarh", "moist deciduous", 19.00, 80.60),
    ("Kanger Valley", "Chhattisgarh", "moist deciduous", 18.85, 81.95),
    ("Kanha", "Madhya Pradesh", "moist deciduous", 22.30, 80.60),
    ("Satpura", "Madhya Pradesh", "dry deciduous", 22.50, 78.30),
    ("Panna", "Madhya Pradesh", "dry deciduous", 24.70, 80.00),
    ("Bandhavgarh", "Madhya Pradesh", "moist deciduous", 23.70, 81.00),
    ("Melghat", "Maharashtra", "dry deciduous", 21.45, 77.20),
    ("Tadoba", "Maharashtra", "dry deciduous", 20.25, 79.40),
    ("Gadchiroli", "Maharashtra", "moist deciduous", 19.80, 80.30),
    ("Nagarjunsagar-Srisailam", "Andhra Pradesh", "dry deciduous", 16.20, 78.90),
    ("Papikonda", "Andhra Pradesh", "moist deciduous", 17.50, 81.50),
    ("Amrabad", "Telangana", "dry deciduous", 16.35, 78.75),
    ("Kawal", "Telangana", "dry deciduous", 19.20, 78.90),
    ("Bandipur", "Karnataka", "dry deciduous", 11.70, 76.55),
    ("Nagarhole", "Karnataka", "moist deciduous", 12.00, 76.15),
    ("BRT Hills", "Karnataka", "dry deciduous", 11.95, 77.15),
    ("Sathyamangalam", "Tamil Nadu", "dry deciduous", 11.60, 77.30),
    ("Mudumalai", "Tamil Nadu", "dry deciduous", 11.60, 76.55),
    ("Wayanad", "Kerala", "moist deciduous", 11.70, 76.20),
    ("Periyar", "Kerala", "evergreen", 9.50, 77.15),
    ("Corbett", "Uttarakhand", "moist deciduous", 29.55, 78.85),
    ("Almora", "Uttarakhand", "chir pine", 29.60, 79.65),
    ("Pauri", "Uttarakhand", "chir pine", 30.20, 78.70),
    ("Kangra", "Himachal Pradesh", "chir pine", 32.10, 76.30),
    ("Mandi", "Himachal Pradesh", "chir pine", 31.60, 77.00),
    ("Palamau", "Jharkhand", "dry deciduous", 23.85, 84.20),
    ("Saranda", "Jharkhand", "moist deciduous", 22.10, 85.40),
    ("Valmiki", "Bihar", "moist deciduous", 27.35, 84.10),
    ("Gir", "Gujarat", "dry deciduous", 21.10, 70.80),
    ("Dangs", "Gujarat", "moist deciduous", 20.80, 73.70),
    ("Ranthambore", "Rajasthan", "thorn / dry deciduous", 26.00, 76.45),
    ("Sariska", "Rajasthan", "thorn / dry deciduous", 27.35, 76.40),
    ("Buxa", "West Bengal", "moist deciduous", 26.65, 89.60),
    ("Karbi Anglong", "Assam", "moist deciduous", 26.20, 93.40),
    ("Lunglei", "Mizoram", "bamboo / jhum", 22.90, 92.75),
    ("Churachandpur", "Manipur", "bamboo / jhum", 24.30, 93.50),
    ("Gomati", "Tripura", "moist deciduous", 23.50, 91.60),
    ("West Garo Hills", "Meghalaya", "bamboo / jhum", 25.50, 90.30),
    ("Mon", "Nagaland", "bamboo / jhum", 26.65, 95.00),
    ("Namdapha", "Arunachal Pradesh", "evergreen", 27.50, 96.40),
]


# ---------------------------------------------------------------------------
# Weather
# ---------------------------------------------------------------------------

def fetch_weather(name: str, lat: float, lng: float) -> pd.DataFrame:
    path = WEATHER / f"{name.replace(' ', '_')}.csv"
    if path.exists():
        return pd.read_csv(path)

    params = {
        "latitude": lat,
        "longitude": lng,
        "start_date": f"{YEARS[0] - 1}-12-01",  # FFMC spin-up before 1 Jan
        "end_date": f"{YEARS[-1]}-12-31",
        "hourly": "temperature_2m,relative_humidity_2m,wind_speed_10m,precipitation",
        "wind_speed_unit": "kmh",
        "timezone": "Asia/Kolkata",
    }
    for attempt in range(5):
        try:
            r = requests.get("https://archive-api.open-meteo.com/v1/archive", params=params, timeout=120)
        except requests.ConnectionError:
            time.sleep(10 * (attempt + 1))
            continue
        if r.status_code == 429:
            time.sleep(60 * (attempt + 1))
            continue
        r.raise_for_status()
        break
    else:
        raise RuntimeError(f"Open-Meteo unavailable for {name}")

    df = pd.DataFrame(r.json()["hourly"])
    WEATHER.mkdir(parents=True, exist_ok=True)
    df.to_csv(path, index=False)
    return df


def daily_features(hourly: pd.DataFrame) -> pd.DataFrame:
    """Noon features per day, computed as the Worker does at runtime."""
    h = hourly.copy()
    h["precipitation"] = h["precipitation"].fillna(0.0)
    h["rain24h"] = h["precipitation"].rolling(24, min_periods=1).sum()
    noon = h[h["time"].str.endswith("T12:00")].dropna(
        subset=["temperature_2m", "relative_humidity_2m", "wind_speed_10m"]
    )
    noon = noon.reset_index(drop=True)

    temp = noon["temperature_2m"].to_numpy()
    rh = noon["relative_humidity_2m"].to_numpy()
    wind = noon["wind_speed_10m"].to_numpy()
    rain = noon["rain24h"].to_numpy()

    rows = []
    for i in range(SPINUP_DAYS, len(noon)):
        f = FFMC_START
        for j in range(i - SPINUP_DAYS, i):
            f = ffmc(temp[j], rh[j], wind[j], rain[j], f)
        f_today = ffmc(temp[i], rh[i], wind[i], rain[i], f)

        window = rain[i - SPINUP_DAYS + 1 : i + 1]  # last 14 days incl. today
        dry_days = 0
        for r in window[::-1]:
            if r >= 1.0:
                break
            dry_days += 1

        rows.append(
            {
                "date": noon["time"].iat[i][:10],
                "Temperature": temp[i],
                "RH": rh[i],
                "Wind": wind[i],
                "Rain": rain[i],
                "FFMC": f_today,
                "ISI": isi(f_today, wind[i]),
                "Rain14": float(window.sum()),
                "DryDays": dry_days,
            }
        )
    return pd.DataFrame(rows)


# ---------------------------------------------------------------------------
# Fire labels
# ---------------------------------------------------------------------------

def load_fires() -> pd.DataFrame:
    parts = []
    for year in YEARS:
        df = pd.read_csv(
            DATA / f"viirs_{year}_India.csv",
            usecols=["latitude", "longitude", "acq_date", "acq_time", "confidence", "type"],
            dtype={"acq_time": str},
        )
        parts.append(df[(df["type"] == 0) & (df["confidence"].isin(["n", "h"]))])
    fires = pd.concat(parts, ignore_index=True)

    utc = pd.to_datetime(fires["acq_date"] + " " + fires["acq_time"].str.zfill(4), format="%Y-%m-%d %H%M")
    # IST, shifted 6 h back so 06:00-06:00 maps to one fire day.
    fires["fire_day"] = (utc + pd.Timedelta(hours=5, minutes=30) - pd.Timedelta(hours=6)).dt.strftime("%Y-%m-%d")
    return fires[["latitude", "longitude", "fire_day"]]


def fire_days_near(fires: pd.DataFrame, lat: float, lng: float) -> dict[str, int]:
    dlat = RADIUS_KM / 111.0
    dlng = RADIUS_KM / (111.0 * np.cos(np.radians(lat)))
    box = fires[
        fires["latitude"].between(lat - dlat, lat + dlat)
        & fires["longitude"].between(lng - dlng, lng + dlng)
    ]
    p1, p2 = np.radians(lat), np.radians(box["latitude"].to_numpy())
    dl = np.radians(box["longitude"].to_numpy() - lng)
    a = np.sin((p2 - p1) / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dl / 2) ** 2
    km = 6371.0 * 2 * np.arcsin(np.sqrt(a))
    return box.loc[km <= RADIUS_KM, "fire_day"].value_counts().to_dict()


def build() -> pd.DataFrame:
    fires = load_fires()
    print(f"{len(fires):,} vegetation fire detections in India {YEARS[0]}-{YEARS[-1]}")

    parts = []
    for name, state, forest, lat, lng in LOCATIONS:
        hourly = fetch_weather(name, lat, lng)
        days = daily_features(hourly)
        days = days[days["date"].str[:4].astype(int).isin(YEARS)].copy()
        counts = fire_days_near(fires, lat, lng)
        days["detections"] = days["date"].map(counts).fillna(0).astype(int)
        days["fire"] = (days["detections"] > 0).astype(int)
        days.insert(0, "location", name)
        days.insert(1, "state", state)
        days.insert(2, "forest", forest)
        days["latitude"], days["longitude"] = lat, lng
        days["month"] = days["date"].str[5:7].astype(int)
        parts.append(days)
        print(f"  {name:<24} {state:<18} {len(days)} days, {days['fire'].sum():>3} fire days")

    return pd.concat(parts, ignore_index=True)


if __name__ == "__main__":
    df = build()
    out = DATA / "dataset.csv"
    df.to_csv(out, index=False)
    print(f"{len(df):,} location-days, {df['fire'].mean():.1%} fire days -> {out}")
