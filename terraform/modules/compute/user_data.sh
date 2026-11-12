#!/bin/bash
set -e

exec > >(tee /var/log/user-data.log) 2>&1

echo "=== Heart Care - Starting deployment ==="
echo "Environment: ${environment}"

# Update and install nginx
apt-get update -y
apt-get install -y nginx

# Create page with hostname (as per cahier des charges section 21)
cat > /var/www/html/index.html << EOF
<html>
<head><title>Heart Care - ${environment}</title></head>
<body>
<h1>Terraform Cloud Project - Heart Care</h1>
<p>Environment: ${environment}</p>
<p>Host: $(hostname)</p>
<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")</p>
</body>
</html>
EOF

# Health check endpoint
mkdir -p /var/www/html/health
echo "OK" > /var/www/html/health/index.html

# Configure nginx on port 8000
cat > /etc/nginx/sites-available/default << 'ENDNGINX'
server {
    listen 8000 default_server;
    server_name _;
    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location /health/ {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }
}
ENDNGINX

# Start nginx
systemctl enable nginx
systemctl restart nginx

echo "=== Deployment complete - nginx running on port 8000 ==="
