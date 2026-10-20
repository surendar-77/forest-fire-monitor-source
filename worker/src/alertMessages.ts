/**
 * The plain-language message stored on every alert: what was seen, why it
 * matters and what to do. Shown in the push notification, on Telegram and
 * in the app.
 */

export interface MessageFacts {
  nodeName: string;
  severity: string;
  /** Camera AI confidence 0-1. */
  aiConfidence?: number | null;
  temperature?: number | null;
  humidity?: number | null;
  smoke?: number | null;
  /** Anomaly: the sensor furthest from normal, and how far (z-score). */
  anomalyDriver?: string | null;
  anomalyZ?: number | null;
  /** Today's fire-danger level at the sensor (LOW ... VERY HIGH). */
  dangerLevel?: string | null;
  /** Satellite detection. */
  distanceKm?: number | null;
  satellite?: string | null;
  satelliteConfidence?: string | null;
  /** Offline: when the sensor last reported. */
  lastSeen?: Date | null;
}

const SENSOR_NAMES: Record<string, string> = {
  mq1: "smoke sensor 1",
  mq2: "smoke sensor 2",
  temp1: "temperature (zone 1)",
  temp2: "temperature (zone 2)",
  hum1: "humidity (zone 1)",
  hum2: "humidity (zone 2)",
};

function conditions(f: MessageFacts): string {
  const parts: string[] = [];
  if (f.temperature != null && f.temperature !== 0) parts.push(`${f.temperature.toFixed(1)} °C`);
  if (f.humidity != null && f.humidity !== 0) parts.push(`${Math.round(f.humidity)}% humidity`);
  if (f.smoke != null && f.smoke > 0) parts.push(`smoke level ${Math.round(f.smoke)}`);
  return parts.length > 0 ? ` Readings: ${parts.join(", ")}.` : "";
}

function danger(f: MessageFacts): string {
  const level = (f.dangerLevel ?? "").toUpperCase();
  return level === "HIGH" || level === "VERY HIGH"
    ? " Fire danger today is high, so a fire could spread fast."
    : "";
}

function sure(f: MessageFacts): string {
  return f.aiConfidence != null ? ` (${Math.round(f.aiConfidence * 100)}% sure)` : "";
}

function timeIst(d: Date): string {
  return d.toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", timeZone: "Asia/Kolkata" });
}

/** The message for a new alert of [type]. */
export function alertMessageFor(type: string, f: MessageFacts): string {
  const where = f.nodeName;
  switch (type) {
    case "FIRE":
      return (
        `The camera at ${where} sees flames${sure(f)}.${conditions(f)}` +
        `${f.severity === "CRITICAL" ? " The smoke and heat sensors agree." : ""}${danger(f)}` +
        " Check the area now and call the fire service if it is confirmed."
      );
    case "SMOKE":
      return (
        `The camera at ${where} sees smoke${sure(f)}.${conditions(f)}${danger(f)}` +
        " A fire may be starting: check the area and watch for flames."
      );
    case "SENSOR_ANOMALY": {
      const sensor = f.anomalyDriver ? SENSOR_NAMES[f.anomalyDriver] ?? f.anomalyDriver : "the sensors";
      const far = f.anomalyZ != null && f.anomalyZ >= 3 ? " far above" : " above";
      return (
        `Readings at ${where} are${far} normal for this sensor, led by ${sensor}.${conditions(f)}` +
        " The camera has not seen fire yet. Check the area: this can be the first sign of a fire."
      );
    }
    case "SATELLITE_HOTSPOT": {
      const km = f.distanceKm != null ? `${f.distanceKm.toFixed(1)} km from ` : "near ";
      const by = f.satellite ? ` (${f.satellite}` + (f.satelliteConfidence ? `, ${f.satelliteConfidence} confidence)` : ")") : "";
      return (
        `A NASA satellite detected a fire ${km}${where}${by}.${danger(f)}` +
        " Check whether it is moving toward the sensor's area."
      );
    }
    case "NODE_OFFLINE":
      return (
        `${where} has stopped sending data` +
        `${f.lastSeen ? ` since ${timeIst(f.lastSeen)}` : ""}. It cannot warn about fires until it is back.` +
        " Check its power supply and Wi-Fi."
      );
    case "ENVIRONMENTAL_RISK":
      return (
        `Conditions at ${where} favour fire: hot, dry or smoky.${conditions(f)}` +
        " No fire seen yet; stay alert and avoid anything that could start one."
      );
    default:
      return `Alert at ${where}.${conditions(f)}`;
  }
}

/** Extra line when a fire has been seen without a break for 2 minutes. */
export const CONFIRMED_MESSAGE =
  "Confirmed: the camera has seen this fire continuously for over 2 minutes. Send help now.";
