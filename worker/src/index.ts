/**
 * Forest Fire Monitor backend on Cloudflare Workers (free plan, no card).
 *
 * Cron triggers (Workers Free allows 5 per account; each run gets its own
 * 50-subrequest budget, which is why ingestion and push are separate):
 *   "* * * * *"     ingest every ThingSpeak channel
 *   "*\/1 * * * *"  push new alerts (every minute, separate budget)
 *   "*\/5 * * * *"  node health, alertActive, escalation, role requests, heartbeat
 *   "7 * * * *"     hourly rollup of the previous hour
 *   "23 21 * * *"   delete readings past retention (03:00 IST)
 *
 * Firestore stays inside the Spark plan's daily quota: queries that usually
 * match nothing cost 1 read, and open alerts are fetched every 5 minutes, not
 * every minute.
 */

import { decideAlert, OPEN_STATUSES } from "./alertRules.js";
import { pushAlert } from "./fcm.js";
import { Firestore, newDocId, type Doc, type Plain, type Write } from "./firestore.js";
import { accessToken, type ServiceAccount } from "./google.js";
import { lookupUser, setClaims } from "./identity.js";
import { calculateRisk } from "./risk.js";
import { fetchLastFeed, parseFeed } from "./thingspeak.js";

export interface Env {
  /** The Firebase service-account JSON, stored with `wrangler secret put`. */
  FIREBASE_SERVICE_ACCOUNT: string;
  READING_RETENTION_DAYS?: string;
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
  return Math.max(0, SUBREQUEST_LIMIT - ctx.fs.requests - used - 3);
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

async function createAlertIfNew(
  ctx: Context,
  nodeId: string,
  type: string,
  severity: string,
  details: Record<string, Plain>,
  knownOpen?: Doc[],
): Promise<string | null> {
  const open = knownOpen
    ? knownOpen.filter((doc) => doc.data.deviceId === nodeId && doc.data.type === type)
    : await openAlertsFor(ctx, nodeId, type);

  if (open.length > 0) return null;

  const alertId = `${nodeId}_${type}_${Math.floor(ctx.now.getTime() / 1000)}`;
  await ctx.fs.set(`alerts/${alertId}`, {
    alertId,
    deviceId: nodeId,
    type,
    severity,
    status: "ACTIVE",
    detectedAt: ctx.now,
    escalationLevel: 0,
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

  const risk = calculateRisk({
    temperature: reading.temperature,
    humidity: reading.humidity,
    mq2_1: reading.mq2_1,
    mq2_2: reading.mq2_2,
    temperature2: reading.temperature2,
    humidity2: reading.humidity2,
  });
  const fireProbability = reading.fireDetected ? reading.aiConfidence * 100 : 0;

  await ctx.fs.commit([
    {
      set: devicePath,
      merge: true,
      data: {
        deviceId: channel.nodeId,
        ...(device ? {} : { name: channel.name ?? channel.nodeId }),
        status: "ONLINE",
        lastSeen: reading.timestamp,
        temperature: reading.temperature,
        humidity: reading.humidity,
        temperature2: reading.temperature2,
        humidity2: reading.humidity2,
        mq2Sensor1: reading.mq2_1,
        mq2Sensor2: reading.mq2_2,
        fireDetected: reading.fireDetected,
        aiConfidence: reading.aiConfidence,
        fireProbability,
        smokeProbability: 0,
        riskPoints: risk.points,
        riskScore: risk.score,
        riskLevel: risk.level,
        thingspeakEntryId: reading.entryId,
        sensorDataAgeSeconds: reading.ageSeconds,
        sensorDataStale: false,
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
        riskScore: risk.score,
        entryId: reading.entryId,
      },
    },
  ]);

  const decision = decideAlert(reading, risk.level);
  if (decision) {
    await createAlertIfNew(ctx, channel.nodeId, decision.type, decision.severity, {
      fireProbability,
      smokeProbability: 0,
      temperature: reading.temperature,
      humidity: reading.humidity,
      latitude: asNumber(device?.data.latitude),
      longitude: asNumber(device?.data.longitude),
      sensorReadings: {
        temperature2: reading.temperature2,
        humidity2: reading.humidity2,
        mq2_1: reading.mq2_1,
        mq2_2: reading.mq2_2,
        aiConfidence: reading.aiConfidence,
        entryId: reading.entryId,
      },
    });
  }
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

    await run(`push ${alert.id}`, async () => {
      await pushAlert(ctx.fs, ctx.projectId, ctx.token, alert.id, alert.data, {
        maxSends: budget(ctx, 3),
      });
      await ctx.fs.set(alert.path, { pushedAt: new Date() }, true);
    });
  }
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
  await run("role requests", () => roleRequests(ctx));
  await run("heartbeat", () =>
    ctx.fs.set("status/backend", {
      lastHeartbeat: new Date(),
      version: VERSION,
      openAlerts: open.length,
      host: "cloudflare-workers",
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

      if (status !== data.status) {
        update.status = status;

        if (status === "OFFLINE") {
          await createAlertIfNew(
            ctx,
            device.id,
            "NODE_OFFLINE",
            "HIGH",
            {
              fireProbability: 0,
              smokeProbability: 0,
              temperature: asNumber(data.temperature),
              humidity: asNumber(data.humidity),
              latitude: asNumber(data.latitude),
              longitude: asNumber(data.longitude),
            },
            open,
          );
          update.alertActive = true;
        } else if (data.status === "OFFLINE") {
          for (const outage of open) {
            if (outage.data.deviceId === device.id && outage.data.type === "NODE_OFFLINE") {
              writes.push({
                set: outage.path,
                merge: true,
                data: {
                  status: "RESOLVED",
                  resolvedBy: "system",
                  resolvedByName: "System",
                  resolvedAt: new Date(),
                  notes: "Node resumed reporting.",
                },
              });
            }
          }
        }
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
    if (data.status !== "ACTIVE" || !detected) continue;

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

    let temperatureSum = 0;
    let humiditySum = 0;
    let smokeMax = 0;
    let fireMax = 0;
    let riskMax = 0;

    for (const { data } of readings) {
      temperatureSum += asNumber(data.temperature);
      humiditySum += asNumber(data.humidity);
      smokeMax = Math.max(smokeMax, asNumber(data.mq2_1), asNumber(data.mq2_2));
      fireMax = Math.max(fireMax, asNumber(data.fireProbability));
      riskMax = Math.max(riskMax, asNumber(data.riskScore));
    }

    writes.push({
      set: `${device.path}/hourly/${hourKey(start)}`,
      data: {
        hour: start,
        count: readings.length,
        temperatureSum,
        humiditySum,
        smokeMax,
        fireProbabilityMax: fireMax,
        riskScoreMax: riskMax,
      },
    });
  }

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

export default {
  async scheduled(event: ScheduledController, env: Env, executionCtx: ExecutionContext) {
    const ctx = context(env);
    const jobs: Record<string, () => Promise<void>> = {
      "* * * * *": () => ingestAll(ctx),
      "*/1 * * * *": () => pushNewAlerts(ctx),
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

  /** Health check only; all work happens on the schedule. */
  async fetch(): Promise<Response> {
    return new Response(`Forest Fire backend ${VERSION}\n`, {
      headers: { "Content-Type": "text/plain" },
    });
  },
} satisfies ExportedHandler<Env>;
