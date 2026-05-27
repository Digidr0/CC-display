// CC:Tweaked Dev Server — base-gui
// Запуск: node dev-server.js
// В игре: wget http://localhost:8000/startup.lua startup.lua

const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = 8000;
const ROOT = __dirname;

const MIME = {
  ".lua": "text/plain; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
  ".json": "application/json",
  ".js": "text/javascript",
  ".png": "image/png",
  ".jpg": "image/jpeg",
};

const server = http.createServer((req, res) => {
  // Нормализуем путь — защита от directory traversal
  let reqPath = req.url.split("?")[0];
  if (reqPath === "/") reqPath = "/index.html";

  const safePath = path.normalize(reqPath).replace(/^\.\.(\/|\\)/, "");
  const filePath = path.join(ROOT, safePath);

  // Проверяем, что файл внутри ROOT
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403);
    return res.end("Forbidden");
  }

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      return res.end("Not Found: " + reqPath);
    }

    const ext = path.extname(filePath);
    res.writeHead(200, { "Content-Type": MIME[ext] || "application/octet-stream" });
    res.end(data);
  });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log("========================================");
  console.log(" CC:Tweaked Dev Server — base-gui");
  console.log("========================================");
  console.log("");
  console.log(" Сервер запущен: http://localhost:" + PORT);
  console.log(" В игре используй:");
  console.log("   wget http://localhost:8000/startup.lua startup.lua");
  console.log("");
  console.log(" Нажми Ctrl+C для остановки.");
  console.log("========================================");
});
