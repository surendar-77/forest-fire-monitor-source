/**
 * Terrain (fuel type) and the final Low / Medium / High risk.
 *
 * How readily fire starts and spreads depends on the fuel. The ML models
 * (weather fire danger, 6-sensor anomaly detection) don't know what grows
 * around a node, so each terrain scales their probabilities by a fuel
 * factor: the odds are multiplied by the factor, which keeps results
 * between 0 and 1 and leaves 0 and 1 unchanged.
 *
 * The factors are set from fire-behaviour knowledge (relative flammability
 * and spread of fuel types), NOT learned: no public fire dataset is labelled
 * by these terrain types. "mixed" = 1.0 matches the mixed Mediterranean
 * forest the danger model was trained on. Adjust here as local data allows.
 */

export interface Terrain {
  id: string;
  label: string;
  factor: number;
  why: string;
}

export const TERRAINS: Terrain[] = [
  { id: "pine", label: "Pine / conifer forest", factor: 1.8, why: "Resin-rich needles and litter; crown fires spread fast" },
  { id: "eucalyptus", label: "Eucalyptus plantation", factor: 1.7, why: "Oily leaves and shedding bark carry fire and embers" },
  { id: "grassland", label: "Grassland / savanna", factor: 1.6, why: "Fine fuels dry within hours; fastest spread" },
  { id: "bamboo", label: "Bamboo (moongil) forest", factor: 1.5, why: "Dry culms and thick leaf litter burn intensely, worst after flowering die-off" },
  { id: "dry_deciduous", label: "Dry deciduous (teak, sal)", factor: 1.3, why: "Heavy leaf fall in the dry season" },
  { id: "scrub", label: "Scrub / thorn forest", factor: 1.2, why: "Dry shrubs ignite easily, patchy fuel" },
  { id: "mixed", label: "Mixed forest", factor: 1.0, why: "Reference fuel the danger model was trained on" },
  { id: "moist_deciduous", label: "Moist deciduous forest", factor: 0.8, why: "Moister litter, slower drying" },
  { id: "evergreen", label: "Tropical evergreen / shola", factor: 0.5, why: "Humid, shaded understorey resists ignition" },
  { id: "desert", label: "Desert / sparse vegetation", factor: 0.4, why: "Too little fuel to carry fire, though very dry" },
  { id: "wetland", label: "Mangrove / wetland", factor: 0.3, why: "Waterlogged fuels rarely burn" },
];

export const DEFAULT_TERRAIN = "mixed";

export function terrainFor(id: unknown): Terrain {
  return TERRAINS.find((t) => t.id === id) ?? TERRAINS.find((t) => t.id === DEFAULT_TERRAIN)!;
}

/** Multiplies the odds p/(1-p) by the factor. */
export function adjustProbability(p: number, factor: number): number {
  const clamped = Math.min(Math.max(p, 0), 1);
  return (clamped * factor) / (1 - clamped + clamped * factor);
}

export type RiskLevel = "LOW" | "MEDIUM" | "HIGH";

export function riskLevel(p: number): RiskLevel {
  if (p >= 0.66) return "HIGH";
  if (p >= 0.33) return "MEDIUM";
  return "LOW";
}

export interface RiskInputs {
  /** 6-sensor anomaly score, 0-100 (0 while the baseline is learning). */
  anomalyScore: number;
  /** Weather fire-danger probability from the ML model, before terrain. */
  dangerProbability: number | null;
  terrain: Terrain;
  /** Camera AI saw fire or smoke with confidence. */
  cameraFire: boolean;
  cameraSmoke: boolean;
}

export interface Risk {
  score: number;
  level: RiskLevel;
  /** What drove the result, for the app and alert text. */
  driver: "camera" | "sensors" | "weather" | "none";
  sensorProbability: number;
  dangerProbability: number | null;
}

/**
 * Overall risk: the larger of the terrain-adjusted sensor anomaly and the
 * terrain-adjusted weather danger. Fire signs at the node (sensors) and fire
 * -prone conditions (weather) each justify concern on their own. A confident
 * camera fire detection is always High.
 */
export function combineRisk(input: RiskInputs): Risk {
  const factor = input.terrain.factor;
  const sensorP = adjustProbability(input.anomalyScore / 100, factor);
  const dangerP =
    input.dangerProbability == null ? null : adjustProbability(input.dangerProbability, factor);

  if (input.cameraFire) {
    return { score: 100, level: "HIGH", driver: "camera", sensorProbability: sensorP, dangerProbability: dangerP };
  }

  let p = Math.max(sensorP, dangerP ?? 0);
  let driver: Risk["driver"] = p === 0 ? "none" : sensorP >= (dangerP ?? 0) ? "sensors" : "weather";

  if (input.cameraSmoke && p < 0.66) {
    p = 0.66; // camera smoke is at least High until someone checks
    driver = "camera";
  }

  return {
    score: Math.round(p * 100),
    level: riskLevel(p),
    driver,
    sensorProbability: Math.round(sensorP * 1000) / 1000,
    dangerProbability: dangerP == null ? null : Math.round(dangerP * 1000) / 1000,
  };
}
