/**
 * Forest Fire Monitor backend on Cloudflare Workers (free plan, no card).
 *
 * Cron triggers (Workers Free allows 5 per account; each run gets its own
 * 50-subrequest budget, which is why ingestion and push are separate):
 *   "* * * * *"     ingest every ThingSpeak channel
 *   "*\/1 * * * *"  push new alerts (every minute, separate budget)
 *   "*\/5 * * * *"  node health, alertActive, escalation, role requests, heartbeat
 *   "7 * * * *"     hourly rollup of the previous hour + fire danger (ML)
 *   "23 21 * * *"   delete readings past retention (03:00 IST)
 *
 * Firestore stays inside the Spark plan's daily quota: queries that usually
 * match nothing cost 1 read, and open alerts are fetched every 5 minutes, not
 * every minute.
 */

import {
  AI_FIRE_CONFIDENCE_THRESHOLD,
  AI_SMOKE_CONFIDENCE_THRESHOLD,
  blocksNewDetection,
  decideAlert,
  foldRepeatDetection,
  outageEnded,
  OPEN_STATUSES,
} from "./alertRules.js";
import {
  hourStats,
  isLearnableHour,
  scoreReading,
  updateBaseline,
  type Baseline,
  type Reading,
} from "./anomaly.js";
import { parseDeviceAlert, safeEqual } from "./deviceAlert.js";
import { loraLink, parseLoraReport } from "./lora.js";
import { dangerIndex, dangerLevel, fireChance, fireDangerModel, terrainDanger } from "./fireDanger.js";
import { ffmc, ffmcAfter, isi } from "./fwi.js";
import { currentConditions, dangerInputs, fetchHourlyWeather, upcomingHours } from "./weather.js";
import { fetchAirQuality } from "./airQuality.js";
import { fetchHotspots } from "./firms.js";
import { compass, estimateSpread } from "./spread.js";
import { adjustProbability, combineRisk, riskLevel as riskLevel3, terrainFor, type Terrain } from "./terrain.js";
import { pushAlert } from "./fcm.js";
import { alertMessage, notifyStations, parseFireServices, stationsFor } from "./fireServices.js";
import { Firestore, newDocId, type Doc, type Plain, type Write } from "./firestore.js";
import { accessToken, type ServiceAccount } from "./google.js";
import { lookupUser, setClaims } from "./identity.js";
import { fetchLastFeed, parseFeed, type SensorReading } from "./thingspeak.js";
import { isHealthAlert, parseHealth, planHealth } from "./health.js";
import { alertMessageFor, CONFIRMED_MESSAGE } from "./alertMessages.js";
import { localAir } from "./localAir.js";
import {
  alertAllowed,
  sensorReading,
  DIRECT_FRESH_MS,
  LORA_DEVICE_WRITE_MS,
  liveValues,
  parseLoraData,
} from "./loraData.js";
import { newNodeKey, parseAddNode } from "./nodes.js";
import { Rtdb } from "./rtdb.js";
import { botUsername, chatsFromUpdates, getUpdates, sendText, type BotCommand } from "./telegram.js";

export interface Env {
  /** The Firebase service-account JSON, stored with `wrangler secret put`. */
  FIREBASE_SERVICE_ACCOUNT: string;
  READING_RETENTION_DAYS?: string;
  /** Telegram bot for fire services (optional), `wrangler secret put`. */
  TELEGRAM_BOT_TOKEN?: string;
  /** Opted-in phones within this distance of a node get its serious alerts. */
  NEARBY_RADIUS_KM?: string;
  /** NASA FIRMS key for satellite fire detections (optional). */
  FIRMS_MAP_KEY?: string;
  /** Satellite detections within this distance of a node are shown. */
  SATELLITE_RADIUS_KM?: string;
  /** Realtime Database URL (board health, device keys). */
  RTDB_URL?: string;
}

const VERSION = "worker-1.0.0";
const SUBREQUEST_LIMIT = 50;

const MAX_FEED_AGE_SECONDS = 120;
const STALE_AFTER_MS = 2 * 60_000;
const OFFLINE_AFTER_MS = 10 * 60_000;
const ESCALATE_AFTER_MS = 10 * 60_000;
const ESCALATION_MAX_AGE_MS = 6 * 3_600_000;
const PUSH_WINDOW_MS = 15 * 60_000;
const ROLES = ["viewer", "officer", "admin"];

interface Context {
  fs: Firestore;
  rtdb: Rtdb;
  projectId: string;
  token: () => Promise<string>;
  now: Date;
  env: Env;
}

interface Channel {
  nodeId: string;
  channelId: string;
  readApiKey?: string;
  name?: string;
}

/** The key as raw JSON (wrangler secret put) or base64 JSON (handy in .dev.vars). */
function parseServiceAccount(value: string): ServiceAccount {
  const text = value.trim().startsWith("{") ? value : atob(value.trim());
  const account = JSON.parse(text) as ServiceAccount;
  if (!account.client_email || !account.private_key || !account.project_id) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT is not a service-account key");
  }
  return account;
}

function context(env: Env): Context {
  const account = parseServiceAccount(env.FIREBASE_SERVICE_ACCOUNT);
  const token = () => accessToken(account);
  return {
    fs: new Firestore(account.project_id, token),
    rtdb: new Rtdb(
      env.RTDB_URL ?? `https://${account.project_id}-default-rtdb.firebaseio.com`,
      token,
    ),
    projectId: account.project_id,
    token,
    now: new Date(),
    env,
  };
}

const asDate = (value: Plain | undefined): Date | null => (value instanceof Date ? value : null);
const asNumber = (value: Plain | undefined, fallback = 0): number =>
  typeof value === "number" ? value : fallback;

/** Subrequests left in this invocation, keeping a small margin. */
function budget(ctx: Context, used = 0): number {
  return Math.max(0, SUBREQUEST_LIMIT - ctx.fs.requests - ctx.rtdb.requests - used - 3);
}

async function run(name: string, task: () => Promise<unknown>): Promise<void> {
  try {
    await task();
  } catch (error) {
    console.error(`${name} failed:`, error instanceof Error ? error.stack ?? error.message : error);
  }
}

// ---------------------------------------------------------------------------
// Ingestion
// ---------------------------------------------------------------------------

async function loadChannels(ctx: Context): Promise<Channel[]> {
  const doc = await ctx.fs.get("config/channels");
  const channels = doc?.data.channels;
  if (!Array.isArray(channels)) {
    console.warn("config/channels is missing; nothing to poll");
    return [];
  }
  return channels.filter(
    (c): c is Channel & Record<string, Plain> =>
      typeof c === "object" && c !== null && !Array.isArray(c) && !(c instanceof Date) &&
      typeof (c as Record<string, Plain>).nodeId === "string" &&
      typeof (c as Record<string, Plain>).channelId === "string",
  ) as unknown as Channel[];
}

/** Single-field filter only, so no composite index has to be deployed. */
async function openAlertsFor(ctx: Context, nodeId: string, type: string): Promise<Doc[]> {
  const open = await ctx.fs.query("alerts", {
    where: [{ field: "status", op: "IN", value: [...OPEN_STATUSES] }],
  });
  return open.filter((doc) => doc.data.deviceId === nodeId && doc.data.type === type);
}

/**
 * A detection that matched an open alert: extend its streak, and once fire
 * has been seen without a break for 2 minutes mark it confirmed, raise it
 * to CRITICAL and send a critical notification (the app then draws its
 * fire area).
 */
async function recordRepeatDetection(ctx: Context, alert: Doc): Promise<void> {
  const update = foldRepeatDetection(alert.data, ctx.now);
  const fields: Record<string, Plain> = {
    lastDetectedAt: update.lastDetectedAt,
    streakStartedAt: update.streakStartedAt,
    detections: update.detections,
  };
  if (update.confirmNow) {
    fields.confirmedAt = ctx.now;
    fields.severity = "CRITICAL";
    const before = typeof alert.data.message === "string" ? ` ${alert.data.message}` : "";
    fields.message = `${CONFIRMED_MESSAGE}${before}`;
  }
  await ctx.fs.set(alert.path, fields, true);
  if (!update.confirmNow) return;

  console.log(`Fire confirmed: ${alert.id} (seen ${update.detections} times without a break)`);
  const confirmed = { ...alert.data, ...fields };
  await run(`confirm telegram ${alert.id}`, () =>
    telegramUsers(ctx, alert.path, confirmed, "🚨 CONFIRMED: fire seen for over 2 minutes"),
  );
  await run(`confirm push ${alert.id}`, () =>
    pushAlert(ctx.fs, ctx.projectId, ctx.token, alert.id, confirmed, {
      maxSends: budget(ctx, 6),
      confirmed: true,
    }),
  );
}

async function createAlertIfNew(
  ctx: Context,
  nodeId: string,
  type: string,
  severity: string,
  details: Record<string, Plain>,
  knownOpen?: Doc[],
  /**
   * For detections (fire, smoke, anomaly): only a recent open alert counts
   * as a duplicate, so an old unresolved alert can't silence a new fire.
   * Conditions (offline, satellite) keep "any open alert" to avoid repeats.
   */
  recentOnly = false,
): Promise<string | null> {
  const open = knownOpen
    ? knownOpen.filter((doc) => doc.data.deviceId === nodeId && doc.data.type === type)
    : await openAlertsFor(ctx, nodeId, type);

  const blocking = recentOnly ? open.filter((doc) => blocksNewDetection(doc.data, ctx.now)) : open;
  if (blocking.length > 0) {
    if (recentOnly) await recordRepeatDetection(ctx, blocking[0]);
    return null;
  }

  const alertId = `${nodeId}_${type}_${Math.floor(ctx.now.getTime() / 1000)}`;
  await ctx.fs.set(`alerts/${alertId}`, {
    alertId,
    deviceId: nodeId,
    type,
    severity,
    status: "ACTIVE",
    detectedAt: ctx.now,
    escalationLevel: 0,
    lastDetectedAt: ctx.now,
    streakStartedAt: ctx.now,
    detections: 1,
    ...details,
  });
  console.log(`Alert created: ${alertId} (${severity})`);
  return alertId;
}

async function ingest(ctx: Context, channel: Channel): Promise<void> {
  const devicePath = `devices/${channel.nodeId}`;
  const [device, feed] = await Promise.all([
    ctx.fs.get(devicePath),
    fetchLastFeed(channel.channelId, channel.readApiKey),
  ]);
  const reading = parseFeed(feed, ctx.now, MAX_FEED_AGE_SECONDS);

  if (reading.isStale || (reading.entryId != null && reading.entryId === device?.data.thingspeakEntryId)) {
    return; // nothing new; the 5-minute job turns lastSeen age into STALE/OFFLINE
  }

  await processReading(ctx, channel.nodeId, channel.name ?? channel.nodeId, device, reading, "thingspeak");
}

/**
 * One reading from a node, from ThingSpeak or from the LoRa gateway: score it
 * against the node's baseline, combine with fire danger and terrain, work out
 * the air at the sensor, save device + history, and apply the alert rules.
 */
async function processReading(
  ctx: Context,
  nodeId: string,
  fallbackName: string,
  device: Doc | null,
  reading: SensorReading,
  source: "thingspeak" | "lora",
): Promise<void> {
  const devicePath = `devices/${nodeId}`;
  // Score the six sensors against this node's learned baseline, then combine
  // with today's weather fire danger and the node's terrain.
  const anomaly = scoreReading(toAnomalyReading(reading), parseBaseline(device?.data.baseline));
  const danger = asMap(device?.data.danger);
  const terrain = terrainFor(device?.data.terrain);
  const risk = combineRisk({
    anomalyScore: anomaly.score,
    dangerProbability: dangerFor(danger, terrain),
    terrain,
    cameraFire: reading.fireDetected && reading.aiConfidence >= AI_FIRE_CONFIDENCE_THRESHOLD,
    cameraSmoke: reading.smokeDetected && reading.aiConfidence >= AI_SMOKE_CONFIDENCE_THRESHOLD,
  });
  const fireProbability = reading.fireDetected ? reading.aiConfidence * 100 : 0;
  const smokeProbability = reading.smokeDetected ? reading.aiConfidence * 100 : 0;
  const air = localAir(
    anomaly,
    reading.aiClass,
    reading.aiConfidence,
    reading.mq2_1 > 0 || reading.mq2_2 > 0,
  );

  await ctx.fs.commit([
    {
      set: devicePath,
      merge: true,
      data: {
        deviceId: nodeId,
        ...(device ? {} : { name: fallbackName }),
        status: "ONLINE",
        lastSeen: reading.timestamp,
        temperature: reading.temperature,
        humidity: reading.humidity,
        temperature2: reading.temperature2,
        humidity2: reading.humidity2,
        mq2Sensor1: reading.mq2_1,
        mq2Sensor2: reading.mq2_2,
        aiClass: reading.aiClass,
        fireDetected: reading.fireDetected,
        aiConfidence: reading.aiConfidence,
        fireProbability,
        smokeProbability,
        riskScore: risk.score,
        riskLevel: risk.level,
        riskDriver: risk.driver,
        anomaly: { score: anomaly.score, level: anomaly.level, z: anomaly.z, driver: anomaly.driver },
        localAir: { ...air, at: reading.timestamp },
        thingspeakEntryId: reading.entryId,
        sensorDataAgeSeconds: reading.ageSeconds,
        sensorDataStale: false,
        via: source,
      },
    },
    {
      set: `${devicePath}/readings/${newDocId()}`,
      data: {
        ts: reading.timestamp,
        temperature: reading.temperature,
        humidity: reading.humidity,
        temperature2: reading.temperature2,
        humidity2: reading.humidity2,
        mq2_1: reading.mq2_1,
        mq2_2: reading.mq2_2,
        fireProbability,
        smokeProbability,
        aiClass: reading.aiClass,
        aiConfidence: reading.aiConfidence,
        riskScore: risk.score,
        anomalyScore: anomaly.score,
        anomalyLevel: anomaly.level,
        entryId: reading.entryId,
        via: source,
      },
    },
  ]);

  const dangerLevel = typeof danger?.level === "string" ? danger.level : null;
  const decision = decideAlert(reading, anomaly, dangerLevel);
  if (decision) {
    const nodeName =
      typeof device?.data.name === "string" ? device.data.name : fallbackName;
    const smokeValues = [reading.mq2_1, reading.mq2_2].filter((v): v is number => typeof v === "number");
    await createAlertIfNew(ctx, nodeId, decision.type, decision.severity, {
      message: alertMessageFor(decision.type, {
        nodeName,
        severity: decision.severity,
        aiConfidence: decision.type === "FIRE" || decision.type === "SMOKE" ? reading.aiConfidence : null,
        temperature: reading.temperature,
        humidity: reading.humidity,
        smoke: smokeValues.length > 0 ? Math.max(...smokeValues) : null,
        anomalyDriver: anomaly.driver,
        anomalyZ: anomaly.driver ? anomaly.z[anomaly.driver] ?? null : null,
        dangerLevel,
      }),
      fireProbability,
      smokeProbability,
      temperature: reading.temperature ?? 0,
      humidity: reading.humidity ?? 0,
      latitude: asNumber(device?.data.latitude),
      longitude: asNumber(device?.data.longitude),
      sensorReadings: {
        temperature2: reading.temperature2,
        humidity2: reading.humidity2,
        mq2_1: reading.mq2_1,
        mq2_2: reading.mq2_2,
        aiClass: reading.aiClass,
        aiConfidence: reading.aiConfidence,
        entryId: reading.entryId,
        anomalyScore: anomaly.score,
        anomalyDriver: anomaly.driver,
        anomalyZ: anomaly.z,
      },
    }, undefined, true);
  }
}

function asMap(value: Plain | undefined): Record<string, Plain> | null {
  return value && typeof value === "object" && !Array.isArray(value) && !(value instanceof Date)
    ? (value as Record<string, Plain>)
    : null;
}

/** The six sensor values (worst of the minute) as anomaly inputs. */
function toAnomalyReading(reading: {
  mq2_1: number;
  mq2_2: number;
  temperature: number | null;
  humidity: number | null;
  temperature2: number | null;
  humidity2: number | null;
}): Reading {
  return {
    mq1: reading.mq2_1,
    mq2: reading.mq2_2,
    temp1: reading.temperature,
    temp2: reading.temperature2,
    hum1: reading.humidity,
    hum2: reading.humidity2,
  };
}

function parseBaseline(value: Plain | undefined): Baseline | null {
  if (!value || typeof value !== "object" || Array.isArray(value) || value instanceof Date) return null;
  const b = value as Record<string, Plain>;
  const raw = b.sensors;
  if (!raw || typeof raw !== "object" || Array.isArray(raw) || raw instanceof Date) return null;
  const sensors = { ...(raw as Record<string, unknown>) };
  // Baselines from the four-sensor version stored the first DHT22 as temp/hum.
  if (sensors.temp && !sensors.temp1) sensors.temp1 = sensors.temp;
  if (sensors.hum && !sensors.hum1) sensors.hum1 = sensors.hum;
  delete sensors.temp;
  delete sensors.hum;
  return { sensors: sensors as Baseline["sensors"], samples: asNumber(b.samples) };
}

async function ingestAll(ctx: Context): Promise<void> {
  const channels = await loadChannels(ctx);
  await Promise.all(channels.map((channel) => run(`ingest ${channel.nodeId}`, () => ingest(ctx, channel))));
}

// ---------------------------------------------------------------------------
// Push for new alerts (created here, by the Python service or by anything else)
// ---------------------------------------------------------------------------

async function pushNewAlerts(ctx: Context): Promise<void> {
  const recent = await ctx.fs.query("alerts", {
    where: [
      {
        field: "detectedAt",
        op: "GREATER_THAN_OR_EQUAL",
        value: new Date(ctx.now.getTime() - PUSH_WINDOW_MS),
      },
    ],
  });

  for (const alert of recent) {
    if (alert.data.status !== "ACTIVE" || alert.data.pushedAt != null) continue;
    await run(`push ${alert.id}`, () => sendNewAlert(ctx, alert.id, alert.path, alert.data));
  }
}

/** Every minute: admin requests from the app, and the Telegram inbox. */
async function minuteJobs(ctx: Context): Promise<void> {
  await run("push", () => pushNewAlerts(ctx));
  await run("admin requests", () => adminRequests(ctx));
  await run("telegram inbox", () => telegramInbox(ctx));
}

const SERIOUS = new Set(["HIGH", "CRITICAL"]);

/**
 * Everything that happens once for a new alert: push to subscribed officers
 * (plus opted-in phones near the node for serious alerts), then tell fire
 * services by Telegram for serious alerts.
 */
async function sendNewAlert(
  ctx: Context,
  alertId: string,
  path: string,
  alert: Record<string, Plain>,
): Promise<void> {
  // Sensor problems go to the team only, never to fire services or the public.
  const serious = SERIOUS.has(String(alert.severity)) && !isHealthAlert(alert.type);
  const lat = typeof alert.latitude === "number" ? alert.latitude : null;
  const lng = typeof alert.longitude === "number" ? alert.longitude : null;
  const located = lat != null && lng != null && (lat !== 0 || lng !== 0);
  const radiusKm = Number(ctx.env.NEARBY_RADIUS_KM ?? "10");

  await pushAlert(ctx.fs, ctx.projectId, ctx.token, alertId, alert, {
    maxSends: budget(ctx, 6),
    nearby: serious && located ? { latitude: lat, longitude: lng, radiusKm } : undefined,
  });
  await ctx.fs.set(path, { pushedAt: new Date() }, true);
  await run(`telegram users ${alertId}`, () => telegramUsers(ctx, path, alert));

  const botToken = ctx.env.TELEGRAM_BOT_TOKEN;
  if (!serious || !botToken || alert.fireServicesNotifiedAt != null) return;

  const config = await loadFireServices(ctx);
  if (config.stations.length === 0) return;

  const device = await ctx.fs.get(`devices/${String(alert.deviceId ?? "")}`);
  const nodeName = typeof device?.data.name === "string" ? device.data.name : String(alert.deviceId ?? "?");
  const stations = stationsFor(config, lat, lng);
  const delivered = await notifyStations(
    botToken,
    stations,
    alertMessage(alert, nodeName),
    located ? { latitude: lat, longitude: lng } : null,
  );

  await ctx.fs.set(
    path,
    {
      fireServicesNotifiedAt: new Date(),
      fireServicesNotified: stations.map((s) => s.name),
      fireServicesDelivered: delivered,
    },
    true,
  );
  console.log(`Alert ${alertId}: fire services told ${delivered}/${stations.length}`);
}

// ---------------------------------------------------------------------------
// Every 5 minutes: node health, alertActive, escalation, roles, heartbeat
// ---------------------------------------------------------------------------

async function maintenance(ctx: Context): Promise<void> {
  const [devices, open] = await Promise.all([
    ctx.fs.query("devices"),
    ctx.fs.query("alerts", { where: [{ field: "status", op: "IN", value: [...OPEN_STATUSES] }] }),
  ]);

  await run("node health", () => nodeHealth(ctx, devices, open));
  await run("board health", () => boardHealth(ctx, devices, open));
  await run("role requests", () => roleRequests(ctx));
  let telegramBot: string | null = null;
  if (ctx.env.TELEGRAM_BOT_TOKEN) {
    await run("telegram bot", async () => {
      telegramBot = await botUsername(ctx.env.TELEGRAM_BOT_TOKEN!);
    });
  }
  await run("heartbeat", () =>
    ctx.fs.set("status/backend", {
      lastHeartbeat: new Date(),
      version: VERSION,
      openAlerts: open.length,
      host: "cloudflare-workers",
      telegramConfigured: Boolean(ctx.env.TELEGRAM_BOT_TOKEN),
      telegramBot,
    }),
  );
  await run("escalation", () => escalate(ctx, open));
}

async function nodeHealth(ctx: Context, devices: Doc[], open: Doc[]): Promise<void> {
  const writes: Write[] = [];
  const now = ctx.now.getTime();

  for (const device of devices) {
    const data = device.data;
    const alertActive = open.some((alert) => alert.data.deviceId === device.id);
    const update: Record<string, Plain> = {};

    if (data.alertActive !== alertActive) update.alertActive = alertActive;

    const lastSeen = asDate(data.lastSeen);
    if (lastSeen) {
      const age = now - lastSeen.getTime();
      const status = age > OFFLINE_AFTER_MS ? "OFFLINE" : age > STALE_AFTER_MS ? "STALE" : "ONLINE";

      if (status !== data.status) update.status = status;

      // Offline alerts by facts, not status flips: one the node has reported
      // after is over (resolve it); an offline node with no alert covering
      // the current outage gets a new one (and a push).
      const outages = open.filter(
        (alert) => alert.data.deviceId === device.id && alert.data.type === "NODE_OFFLINE",
      );
      const ended = outages.filter((alert) => outageEnded(alert.data, lastSeen));
      for (const outage of ended) {
        writes.push({
          set: outage.path,
          merge: true,
          data: {
            status: "RESOLVED",
            resolvedBy: "system",
            resolvedByName: "System",
            resolvedAt: new Date(),
            notes: "Resolved automatically: the sensor reported again.",
          },
        });
      }
      const current = outages.filter((alert) => !ended.includes(alert));

      if (status === "OFFLINE" && current.length === 0) {
        await createAlertIfNew(
          ctx,
          device.id,
          "NODE_OFFLINE",
          "HIGH",
          {
            message: alertMessageFor("NODE_OFFLINE", {
              nodeName: typeof data.name === "string" ? data.name : device.id,
              severity: "HIGH",
              lastSeen,
            }),
            fireProbability: 0,
            smokeProbability: 0,
            temperature: asNumber(data.temperature),
            humidity: asNumber(data.humidity),
            latitude: asNumber(data.latitude),
            longitude: asNumber(data.longitude),
            lastSeen,
          },
          open.filter((alert) => !ended.includes(alert)),
        );
        update.alertActive = true;
      }
    }

    if (Object.keys(update).length > 0) writes.push({ set: device.path, merge: true, data: update });
  }

  await ctx.fs.commit(writes);
}

async function escalate(ctx: Context, open: Doc[]): Promise<void> {
  const now = ctx.now.getTime();

  for (const alert of open) {
    const data = alert.data;
    const detected = asDate(data.detectedAt);
    if (data.status !== "ACTIVE" || !detected || isHealthAlert(data.type)) continue;

    const age = now - detected.getTime();
    if (age < ESCALATE_AFTER_MS || age > ESCALATION_MAX_AGE_MS) continue;

    const level = asNumber(data.escalationLevel);
    if (level >= 2) continue;

    const escalatedAt = asDate(data.escalatedAt);
    if (escalatedAt && now - escalatedAt.getTime() < ESCALATE_AFTER_MS) continue;

    const next = level + 1;
    await run(`escalate ${alert.id}`, async () => {
      await pushAlert(ctx.fs, ctx.projectId, ctx.token, alert.id, data, {
        adminsOnly: next === 2,
        escalation: next,
        maxSends: budget(ctx, 3),
      });
      await ctx.fs.set(alert.path, { escalationLevel: next, escalatedAt: new Date() }, true);
    });
  }
}

/**
 * Sensor problems from each online board's health report: raise an alert
 * once a problem has lasted long enough, resolve it when it clears.
 */
async function boardHealth(ctx: Context, devices: Doc[], open: Doc[]): Promise<void> {
  const writes: Write[] = [];

  for (const device of devices) {
    const lastSeen = asDate(device.data.lastSeen);
    if (!lastSeen || ctx.now.getTime() - lastSeen.getTime() > OFFLINE_AFTER_MS) continue;

    const health = parseHealth(await ctx.rtdb.get(`health/${encodeURIComponent(device.id)}/info`));
    if (!health) continue;
    const previous = device.data.healthIssues;
    const plan = planHealth(
      health,
      ctx.now,
      previous && typeof previous === "object" && !Array.isArray(previous) && !(previous instanceof Date)
        ? (previous as Record<string, Plain>)
        : null,
      typeof device.data.brownoutStart === "number" ? device.data.brownoutStart : null,
    );
    if (!plan) continue;

    for (const issue of plan.raise) {
      await createAlertIfNew(
        ctx,
        device.id,
        issue.type,
        issue.severity,
        {
          message: issue.message,
          fireProbability: 0,
          smokeProbability: 0,
          temperature: asNumber(device.data.temperature),
          humidity: asNumber(device.data.humidity),
          latitude: asNumber(device.data.latitude),
          longitude: asNumber(device.data.longitude),
        },
        open,
      );
    }

    for (const alert of open) {
      if (alert.data.deviceId !== device.id || !plan.clear.includes(alert.data.type as never)) continue;
      writes.push({
        set: alert.path,
        merge: true,
        data: {
          status: "RESOLVED",
          resolvedBy: "system",
          resolvedByName: "System",
          resolvedAt: new Date(),
          notes: "Resolved automatically: the problem cleared.",
        },
      });
    }

    const update: Record<string, Plain> = { healthIssues: plan.since, healthCheckedAt: ctx.now };
    if (plan.brownoutStart != null) update.brownoutStart = plan.brownoutStart;
    writes.push({ set: device.path, merge: true, data: update });
  }

  await ctx.fs.commit(writes);
}

/**
 * Sends an alert by Telegram to app users who linked their Telegram, with
 * the same audience as push (all sensors, or the ones they follow).
 */
async function telegramUsers(
  ctx: Context,
  path: string,
  alert: Record<string, Plain>,
  heading?: string,
): Promise<void> {
  const botToken = ctx.env.TELEGRAM_BOT_TOKEN;
  if (!botToken) return;
  const users = await ctx.fs.query("users");
  const linked = users.filter((user) => {
    const chat = user.data.telegramChatId;
    if (typeof chat !== "string" && typeof chat !== "number") return false;
    const nodes = user.data.subscribedNodes;
    return !Array.isArray(nodes) || nodes.length === 0 || nodes.includes(alert.deviceId as Plain);
  });
  if (linked.length === 0) return;

  const device = await ctx.fs.get(`devices/${String(alert.deviceId ?? "")}`);
  const nodeName = typeof device?.data.name === "string" ? device.data.name : String(alert.deviceId ?? "?");
  const text = `${heading ? `${heading}\n` : ""}${alertMessage(alert, nodeName)}`;
  let sent = 0;
  for (const user of linked.slice(0, budget(ctx, 2))) {
    await run(`telegram user ${user.id}`, async () => {
      await sendText(botToken, String(user.data.telegramChatId), text);
      sent++;
    });
  }
  await ctx.fs.set(path, { telegramUsersNotified: sent }, true);
}

/** Fire stations from the app (fireStations) plus any in config/fireServices. */
async function loadFireServices(ctx: Context) {
  const [config, docs] = await Promise.all([
    ctx.fs.get("config/fireServices"),
    ctx.fs.query("fireStations"),
  ]);
  const base = parseFireServices(config?.data);
  const extra = parseFireServices({ stations: docs.map((doc) => doc.data) });
  return { radiusKm: base.radiusKm, stations: [...base.stations, ...extra.stations] };
}

/**
 * Admin requests filed from the app (Spark has no callable functions):
 * add a sensor, or send a test message to a fire station.
 */
async function adminRequests(ctx: Context): Promise<void> {
  const pending = await ctx.fs.query("adminRequests", {
    where: [{ field: "status", op: "EQUAL", value: "pending" }],
  });
  if (pending.length === 0) return;
  const token = await ctx.token();

  for (const request of pending) {
    const finish = (status: string, message: string, extra: Record<string, Plain> = {}) =>
      ctx.fs.set(request.path, { status, message, processedAt: new Date(), ...extra }, true);

    await run(`admin request ${request.id}`, async () => {
      const requester = await lookupUser(ctx.projectId, token, { uid: String(request.data.requestedBy ?? "") });
      if (requester?.claims.role !== "admin") return finish("error", "Only administrators can do this.");

      if (request.data.kind === "addNode") {
        const add = parseAddNode(request.data);
        if (typeof add === "string") return finish("error", add);
        const [existing, keys] = await Promise.all([
          ctx.fs.get(`devices/${add.nodeId}`),
          ctx.fs.get("config/deviceKeys"),
        ]);
        if (existing || keys?.data[add.nodeId] != null) {
          return finish("error", `${add.nodeId} already exists. Choose another ID.`);
        }

        const key = newNodeKey();
        await ctx.rtdb.put(`deviceKeys/${add.nodeId}`, key);
        const writes: Write[] = [
          { set: "config/deviceKeys", merge: true, data: { [add.nodeId]: key } },
          {
            set: `devices/${add.nodeId}`,
            data: {
              deviceId: add.nodeId,
              name: add.name,
              ...(add.zone ? { zone: add.zone } : {}),
              ...(add.terrain ? { terrain: add.terrain } : {}),
              status: "NEW",
              createdAt: new Date(),
              createdBy: requester.uid,
            },
          },
        ];
        if (add.channelId) {
          const channels = (await ctx.fs.get("config/channels"))?.data.channels;
          const list = Array.isArray(channels) ? [...channels] : [];
          list.push({
            nodeId: add.nodeId,
            channelId: add.channelId,
            name: add.name,
            ...(add.readApiKey ? { readApiKey: add.readApiKey } : {}),
          });
          writes.push({ set: "config/channels", merge: true, data: { channels: list } });
        }
        await ctx.fs.commit(writes);
        deviceKeys = null; // pick up the new key at once
        console.log(`Node added: ${add.nodeId} by ${requester.uid}`);
        return finish("done", `${add.name} (${add.nodeId}) was added.`, { nodeId: add.nodeId, nodeKey: key });
      }

      if (request.data.kind === "testStation") {
        const botToken = ctx.env.TELEGRAM_BOT_TOKEN;
        if (!botToken) return finish("error", "The Telegram bot isn't set up on the backend yet.");
        const station = await ctx.fs.get(`fireStations/${String(request.data.stationId ?? "")}`);
        const chatId = station?.data.telegramChatId;
        if (!station || (typeof chatId !== "string" && typeof chatId !== "number")) {
          return finish("error", "That station has no Telegram chat.");
        }
        try {
          await sendText(
            botToken,
            String(chatId),
            `✅ Test from Forest Fire Monitor: ${String(station.data.name ?? "this station")} will get fire alerts here.`,
          );
        } catch (error) {
          return finish("error", `Telegram refused it: ${error instanceof Error ? error.message : error}`);
        }
        return finish("done", "Test message sent.");
      }

      return finish("error", "Unknown request.");
    });
  }
}

/**
 * Records who has messaged the bot (telegramChats) so an admin can pick a
 * fire station's chat in the app, and greets chats that send /start.
 */
async function telegramInbox(ctx: Context): Promise<void> {
  const botToken = ctx.env.TELEGRAM_BOT_TOKEN;
  if (!botToken) return;

  const state = await ctx.fs.get("status/telegram");
  const offset = typeof state?.data.offset === "number" ? state.data.offset : null;
  const { chats, commands, nextOffset } = chatsFromUpdates(await getUpdates(botToken, offset));
  if (nextOffset == null) return;

  const writes: Write[] = chats.map((chat) => ({
    set: `telegramChats/${chat.chatId}`,
    merge: true,
    data: { ...chat },
  }));
  writes.push({ set: "status/telegram", merge: true, data: { offset: nextOffset, checkedAt: ctx.now } });
  await ctx.fs.commit(writes);

  for (const command of commands) {
    await run(`telegram ${command.command} ${command.chatId}`, () => telegramCommand(ctx, botToken, command));
  }
}

/** Link codes older than this no longer work. */
const TELEGRAM_LINK_MAX_AGE_MS = 60 * 60_000;

/**
 * /start CODE links the chat to the app user who made the code (Settings ->
 * Connect Telegram); /start alone greets; /stop unlinks.
 */
async function telegramCommand(ctx: Context, botToken: string, command: BotCommand): Promise<void> {
  if (command.command === "stop") {
    const linked = await ctx.fs.query("users", {
      where: [{ field: "telegramChatId", op: "EQUAL", value: command.chatId }],
    });
    await ctx.fs.commit(
      linked.map((user) => ({
        set: user.path,
        merge: true,
        data: { telegramChatId: null, telegramName: null, telegramLinkedAt: null },
      })),
    );
    await sendText(
      botToken,
      command.chatId,
      linked.length > 0
        ? "Alerts turned off for this chat. Connect again from the app any time."
        : "This chat wasn't getting alerts.",
    );
    return;
  }

  const code = command.argument;
  if (!/^[A-Za-z0-9_-]{16,64}$/.test(code)) {
    await sendText(
      botToken,
      command.chatId,
      "Hello from Forest Fire Monitor. To get alerts here, open the app: Settings -> Connect Telegram. " +
        "An administrator can also add this chat as a fire station.",
    );
    return;
  }

  const link = await ctx.fs.get(`telegramLinks/${code}`);
  const created = asDate(link?.data.createdAt);
  const uid = typeof link?.data.uid === "string" ? link.data.uid : null;
  if (!link || !uid || !created || ctx.now.getTime() - created.getTime() > TELEGRAM_LINK_MAX_AGE_MS) {
    await sendText(
      botToken,
      command.chatId,
      "This link has expired. In the app, tap Connect Telegram again.",
    );
    return;
  }

  const chat = await ctx.fs.get(`telegramChats/${command.chatId}`);
  await ctx.fs.commit([
    {
      set: `users/${uid}`,
      merge: true,
      data: {
        telegramChatId: command.chatId,
        telegramName: typeof chat?.data.name === "string" ? chat.data.name : null,
        telegramLinkedAt: ctx.now,
      },
    },
    { delete: link.path },
  ]);
  await sendText(
    botToken,
    command.chatId,
    "✅ Connected. Forest Fire Monitor alerts for your sensors will arrive here too. Send /stop to turn them off.",
  );
}

async function roleRequests(ctx: Context): Promise<void> {
  const pending = await ctx.fs.query("roleRequests", {
    where: [{ field: "status", op: "EQUAL", value: "pending" }],
  });
  if (pending.length === 0) return;

  const token = await ctx.token();

  for (const request of pending) {
    const finish = (status: string, message: string) =>
      ctx.fs.set(request.path, { status, message, processedAt: new Date() }, true);

    await run(`role request ${request.id}`, async () => {
      const requesterUid = String(request.data.requestedBy ?? "");
      const email = String(request.data.email ?? "").trim().toLowerCase();
      const role = String(request.data.role ?? "");

      const requester = await lookupUser(ctx.projectId, token, { uid: requesterUid });
      if (requester?.claims.role !== "admin") {
        return finish("error", "Only administrators can change roles.");
      }
      if (!ROLES.includes(role)) {
        return finish("error", `Role must be one of ${ROLES.join(", ")}.`);
      }

      const user = await lookupUser(ctx.projectId, token, { email });
      if (!user) {
        return finish("error", `No account for ${email}. Create it in Firebase Authentication first.`);
      }
      if (user.uid === requesterUid && role !== "admin") {
        return finish("error", "You can't remove your own admin role.");
      }

      await setClaims(ctx.projectId, token, user.uid, { ...user.claims, role });
      await ctx.fs.set(
        `users/${user.uid}`,
        { email, role, roleUpdatedAt: new Date(), roleUpdatedBy: requesterUid },
        true,
      );
      await finish("done", `${email} is now ${role}.`);
    });
  }
}

// ---------------------------------------------------------------------------
// Hourly rollups and retention
// ---------------------------------------------------------------------------

function hourKey(date: Date): string {
  return date.toISOString().slice(0, 13).replace(/[-T]/g, "");
}

async function hourlyRollup(ctx: Context): Promise<void> {
  const end = new Date(ctx.now);
  end.setUTCMinutes(0, 0, 0);
  const start = new Date(end.getTime() - 3_600_000);

  const devices = await ctx.fs.query("devices");
  await run("fire danger", () => fireDangerJob(ctx, devices));

  const writes: Write[] = [];

  for (const device of devices) {
    const readings = await ctx.fs.query("readings", {
      parent: device.path,
      where: [
        { field: "ts", op: "GREATER_THAN_OR_EQUAL", value: start },
        { field: "ts", op: "LESS_THAN", value: end },
      ],
    });
    if (readings.length === 0) continue;

    // Averages skip readings where the DHT22 gave nothing.
    let temperatureSum = 0;
    let temperatureCount = 0;
    let humiditySum = 0;
    let humidityCount = 0;
    let temperature2Sum = 0;
    let temperature2Count = 0;
    let humidity2Sum = 0;
    let humidity2Count = 0;
    let smoke1Max = 0;
    let smoke2Max = 0;
    let smokeProbabilityMax = 0;
    let smokeMax = 0;
    let fireMax = 0;
    let riskMax = 0;

    for (const { data } of readings) {
      if (typeof data.temperature === "number") {
        temperatureSum += data.temperature;
        temperatureCount++;
      }
      if (typeof data.humidity === "number") {
        humiditySum += data.humidity;
        humidityCount++;
      }
      if (typeof data.temperature2 === "number") {
        temperature2Sum += data.temperature2;
        temperature2Count++;
      }
      if (typeof data.humidity2 === "number") {
        humidity2Sum += data.humidity2;
        humidity2Count++;
      }
      smoke1Max = Math.max(smoke1Max, asNumber(data.mq2_1));
      smoke2Max = Math.max(smoke2Max, asNumber(data.mq2_2));
      smokeProbabilityMax = Math.max(smokeProbabilityMax, asNumber(data.smokeProbability));
      smokeMax = Math.max(smokeMax, asNumber(data.mq2_1), asNumber(data.mq2_2));
      fireMax = Math.max(fireMax, asNumber(data.fireProbability));
      riskMax = Math.max(riskMax, asNumber(data.riskScore));
    }

    // Learn this hour into the node's baseline unless it looked anomalous
    // (so a smouldering fire isn't learned as "normal").
    const scores = readings.map(({ data }) => asNumber(data.anomalyScore ?? data.riskScore));
    if (isLearnableHour(scores)) {
      const num = (v: Plain | undefined) => (typeof v === "number" ? v : null);
      const hourReadings: Reading[] = readings.map(({ data }) => ({
        mq1: num(data.mq2_1),
        mq2: num(data.mq2_2),
        temp1: num(data.temperature),
        temp2: num(data.temperature2),
        hum1: num(data.humidity),
        hum2: num(data.humidity2),
      }));
      const baseline = updateBaseline(
        parseBaseline(device.data.baseline),
        hourStats(hourReadings),
        readings.length,
      );
      writes.push({
        set: device.path,
        merge: true,
        data: {
          baseline: {
            sensors: baseline.sensors as unknown as Record<string, Plain>,
            samples: baseline.samples,
            updatedAt: new Date(),
          },
        },
      });
    }

    writes.push({
      set: `${device.path}/hourly/${hourKey(start)}`,
      data: {
        hour: start,
        count: readings.length,
        temperatureSum,
        temperatureCount,
        humiditySum,
        humidityCount,
        temperature2Sum,
        temperature2Count,
        humidity2Sum,
        humidity2Count,
        smoke1Max,
        smoke2Max,
        smokeProbabilityMax,
        smokeMax,
        fireProbabilityMax: fireMax,
        riskScoreMax: riskMax,
      },
    });
  }

  await ctx.fs.commit(writes);
}

// ---------------------------------------------------------------------------
// Fire danger (ML): hourly, per node with saved coordinates
// ---------------------------------------------------------------------------

/**
 * Terrain-adjusted danger index for combining with sensor risk, from the
 * node's last hourly rating. Re-applies the current terrain, so a terrain
 * change takes effect on the next reading rather than the next hour.
 */
function dangerFor(danger: Record<string, Plain> | null | undefined, terrain: Terrain): number | null {
  if (typeof danger?.baseChance === "number") return terrainDanger(danger.baseChance, terrain.factor);
  return typeof danger?.probability === "number" ? danger.probability : null;
}

/**
 * Today's fire-danger rating from today's noon weather (forecast before
 * noon), matching the daily noon features the model was trained on. FFMC is
 * rebuilt each run from 14 days of noon weather (it forgets older weather
 * within days), so no state needs storing.
 */
async function nodeFireDanger(
  latitude: number,
  longitude: number,
  terrain: Terrain,
): Promise<Record<string, Plain>> {
  const weather = await fetchHourlyWeather(latitude, longitude);
  const inputs = dangerInputs(weather.hourly, weather.nowLocal);
  if (!inputs) throw new Error("No usable weather for this location");

  const ffmcYesterday = ffmcAfter(inputs.pastNoons);
  const { temp, rh, wind, rain24h } = inputs.today;
  const ffmcToday = ffmc(temp, rh, wind, rain24h, ffmcYesterday);
  const isiToday = isi(ffmcToday, wind);
  const month = Number(inputs.todayNoon.slice(5, 7));
  const baseChance = fireChance({ temp, rh, wind, rain24h, ffmc: ffmcToday, isi: isiToday, month });
  const chance = adjustProbability(baseChance, terrain.factor);
  const baseProbability = dangerIndex(baseChance);
  const probability = dangerIndex(chance);

  const round = (v: number, d: number) => Math.round(v * 10 ** d) / 10 ** d;

  // When: the same model on each forecast hour of the next day, from
  // yesterday's fuel moisture. An approximation (trained on noon weather),
  // but it places the afternoon peak and overnight lull correctly.
  const timeline = upcomingHours(weather.hourly, weather.nowLocal, 24).map(({ time, weather: h }) => {
    const f = ffmc(h.temp, h.rh, h.wind, h.rain24h, ffmcYesterday);
    const hourChance = fireChance({ ...h, ffmc: f, isi: isi(f, h.wind), month: Number(time.slice(5, 7)) });
    const p = terrainDanger(hourChance, terrain.factor);
    return { time, probability: round(p, 3), level: riskLevel3(p) };
  });
  const peak = timeline.reduce<(typeof timeline)[number] | null>(
    (best, hour) => (!best || hour.probability > best.probability ? hour : best),
    null,
  );

  // If a fire started now: rate and direction of spread for this terrain.
  const current = currentConditions(weather.hourly, weather.nowLocal);
  const spread = current
    ? estimateSpread(
        terrain.id,
        ffmc(current.temp, current.rh, current.wind, current.rain24h, ffmcYesterday),
        current.wind,
        current.windFromDeg,
      )
    : null;

  return {
    probability: round(probability, 3),
    baseProbability: round(baseProbability, 3),
    chance: round(chance, 4),
    baseChance: round(baseChance, 4),
    averageChance: fireDangerModel.baseRate ?? null,
    level: riskLevel3(probability),
    modelLevel: dangerLevel(baseProbability),
    terrain: terrain.id,
    terrainFactor: terrain.factor,
    timeline: timeline as unknown as Plain[],
    peak: peak as unknown as Plain,
    spread: spread ? ({ ...spread, towardCompass: compass(spread.towardDeg) } as unknown as Plain) : null,
    ffmc: round(ffmcToday, 1),
    isi: round(isiToday, 2),
    temperature: round(temp, 1),
    humidity: round(rh, 0),
    wind: round(wind, 1),
    rain24h: round(rain24h, 1),
    forDate: inputs.todayNoon.slice(0, 10),
    forecast: inputs.forecast,
    model: fireDangerModel.id,
    updatedAt: new Date(),
  };
}

/** Satellite detections this close to a node raise an alert. */
const SATELLITE_ALERT_KM = 5;

async function fireDangerJob(ctx: Context, devices: Doc[]): Promise<void> {
  const writes: Write[] = [];
  const mapKey = ctx.env.FIRMS_MAP_KEY;
  const satelliteRadius = Number(ctx.env.SATELLITE_RADIUS_KM ?? "25");

  await Promise.all(
    devices.map(async (device) => {
      const lat = device.data.latitude;
      const lng = device.data.longitude;
      if (typeof lat !== "number" || typeof lng !== "number" || (lat === 0 && lng === 0)) return;
      const update: Record<string, Plain> = {};

      const [danger, air, hotspots] = await Promise.allSettled([
        nodeFireDanger(lat, lng, terrainFor(device.data.terrain)),
        fetchAirQuality(lat, lng),
        mapKey ? fetchHotspots(mapKey, lat, lng, satelliteRadius) : Promise.resolve(null),
      ]);

      if (danger.status === "fulfilled") update.danger = danger.value;
      else console.error(`fire danger ${device.id}:`, String(danger.reason));

      if (air.status === "fulfilled") {
        update.airQuality = { ...air.value, updatedAt: new Date() } as unknown as Plain;
      } else {
        console.warn(`air quality ${device.id}:`, String(air.reason));
      }

      if (hotspots.status === "fulfilled" && hotspots.value) {
        const list = hotspots.value;
        update.satellite = {
          count: list.length,
          nearestKm: list[0]?.distanceKm ?? null,
          radiusKm: satelliteRadius,
          hotspots: list.slice(0, 20) as unknown as Plain[],
          checkedAt: new Date(),
        };

        const close = list.find((h) => h.distanceKm <= SATELLITE_ALERT_KM && h.confidence !== "low");
        if (close) {
          const dangerLevel = danger.status === "fulfilled" ? danger.value.level : null;
          await run(`satellite alert ${device.id}`, () =>
            createAlertIfNew(ctx, device.id, "SATELLITE_HOTSPOT", dangerLevel === "HIGH" ? "CRITICAL" : "HIGH", {
              message: alertMessageFor("SATELLITE_HOTSPOT", {
                nodeName: typeof device.data.name === "string" ? device.data.name : device.id,
                severity: dangerLevel === "HIGH" ? "CRITICAL" : "HIGH",
                distanceKm: typeof close.distanceKm === "number" ? close.distanceKm : null,
                satellite: typeof close.satellite === "string" ? close.satellite : null,
                satelliteConfidence: typeof close.confidence === "string" ? close.confidence : null,
                dangerLevel: typeof dangerLevel === "string" ? dangerLevel : null,
              }),
              fireProbability: 0,
              smokeProbability: 0,
              temperature: asNumber(device.data.temperature),
              humidity: asNumber(device.data.humidity),
              latitude: close.latitude,
              longitude: close.longitude,
              sensorReadings: {
                satellite: close.satellite,
                acquired: close.acquired,
                confidence: close.confidence,
                frp: close.frp,
                distanceKm: close.distanceKm,
              },
            }),
          );
        }
      } else if (hotspots.status === "rejected") {
        console.warn(`satellite ${device.id}:`, String(hotspots.reason));
      }

      if (Object.keys(update).length > 0) writes.push({ set: device.path, merge: true, data: update });
    }),
  );

  await ctx.fs.commit(writes);
}

async function deleteOldReadings(ctx: Context): Promise<void> {
  const days = Number(ctx.env.READING_RETENTION_DAYS ?? "30");
  const cutoff = new Date(ctx.now.getTime() - days * 86_400_000);
  const devices = await ctx.fs.query("devices");

  for (const device of devices) {
    while (budget(ctx) > 2) {
      const old = await ctx.fs.query("readings", {
        parent: device.path,
        where: [{ field: "ts", op: "LESS_THAN", value: cutoff }],
        limit: 400,
      });
      if (old.length === 0) break;
      await ctx.fs.commit(old.map((doc) => ({ delete: doc.path })));
      console.log(`Deleted ${old.length} old readings for ${device.id}`);
    }
  }
}

// ---------------------------------------------------------------------------
// Instant alerts from nodes: POST /alert
// ---------------------------------------------------------------------------

/** Per-node secrets from config/deviceKeys, cached per isolate for 5 minutes. */
let deviceKeys: { keys: Record<string, Plain>; loaded: number } | null = null;

async function deviceKeyFor(ctx: Context, node: string): Promise<string | null> {
  if (!deviceKeys || Date.now() - deviceKeys.loaded > 300_000) {
    const doc = await ctx.fs.get("config/deviceKeys");
    deviceKeys = { keys: doc?.data ?? {}, loaded: Date.now() };
  }
  const key = deviceKeys.keys[node];
  return typeof key === "string" ? key : null;
}

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function handleDeviceAlert(request: Request, env: Env): Promise<Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "Body must be JSON." });
  }

  const alert = parseDeviceAlert(body);
  if (typeof alert === "string") return json(400, { error: alert });

  const ctx = context(env);
  const expected = await deviceKeyFor(ctx, alert.node);
  if (!expected || !safeEqual(expected, alert.key)) {
    return json(403, { error: "Unknown node or wrong key." });
  }

  const confidence = alert.aiConfidence ?? 0;
  // Older firmware alerts on fire from 50%; only confident fires count.
  if (alert.type === "FIRE" && confidence < AI_FIRE_CONFIDENCE_THRESHOLD) {
    return json(200, { status: "ignored", reason: "fire confidence below threshold" });
  }

  const device = await ctx.fs.get(`devices/${alert.node}`);
  const smokeValues = [alert.mq2_1, alert.mq2_2].filter((v): v is number => typeof v === "number");
  const alertId = await createAlertIfNew(ctx, alert.node, alert.type, alert.severity, {
    message: alertMessageFor(alert.type, {
      nodeName: typeof device?.data.name === "string" ? device.data.name : alert.node,
      severity: alert.severity,
      aiConfidence: alert.aiConfidence,
      temperature: alert.temperature,
      humidity: alert.humidity,
      smoke: smokeValues.length > 0 ? Math.max(...smokeValues) : null,
      dangerLevel: typeof (device?.data.danger as Record<string, Plain> | undefined)?.level === "string"
        ? String((device!.data.danger as Record<string, Plain>).level)
        : null,
    }),
    source: "device",
    fireProbability: alert.aiClass === "Fire" ? confidence * 100 : 0,
    smokeProbability: alert.aiClass === "Smoke" ? confidence * 100 : 0,
    temperature: alert.temperature ?? 0,
    humidity: alert.humidity ?? 0,
    latitude: asNumber(device?.data.latitude),
    longitude: asNumber(device?.data.longitude),
    sensorReadings: {
      mq2_1: alert.mq2_1,
      mq2_2: alert.mq2_2,
      aiClass: alert.aiClass,
      aiConfidence: alert.aiConfidence,
      riskScore: alert.riskScore,
    },
  }, undefined, true);

  if (!alertId) return json(200, { status: "duplicate" });

  // Push and tell fire services now rather than on the next minute's sweep.
  const created = await ctx.fs.get(`alerts/${alertId}`);
  if (created) {
    await run(`push ${alertId}`, () => sendNewAlert(ctx, alertId, created.path, created.data));
  }

  return json(201, { status: "created", alertId });
}

// ---------------------------------------------------------------------------
// LoRa link reports from a receiver board: POST /lora (once a minute)
// ---------------------------------------------------------------------------

async function handleLoraReport(request: Request, env: Env): Promise<Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "Body must be JSON." });
  }

  const report = parseLoraReport(body);
  if (typeof report === "string") return json(400, { error: report });

  const ctx = context(env);
  const expected = await deviceKeyFor(ctx, report.gateway);
  if (!expected || !safeEqual(expected, report.key)) {
    return json(403, { error: "Unknown gateway or wrong key." });
  }

  const devicePath = `devices/${report.node}`;
  if (!(await ctx.fs.get(devicePath))) return json(404, { error: "Unknown node." });

  await ctx.fs.commit([
    { set: devicePath, merge: true, data: { lora: loraLink(report, new Date()) as unknown as Plain } },
  ]);
  return json(200, { status: "saved" });
}

/**
 * POST /lora/data: one node packet relayed by a receiver. The latest copy is
 * always kept (RTDB lora/{node}); when the node's own Wi-Fi feed has been
 * quiet for 30 s the LoRa data takes over the live panel, the device and
 * history (once a minute) and fire/smoke alerts. While Wi-Fi works this
 * costs no Firestore reads.
 */
async function handleLoraData(request: Request, env: Env): Promise<Response> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "Body must be JSON." });
  }
  const data = parseLoraData(body);
  if (typeof data === "string") return json(400, { error: data });

  const ctx = context(env);
  const expected = await deviceKeyFor(ctx, data.gateway);
  if (!expected || !safeEqual(expected, data.key)) {
    return json(403, { error: "Unknown gateway or wrong key." });
  }

  const node = encodeURIComponent(data.node);
  const p = data.packet;
  await ctx.rtdb.put(`lora/${node}`, {
    ...liveValues(p),
    ...(p.pkt != null ? { pkt: p.pkt } : {}),
    ...(p.wifiUp != null ? { wifiUp: p.wifiUp } : {}),
    ...(p.cameraAgeSec != null ? { camAge: p.cameraAgeSec } : {}),
    ...(p.smokeFault != null ? { smokeFault: p.smokeFault } : {}),
    ...(data.rssi != null ? { rssi: data.rssi } : {}),
    ...(data.snr != null ? { snr: data.snr } : {}),
    gateway: data.gateway,
    ts: { ".sv": "timestamp" },
  });

  const live = await ctx.rtdb.get(`live/${node}/values`);
  const liveTs = live && typeof live === "object" ? (live as Record<string, unknown>).ts : null;
  const liveVia = live && typeof live === "object" ? (live as Record<string, unknown>).via : null;
  const now = Date.now();
  const fresh = typeof liveTs === "number" && now - liveTs < DIRECT_FRESH_MS;
  if (fresh && liveVia !== "lora") {
    return json(200, { status: "stored", fallback: false });
  }

  // The node's own feed is quiet: LoRa takes over. (The gateway writes the
  // live values itself every second while the node reports Wi-Fi down; this
  // covers a node that has Wi-Fi but no internet.)
  if (!fresh) {
    await ctx.rtdb.put(`live/${node}/values`, { ...liveValues(p), ts: { ".sv": "timestamp" } });
  }

  // Device, history and the alert rules once a minute (like ThingSpeak did).
  const meta = await ctx.rtdb.get(`loraMeta/${node}/deviceWriteAt`);
  if (typeof meta !== "number" || now - meta >= LORA_DEVICE_WRITE_MS) {
    const device = await ctx.fs.get(`devices/${data.node}`);
    if (!device) return json(404, { error: "Unknown node." });
    await ctx.rtdb.put(`loraMeta/${node}/deviceWriteAt`, now);
    await processReading(ctx, data.node, data.node, device, sensorReading(p, ctx.now), "lora");
  }

  if (p.alert && alertAllowed(p, AI_FIRE_CONFIDENCE_THRESHOLD)) {
    const device = await ctx.fs.get(`devices/${data.node}`);
    const alertId = await createAlertIfNew(ctx, data.node, p.alert.type, p.alert.severity, {
      message:
        alertMessageFor(p.alert.type, {
          nodeName: typeof device?.data.name === "string" ? device.data.name : data.node,
          severity: p.alert.severity,
          aiConfidence: p.alert.type === "ENVIRONMENTAL_RISK" ? null : p.conf,
          temperature: p.t1,
          humidity: p.h1,
          smoke: p.mq1,
        }) + " (Relayed by LoRa: the sensor's Wi-Fi is down.)",
      source: "lora",
      fireProbability: p.ai === "Fire" && p.conf != null ? p.conf * 100 : 0,
      smokeProbability: p.ai === "Smoke" && p.conf != null ? p.conf * 100 : 0,
      temperature: p.t1 ?? 0,
      humidity: p.h1 ?? 0,
      latitude: asNumber(device?.data.latitude),
      longitude: asNumber(device?.data.longitude),
      sensorReadings: { mq2_1: p.mq1, mq2_2: p.mq2, aiClass: p.ai, aiConfidence: p.conf, riskScore: p.risk },
    }, undefined, true);
    if (alertId) {
      const created = await ctx.fs.get(`alerts/${alertId}`);
      if (created) await run(`push ${alertId}`, () => sendNewAlert(ctx, alertId, created.path, created.data));
    }
  }

  return json(200, { status: "relayed", fallback: true });
}

// ---------------------------------------------------------------------------

export default {
  async scheduled(event: ScheduledController, env: Env, executionCtx: ExecutionContext) {
    const ctx = context(env);
    const jobs: Record<string, () => Promise<void>> = {
      "* * * * *": () => ingestAll(ctx),
      "*/1 * * * *": () => minuteJobs(ctx),
      "*/5 * * * *": () => maintenance(ctx),
      "7 * * * *": () => hourlyRollup(ctx),
      "23 21 * * *": () => deleteOldReadings(ctx),
    };

    const job = jobs[event.cron];
    if (!job) {
      console.warn(`No job for cron "${event.cron}"`);
      return;
    }
    executionCtx.waitUntil(run(event.cron, job));
  },

  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/alert") {
      if (request.method !== "POST") return json(405, { error: "Use POST." });
      try {
        return await handleDeviceAlert(request, env);
      } catch (error) {
        console.error("device alert failed:", error instanceof Error ? error.message : error);
        return json(500, { error: "Alert could not be saved; the node will retry." });
      }
    }

    if (url.pathname === "/lora/data") {
      if (request.method !== "POST") return json(405, { error: "Use POST." });
      try {
        return await handleLoraData(request, env);
      } catch (error) {
        console.error("lora data failed:", error instanceof Error ? error.message : error);
        return json(500, { error: "Packet could not be saved." });
      }
    }

    if (url.pathname === "/lora") {
      if (request.method !== "POST") return json(405, { error: "Use POST." });
      try {
        return await handleLoraReport(request, env);
      } catch (error) {
        console.error("lora report failed:", error instanceof Error ? error.message : error);
        return json(500, { error: "Report could not be saved." });
      }
    }

    return new Response(`Forest Fire backend ${VERSION}\n`, {
      headers: { "Content-Type": "text/plain" },
    });
  },
} satisfies ExportedHandler<Env>;
