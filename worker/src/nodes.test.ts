import assert from "node:assert/strict";
import test from "node:test";

import { newNodeKey, parseAddNode, suggestNodeId } from "./nodes.js";
import { chatsFromUpdates } from "./telegram.js";

test("add-sensor requests are checked", () => {
  const ok = parseAddNode({ nodeId: "node-02", name: " Hill top ", terrain: "pine", channelId: "3444999" });
  assert.equal(typeof ok, "object");
  assert.deepEqual(ok, {
    nodeId: "NODE-02",
    name: "Hill top",
    zone: null,
    terrain: "pine",
    channelId: "3444999",
    readApiKey: null,
  });
  assert.equal(typeof parseAddNode({ nodeId: "../x", name: "A" }), "string");
  assert.equal(typeof parseAddNode({ nodeId: "NODE-03" }), "string");
  assert.equal(typeof parseAddNode({ nodeId: "NODE-03", name: "A", terrain: "lava" }), "string");
  assert.equal(typeof parseAddNode({ nodeId: "NODE-03", name: "A", channelId: "abc" }), "string");
});

test("node keys are long and random; ids count up", () => {
  const a = newNodeKey();
  assert.match(a, /^[0-9a-f]{32}$/);
  assert.notEqual(a, newNodeKey());
  assert.equal(suggestNodeId(["NODE-01", "UAV-01"]), "NODE-02");
  assert.equal(suggestNodeId([]), "NODE-01");
});

test("telegram updates become one chat each, with the next offset", () => {
  const { chats, nextOffset } = chatsFromUpdates([
    { update_id: 10, message: { date: 1, text: "/start", chat: { id: 55, type: "private", first_name: "Ravi", last_name: "K" } } },
    { update_id: 11, message: { date: 2, text: "hello", chat: { id: 55, type: "private", first_name: "Ravi", last_name: "K" } } },
    { update_id: 12, message: { date: 3, text: "hi", chat: { id: -900, type: "group", title: "Fire Station Ooty" } } },
    { update_id: 13 },
  ]);
  assert.equal(nextOffset, 14);
  assert.equal(chats.length, 2);
  assert.equal(chats.find((c) => c.chatId === "55")?.name, "Ravi K");
  assert.equal(chats.find((c) => c.chatId === "55")?.lastText, "hello");
  assert.equal(chats.find((c) => c.chatId === "-900")?.name, "Fire Station Ooty");
  assert.equal(chatsFromUpdates([]).nextOffset, null);
});

test("bot commands keep the link code and survive later messages", () => {
  const { commands, chats } = chatsFromUpdates([
    { update_id: 1, message: { date: 1, text: "/start AbCdEfGhIjKlMnOpQrSt", chat: { id: 7, type: "private", first_name: "A" } } },
    { update_id: 2, message: { date: 2, text: "thanks", chat: { id: 7, type: "private", first_name: "A" } } },
    { update_id: 3, message: { date: 3, text: "/stop@FPERBOT", chat: { id: 8, type: "private", first_name: "B" } } },
    { update_id: 4, message: { date: 4, text: "/start", chat: { id: 9, type: "private", first_name: "C" } } },
  ]);
  assert.deepEqual(commands, [
    { chatId: "7", command: "start", argument: "AbCdEfGhIjKlMnOpQrSt" },
    { chatId: "8", command: "stop", argument: "" },
    { chatId: "9", command: "start", argument: "" },
  ]);
  assert.equal(chats.find((c) => c.chatId === "7")?.lastText, "thanks");
});
