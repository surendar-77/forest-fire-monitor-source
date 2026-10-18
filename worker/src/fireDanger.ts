/**
 * Fire-danger model: gradient-boosted trees trained in ml/train_fire_danger.py
 * on the UCI Algerian Forest Fires dataset, exported to models/fireDanger.json.
 * Gives the probability that today's weather matches fire days.
 */

import modelJson from "./models/fireDanger.json" with { type: "json" };

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
}

export const fireDangerModel = modelJson as unknown as FireDangerModel & {
  metrics: Record<string, unknown>;
  fixtures: { input: number[]; probability: number }[];
};

export type DangerLevel = "LOW" | "MODERATE" | "HIGH" | "VERY HIGH";

function leafValue(tree: Tree, x: number[]): number {
  let node = 0;
  while (tree.feature[node] >= 0) {
    node = x[tree.feature[node]] <= tree.threshold[node] ? tree.left[node] : tree.right[node];
  }
  return tree.value[node];
}

/** Probability (0-1) for features in model order: [Temperature, Rain, ISI]. */
export function fireDangerProbability(x: number[], model: FireDangerModel = fireDangerModel): number {
  let score = model.init;
  for (const tree of model.trees) score += model.learningRate * leafValue(tree, x);
  return 1 / (1 + Math.exp(-score));
}

export function dangerLevel(probability: number): DangerLevel {
  if (probability < 0.25) return "LOW";
  if (probability < 0.5) return "MODERATE";
  if (probability < 0.75) return "HIGH";
  return "VERY HIGH";
}
