// A small Creality-like printer for testing the PrintHub spike harness.
//
//   ws://127.0.0.1:9999     status/control, subprotocol "wsslicer"
//   http://127.0.0.1:8080   MJPEG snapshot/stream
//   http://127.0.0.1:8000   fake WebRTC signalling endpoint
//
// It is deliberately opinionated about the protocol so the client has to do
// the right handshake and heartbeat. No auth, like the real thing.

import http from "node:http";
import fs from "node:fs";
import { WebSocketServer } from "ws";

const frame = fs.readFileSync(new URL("./frame.jpg", import.meta.url));
const startedAt = Date.now();
const PRINTER_PORT = Number(process.env.MOCK_PRINTER_PORT ?? 9999);
const CAMERA_PORT = Number(process.env.MOCK_CAMERA_PORT ?? 18080);
const WEBRTC_PORT = Number(process.env.MOCK_WEBRTC_PORT ?? 18000);

const state = {
  state: 1,
  printFileName: "/usr/data/printer_data/gcodes/Benchy.gcode",
  printProgress: 0,
  printJobTime: 0,
  printLeftTime: 5400,
  layer: 0,
  TotalLayer: 200,
  nozzleTemp: 215.0,
  targetNozzleTemp: 215.0,
  bedTemp0: 60.0,
  targetBedTemp: 60.0,
  boxTemp: 38.0,
  targetBoxTemp: 40.0,
  lightSw: 1,
  cfsConnect: 1,
  materialStatus: 0,
  deviceState: 0,
  withSelfTest: 0,
  model: "K2 Plus",
  modelVersion: "F008",
  hostname: "mock-k2",
  webrtcSupport: 1,
  err: { errcode: 0 },
  boxsInfo: {
    materialType: "PLA",
    boxs: [
      { id: 0, material: "PLA", color: "#D9534F", remain: 82 },
      { id: 1, material: "PLA", color: "#2FB7A8", remain: 64 },
      { id: 2, material: "PETG", color: "#4A90D9", remain: 41 },
      { id: 3, material: "", color: "", remain: 0 }
    ]
  }
};

function log(...args) {
  console.log(new Date().toISOString().slice(11, 19), ...args);
}

function fullState() {
  return { ...state };
}

function printProgressState() {
  return {
    state: state.state,
    printFileName: state.printFileName,
    printProgress: state.printProgress,
    printJobTime: state.printJobTime,
    printLeftTime: state.printLeftTime,
    layer: state.layer,
    TotalLayer: state.TotalLayer
  };
}

// ---------------------------------------------------------------------------
// MJPEG camera
// ---------------------------------------------------------------------------

const camera = http.createServer((req, res) => {
  const url = new URL(req.url ?? "/", "http://localhost");

  if (url.pathname === "/" && url.searchParams.get("action") === "snapshot") {
    res.writeHead(200, {
      "Content-Type": "image/jpeg",
      "Content-Length": frame.length,
      "Cache-Control": "no-cache"
    });
    res.end(frame);
    return;
  }

  if (url.pathname === "/" && url.searchParams.get("action") === "stream") {
    res.writeHead(200, {
      "Content-Type": "multipart/x-mixed-replace; boundary=frame",
      "Cache-Control": "no-cache",
      Connection: "keep-alive"
    });

    const timer = setInterval(() => {
      res.write("--frame\r\n");
      res.write("Content-Type: image/jpeg\r\n");
      res.write(`Content-Length: ${frame.length}\r\n\r\n`);
      res.write(frame);
      res.write("\r\n");
    }, 100);

    req.on("close", () => clearInterval(timer));
    return;
  }

  res.writeHead(200, { "Content-Type": "text/html" });
  res.end("<h1>PrintHub mock camera</h1><p>Use /?action=stream or /?action=snapshot.</p>");
});

// ---------------------------------------------------------------------------
// Fake WebRTC signalling endpoint (enough for the probe)
// ---------------------------------------------------------------------------

const webrtc = http.createServer((req, res) => {
  if (req.method === "POST") {
    res.writeHead(501, { "Content-Type": "text/plain" });
    res.end("mock printer does not implement WebRTC yet");
    return;
  }

  if (req.url === "/call/webrtc_local" || req.url === "/call") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end("{}");
    return;
  }

  res.writeHead(404, { "Content-Type": "text/plain" });
  res.end("not found");
});

// ---------------------------------------------------------------------------
// Printer WebSocket
// ---------------------------------------------------------------------------

const wss = new WebSocketServer({
  port: PRINTER_PORT,
  handleProtocols: (protocols) => {
    if (protocols.has("wsslicer")) return "wsslicer";
    log("rejected client without wsslicer subprotocol:", [...protocols]);
    return false;
  }
});

wss.on("connection", (ws, request) => {
  log("client connected", request.socket.remoteAddress);

  const send = (value) => {
    if (ws.readyState === ws.OPEN) {
      ws.send(JSON.stringify(value));
    }
  };

  send({ ModeCode: "heart_beat" });

  const heartbeat = setInterval(() => {
    send({ ModeCode: "heart_beat" });
  }, 5000);

  ws.on("message", (data) => {
    const text = data.toString();
    if (text === "ok") return;

    let message;
    try {
      message = JSON.parse(text);
    } catch {
      log("non-JSON message:", text.slice(0, 80));
      return;
    }

    if (message.method === "get") {
      const params = message.params ?? {};
      if (params.ReqPrinterPara) send(fullState());
      if (params.reqPrintObjects) send(printProgressState());
      if (params.boxsInfo) send({ boxsInfo: state.boxsInfo, cfsConnect: state.cfsConnect });
      if (params.reqGcodeFile) {
        send({
          retGcodeFileInfo2: [
            { name: "Benchy.gcode", size: 1234567, time: 5400 },
            { name: "CalibrationCube.gcode", size: 234567, time: 1200 }
          ]
        });
      }
      return;
    }

    if (message.method === "set") {
      const params = message.params ?? {};
      log("set", JSON.stringify(params));

      if (params.pause !== undefined) {
        state.state = Number(params.pause) === 1 ? 5 : 1;
        send(fullState());
      }
      if (params.stop !== undefined) {
        state.state = 4;
        state.printProgress = 0;
        state.printLeftTime = 0;
        send(fullState());
      }
      if (params.lightSw !== undefined) {
        state.lightSw = Number(params.lightSw) === 1 ? 1 : 0;
        send(fullState());
      }
      if (params.nozzleTempControl !== undefined) {
        state.targetNozzleTemp = Number(params.nozzleTempControl);
        send(fullState());
      }
      if (params.bedTempControl !== undefined) {
        state.targetBedTemp = Number(params.bedTempControl.val);
        send(fullState());
      }
      if (params.boxTempControl !== undefined) {
        state.targetBoxTemp = Number(params.boxTempControl);
        send(fullState());
      }
      if (params.opGcodeFile !== undefined) {
        state.printFileName = String(params.opGcodeFile);
        state.state = 1;
        state.printProgress = 0;
        send(fullState());
      }
      return;
    }

    log("unknown message", message);
  });

  ws.on("close", () => {
    clearInterval(heartbeat);
    log("client disconnected");
  });
});

// ---------------------------------------------------------------------------
// Simulated print progress
// ---------------------------------------------------------------------------

setInterval(() => {
  if (state.state !== 1) return;

  state.printProgress = Math.min(100, state.printProgress + 0.25);
  state.printJobTime += 2;
  state.printLeftTime = Math.max(0, 5400 - state.printJobTime);
  state.layer = Math.min(state.TotalLayer, state.layer + 1);
  state.nozzleTemp = 215 + Math.sin(Date.now() / 5000);
  state.boxTemp = 38 + Math.sin(Date.now() / 9000);

  if (state.printProgress >= 100) {
    state.state = 2;
    state.printLeftTime = 0;
    log("mock print complete");
  }

  for (const client of wss.clients) {
    if (client.readyState === client.OPEN) {
      client.send(JSON.stringify(printProgressState()));
    }
  }
}, 2000);

camera.listen(CAMERA_PORT, "0.0.0.0", () => log(`camera on http://127.0.0.1:${CAMERA_PORT}`));
webrtc.listen(WEBRTC_PORT, "0.0.0.0", () => log(`fake WebRTC on http://127.0.0.1:${WEBRTC_PORT}`));
log(`printer WebSocket on ws://127.0.0.1:${PRINTER_PORT} (wsslicer)`);
log(`mock uptime origin ${startedAt}`);
