const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const HTTP_PORT = 8000;
const HTTPS_PORT = 8001;

// MIME types dictionary for static file serving
const MIME_TYPES = {
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'application/javascript',
    '.json': 'application/json',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.wasm': 'application/wasm',
    '.pck': 'application/octet-stream',
    '.apple-touch-icon.png': 'image/png'
};

// Static file server logic
function serveStaticFile(req, res) {
    // Strip query parameters
    const urlPath = req.url.split('?')[0];
    let filePath = path.join(__dirname, urlPath === '/' ? 'index.html' : urlPath);
    
    // Normalize path to prevent directory traversal
    filePath = path.normalize(filePath);
    if (!filePath.startsWith(__dirname)) {
        res.writeHead(403, { 'Content-Type': 'text/plain' });
        res.end('Forbidden');
        return;
    }

    const ext = path.extname(filePath);
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    fs.readFile(filePath, (err, content) => {
        if (err) {
            if (err.code === 'ENOENT') {
                res.writeHead(404, { 'Content-Type': 'text/plain' });
                res.end('404 Not Found');
            } else {
                res.writeHead(500, { 'Content-Type': 'text/plain' });
                res.end(`Server Error: ${err.code}`);
            }
        } else {
            // Send headers, including Cross-Origin Isolation for Godot 4 Web assembly
            res.writeHead(200, {
                'Content-Type': contentType,
                'Cross-Origin-Opener-Policy': 'same-origin',
                'Cross-Origin-Embedder-Policy': 'require-corp',
                'Access-Control-Allow-Origin': '*'
            });
            res.end(content, 'utf-8');
        }
    });
}

// 1. Create HTTP server on Port 8000
const httpServer = http.createServer(serveStaticFile);

// 2. Create HTTPS server on Port 8001
let httpsServer;
try {
    const options = {
        key: fs.readFileSync(path.join(__dirname, 'key.pem')),
        cert: fs.readFileSync(path.join(__dirname, 'cert.pem'))
    };
    httpsServer = https.createServer(options, serveStaticFile);
} catch (e) {
    console.error("Warning: Failed to load SSL certificates. HTTPS server will not start. Details:", e.message);
}

// 3. Create WebSocket Server with noServer option (shared upgrade handler)
const wss = new WebSocketServer({ noServer: true });

wss.on('connection', (ws) => {
    console.log('Client connected to WebSocket server.');

    ws.on('message', (message) => {
        // Broadcast message to all other connected clients
        wss.clients.forEach((client) => {
            if (client !== ws && client.readyState === 1) { // 1 = OPEN
                client.send(message.toString());
            }
        });
    });

    ws.on('close', () => {
        console.log('Client disconnected.');
    });
});

// Upgrade handler to share WebSocket across both ports
function handleUpgrade(request, socket, head) {
    wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit('connection', ws, request);
    });
}

httpServer.on('upgrade', handleUpgrade);

httpServer.listen(HTTP_PORT, () => {
    console.log(`HTTP Server running at http://localhost:${HTTP_PORT}`);
    console.log(`WebSocket server active on ws://localhost:${HTTP_PORT}`);
});

if (httpsServer) {
    httpsServer.on('upgrade', handleUpgrade);
    httpsServer.listen(HTTPS_PORT, () => {
        console.log(`HTTPS Server running at https://localhost:${HTTPS_PORT}`);
        console.log(`Secure WebSocket server active on wss://localhost:${HTTPS_PORT}`);
    });
}
