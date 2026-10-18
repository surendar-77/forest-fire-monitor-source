/**
 * Indicative fire-spread estimate: "if a fire started at the node now, how
 * fast and which way would it run?" (cf. OroraTech Fire Spread, Watch Duty
 * wind layer).
 *
 * Uses the Canadian Forest Fire Behavior Prediction (FBP) System (Forestry
 * Canada 1992, ST-X-3): head rate of spread ROS = a(1 - e^(-b·ISI))^c in
 * m/min per fuel type, the length-to-breadth ratio of the spread ellipse
 * from wind speed, and back spread from zero-wind ISI. Fires run downwind.
 *
 * FBP fuel types are Canadian; each terrain maps to the closest one and,
 * where there's no close match (bamboo, eucalyptus, tropical forests), an
 * approximation that's labelled as such. Treat results as indicative
 * guidance for responders, not a simulation (no slope or terrain data).
 */

import { isi } from "./fwi.js";

interface FuelCoefficients {
  a: number;
  b: number;
  c: number;
}

const FBP: Record<string, FuelCoefficients> = {
  "C-2": { a: 110, b: 0.0282, c: 1.5 }, // boreal spruce
  "C-3": { a: 110, b: 0.0444, c: 3.0 }, // mature jack / lodgepole pine
  "C-6": { a: 30, b: 0.08, c: 3.0 }, // conifer plantation
  "C-7": { a: 45, b: 0.0305, c: 2.0 }, // ponderosa pine / Douglas-fir
  "D-1": { a: 30, b: 0.0232, c: 1.6 }, // leafless aspen
  "S-1": { a: 75, b: 0.0297, c: 1.3 }, // jack / lodgepole pine slash
  "O-1a": { a: 190, b: 0.031, c: 1.4 }, // matted grass
  "O-1b": { a: 250, b: 0.035, c: 1.7 }, // standing grass
};

interface FuelModel {
  fbp: string;
  /** Multiplier for terrains the FBP fuel only approximates. */
  scale: number;
  note: string;
}

/** Grass curing (%) assumed for the dry season, when danger matters. */
const GRASS_CURING = 80;

const TERRAIN_FUEL: Record<string, FuelModel> = {
  pine: { fbp: "C-3", scale: 1, note: "FBP C-3 (mature pine)" },
  eucalyptus: { fbp: "C-7", scale: 1.2, note: "approximated with FBP C-7, scaled up for oily litter" },
  grassland: { fbp: "O-1b", scale: 1, note: "FBP O-1b (standing grass, 80% cured)" },
  bamboo: { fbp: "S-1", scale: 1, note: "approximated with FBP S-1 (dense dry fine fuel)" },
  dry_deciduous: { fbp: "D-1", scale: 1, note: "FBP D-1 (leafless deciduous)" },
  scrub: { fbp: "O-1a", scale: 0.8, note: "approximated with FBP O-1a (matted grass/shrub)" },
  mixed: { fbp: "M-1", scale: 1, note: "FBP M-1 (50% conifer mixedwood)" },
  moist_deciduous: { fbp: "D-1", scale: 0.5, note: "FBP D-1, halved for moist litter" },
  evergreen: { fbp: "D-1", scale: 0.3, note: "approximated with FBP D-1, strongly reduced for humid understorey" },
  desert: { fbp: "O-1a", scale: 0.2, note: "approximated with FBP O-1a, reduced for sparse fuel" },
  wetland: { fbp: "D-1", scale: 0.05, note: "waterlogged fuels; spread negligible" },
};

function curingFactor(curing: number): number {
  return curing < 58.8 ? 0.005 * (Math.exp(0.061 * curing) - 1) : 0.176 + 0.02 * (curing - 58.8);
}

function basicRos(fbp: string, isiValue: number): number {
  if (fbp === "M-1") {
    // 50% conifer: weighted C-2 and D-1.
    return 0.5 * basicRos("C-2", isiValue) + 0.5 * basicRos("D-1", isiValue);
  }
  const k = FBP[fbp];
  const ros = k.a * (1 - Math.exp(-k.b * isiValue)) ** k.c;
  return fbp.startsWith("O-1") ? ros * curingFactor(GRASS_CURING) : ros;
}

/** Ellipse length-to-breadth ratio from wind speed (km/h). */
export function lengthToBreadth(fbp: string, windKmh: number): number {
  if (fbp.startsWith("O-1")) {
    return windKmh < 1 ? 1 : 1.1 * windKmh ** 0.464;
  }
  return 1 + 8.729 * (1 - Math.exp(-0.03 * windKmh)) ** 2.155;
}

export interface SpreadEstimate {
  fuelModel: string;
  note: string;
  /** Head (downwind) and back rates of spread, metres per minute. */
  headRos: number;
  backRos: number;
  lengthToBreadth: number;
  /** Direction the head fire runs, degrees clockwise from north. */
  towardDeg: number;
  /** Distances after one hour, metres. */
  headDistance1h: number;
  backDistance1h: number;
  windKmh: number;
  windFromDeg: number;
}

/**
 * @param ffmcValue  current fine fuel moisture code
 * @param windKmh    10 m wind speed
 * @param windFromDeg  direction the wind blows from (meteorological)
 */
export function estimateSpread(
  terrain: string,
  ffmcValue: number,
  windKmh: number,
  windFromDeg: number,
): SpreadEstimate {
  const fuel = TERRAIN_FUEL[terrain] ?? TERRAIN_FUEL.mixed;
  const headRos = basicRos(fuel.fbp, isi(ffmcValue, windKmh)) * fuel.scale;
  const backRos = basicRos(fuel.fbp, isi(ffmcValue, 0)) * fuel.scale * 0.5;
  const round = (v: number, d = 1) => Math.round(v * 10 ** d) / 10 ** d;

  return {
    fuelModel: fuel.fbp,
    note: fuel.note,
    headRos: round(headRos, 2),
    backRos: round(Math.min(backRos, headRos), 2),
    lengthToBreadth: round(lengthToBreadth(fuel.fbp, windKmh), 2),
    towardDeg: Math.round((windFromDeg + 180) % 360),
    headDistance1h: Math.round(headRos * 60),
    backDistance1h: Math.round(Math.min(backRos, headRos) * 60),
    windKmh: round(windKmh),
    windFromDeg: Math.round(windFromDeg),
  };
}

const COMPASS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];

export function compass(deg: number): string {
  return COMPASS[Math.round((((deg % 360) + 360) % 360) / 45) % 8];
}
