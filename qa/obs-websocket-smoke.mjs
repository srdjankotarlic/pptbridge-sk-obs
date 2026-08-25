#!/usr/bin/env node

import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import dgram from "node:dgram";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const [pptxPath, pdfPath, outputDirectory = "/tmp/pptbridge-obs-websocket-smoke"] = process.argv.slice(2);
if (!pptxPath || !pdfPath) {
  console.error("usage: obs-websocket-smoke.mjs /path/to/deck.pptx /path/to/deck.pdf [output-directory]");
  process.exit(2);
}

await fs.mkdir(outputDirectory, { recursive: true });

const minimumLiveScreenshotBytes = Number.parseInt(
  process.env.PPTBRIDGE_QA_MIN_LIVE_PNG_BYTES || "20000", 10);
const minimumStaticScreenshotBytes = Number.parseInt(
  process.env.PPTBRIDGE_QA_MIN_STATIC_PNG_BYTES || "10000", 10);
const keepSources = process.env.PPTBRIDGE_QA_KEEP_SOURCES === "1";
const closeOnShutdown = process.env.PPTBRIDGE_QA_CLOSE_ON_SHUTDOWN !== "0";
const obsWebSocketPassword = process.env.PPTBRIDGE_QA_OBS_PASSWORD || "";
const visualDifferenceThreshold = Number.parseFloat(
  process.env.PPTBRIDGE_QA_VISUAL_DIFF_THRESHOLD || "0.01");
const ffmpegExecutable = process.env.PPTBRIDGE_QA_FFMPEG || "ffmpeg";
const presenterBackgroundImage = process.env.PPTBRIDGE_QA_BACKGROUND_IMAGE || path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../native-plugin/media/github/pptbridge-sk-social-preview.png");
const expectedFeedbackAddresses = new Set([
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

function paddedOscString(packet, offset) {
  const end = packet.indexOf(0, offset);
  if (end < 0) {
    throw new Error("OSC packet contains an unterminated string");
  }
  const value = packet.subarray(offset, end).toString("utf8");
  return { value, next: Math.ceil((end + 1) / 4) * 4 };
}

function parseOscPacket(packet) {
  const address = paddedOscString(packet, 0);
  const tags = paddedOscString(packet, address.next);
  if (tags.value === ",i") {
    if (tags.next + 4 > packet.length) {
      throw new Error(`OSC int packet is truncated: ${address.value}`);
    }
    return { address: address.value, value: packet.readInt32BE(tags.next) };
  }
  if (tags.value === ",s") {
    return { address: address.value, value: paddedOscString(packet, tags.next).value };
  }
  throw new Error(`unsupported OSC type tag ${tags.value} for ${address.value}`);
}

const socket = new WebSocket("ws://127.0.0.1:4455");
const pending = new Map();
let requestNumber = 0;
let identifiedResolve;
let identifiedReject;
const identified = new Promise((resolve, reject) => {
  identifiedResolve = resolve;
  identifiedReject = reject;
});

const identifyTimeout = setTimeout(() => identifiedReject(new Error("OBS WebSocket identify timed out")), 10000);
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
      `${message.d.requestType} failed (${message.d.requestStatus?.code}): ${message.d.requestStatus?.comment || "unknown error"}`));
    return;
  }
  waiter.resolve(message.d.responseData || {});
});

await identified;

function request(requestType, requestData = {}) {
  const requestId = `pptbridge-qa-${++requestNumber}`;
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pending.delete(requestId);
      reject(new Error(`${requestType} timed out`));
    }, 15000);
    pending.set(requestId, { resolve, reject, timeout });
    socket.send(JSON.stringify({ op: 6, d: { requestType, requestId, requestData } }));
  });
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

const feedbackReceived = new Map();
const feedbackHistory = [];
let feedbackSequence = 0;
let feedbackParseError = null;

async function waitForFeedback(
  address,
  predicate,
  timeoutMilliseconds = 5000,
  afterSequence = 0,
) {
  const deadline = Date.now() + timeoutMilliseconds;
  while (Date.now() < deadline) {
    if (feedbackParseError) {
      throw feedbackParseError;
    }
    for (let index = feedbackHistory.length - 1; index >= 0; index -= 1) {
      const event = feedbackHistory[index];
      if (event.sequence <= afterSequence) {
        break;
      }
      if (event.address === address && predicate(event.value)) {
        return event.value;
      }
    }
    if (afterSequence === 0 && feedbackReceived.has(address)) {
      const value = feedbackReceived.get(address);
      if (predicate(value)) {
        return value;
      }
    }
    await sleep(100);
  }
  throw new Error(`timed out waiting for OSC feedback ${address}`);
}

async function waitForFeedbackState(expected, timeoutMilliseconds = 5000, afterSequence = 0) {
  const values = {};
  for (const [address, predicate] of Object.entries(expected)) {
    values[address] = await waitForFeedback(
      address,
      predicate,
      timeoutMilliseconds,
      afterSequence);
  }
  return values;
}

function activateObsForFocusedHotkeyTest() {
  const result = spawnSync("/usr/bin/osascript", [
    "-e",
    'tell application "OBS" to activate',
    "-e",
    'tell application "System Events" to tell process "OBS" to set frontmost to true',
  ], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`could not activate OBS for focused hotkey test: ${result.stderr || "unknown error"}`);
  }
}

function renderVisualThumbnail(pngPath) {
  const result = spawnSync(ffmpegExecutable, [
    "-hide_banner",
    "-loglevel", "error",
    "-i", pngPath,
    "-vf", "scale=32:18,format=gray",
    "-frames:v", "1",
    "-f", "rawvideo",
    "pipe:1",
  ], {
    maxBuffer: 1024 * 1024,
    timeout: 10000,
  });
  if (result.error || result.status !== 0 || result.stdout?.length !== 32 * 18) {
    throw new Error(
      `ffmpeg could not decode an OBS screenshot: ${String(result.error || result.stderr || "unknown error")}`);
  }
  return result.stdout;
}

function visualDistance(first, second) {
  if (!first?.thumbnail || !second?.thumbnail || first.thumbnail.length !== second.thumbnail.length) {
    return 1;
  }
  let absoluteDifference = 0;
  for (let index = 0; index < first.thumbnail.length; index += 1) {
    absoluteDifference += Math.abs(first.thumbnail[index] - second.thumbnail[index]);
  }
  return absoluteDifference / (first.thumbnail.length * 255);
}

function visuallySame(first, second) {
  return visualDistance(first, second) < visualDifferenceThreshold;
}

function visuallyDifferent(first, second) {
  return !visuallySame(first, second);
}

async function setProgramSceneAndConfirm(sceneName) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    await request("SetCurrentProgramScene", { sceneName });
    await sleep(150);
    const current = await request("GetCurrentProgramScene");
    if (current.currentProgramSceneName === sceneName) {
      // Let an active Studio Mode transition finish before routing commands.
      await sleep(450);
      return;
    }
  }
  throw new Error(`OBS did not switch the Program scene to ${sceneName}`);
}

function sendOsc(address, port = 57130) {
  return new Promise((resolve, reject) => {
    const client = dgram.createSocket("udp4");
    const bytes = Buffer.from(`${address}\0`);
    const packet = Buffer.alloc(Math.ceil(bytes.length / 4) * 4);
    bytes.copy(packet);
    client.send(packet, port, "127.0.0.1", (error) => {
      client.close();
      error ? reject(error) : resolve();
    });
  });
}

async function screenshot(sourceName, fileName, minimumBytes = 2000) {
  const response = await request("GetSourceScreenshot", {
    sourceName,
    imageFormat: "png",
    imageWidth: 640,
    imageHeight: 360,
    imageCompressionQuality: 80,
  });
  const prefix = "data:image/png;base64,";
  if (!response.imageData?.startsWith(prefix)) {
    throw new Error(`OBS did not return a PNG screenshot for ${sourceName}`);
  }
  const bytes = Buffer.from(response.imageData.slice(prefix.length), "base64");
  if (bytes.length < minimumBytes) {
    throw new Error(`OBS screenshot for ${sourceName} is unexpectedly small (${bytes.length} bytes)`);
  }
  const filePath = path.join(outputDirectory, fileName);
  await fs.writeFile(filePath, bytes);
  return {
    filePath,
    bytes: bytes.length,
    hash: crypto.createHash("sha256").update(bytes).digest("hex"),
    thumbnail: renderVisualThumbnail(filePath),
  };
}

async function waitForScreenshot(
  sourceName,
  fileName,
  predicate,
  timeoutMilliseconds = 15000,
  minimumBytes = 2000,
) {
  const deadline = Date.now() + timeoutMilliseconds;
  let lastScreenshot;
  let lastError;
  while (Date.now() < deadline) {
    try {
      lastScreenshot = await screenshot(sourceName, fileName, minimumBytes);
      if (predicate(lastScreenshot)) {
        return lastScreenshot;
      }
    } catch (error) {
      lastError = error;
    }
    await sleep(250);
  }
  if (lastError && !lastScreenshot) {
    throw lastError;
  }
  throw new Error(`timed out waiting for ${sourceName} screenshot state`);
}

const suffix = Date.now().toString(36);
const sceneA = `PPTBridge Automated QA A ${suffix}`;
const sceneB = `PPTBridge Automated QA B ${suffix}`;
const slideA = `PPTBridge QA Slide A ${suffix}`;
const presenterA = `PPTBridge QA Presenter A ${suffix}`;
const slideB = `PPTBridge QA Slide B ${suffix}`;
const createdInputs = [];
const createdScenes = [];
let originalProgramScene = "";
let feedbackSocket = null;
let feedbackPort = 0;
let cueExportPath = "";
let cueExportOriginal = null;

try {
  await fs.access(presenterBackgroundImage);
  feedbackSocket = dgram.createSocket("udp4");
  feedbackSocket.on("message", (packet) => {
    try {
      const message = parseOscPacket(packet);
      feedbackReceived.set(message.address, message.value);
      feedbackHistory.push({ ...message, sequence: ++feedbackSequence, receivedAt: Date.now() });
    } catch (error) {
      feedbackParseError = error;
    }
  });
  await new Promise((resolve, reject) => {
    feedbackSocket.once("error", reject);
    feedbackSocket.bind(0, "127.0.0.1", resolve);
  });
  feedbackSocket.removeAllListeners("error");
  feedbackSocket.on("error", (error) => {
    feedbackParseError = error;
  });
  feedbackPort = feedbackSocket.address().port;

  const version = await request("GetVersion");
  const kinds = await request("GetInputKindList", { unversioned: true });
  for (const requiredKind of ["pptbridge_slide_source", "pptbridge_presenter_source"]) {
    if (!kinds.inputKinds?.includes(requiredKind)) {
      throw new Error(`installed OBS does not expose ${requiredKind}`);
    }
  }

  const currentProgram = await request("GetCurrentProgramScene");
  originalProgramScene = currentProgram.currentProgramSceneName;

  await request("CreateScene", { sceneName: sceneA });
  createdScenes.push(sceneA);
  await request("CreateScene", { sceneName: sceneB });
  createdScenes.push(sceneB);

  await request("CreateInput", {
    sceneName: sceneA,
    inputName: slideA,
    inputKind: "pptbridge_slide_source",
    inputSettings: {
      pptx_path: pptxPath,
      use_live_powerpoint: false,
      auto_start_live_powerpoint: false,
      close_live_powerpoint_on_shutdown: closeOnShutdown,
      pptbridge_osc_feedback_enabled: true,
      pptbridge_osc_feedback_host: "127.0.0.1",
      pptbridge_osc_feedback_port: feedbackPort,
    },
    sceneItemEnabled: true,
  });
  createdInputs.push(slideA);
  await request("CreateInput", {
    sceneName: sceneA,
    inputName: presenterA,
    inputKind: "pptbridge_presenter_source",
    inputSettings: {
      pptx_path: pptxPath,
      canvas_width: 1280,
      canvas_height: 720,
      presenter_layout: "balanced",
      presenter_show_cue_list: true,
    },
    sceneItemEnabled: true,
  });
  createdInputs.push(presenterA);
  await request("CreateInput", {
    sceneName: sceneB,
    inputName: slideB,
    inputKind: "pptbridge_slide_source",
    inputSettings: {
      pptx_path: pdfPath,
      use_live_powerpoint: false,
    },
    sceneItemEnabled: true,
  });
  createdInputs.push(slideB);

  // Uncached PPTX conversion can take several seconds. Never treat the stable
  // loading placeholder as slide 1 or navigation assertions become meaningless.
  const slideAInitial = await waitForScreenshot(
    slideA,
    "slide-a-initial.png",
    (candidate) => candidate.bytes >= minimumStaticScreenshotBytes,
    45000);
  const presenterInitial = await waitForScreenshot(
    presenterA,
    "presenter-a-initial.png",
    (candidate) => candidate.bytes >= minimumStaticScreenshotBytes,
    15000);
  const slideBInitial = await waitForScreenshot(
    slideB,
    "slide-b-initial.png",
    (candidate) => candidate.bytes >= minimumStaticScreenshotBytes,
    15000);

  for (const address of expectedFeedbackAddresses) {
    await waitForFeedback(address, () => true, 10000);
  }
  await waitForFeedbackState({
    "/pptbridge/status/current": (value) => value === 1,
    "/pptbridge/status/total": (value) => value >= 2,
    "/pptbridge/status/loading": (value) => value === 0,
    "/pptbridge/status/loaded": (value) => value === 1,
    "/pptbridge/status/live": (value) => value === 0,
    "/pptbridge/status/black": (value) => value === 0,
  }, 15000);
  const initialFeedback = Object.fromEntries(
    [...feedbackReceived.entries()].filter(([address]) => expectedFeedbackAddresses.has(address)));
  if (initialFeedback["/pptbridge/status/source_name"] !== slideA) {
    throw new Error("OSC source_name does not match the automated slide source");
  }
  if (initialFeedback["/pptbridge/status/deck_path"] !== pptxPath) {
    throw new Error("OSC deck_path does not match the selected PowerPoint deck");
  }
  if (initialFeedback["/pptbridge/status/current"] !== 1 ||
      initialFeedback["/pptbridge/status/total"] < 2 ||
      initialFeedback["/pptbridge/status/loading"] !== 0 ||
      initialFeedback["/pptbridge/status/loaded"] !== 1 ||
      initialFeedback["/pptbridge/status/live"] !== 0 ||
      initialFeedback["/pptbridge/status/black"] !== 0 ||
      initialFeedback["/pptbridge/status/cue_current_checked"] !== 0 ||
      initialFeedback["/pptbridge/status/cue_next_checked"] !== 0 ||
      initialFeedback["/pptbridge/status/cue_checked_count"] !== 0) {
    throw new Error(
      `initial OSC loading/slide/live status is inconsistent: ${JSON.stringify(initialFeedback)}`);
  }
  for (const requiredTextAddress of [
    "/pptbridge/status/title",
    "/pptbridge/status/next_title",
    "/pptbridge/status/deck_name",
  ]) {
    if (typeof initialFeedback[requiredTextAddress] !== "string" ||
        initialFeedback[requiredTextAddress].length === 0) {
      throw new Error(`initial OSC text status is empty: ${requiredTextAddress}`);
    }
  }
  if (!Number.isInteger(initialFeedback["/pptbridge/status/timer"]) ||
      initialFeedback["/pptbridge/status/timer"] < 0) {
    throw new Error("initial OSC timer status is not a non-negative integer");
  }
  if (initialFeedback["/pptbridge/status/error"] !== "") {
    throw new Error(`initial OSC error status is not empty: ${initialFeedback["/pptbridge/status/error"]}`);
  }
  const totalSlides = initialFeedback["/pptbridge/status/total"];

  let feedbackMarker = feedbackSequence;
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_send_osc_status_btn",
  });
  await waitForFeedback(
    "/pptbridge/status/source_name",
    (value) => value === slideA,
    5000,
    feedbackMarker);

  await setProgramSceneAndConfirm(sceneA);
  activateObsForFocusedHotkeyTest();
  await sleep(500);
  await request("TriggerHotkeyByName", { hotkeyName: "pptbridge_native_next" });
  const slideAAfterHotkeyNext = await waitForScreenshot(
    slideA,
    "slide-a-after-hotkey-next.png",
    (candidate) => visuallyDifferent(candidate, slideAInitial));
  await request("TriggerHotkeyByName", { hotkeyName: "pptbridge_native_previous" });
  const slideAAfterHotkeyPrevious = await waitForScreenshot(
    slideA,
    "slide-a-after-hotkey-previous.png",
    (candidate) => visuallySame(candidate, slideAInitial));

  feedbackMarker = feedbackSequence;
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_last_btn",
  });
  await waitForFeedback(
    "/pptbridge/status/current",
    (value) => value === totalSlides,
    5000,
    feedbackMarker);
  const slideAAfterPropertyLast = await waitForScreenshot(
    slideA,
    "slide-a-after-property-last.png",
    (candidate) => visuallyDifferent(candidate, slideAInitial));

  feedbackMarker = feedbackSequence;
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_first_btn",
  });
  await waitForFeedback(
    "/pptbridge/status/current",
    (value) => value === 1,
    5000,
    feedbackMarker);
  const slideAAfterPropertyFirst = await waitForScreenshot(
    slideA,
    "slide-a-after-property-first.png",
    (candidate) => visuallySame(candidate, slideAInitial));

  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_cue_clear_checks_btn",
  });
  await waitForFeedback(
    "/pptbridge/status/cue_checked_count",
    (value) => value === 0,
    5000);

  feedbackMarker = feedbackSequence;
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_cue_toggle_current_btn",
  });
  await waitForFeedbackState({
    "/pptbridge/status/cue_current_checked": (value) => value === 1,
    "/pptbridge/status/cue_checked_count": (value) => value === 1,
  }, 5000, feedbackMarker);

  feedbackMarker = feedbackSequence;
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_cue_toggle_next_btn",
  });
  await waitForFeedbackState({
    "/pptbridge/status/cue_next_checked": (value) => value === 1,
    "/pptbridge/status/cue_checked_count": (value) => value === 2,
  }, 5000, feedbackMarker);

  const parsedDeckPath = path.parse(pptxPath);
  cueExportPath = path.join(parsedDeckPath.dir, `${parsedDeckPath.name}.pptbridge-cues.txt`);
  try {
    cueExportOriginal = await fs.readFile(cueExportPath);
  } catch (error) {
    if (error?.code !== "ENOENT") {
      throw error;
    }
  }
  await request("PressInputPropertiesButton", {
    inputName: presenterA,
    propertyName: "pptbridge_export_cue_list_btn",
  });
  const cueExport = await fs.readFile(cueExportPath, "utf8");
  if (!cueExport.includes("PPTBridge SK Cue List") ||
      !cueExport.includes("[x] > 1.") ||
      !cueExport.includes("[x] next 2.")) {
    throw new Error("exported cue list does not contain the checked current/next cues");
  }

  feedbackMarker = feedbackSequence;
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_cue_toggle_current_btn",
  });
  await waitForFeedbackState({
    "/pptbridge/status/cue_current_checked": (value) => value === 0,
    "/pptbridge/status/cue_next_checked": (value) => value === 1,
    "/pptbridge/status/cue_checked_count": (value) => value === 1,
  }, 5000, feedbackMarker);

  feedbackMarker = feedbackSequence;
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_cue_clear_checks_btn",
  });
  await waitForFeedbackState({
    "/pptbridge/status/cue_current_checked": (value) => value === 0,
    "/pptbridge/status/cue_next_checked": (value) => value === 0,
    "/pptbridge/status/cue_checked_count": (value) => value === 0,
  }, 5000, feedbackMarker);

  feedbackMarker = feedbackSequence;
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_reload_btn",
  });
  await waitForFeedback(
    "/pptbridge/status/loading",
    (value) => value === 1,
    5000,
    feedbackMarker);
  await waitForFeedbackState({
    "/pptbridge/status/loading": (value) => value === 0,
    "/pptbridge/status/loaded": (value) => value === 1,
    "/pptbridge/status/current": (value) => value === 1,
  }, 15000, feedbackMarker);
  const slideAAfterReload = await waitForScreenshot(
    slideA,
    "slide-a-after-reload.png",
    (candidate) => visuallySame(candidate, slideAInitial));

  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_follow_live_resize_btn",
  });
  const followResizeSettings = (await request("GetInputSettings", { inputName: slideA })).inputSettings;
  if (followResizeSettings.live_capture_resize_mode !== "fit_window") {
    throw new Error("Follow PowerPoint Window Size did not persist fit_window mode");
  }
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_lock_live_resize_btn",
  });
  const lockResizeSettings = (await request("GetInputSettings", { inputName: slideA })).inputSettings;
  if (lockResizeSettings.live_capture_resize_mode !== "lock_canvas") {
    throw new Error("Lock OBS Size Against PPT Resize did not persist lock_canvas mode");
  }

  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_operator_next_btn",
  });
  const slideAAfterOperatorNext = await waitForScreenshot(
    slideA,
    "slide-a-after-operator-next.png",
    (candidate) => visuallyDifferent(candidate, slideAInitial));
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_operator_previous_btn",
  });
  const slideAAfterOperatorPrevious = await waitForScreenshot(
    slideA,
    "slide-a-after-operator-previous.png",
    (candidate) => visuallySame(candidate, slideAInitial));

  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_next_btn",
  });
  const slideAAfterPropertyNext = await waitForScreenshot(
    slideA,
    "slide-a-after-property-next.png",
    (candidate) => visuallyDifferent(candidate, slideAInitial));
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_prev_btn",
  });
  const slideAAfterPropertyPrevious = await waitForScreenshot(
    slideA,
    "slide-a-after-property-previous.png",
    (candidate) => visuallySame(candidate, slideAInitial));

  await sendOsc("/pptbridge/next");
  const slideAAfterNext = await waitForScreenshot(
    slideA,
    "slide-a-after-next.png",
    (candidate) => visuallyDifferent(candidate, slideAInitial));
  const slideBWhileAActive = await screenshot(slideB, "slide-b-while-a-active.png");

  await setProgramSceneAndConfirm(sceneB);
  await sendOsc("/pptbridge/next");
  const slideBAfterNext = await waitForScreenshot(
    slideB,
    "slide-b-after-next.png",
    (candidate) => visuallyDifferent(candidate, slideBInitial));

  await request("SetInputSettings", {
    inputName: presenterA,
    inputSettings: {
      presenter_layout: "large_notes",
      presenter_preview_scale_mode: "crop",
      presenter_preview_scale_percent: 125,
      presenter_notes_font_size: 24,
      presenter_notes_zoom_percent: 130,
      presenter_background_color: 0x203040,
      presenter_background_image_path: presenterBackgroundImage,
      presenter_background_image_mode: "watermark",
      presenter_background_image_opacity_percent: 30,
      presenter_show_cue_list: true,
    },
    overlay: true,
  });
  await sleep(500);
  const presenterCustomized = await screenshot(presenterA, "presenter-a-customized.png");
  if (visuallySame(presenterInitial, presenterCustomized)) {
    throw new Error("presenter customization did not change the rendered output");
  }

  await setProgramSceneAndConfirm(sceneA);
  feedbackMarker = feedbackSequence;
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_operator_start_live_btn",
  });
  await waitForFeedback(
    "/pptbridge/status/live",
    (value) => value === 1,
    130000,
    feedbackMarker);
  const slideAManualLive = await waitForScreenshot(
    slideA,
    "slide-a-manual-live.png",
    (candidate) => candidate.bytes >= minimumLiveScreenshotBytes &&
      visuallyDifferent(candidate, slideAAfterNext),
    20000);

  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_reattach_live_btn",
  });
  const slideAAfterReattach = await waitForScreenshot(
    slideA,
    "slide-a-after-reattach.png",
    (candidate) => candidate.bytes >= minimumLiveScreenshotBytes &&
      visuallySame(candidate, slideAManualLive),
    15000);

  feedbackMarker = feedbackSequence;
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_operator_stop_live_btn",
  });
  await waitForFeedback(
    "/pptbridge/status/live",
    (value) => value === 0,
    10000,
    feedbackMarker);
  const slideAAfterManualStop = await waitForScreenshot(
    slideA,
    "slide-a-after-manual-stop.png",
    (candidate) => visuallySame(candidate, slideAInitial));

  feedbackMarker = feedbackSequence;
  await request("SetInputSettings", {
    inputName: slideA,
    inputSettings: {
      use_live_powerpoint: true,
      auto_start_live_powerpoint: true,
    },
    overlay: true,
  });
  await waitForFeedback(
    "/pptbridge/status/live",
    (value) => value === 1,
    20000,
    feedbackMarker);
  const slideAAutoStartedLive = await waitForScreenshot(
    slideA,
    "slide-a-auto-started-live.png",
    (candidate) => candidate.bytes >= minimumLiveScreenshotBytes &&
      visuallyDifferent(candidate, slideAAfterNext),
    20000);

  feedbackMarker = feedbackSequence;
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_stop_live_btn",
  });
  await waitForFeedback(
    "/pptbridge/status/live",
    (value) => value === 0,
    10000,
    feedbackMarker);
  const slideAAfterAutoStartStop = await waitForScreenshot(
    slideA,
    "slide-a-after-auto-start-stop.png",
    (candidate) => visuallySame(candidate, slideAInitial));
  await request("SetInputSettings", {
    inputName: slideA,
    inputSettings: { auto_start_live_powerpoint: false },
    overlay: true,
  });
  // OBS applies nested source-property updates through its UI event loop.
  // Do not press the manual Start button in the same turn and let the delayed
  // auto-start=false update cancel the newer explicit start request.
  await sleep(500);

  feedbackMarker = feedbackSequence;
  await request("PressInputPropertiesButton", {
    inputName: slideA,
    propertyName: "pptbridge_start_live_btn",
  });
  await waitForFeedback(
    "/pptbridge/status/live",
    (value) => value === 1,
    20000,
    feedbackMarker);
  const slideALive = await waitForScreenshot(
    slideA,
    "slide-a-live.png",
    (candidate) => candidate.bytes >= minimumLiveScreenshotBytes &&
      visuallyDifferent(candidate, slideAAfterNext),
    20000);

  feedbackMarker = feedbackSequence;
  await sendOsc("/pptbridge/last");
  await waitForFeedback(
    "/pptbridge/status/current",
    (value) => value === totalSlides,
    10000,
    feedbackMarker);
  // ScreenCaptureKit can trail the AppleScript status update briefly. Give
  // the live window one frame interval to catch up before exercising the
  // final-slide guard.
  await sleep(1000);
  const slideALiveLast = await screenshot(slideA, "slide-a-live-last.png", minimumLiveScreenshotBytes);
  await sendOsc("/pptbridge/next");
  await sleep(1000);
  if (feedbackReceived.get("/pptbridge/status/current") !== totalSlides ||
      feedbackReceived.get("/pptbridge/status/live") !== 1) {
    throw new Error("OSC Next after the final slide changed position or closed live mode");
  }
  // Animated media on the final slide is expected to change pixels while the
  // deck remains on the same slide. Status plus a valid live frame is the
  // reliable final-slide assertion; pixel equality would reject correct GIF
  // or video playback.
  const slideALiveAfterFinalNext = await screenshot(
    slideA,
    "slide-a-live-after-final-next.png",
    minimumLiveScreenshotBytes);
  const finalSlideGuardStable =
    feedbackReceived.get("/pptbridge/status/current") === totalSlides &&
    feedbackReceived.get("/pptbridge/status/live") === 1 &&
    slideALiveAfterFinalNext.bytes >= minimumLiveScreenshotBytes;

  feedbackMarker = feedbackSequence;
  await sendOsc("/pptbridge/previous");
  await waitForFeedback(
    "/pptbridge/status/current",
    (value) => value === totalSlides - 1,
    10000,
    feedbackMarker);
  const slideALiveAfterPrevious = await waitForScreenshot(
    slideA,
    "slide-a-live-after-previous.png",
    (candidate) => visuallyDifferent(candidate, slideALiveLast));

  feedbackMarker = feedbackSequence;
  await sendOsc("/pptbridge/black");
  await waitForFeedback(
    "/pptbridge/status/black",
    (value) => value === 1,
    5000,
    feedbackMarker);
  const slideALiveBlack = await waitForScreenshot(
    slideA,
    "slide-a-live-black.png",
    (candidate) => visuallyDifferent(candidate, slideALiveAfterPrevious),
    5000,
    100);
  feedbackMarker = feedbackSequence;
  await sendOsc("/pptbridge/black");
  await waitForFeedback(
    "/pptbridge/status/black",
    (value) => value === 0,
    5000,
    feedbackMarker);
  const slideALiveAfterBlack = await waitForScreenshot(
    slideA,
    "slide-a-live-after-black.png",
    (candidate) => visuallyDifferent(candidate, slideALiveBlack),
    15000,
    minimumLiveScreenshotBytes);

  let slideAAfterLiveStop = null;
  if (!keepSources) {
    await request("SetInputSettings", {
      inputName: slideA,
      inputSettings: {
        use_live_powerpoint: false,
        auto_start_live_powerpoint: false,
      },
      overlay: true,
    });
    slideAAfterLiveStop = await waitForScreenshot(
      slideA,
      "slide-a-after-live-stop.png",
      (candidate) => visuallyDifferent(candidate, slideALiveAfterPrevious));
  }

  console.log(JSON.stringify({
    obsVersion: version.obsVersion,
    obsWebSocketVersion: version.obsWebSocketVersion,
    scenes: [sceneA, sceneB],
    staticRouting: {
      hotkeyNextChanged: visuallyDifferent(slideAAfterHotkeyNext, slideAInitial),
      hotkeyPreviousRestored: visuallySame(slideAAfterHotkeyPrevious, slideAInitial),
      propertyLastChanged: visuallyDifferent(slideAAfterPropertyLast, slideAInitial),
      propertyFirstRestored: visuallySame(slideAAfterPropertyFirst, slideAInitial),
      reloadRestoredFirstSlide: visuallySame(slideAAfterReload, slideAInitial),
      operatorNextChanged: visuallyDifferent(slideAAfterOperatorNext, slideAInitial),
      operatorPreviousRestored: visuallySame(slideAAfterOperatorPrevious, slideAInitial),
      propertyNextChanged: visuallyDifferent(slideAAfterPropertyNext, slideAInitial),
      propertyPreviousRestored: visuallySame(slideAAfterPropertyPrevious, slideAInitial),
      slideAChanged: visuallyDifferent(slideAInitial, slideAAfterNext),
      slideBStayedStableWhileAActive: visuallySame(slideBInitial, slideBWhileAActive),
      slideBChanged: visuallyDifferent(slideBInitial, slideBAfterNext),
    },
    presenterCustomized: visuallyDifferent(presenterInitial, presenterCustomized),
    presenterBackgroundImage,
    cueListExported: cueExportPath,
    oscFeedback: {
      port: feedbackPort,
      addresses: [...expectedFeedbackAddresses].sort(),
      messageCount: feedbackHistory.length,
      initial: initialFeedback,
      cueToggleAndClearPassed: true,
      manualSendPassed: true,
    },
    resizeControlsPersisted: {
      follow: followResizeSettings.live_capture_resize_mode,
      lock: lockResizeSettings.live_capture_resize_mode,
    },
    manualPropertyLiveScreenshotBytes: slideAManualLive.bytes,
    reattachRestoredLiveOutput: visuallySame(slideAAfterReattach, slideAManualLive),
    manualPropertyStopReturnedStaticOutput: visuallySame(slideAAfterManualStop, slideAInitial),
    autoStartLiveScreenshotBytes: slideAAutoStartedLive.bytes,
    autoStartStopReturnedStaticOutput: visuallySame(slideAAfterAutoStartStop, slideAInitial),
    manualPropertyRestartScreenshotBytes: slideALive.bytes,
    liveScreenshotBytes: slideALive.bytes,
    finalSlideGuardStable,
    livePreviousChanged: visuallyDifferent(slideALiveAfterPrevious, slideALiveLast),
    blackScreenChanged: visuallyDifferent(slideALiveBlack, slideALiveAfterPrevious),
    blackScreenRestored:
      feedbackReceived.get("/pptbridge/status/black") === 0 &&
      visuallyDifferent(slideALiveAfterBlack, slideALiveBlack),
    blackScreenshotBytes: slideALiveBlack.bytes,
    explicitLiveStopReturnedStaticOutput: Boolean(slideAAfterLiveStop),
    visualDifferenceThreshold,
    closeOnShutdown,
    keptSourcesForShutdownTest: keepSources,
    screenshots: outputDirectory,
  }, null, 2));
} finally {
  if (!keepSources) {
    if (originalProgramScene) {
      await setProgramSceneAndConfirm(originalProgramScene).catch(() => {});
    }
    for (const inputName of createdInputs.reverse()) {
      await request("RemoveInput", { inputName }).catch(() => {});
    }
    for (const sceneName of createdScenes.reverse()) {
      await request("RemoveScene", { sceneName }).catch(() => {});
    }
  }
  if (cueExportPath) {
    if (cueExportOriginal !== null) {
      await fs.writeFile(cueExportPath, cueExportOriginal).catch(() => {});
    } else {
      await fs.rm(cueExportPath, { force: true }).catch(() => {});
    }
  }
  feedbackSocket?.close();
  socket.close();
}
