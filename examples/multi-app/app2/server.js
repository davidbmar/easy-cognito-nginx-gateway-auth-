const express = require('express');
const app = express();
const PORT = 3002;

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
    <title>Analytics - App 2</title>
    <style>
        body { font-family: sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%); color: white; padding: 30px; border-radius: 8px; margin-bottom: 30px; }
        .card { background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px; border-left: 4px solid #11998e; }
        .nav { margin: 20px 0; }
        .btn { display: inline-block; padding: 10px 20px; background: #11998e; color: white; text-decoration: none; border-radius: 6px; margin-right: 10px; }
        .btn:hover { background: #0f8073; }
        .metric { display: inline-block; background: white; padding: 15px 25px; border-radius: 6px; margin: 10px 10px 10px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .metric-value { font-size: 2em; font-weight: bold; color: #11998e; }
        .metric-label { color: #666; font-size: 0.9em; margin-top: 5px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>📈 Analytics (App 2)</h1>
        <p>Authenticated user: ${req.user.email}</p>
    </div>

    <div class="card">
        <h3>Real-time Analytics Dashboard</h3>
        <p>This is App 2 running on port ${PORT}.</p>
        <p><strong>Session shared across all apps!</strong> You didn't need to login again.</p>
    </div>

    <div class="card">
        <h3>Key Metrics</h3>
        <div class="metric">
            <div class="metric-value">1,234</div>
            <div class="metric-label">Page Views</div>
        </div>
        <div class="metric">
            <div class="metric-value">567</div>
            <div class="metric-label">Visitors</div>
        </div>
        <div class="metric">
            <div class="metric-value">89%</div>
            <div class="metric-label">Engagement</div>
        </div>
    </div>

    <div class="card">
        <h3>User Information</h3>
        <p>Email: <code>${req.user.email}</code></p>
        <p>Username: <code>${req.user.username}</code></p>
    </div>

    <div class="nav">
        <h3>Navigate to other apps:</h3>
        <a href="/app1/" class="btn">📊 Dashboard (App 1)</a>
        <a href="/app3/" class="btn">⚙️ Settings (App 3)</a>
        <a href="/logout" class="btn" style="background: #dc3545;">Logout</a>
    </div>

    <div class="card">
        <h4>Same authentication, different app:</h4>
        <ul>
            <li>✓ No separate login required</li>
            <li>✓ Same session cookie works for all apps</li>
            <li>✓ Single logout affects all apps</li>
            <li>✓ Centralized user management in Cognito</li>
        </ul>
    </div>
</body>
</html>
    `);
});

// API endpoint
app.get('/api/metrics', (req, res) => {
    res.json({
        app: 'Analytics',
        port: PORT,
        user: req.user.email,
        metrics: {
            pageViews: 1234,
            visitors: 567,
            engagementRate: 0.89,
            avgSessionDuration: 245
        }
    });
});

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', app: 'app2', port: PORT });
});

app.listen(PORT, () => {
    console.log(`App 2 (Analytics) listening on port ${PORT}`);
});
