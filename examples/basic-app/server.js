const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3001;

// Middleware
app.use(express.json());
app.use(express.static('public'));
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Middleware to extract user info from headers
app.use((req, res, next) => {
    // These headers are set by nginx after oauth2-proxy validates authentication
    req.user = {
        email: req.headers['x-user-email'] || 'anonymous',
        username: req.headers['x-user'] || 'anonymous',
        groups: req.headers['x-user-groups'] || ''
    };
    next();
});

// Logging middleware
app.use((req, res, next) => {
    const timestamp = new Date().toISOString();
    console.log(`${timestamp} - ${req.user.email} - ${req.method} ${req.path}`);
    next();
});

// Routes

// Home page - shows authenticated user info
app.get('/', (req, res) => {
    res.render('index', {
        user: req.user,
        timestamp: new Date().toISOString()
    });
});

// API endpoint - returns user info as JSON
app.get('/api/user', (req, res) => {
    res.json({
        email: req.user.email,
        username: req.user.username,
        groups: req.user.groups
    });
});

// API endpoint - shows all request headers (for debugging)
app.get('/api/headers', (req, res) => {
    res.json({
        headers: req.headers,
        user: req.user
    });
});

// Logout - redirects to oauth2-proxy logout
app.get('/logout', (req, res) => {
    console.log(`User ${req.user.email} logging out`);
    res.redirect('/oauth2/sign_out');
});

// Health check endpoint (no auth required - configure nginx to skip auth for this)
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString()
    });
});

// Dashboard example - could check for specific roles
app.get('/dashboard', (req, res) => {
    res.render('dashboard', {
        user: req.user
    });
});

// Admin page example - could check for admin role
app.get('/admin', (req, res) => {
    // Check if user has admin role
    const groups = req.user.groups.split(',').map(g => g.trim());
    if (!groups.includes('admin')) {
        return res.status(403).render('error', {
            message: 'Access Denied',
            detail: 'You must be an administrator to access this page.'
        });
    }

    res.render('admin', {
        user: req.user
    });
});

// 404 handler
app.use((req, res) => {
    res.status(404).render('error', {
        message: 'Page Not Found',
        detail: `The page ${req.path} does not exist.`
    });
});

// Error handler
app.use((err, req, res, next) => {
    console.error(`Error: ${err.message}`);
    res.status(500).render('error', {
        message: 'Server Error',
        detail: err.message
    });
});

// Start server
app.listen(PORT, () => {
    console.log(`Basic app example listening on port ${PORT}`);
    console.log(`This app expects to be behind nginx + oauth2-proxy`);
    console.log(`User information will be in X-User-Email and X-User headers`);
});
