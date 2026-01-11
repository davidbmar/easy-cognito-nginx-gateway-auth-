const express = require('express');
const app = express();
const PORT = 3003;

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
    <title>Settings - App 3</title>
    <style>
        body { font-family: sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        .header { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); color: white; padding: 30px; border-radius: 8px; margin-bottom: 30px; }
        .card { background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px; border-left: 4px solid #f093fb; }
        .nav { margin: 20px 0; }
        .btn { display: inline-block; padding: 10px 20px; background: #f093fb; color: white; text-decoration: none; border-radius: 6px; margin-right: 10px; }
        .btn:hover { background: #e882ea; }
        .setting { background: white; padding: 15px; border-radius: 6px; margin: 10px 0; display: flex; justify-content: space-between; align-items: center; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .toggle { background: #ddd; width: 50px; height: 26px; border-radius: 13px; position: relative; cursor: pointer; }
        .toggle.on { background: #f093fb; }
        .toggle::after { content: ''; position: absolute; width: 20px; height: 20px; border-radius: 50%; background: white; top: 3px; left: 3px; transition: 0.3s; }
        .toggle.on::after { left: 27px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>⚙️ Settings (App 3)</h1>
        <p>Authenticated user: ${req.user.email}</p>
    </div>

    <div class="card">
        <h3>User Settings</h3>
        <p>This is App 3 running on port ${PORT}.</p>
        <p><strong>Three apps, one authentication!</strong> All protected by the same gateway.</p>
    </div>

    <div class="card">
        <h3>Account Settings</h3>
        <div class="setting">
            <div>
                <strong>Email Notifications</strong>
                <div style="color: #666; font-size: 0.9em;">Receive updates via email</div>
            </div>
            <div class="toggle on"></div>
        </div>
        <div class="setting">
            <div>
                <strong>Two-Factor Authentication</strong>
                <div style="color: #666; font-size: 0.9em;">Add extra security layer</div>
            </div>
            <div class="toggle"></div>
        </div>
        <div class="setting">
            <div>
                <strong>Data Sharing</strong>
                <div style="color: #666; font-size: 0.9em;">Share analytics data</div>
            </div>
            <div class="toggle on"></div>
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
        <a href="/app2/" class="btn">📈 Analytics (App 2)</a>
        <a href="/logout" class="btn" style="background: #dc3545;">Logout</a>
    </div>

    <div class="card">
        <h4>Multi-app benefits:</h4>
        <ul>
            <li>✓ Separate apps for different concerns (Dashboard, Analytics, Settings)</li>
            <li>✓ Each app can be developed independently</li>
            <li>✓ Can use different technologies (Node, Python, Go, etc.)</li>
            <li>✓ Deploy and scale apps independently</li>
            <li>✓ One authentication system for all</li>
        </ul>
    </div>
</body>
</html>
    `);
});

// API endpoint
app.get('/api/settings', (req, res) => {
    res.json({
        app: 'Settings',
        port: PORT,
        user: req.user.email,
        settings: {
            emailNotifications: true,
            twoFactorAuth: false,
            dataSharing: true,
            theme: 'light'
        }
    });
});

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', app: 'app3', port: PORT });
});

app.listen(PORT, () => {
    console.log(`App 3 (Settings) listening on port ${PORT}`);
});
