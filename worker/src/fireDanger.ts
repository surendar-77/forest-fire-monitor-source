/**
 * Fire-danger model: gradient-boosted trees trained in
 * ml/train_fire_danger_india.py on Indian forest fires (NASA VIIRS, 45
 * forest locations in 23 states, 2022-2024), exported to
 * models/fireDanger.json. Gives the probability of a satellite-detected
 * vegetation fire within 10 km today, from noon weather and the month.
 */

import modelJson from "./models/fireDanger.json" with { type: "json" };
import { adjustProbability } from "./terrain.js";

interface Tree {
  feature: number[];
  threshold: number[];
  left: number[];
  right: number[];
  value: number[];
}

export interface FireDangerModel {
  id: string;
  features: string[];
  init: number;
  learningRate: number;
  trees: Tree[];
  /** Raw probability where the danger index reaches 1/3, 2/3 and 1. */
  levels?: { medium: number; high: number; max: number };
  baseRate?: number;
}

export const fireDangerModel = modelJson as unknown as FireDangerModel & {
  metrics: Record<string, unknown>;
  fixtures: { input: number[]; probability: number }[];
};

export type DangerLevel = "LOW" | "MODERATE" | "HIGH" | "VERY HIGH";

/** Weather on the day being rated, as the Worker computes it. */
export interface DangerFeatures {
  temp: number;
  rh: number;
  wind: number;
  rain24h: number;
  ffmc: number;
  isi: number;
  /** 1-12, local. */
  month: number;
}

function featureValue(name: string, f: DangerFeatures): number {
  const angle = (2 * Math.PI * (f.month - 1)) / 12;
  switch (name) {
    case "Temperature": return f.temp;
    case "RH": return f.rh;
    case "Wind": return f.wind;
    case "Rain": return f.rain24h;
    case "FFMC": return f.ffmc;
    case "ISI": return f.isi;
    case "MonthSin": return Math.sin(angle);
    case "MonthCos": return Math.cos(angle);
    default: throw new Error(`Unknown model feature ${name}`);
  }
}

/** Feature vector in the model's order. */
export function featureVector(f: DangerFeatures, model: FireDangerModel = fireDangerModel): number[] {
  return model.features.map((name) => featureValue(name, f));
}

function leafValue(tree: Tree, x: number[]): number {
  let node = 0;
  while (tree.feature[node] >= 0) {
    node = x[tree.feature[node]] <= tree.threshold[node] ? tree.left[node] : tree.right[node];
  }
  return tree.value[node];
}

/** Raw model probability for a feature vector in model order. */
export function rawProbability(x: number[], model: FireDangerModel = fireDangerModel): number {
  let score = model.init;
  for (const tree of model.trees) score += model.learningRate * leafValue(tree, x);
  return 1 / (1 + Math.exp(-score));
}

/** Chance (0-1) of a satellite-detected fire within 10 km today. */
export function fireChance(f: DangerFeatures, model: FireDangerModel = fireDangerModel): number {
  return rawProbability(featureVector(f, model), model);
}

/**
 * Danger index 0-1 from the raw chance: piecewise linear through the
 * model's breakpoints, so 1/3 = Medium and 2/3 = High everywhere else.
 */
export function dangerIndex(chance: number, model: FireDangerModel = fireDangerModel): number {
  const l = model.levels;
  if (!l) return chance;
  const xs = [0, l.medium, l.high, l.max];
  const ys = [0, 1 / 3, 2 / 3, 1];
  if (chance >= l.max) return 1;
  for (let i = 1; i < xs.length; i++) {
    if (chance <= xs[i]) return ys[i - 1] + ((chance - xs[i - 1]) / (xs[i] - xs[i - 1])) * (ys[i] - ys[i - 1]);
  }
  return 1;
}

/** Danger index (0-1) for today's weather. */
export function fireDangerProbability(f: DangerFeatures, model: FireDangerModel = fireDangerModel): number {
  return dangerIndex(fireChance(f, model), model);
}

/**
 * Danger index for a terrain: the fuel factor scales the odds of the raw
 * chance, which is then mapped to the index.
 */
export function terrainDanger(chance: number, factor: number, model: FireDangerModel = fireDangerModel): number {
  return dangerIndex(adjustProbability(chance, factor), model);
}

export function dangerLevel(index: number): DangerLevel {
  if (index < 0.25) return "LOW";
  if (index < 0.5) return "MODERATE";
  if (index < 0.75) return "HIGH";
  return "VERY HIGH";
}
