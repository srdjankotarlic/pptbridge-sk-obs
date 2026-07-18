#!/usr/bin/env node

import crypto from "node:crypto";
import dgram from "node:dgram";

const [pptxPath] = process.argv.slice(2);
if (!pptxPath) {
  console.error("usage: obs-audio-runtime-smoke.mjs /path/to/deck-with-embedded-audio.pptx");
  process.exit(2);
}
const referenceAudioPath = process.env.PPTBRIDGE_TEST_REFERENCE_AUDIO || "";
const recordOutput = process.env.PPTBRIDGE_TEST_RECORD_OUTPUT === "1";
const audioEnabled = process.env.PPTBRIDGE_TEST_AUDIO_ENABLED !== "0";
const audioGainDb = Number(process.env.PPTBRIDGE_TEST_AUDIO_GAIN_DB || "0");
const holdMilliseconds = Number(process.env.PPTBRIDGE_TEST_HOLD_MS || "0");
const expectSignal = process.env.PPTBRIDGE_TEST_EXPECT_SIGNAL
  ? process.env.PPTBRIDGE_TEST_EXPECT_SIGNAL === "1"
  : audioEnabled;
const obsWebSocketPassword = process.env.PPTBRIDGE_QA_OBS_PASSWORD || "";

if (!Number.isFinite(audioGainDb) || audioGainDb < -60 || audioGainDb > 24) {
  console.error("PPTBRIDGE_TEST_AUDIO_GAIN_DB must be between -60 and 24");
  process.exit(2);
}
if (!Number.isFinite(holdMilliseconds) || holdMilliseconds < 0 || holdMilliseconds > 60000) {
  console.error("PPTBRIDGE_TEST_HOLD_MS must be between 0 and 60000");
  process.exit(2);
}

const socket = new WebSocket("ws://127.0.0.1:4455");
const pending = new Map();
const meterSamples = [];
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
    const identifyData = { rpcVersion: 1, eventSubscriptions: 1 << 16 };
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
    socket.send(JSON.stringify({
      op: 1,
      d: identifyData,
    }));
    return;
  }
  if (message.op === 2) {
    clearTimeout(identifyTimeout);
    identifiedResolve();
    return;
  }
  if (message.op === 5 && message.d.eventType === "InputVolumeMeters") {
    meterSamples.push(...(message.d.eventData?.inputs || []));
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
  const requestId = `pptbridge-audio-qa-${++requestNumber}`;
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

async function setProgramSceneAndConfirm(sceneName) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    await request("SetCurrentProgramScene", { sceneName });
    await sleep(150);
    const current = await request("GetCurrentProgramScene");
    if (current.currentProgramSceneName === sceneName) {
      // Let an active Studio Mode transition finish before the next scene mutation.
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

function sampleHasSignal(sample) {
  const dbChannels = sample?.inputLevelsDb || [];
  if (dbChannels.some((channel) =>
      Array.isArray(channel) && channel.some((level) => Number.isFinite(level) && level > -90))) {
    return true;
  }

  const multiplierChannels = sample?.inputLevelsMul || [];
  return multiplierChannels.some((channel) =>
    Array.isArray(channel) && channel.some((level) => Number.isFinite(level) && level > 0.00003));
}

async function waitForSignal(inputNames, timeoutMilliseconds) {
  const expected = new Set(inputNames);
  const deadline = Date.now() + timeoutMilliseconds;
  while (Date.now() < deadline) {
    const match = meterSamples.find((sample) =>
      expected.has(sample.inputName) && sampleHasSignal(sample));
    if (match) {
      return match;
    }
    await sleep(100);
  }
  return null;
}

await identified;
const suffix = Date.now().toString(36);
const sceneName = `PPTBridge Audio QA ${suffix}`;
const inputName = `PPTBridge Audio Source ${suffix}`;
const referenceInputName = `PPTBridge Audio Reference ${suffix}`;
let originalProgramScene = "";
let recordingStarted = false;
let recordingOutputPath = "";

try {
  originalProgramScene = (await request("GetCurrentProgramScene")).currentProgramSceneName;
  await request("CreateScene", { sceneName });
  await setProgramSceneAndConfirm(sceneName);

  if (referenceAudioPath) {
    await request("CreateInput", {
      sceneName,
      inputName: referenceInputName,
      inputKind: "ffmpeg_source",
      inputSettings: {
        is_local_file: true,
        local_file: referenceAudioPath,
        looping: false,
        restart_on_activate: true,
        close_when_inactive: false,
      },
      sceneItemEnabled: true,
    });
    meterSamples.length = 0;
    await request("TriggerMediaInputAction", {
      inputName: referenceInputName,
      mediaAction: "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART",
    });
    const referenceSignal = await waitForSignal([referenceInputName], 6000);
    if (!referenceSignal) {
      const observedInputs = [...new Set(meterSamples.map((sample) => sample.inputName).filter(Boolean))];
      throw new Error(
        `reference OBS Media Source produced no meter signal; ` +
        `observed inputs=${JSON.stringify(observedInputs)}`);
    }
    await request("RemoveInput", { inputName: referenceInputName });
  }

  await request("CreateInput", {
    sceneName,
    inputName,
    inputKind: "pptbridge_slide_source",
    inputSettings: {
      pptx_path: pptxPath,
      use_live_powerpoint: false,
      audio_enabled: audioEnabled,
      audio_gain_db: audioGainDb,
    },
    sceneItemEnabled: true,
  });
  await sleep(2000);
  meterSamples.length = 0;
  if (recordOutput) {
    const recordStatus = await request("GetRecordStatus");
    if (recordStatus.outputActive) {
      throw new Error("OBS recording is already active; refusing to alter an existing recording");
    }
    await request("StartRecord");
    recordingStarted = true;
    await sleep(500);
  }
  await sendOsc("/pptbridge/first");
  await sendOsc("/pptbridge/next");
  const mediaTriggeredAt = Date.now();

  const childPrefix = `${inputName} Media `;
  if (expectSignal) {
    await waitForSignal([inputName], 6000);
  } else {
    await sleep(4000);
  }
  if (recordingStarted) {
    const remainingRecordTime = 4000 - (Date.now() - mediaTriggeredAt);
    if (remainingRecordTime > 0) {
      await sleep(remainingRecordTime);
    }
    const stopped = await request("StopRecord");
    recordingStarted = false;
    recordingOutputPath = stopped.outputPath || "";
  }
  const matchingSamples = meterSamples.filter((sample) => sample.inputName === inputName);
  const childSamples = meterSamples.filter((sample) => sample.inputName?.startsWith(childPrefix));
  const signalDetected = matchingSamples.some(sampleHasSignal);
  if (expectSignal && !signalDetected) {
    const observedInputs = [...new Set(meterSamples.map((sample) => sample.inputName).filter(Boolean))];
    const lastMatchingSample = matchingSamples.at(-1) || null;
    throw new Error(
      `no audible meter signal received for ${inputName}; ` +
      `observed inputs=${JSON.stringify(observedInputs)}; ` +
      `last matching sample=${JSON.stringify(lastMatchingSample)}; ` +
      `recording=${JSON.stringify(recordingOutputPath)}`);
  }
  if (!expectSignal && signalDetected) {
    throw new Error(
      `unexpected audible parent meter signal received for ${inputName}; ` +
      `last matching sample=${JSON.stringify(matchingSamples.at(-1) || null)}; ` +
      `recording=${JSON.stringify(recordingOutputPath)}`);
  }
  if (holdMilliseconds > 0) {
    await sleep(holdMilliseconds);
  }
  console.log(JSON.stringify({
    inputName,
    audioEnabled,
    audioGainDb,
    expectedSignal: expectSignal,
    matchingSamples: matchingSamples.length,
    childSamples: childSamples.length,
    signalDetected,
    recordingOutputPath,
  }, null, 2));
} finally {
  if (recordingStarted) {
    const stopped = await request("StopRecord").catch(() => ({}));
    recordingOutputPath ||= stopped.outputPath || "";
  }
  if (originalProgramScene) {
    await setProgramSceneAndConfirm(originalProgramScene).catch(() => {});
  }
  await request("RemoveInput", { inputName: referenceInputName }).catch(() => {});
  await request("RemoveInput", { inputName }).catch(() => {});
  await request("RemoveScene", { sceneName }).catch(() => {});
  socket.close();
}
