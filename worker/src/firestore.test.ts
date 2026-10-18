import assert from "node:assert/strict";
import { test } from "node:test";

import { fromFields, newDocId, toFields } from "./firestore.js";

test("Firestore values round-trip", () => {
  const when = new Date("2026-10-18T12:00:00.000Z");
  const data = {
    name: "Ridge",
    count: 3,
    temperature: 31.5,
    active: true,
    missing: null,
    lastSeen: when,
    nodes: ["NODE-01", "NODE-02"],
    readings: { mq2_1: 420, nested: { ok: false } },
  };

  const fields = toFields(data);

  assert.deepEqual(fields.count, { integerValue: "3" });
  assert.deepEqual(fields.temperature, { doubleValue: 31.5 });
  assert.deepEqual(fields.lastSeen, { timestampValue: "2026-10-18T12:00:00.000Z" });
  assert.deepEqual(fromFields(fields), data);
});

test("undefined fields are left out", () => {
  assert.deepEqual(toFields({ a: 1, b: undefined }), { a: { integerValue: "1" } });
});

test("document ids are 20 safe characters", () => {
  const id = newDocId();
  assert.match(id, /^[A-Za-z0-9]{20}$/);
  assert.notEqual(id, newDocId());
});
