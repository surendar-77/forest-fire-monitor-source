"""Canadian Fire Weather Index components used by the fire-danger model.

FFMC (Fine Fuel Moisture Code) and ISI (Initial Spread Index), following
Van Wagner (1987) "Development and structure of the Canadian Forest Fire
Weather Index System" and the reference implementation of Wang et al.
(2015). Inputs are noon weather: temperature (°C), relative humidity (%),
wind speed (km/h) and rain over the previous 24 h (mm).
"""

from __future__ import annotations

import math

FFMC_START = 85.0  # standard start-up value


def ffmc(temp: float, rh: float, wind: float, rain: float, ffmc_prev: float) -> float:
    rh = min(max(rh, 0.0), 100.0)
    mo = 147.2 * (101.0 - ffmc_prev) / (59.5 + ffmc_prev)

    if rain > 0.5:
        rf = rain - 0.5
        wetting = 42.5 * rf * math.exp(-100.0 / (251.0 - mo)) * (1.0 - math.exp(-6.93 / rf))
        if mo > 150.0:
            mo = mo + wetting + 0.0015 * (mo - 150.0) ** 2 * math.sqrt(rf)
        else:
            mo = mo + wetting
        mo = min(mo, 250.0)

    ed = (
        0.942 * rh**0.679
        + 11.0 * math.exp((rh - 100.0) / 10.0)
        + 0.18 * (21.1 - temp) * (1.0 - math.exp(-0.115 * rh))
    )

    if mo > ed:
        ko = 0.424 * (1.0 - (rh / 100.0) ** 1.7) + 0.0694 * math.sqrt(wind) * (1.0 - (rh / 100.0) ** 8)
        kd = ko * 0.581 * math.exp(0.0365 * temp)
        m = ed + (mo - ed) * 10.0 ** (-kd)
    else:
        ew = (
            0.618 * rh**0.753
            + 10.0 * math.exp((rh - 100.0) / 10.0)
            + 0.18 * (21.1 - temp) * (1.0 - math.exp(-0.115 * rh))
        )
        if mo < ew:
            k1 = 0.424 * (1.0 - ((100.0 - rh) / 100.0) ** 1.7) + 0.0694 * math.sqrt(wind) * (
                1.0 - ((100.0 - rh) / 100.0) ** 8
            )
            kw = k1 * 0.581 * math.exp(0.0365 * temp)
            m = ew - (ew - mo) * 10.0 ** (-kw)
        else:
            m = mo

    value = 59.5 * (250.0 - m) / (147.2 + m)
    return min(max(value, 0.0), 101.0)


def isi(ffmc_value: float, wind: float) -> float:
    fm = 147.2 * (101.0 - ffmc_value) / (59.5 + ffmc_value)
    f_wind = math.exp(0.05039 * wind)
    f_fuel = 91.9 * math.exp(-0.1386 * fm) * (1.0 + fm**5.31 / 4.93e7)
    return 0.208 * f_wind * f_fuel


def ffmc_series(days: list[tuple[float, float, float, float]], start: float = FFMC_START) -> list[float]:
    """FFMC for consecutive days of (temp, rh, wind, rain)."""
    values = []
    prev = start
    for temp, rh, wind, rain in days:
        prev = ffmc(temp, rh, wind, rain, prev)
        values.append(prev)
    return values
