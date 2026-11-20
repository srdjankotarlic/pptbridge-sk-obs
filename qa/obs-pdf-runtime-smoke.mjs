#!/usr/bin/env node
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { writeFile } from "node:fs/promises";
import { setTimeout as delay } from "node:timers/promises";

const [pdfPath] = process.argv.slice(2);
assert(pdfPath, "usage: obs-pdf-runtime-smoke.mjs /absolute/path/to/three-page.pdf");
const password = process.env.PPTBRIDGE_QA_OBS_PASSWORD;
const socket = new WebSocket("ws://127.0.0.1:4455");
const pending = new Map();
let requestNumber = 0;
const hash = (value) => createHash("sha256").update(value).digest("base64");

const identified = new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error("OBS WebSocket did not identify")), 10000);
  socket.addEventListener("error", () => reject(new Error("OBS WebSocket connection failed")), { once: true });
  socket.addEventListener("message", ({ data }) => {
    const message = JSON.parse(data);
    if (message.op === 0) {
      const challenge = message.d.authentication;
      const authentication = challenge ? hash(hash(password + challenge.salt) + challenge.challenge) : undefined;
      socket.send(JSON.stringify({ op: 1, d: { rpcVersion: 1, authentication } }));
    } else if (message.op === 2) {
      clearTimeout(timeout);
      resolve();
    } else if (message.op === 7) {
      const response = pending.get(message.d.requestId);
      pending.delete(message.d.requestId);
      response?.(message.d);
    }
  });
});

function request(requestType, requestData) {
  return new Promise((resolve, reject) => {
    const requestId = String(++requestNumber);
    const timeout = setTimeout(() => {
      pending.delete(requestId);
      reject(new Error(`${requestType} timed out`));
    }, 10000);
    pending.set(requestId, ({ requestStatus, responseData }) => {
      clearTimeout(timeout);
      if (requestStatus.result) resolve(responseData);
      else reject(new Error(`${requestType}: ${requestStatus.comment ?? requestStatus.code}`));
    });
    socket.send(JSON.stringify({ op: 6, d: { requestId, requestType, requestData } }));
  });
}

async function screenshot(sourceName) {
  const response = await request("GetSourceScreenshot", {
    sourceName, imageFormat: "png", imageWidth: 640, imageHeight: 360,
  });
  assert(response.imageData.startsWith("data:image/png;base64,"));
  const bytes = Buffer.from(response.imageData.split(",")[1], "base64");
  assert(bytes.length > 2000, "OBS returned an unexpectedly empty frame");
  return bytes;
}

async function waitForChangedFrame(sourceName, reference) {
  for (let attempt = 0; attempt < 40; attempt += 1) {
    await delay(200);
    const frame = await screenshot(sourceName);
    if (!frame.equals(reference)) return frame;
  }
  throw new Error("PDF navigation did not change the OBS frame");
}

let original;
let testSceneCreated = false;
const testScene = "PPTBridge PDF runtime smoke";
const slide = "PPTBridge PDF Slide QA";
const presenter = "PPTBridge PDF Presenter QA";
try {
  await identified;
  const { obsVersion } = await request("GetVersion");
  original = (await request("GetCurrentProgramScene")).currentProgramSceneName;
  await request("CreateScene", { sceneName: testScene });
  testSceneCreated = true;
  for (const [inputName, inputKind] of [[slide, "pptbridge_slide_source"], [presenter, "pptbridge_presenter_source"]]) {
    await request("CreateInput", {
      sceneName: testScene, inputName, inputKind,
      inputSettings: { pptx_path: pdfPath, use_live_powerpoint: false },
      sceneItemEnabled: true,
    });
  }
  await request("SetCurrentProgramScene", { sceneName: testScene });
  await delay(1500);

  const first = await screenshot(slide);
  await request("PressInputPropertiesButton", { inputName: slide, propertyName: "pptbridge_next_btn" });
  const second = await waitForChangedFrame(slide, first);
  await request("PressInputPropertiesButton", { inputName: slide, propertyName: "pptbridge_next_btn" });
  const last = await waitForChangedFrame(slide, second);
  assert(!last.equals(first), "Expected three different rendered PDF pages");
  await request("PressInputPropertiesButton", { inputName: slide, propertyName: "pptbridge_next_btn" });
  await delay(400);
  assert((await screenshot(slide)).equals(last), "Next on the final PDF page changed the output");
  const confidence = await screenshot(presenter);
  assert(!confidence.equals(last), "Presenter should have its own rendered layout");
  await Promise.all([
    writeFile("pdf-page-one.png", first), writeFile("pdf-page-two.png", second),
    writeFile("pdf-page-three.png", last), writeFile("pdf-presenter.png", confidence),
  ]);
  console.log(`OBS ${obsVersion}: PDF Slide, Presenter, three pages and final-page guard passed.`);
} finally {
  if (testSceneCreated) {
    await request("SetCurrentProgramScene", { sceneName: original }).catch(console.warn);
    await request("RemoveScene", { sceneName: testScene }).catch(console.warn);
  }
  socket.close();
}
