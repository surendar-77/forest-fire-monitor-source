/**
 * Adding a sensor from the app: an admin files a request, the backend
 * checks it, creates the node and its secret key, and returns the key to
 * that admin once (it goes into the new board's firmware).
 */

import type { Plain } from "./firestore.js";

export const NODE_ID = /^[A-Z0-9][A-Z0-9-]{1,23}$/;

export const TERRAINS = [
  "pine", "eucalyptus", "grassland", "bamboo", "dry_deciduous", "scrub",
  "mixed", "moist_deciduous", "evergreen", "desert", "wetland",
];

export interface AddNodeRequest {
  nodeId: string;
  name: string;
  zone: string | null;
  terrain: string | null;
  channelId: string | null;
  readApiKey: string | null;
}

const text = (v: Plain | undefined, max: number): string | null =>
  typeof v === "string" && v.trim().length > 0 ? v.trim().slice(0, max) : null;

/** The validated request, or an error message for the admin. */
export function parseAddNode(data: Record<string, Plain>): AddNodeRequest | string {
  const nodeId = (text(data.nodeId, 24) ?? "").toUpperCase();
  if (!NODE_ID.test(nodeId)) return "Sensor ID must be 2-24 capital letters, digits or dashes, like NODE-02.";
  const name = text(data.name, 40);
  if (!name) return "Give the sensor a name.";
  const terrain = text(data.terrain, 20);
  if (terrain && !TERRAINS.includes(terrain)) return "Unknown terrain type.";
  const channelId = text(data.channelId, 12);
  if (channelId && !/^\d{1,12}$/.test(channelId)) return "ThingSpeak channel ID is a number.";
  return {
    nodeId,
    name,
    zone: text(data.zone, 40),
    terrain,
    channelId,
    readApiKey: text(data.readApiKey, 32),
  };
}

/** A random 32-character hex key. */
export function newNodeKey(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** The next free id like NODE-02, given the existing ids. */
export function suggestNodeId(existing: string[]): string {
  let highest = 0;
  for (const id of existing) {
    const match = /^NODE-(\d+)$/.exec(id);
    if (match) highest = Math.max(highest, Number(match[1]));
  }
  return `NODE-${String(highest + 1).padStart(2, "0")}`;
}
