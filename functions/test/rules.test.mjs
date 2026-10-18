// Security rules tests. Run from functions/ with:  npm run test:rules
// (starts the Firestore emulator; needs Java 11+ and firebase-tools).

import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { deleteField, doc, getDoc, serverTimestamp, setDoc, updateDoc } from "firebase/firestore";

let env;

const as = (uid, role) =>
  env.authenticatedContext(uid, role ? { role } : {}).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-forest-fire",
    firestore: { rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8") },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "devices/NODE-01"), { name: "Node 1", temperature: 30, riskScore: 10 });
    await setDoc(doc(db, "devices/NODE-01/readings/r1"), { ts: new Date(), temperature: 30 });
    await setDoc(doc(db, "alerts/a1"), { deviceId: "NODE-01", status: "ACTIVE", severity: "HIGH" });
    await setDoc(doc(db, "alerts/a2"), { deviceId: "NODE-01", status: "ACKNOWLEDGED", severity: "HIGH" });
    await setDoc(doc(db, "config/channels"), { channels: [] });
  });
});

describe("reading data", () => {
  test("signed-out users can't read anything", async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "devices/NODE-01")));
    await assertFails(getDoc(doc(db, "alerts/a1")));
  });

  test("any signed-in user can read nodes, readings and alerts", async () => {
    const db = as("viewer1");
    await assertSucceeds(getDoc(doc(db, "devices/NODE-01")));
    await assertSucceeds(getDoc(doc(db, "devices/NODE-01/readings/r1")));
    await assertSucceeds(getDoc(doc(db, "alerts/a1")));
  });

  test("nobody in the app can read backend config", async () => {
    await assertFails(getDoc(doc(as("admin1", "admin"), "config/channels")));
  });
});

describe("sensor data is backend-only", () => {
  test("officers can't change readings", async () => {
    await assertFails(updateDoc(doc(as("o1", "officer"), "devices/NODE-01"), { temperature: 99 }));
  });

  test("admins can't change readings either", async () => {
    await assertFails(updateDoc(doc(as("admin1", "admin"), "devices/NODE-01"), { riskScore: 0 }));
  });

  test("admins can set a node's location", async () => {
    await assertSucceeds(
      setDoc(
        doc(as("admin1", "admin"), "devices/NODE-01"),
        { name: "Ridge camp", latitude: 12.97, longitude: 77.59 },
        { merge: true },
      ),
    );
  });

  test("invalid coordinates are rejected", async () => {
    await assertFails(
      setDoc(
        doc(as("admin1", "admin"), "devices/NODE-01"),
        { name: "x", latitude: 120, longitude: 77.59 },
        { merge: true },
      ),
    );
  });

  test("officers can't set node locations", async () => {
    await assertFails(
      setDoc(
        doc(as("o1", "officer"), "devices/NODE-01"),
        { name: "x", latitude: 12, longitude: 77 },
        { merge: true },
      ),
    );
  });
});

describe("alert workflow", () => {
  const ack = (uid) => ({
    status: "ACKNOWLEDGED",
    ackBy: uid,
    ackByName: "Officer",
    ackAt: serverTimestamp(),
  });

  test("viewers can't acknowledge", async () => {
    await assertFails(updateDoc(doc(as("v1", "viewer"), "alerts/a1"), ack("v1")));
  });

  test("users without a role are viewers", async () => {
    await assertFails(updateDoc(doc(as("nobody"), "alerts/a1"), ack("nobody")));
  });

  test("officers can acknowledge as themselves", async () => {
    await assertSucceeds(updateDoc(doc(as("o1", "officer"), "alerts/a1"), ack("o1")));
  });

  test("officers can't acknowledge on someone else's behalf", async () => {
    await assertFails(updateDoc(doc(as("o1", "officer"), "alerts/a1"), ack("o2")));
  });

  test("acknowledging can't rewrite the alert", async () => {
    await assertFails(
      updateDoc(doc(as("o1", "officer"), "alerts/a1"), { ...ack("o1"), severity: "LOW" }),
    );
  });

  test("an active alert can't skip straight to resolved", async () => {
    await assertFails(
      updateDoc(doc(as("o1", "officer"), "alerts/a1"), {
        status: "RESOLVED",
        resolvedBy: "o1",
        resolvedAt: serverTimestamp(),
      }),
    );
  });

  test("officers can resolve an acknowledged alert with notes", async () => {
    await assertSucceeds(
      updateDoc(doc(as("o1", "officer"), "alerts/a2"), {
        status: "RESOLVED",
        resolvedBy: "o1",
        resolvedByName: "Officer",
        resolvedAt: serverTimestamp(),
        notes: "Controlled burn, no action needed.",
      }),
    );
  });

  test("apps can't create or delete alerts", async () => {
    const db = as("admin1", "admin");
    await assertFails(setDoc(doc(db, "alerts/fake"), { deviceId: "NODE-01", status: "ACTIVE" }));
    await assertFails(updateDoc(doc(db, "alerts/a1"), { status: deleteField() }));
  });
});

describe("profiles and push tokens", () => {
  test("users manage their own profile but can't grant themselves a role", async () => {
    const db = as("u1");
    await assertSucceeds(setDoc(doc(db, "users/u1"), { subscribedNodes: ["NODE-01"] }));
    await assertFails(setDoc(doc(db, "users/u1"), { role: "admin" }, { merge: true }));
  });

  test("users can't touch other users' profiles or tokens", async () => {
    const db = as("u1");
    await assertFails(getDoc(doc(db, "users/u2")));
    await assertFails(setDoc(doc(db, "users/u2/tokens/abc"), { platform: "android" }));
  });

  test("users register their own push token", async () => {
    await assertSucceeds(
      setDoc(doc(as("u1"), "users/u1/tokens/abc"), {
        platform: "android",
        updatedAt: serverTimestamp(),
      }),
    );
  });
});
