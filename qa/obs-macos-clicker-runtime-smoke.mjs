#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs/promises";
import { spawn, spawnSync } from "node:child_process";

const [deckPath, receiverPath] = process.argv.slice(2);
if (!deckPath || !receiverPath) {
  console.error("usage: obs-macos-clicker-runtime-smoke.mjs /path/to/deck.pdf /path/to/key-receiver");
  process.exit(2);
}

const obsWebSocketPassword = process.env.PPTBRIDGE_QA_OBS_PASSWORD || "";
const receiverLogPath = "/tmp/pptbridge-key-receiver.log";
const socket = new WebSocket("ws://127.0.0.1:4455");
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
socket.addEventListener("error", () => identifiedReject(new Error("OBS WebSocket connection failed")));
socket.addEventListener("message", (event) => {
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
    socket.send(JSON.stringify({ op: 1, d: identifyData }));
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
  const requestId = `pptbridge-clicker-qa-${++requestNumber}`;
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pending.delete(requestId);
      reject(new Error(`${requestType} timed out`));
    }, 10000);
    pending.set(requestId, { resolve, reject, timeout });
    socket.send(JSON.stringify({ op: 6, d: { requestType, requestId, requestData } }));
  });
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitFor(predicate, timeoutMilliseconds, failureMessage) {
  const deadline = Date.now() + timeoutMilliseconds;
  while (Date.now() < deadline) {
    if (await predicate()) {
      return;
    }
    await sleep(100);
  }
  throw new Error(failureMessage);
}

async function setProgramSceneAndConfirm(sceneName) {
  await request("SetCurrentProgramScene", { sceneName });
  await waitFor(async () => {
    const current = await request("GetCurrentProgramScene");
    return current.currentProgramSceneName === sceneName;
  }, 5000, `OBS did not switch Program to ${sceneName}`);
  await sleep(500);
}

async function screenshot(inputName) {
  const response = await request("GetSourceScreenshot", {
    sourceName: inputName,
    imageFormat: "png",
    imageWidth: 640,
    imageHeight: 360,
    imageCompressionQuality: 80,
  });
  const prefix = "data:image/png;base64,";
  if (!response.imageData?.startsWith(prefix)) {
    throw new Error(`OBS did not return a PNG screenshot for ${inputName}`);
  }
  const bytes = Buffer.from(response.imageData.slice(prefix.length), "base64");
  return {
    bytes: bytes.length,
    hash: crypto.createHash("sha256").update(bytes).digest("hex"),
  };
}

async function waitForScreenshot(inputName, predicate, failureMessage) {
  let last = null;
  await waitFor(async () => {
    try {
      last = await screenshot(inputName);
      return last.bytes > 10000 && predicate(last);
    } catch {
      return false;
    }
  }, 10000, failureMessage);
  return last;
}

function sendKeyCode(keyCode) {
  const result = spawnSync("/usr/bin/osascript", [
    "-e",
    `tell application "System Events" to key code ${keyCode}`,
  ], { encoding: "utf8", timeout: 5000 });
  if (result.error || result.status !== 0) {
    throw new Error(
      `could not send macOS key code ${keyCode}: ` +
      `${result.error || result.stderr || "unknown error"}`);
  }
}

await identified;
const suffix = Date.now().toString(36);
const sceneName = `PPTBridge Clicker QA ${suffix}`;
const inputName = `PPTBridge Clicker Source ${suffix}`;
let originalProgramScene = "";
let receiver = null;

try {
  originalProgramScene = (await request("GetCurrentProgramScene")).currentProgramSceneName;
  await request("CreateScene", { sceneName });
  await request("CreateInput", {
    sceneName,
    inputName,
    inputKind: "pptbridge_slide_source",
    inputSettings: {
      pptx_path: deckPath,
      use_live_powerpoint: false,
    },
    sceneItemEnabled: true,
  });
  await setProgramSceneAndConfirm(sceneName);
  const initial = await waitForScreenshot(
    inputName,
    () => true,
    "PPTBridge source did not render an initial frame");

  receiver = spawn(receiverPath, [], { stdio: "ignore" });
  await waitFor(async () => {
    try {
      return (await fs.readFile(receiverLogPath, "utf8")).includes("focused");
    } catch {
      return false;
    }
  }, 5000, "key receiver did not gain keyboard focus");

  // Plain navigation/typing keys must remain available to the focused app.
  for (const [keyCode, expected] of [
    [123, "up left"],
    [124, "up right"],
    [49, "up keycode-49"],
  ]) {
    sendKeyCode(keyCode);
    await waitFor(async () => {
      try {
        return (await fs.readFile(receiverLogPath, "utf8")).includes(expected);
      } catch {
        return false;
      }
    }, 2000, `focused app did not receive ${expected}`);
  }
  const afterPlainKeys = await screenshot(inputName);
  if (afterPlainKeys.hash !== initial.hash) {
    throw new Error("Left, Right, or Space unexpectedly moved the PPTBridge deck");
  }
  const plainKeyLog = await fs.readFile(receiverLogPath, "utf8");
  for (const expected of ["down left", "up left", "down right", "up right", "down keycode-49", "up keycode-49"]) {
    if (!plainKeyLog.includes(expected)) {
      throw new Error(`focused app did not receive ${expected}`);
    }
  }

  // PageDown/PageUp are the stage-clicker defaults: route them to PPTBridge
  // globally and suppress them from the focused app.
  sendKeyCode(121); // PageDown
  const afterPageDown = await waitForScreenshot(
    inputName,
    (candidate) => candidate.hash !== initial.hash,
    "PageDown did not move the Program-scene PPTBridge deck");
  sendKeyCode(116); // PageUp
  const afterPageUp = await waitForScreenshot(
    inputName,
    (candidate) => candidate.hash === initial.hash,
    "PageUp did not restore the first slide");
  const finalLog = await fs.readFile(receiverLogPath, "utf8");
  if (/page(up|down)/.test(finalLog)) {
    throw new Error("captured PageUp/PageDown leaked into the focused app");
  }

  console.log(JSON.stringify({
    sceneName,
    inputName,
    plainKeysReachedFocusedApp: true,
    plainKeysLeftDeckUnchanged: afterPlainKeys.hash === initial.hash,
    pageDownMovedDeck: afterPageDown.hash !== initial.hash,
    pageUpRestoredDeck: afterPageUp.hash === initial.hash,
    capturedClickerKeysSuppressed: true,
  }, null, 2));
} finally {
  if (receiver && !receiver.killed) {
    receiver.kill("SIGTERM");
  }
  if (originalProgramScene) {
    await setProgramSceneAndConfirm(originalProgramScene).catch(() => {});
  }
  await request("RemoveInput", { inputName }).catch(() => {});
  await request("RemoveScene", { sceneName }).catch(() => {});
  socket.close();
}
