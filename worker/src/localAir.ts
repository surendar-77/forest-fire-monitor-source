/**
 * Air at the sensor from the MQ-2 smoke sensors, judged against this
 * sensor's own learned clean-air level (the anomaly baseline), with the
 * camera and the heat/dryness readings deciding between smoke and gas: an
 * MQ-2 reacts to both, but a fire also brings visible smoke or heat.
 */

import type { AnomalyResult } from "./anomaly.js";

export type AirStatus = "LEARNING" | "UNKNOWN" | "CLEAN" | "SLIGHT" | "SMOKE" | "HEAVY_SMOKE" | "GAS";

export interface LocalAir {
  status: AirStatus;
  label: string;
  detail: string;
}

/** z-scores (one-sided, above normal) that mark each step. */
const SLIGHT_Z = 2;
const HIGH_Z = 4;
const HEAVY_Z = 7;

export function localAir(
  anomaly: AnomalyResult,
  aiClass: string | null,
  aiConfidence: number,
  smokeSensorReading: boolean,
): LocalAir {
  if (!smokeSensorReading) {
    return { status: "UNKNOWN", label: "Air: no reading", detail: "The smoke sensor is not reporting." };
  }
  if (anomaly.level === "LEARNING") {
    return {
      status: "LEARNING",
      label: "Learning clean air",
      detail: "The sensor is learning what clean air looks like here (first hour).",
    };
  }

  const z = anomaly.z;
  const smokeZ = Math.max(z.mq1 ?? 0, z.mq2 ?? 0);
  const heat = Math.max(z.temp1 ?? 0, z.temp2 ?? 0, z.hum1 ?? 0, z.hum2 ?? 0) >= SLIGHT_Z;
  const cameraSmoke = (aiClass === "Smoke" || aiClass === "Fire") && aiConfidence >= 0.5;

  if (smokeZ < SLIGHT_Z) {
    return cameraSmoke
      ? {
          status: "SMOKE",
          label: "Smoke seen by camera",
          detail: "The camera sees smoke; the smoke sensor has not picked it up yet.",
        }
      : { status: "CLEAN", label: "Clean air", detail: "Smoke sensor at its normal clean-air level." };
  }

  if (smokeZ < HIGH_Z) {
    return cameraSmoke
      ? { status: "SMOKE", label: "Smoke detected", detail: "Smoke sensor above normal and the camera sees smoke." }
      : {
          status: "SLIGHT",
          label: "Slightly unusual air",
          detail: "Smoke sensor a little above normal: light smoke, dust or gas nearby.",
        };
  }

  if (cameraSmoke || heat) {
    const heavy = smokeZ >= HEAVY_Z;
    return {
      status: heavy ? "HEAVY_SMOKE" : "SMOKE",
      label: heavy ? "Heavy smoke" : "Smoke detected",
      detail: cameraSmoke
        ? "Smoke sensor well above normal and the camera sees smoke."
        : "Smoke sensor well above normal with rising heat or dryness.",
    };
  }

  return {
    status: "GAS",
    label: "Gas detected",
    detail:
      "Smoke sensor well above normal but no smoke on camera and no heat: likely gas " +
      "(LPG, methane), vehicle exhaust or alcohol vapour nearby.",
  };
}
