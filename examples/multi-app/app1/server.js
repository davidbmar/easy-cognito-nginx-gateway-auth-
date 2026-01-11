const express = require('express');
const app = express();
const PORT = 3001;

app.use(express.json());

// Extract user info from headers
app.use((req, res, next) => {
    req.user = {
        email: req.headers['x-user-email'] || 'anonymous',
        username: req.headers['x-user'] || 'anonymous'
    };
    console.log(`${new Date().toISOString()} - ${req.user.email} - ${req.method} ${req.path}`);
    next();
});

// Home page
app.get('/', (req, res) => {
    res.send(`
<!DOCTYPE html>
<html>
<head>
    <title>Dashboard - App 1</title>
    <style>
        body { font-family: sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 8px; margin-bottom: 30px; }
        .card { background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px; border-left: 4px solid #667eea; }
        .nav { margin: 20px 0; }
        .btn { display: inline-block; padding: 10px 20px; background: #667eea; color: white; text-decoration: none; border-radius: 6px; margin-right: 10px; }
        .btn:hover { background: #5568d3; }
    </style>
</head>
<body>
    <div class="header">
        <h1>📊 Dashboard (App 1)</h1>
        <p>Authenticated user: ${req.user.email}</p>
    </div>

    <div class="card">
        <h3>Welcome to the Dashboard!</h3>
        <p>This is App 1 running on port ${PORT}.</p>
        <p><strong>No authentication code in this app!</strong> User info comes from nginx headers.</p>
    </div>

    <div class="card">
        <h3>User Information</h3>
        <p>Email: <code>${req.user.email}</code></p>
        <p>Username: <code>${req.user.username}</code></p>
    </div>

    <div class="nav">
        <h3>Navigate to other apps:</h3>
        <a href="/app2/" class="btn">📈 Analytics (App 2)</a>
        <a href="/app3/" class="btn">⚙️ Settings (App 3)</a>
        <a href="/logout" class="btn" style="background: #dc3545;">Logout</a>
    </div>

    <div class="card">
        <h4>How this works:</h4>
        <ul>
            <li>All apps share the same authentication</li>
            <li>No need to login again when switching apps</li>
            <li>Each app just reads the X-User-Email header</li>
            <li>nginx + oauth2-proxy handle all authentication</li>
        </ul>
    </div>
</body>
</html>
    `);
});

// API endpoint
app.get('/api/stats', (req, res) => {
    res.json({
        app: 'Dashboard',
        port: PORT,
        user: req.user.email,
        stats: {
            activeUsers: 42,
            todayLogins: 127,
            serverUptime: process.uptime()
        }
    });
});

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', app: 'app1', port: PORT });
});

app.listen(PORT, () => {
    console.log(`App 1 (Dashboard) listening on port ${PORT}`);
});
