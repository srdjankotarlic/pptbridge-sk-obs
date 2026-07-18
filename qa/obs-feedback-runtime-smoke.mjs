#!/usr/bin/env node

import crypto from "node:crypto";
import dgram from "node:dgram";

const [inputName] = process.argv.slice(2);
if (!inputName) {
  console.error("usage: obs-feedback-runtime-smoke.mjs 'PPTBridge source name'");
  process.exit(2);
}
const obsWebSocketPassword = process.env.PPTBRIDGE_QA_OBS_PASSWORD || "";

const expectedAddresses = new Set([
  "/pptbridge/status/current",
  "/pptbridge/status/total",
  "/pptbridge/status/title",
  "/pptbridge/status/next_title",
  "/pptbridge/status/deck_name",
  "/pptbridge/status/deck_path",
  "/pptbridge/status/source_name",
  "/pptbridge/status/error",
  "/pptbridge/status/timer",
  "/pptbridge/status/live",
  "/pptbridge/status/loading",
  "/pptbridge/status/loaded",
  "/pptbridge/status/black",
  "/pptbridge/status/cue_current_checked",
  "/pptbridge/status/cue_next_checked",
  "/pptbridge/status/cue_checked_count",
]);

function paddedString(packet, offset) {
  const end = packet.indexOf(0, offset);
  if (end < 0) {
    throw new Error("OSC packet contains an unterminated string");
  }
  const value = packet.subarray(offset, end).toString("utf8");
  return { value, next: Math.ceil((end + 1) / 4) * 4 };
}

function parseOscPacket(packet) {
  const address = paddedString(packet, 0);
  const tags = paddedString(packet, address.next);
  if (tags.value === ",i") {
    if (tags.next + 4 > packet.length) {
      throw new Error(`OSC int packet is truncated: ${address.value}`);
    }
    return { address: address.value, value: packet.readInt32BE(tags.next) };
  }
  if (tags.value === ",s") {
    return { address: address.value, value: paddedString(packet, tags.next).value };
  }
  throw new Error(`unsupported OSC type tag ${tags.value} for ${address.value}`);
}

const udp = dgram.createSocket("udp4");
const received = new Map();
udp.on("message", (packet) => {
  const message = parseOscPacket(packet);
  received.set(message.address, message.value);
});
await new Promise((resolve, reject) => {
  udp.once("error", reject);
  udp.bind(0, "127.0.0.1", resolve);
});
const feedbackPort = udp.address().port;

const websocket = new WebSocket("ws://127.0.0.1:4455");
const pending = new Map();
let requestNumber = 0;
let identifiedResolve;
let identifiedReject;
const identified = new Promise((resolve, reject) => {
  identifiedResolve = resolve;
  identifiedReject = reject;
});

const identifyTimeout = setTimeout(
  () => identifiedReject(new Error("OBS WebSocket identify timed out")),
  10000);
websocket.addEventListener("error", () => identifiedReject(new Error("OBS WebSocket connection failed")));
websocket.addEventListener("message", (event) => {
  const message = JSON.parse(String(event.data));
  if (message.op === 0) {
    const identifyData = { rpcVersion: 1, eventSubscriptions: 0 };
    if (message.d.authentication) {
      if (!obsWebSocketPassword) {
        identifiedReject(new Error(
          "OBS WebSocket requires authentication; set PPTBRIDGE_QA_OBS_PASSWORD"));
        return;
      }
      const secret = crypto.createHash("sha256")
        .update(obsWebSocketPassword + message.d.authentication.salt)
        .digest("base64");
      identifyData.authentication = crypto.createHash("sha256")
        .update(secret + message.d.authentication.challenge)
        .digest("base64");
    }
    websocket.send(JSON.stringify({ op: 1, d: identifyData }));
    return;
  }
  if (message.op === 2) {
    clearTimeout(identifyTimeout);
    identifiedResolve();
    return;
  }
  if (message.op !== 7) {
    return;
  }
  const waiter = pending.get(message.d.requestId);
  if (!waiter) {
    return;
  }
  pending.delete(message.d.requestId);
  clearTimeout(waiter.timeout);
  if (!message.d.requestStatus?.result) {
    waiter.reject(new Error(
      `${message.d.requestType} failed (${message.d.requestStatus?.code}): ` +
      `${message.d.requestStatus?.comment || "unknown error"}`));
    return;
  }
  waiter.resolve(message.d.responseData || {});
});

function request(requestType, requestData = {}) {
  const requestId = `pptbridge-feedback-qa-${++requestNumber}`;
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pending.delete(requestId);
      reject(new Error(`${requestType} timed out`));
    }, 10000);
    pending.set(requestId, { resolve, reject, timeout });
    websocket.send(JSON.stringify({ op: 6, d: { requestType, requestId, requestData } }));
  });
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

let originalSettings;
try {
  await identified;
  originalSettings = (await request("GetInputSettings", { inputName })).inputSettings;
  await request("SetInputSettings", {
    inputName,
    inputSettings: {
      pptbridge_osc_feedback_enabled: true,
      pptbridge_osc_feedback_host: "127.0.0.1",
      pptbridge_osc_feedback_port: feedbackPort,
    },
    overlay: true,
  });

  const deadline = Date.now() + 5000;
  while (Date.now() < deadline && [...expectedAddresses].some((address) => !received.has(address))) {
    await sleep(100);
  }

  const missing = [...expectedAddresses].filter((address) => !received.has(address));
  if (missing.length > 0) {
    throw new Error(`missing OSC feedback: ${missing.join(", ")}`);
  }
  if (received.get("/pptbridge/status/source_name") !== inputName) {
    throw new Error("OSC source_name does not match the tested OBS source");
  }
  if (received.get("/pptbridge/status/current") < 1 ||
      received.get("/pptbridge/status/total") < received.get("/pptbridge/status/current")) {
    throw new Error("OSC slide position is inconsistent");
  }
  if (!received.get("/pptbridge/status/deck_name") || !received.get("/pptbridge/status/deck_path")) {
    throw new Error("OSC deck identity is empty");
  }

  console.log(JSON.stringify({
    inputName,
    feedbackPort,
    messageCount: received.size,
    values: Object.fromEntries([...received.entries()].sort()),
  }, null, 2));
} finally {
  if (originalSettings) {
    await request("SetInputSettings", {
      inputName,
      inputSettings: {
        pptbridge_osc_feedback_enabled: Boolean(originalSettings.pptbridge_osc_feedback_enabled),
        pptbridge_osc_feedback_host: originalSettings.pptbridge_osc_feedback_host || "127.0.0.1",
        pptbridge_osc_feedback_port: originalSettings.pptbridge_osc_feedback_port || 57131,
      },
      overlay: true,
    }).catch(() => {});
  }
  websocket.close();
  udp.close();
}
