#!/bin/bash
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== Heart Care Deployment ==="

# Install dependencies
apt-get update -y
apt-get install -y python3-pip python3-venv nginx git

# Clone the Heart Care app
git clone https://github.com/badretr/Heart-Care.git /opt/heartcare
cd /opt/heartcare

# Install Python dependencies
python3 -m venv /opt/venv
/opt/venv/bin/pip install --upgrade pip
/opt/venv/bin/pip install Django==2.2 Pillow gunicorn whitenoise

# Configure Django settings for production
cat >> /opt/heartcare/heartcare/settings.py << 'EOF'

# Production settings
ALLOWED_HOSTS = ['*']
STATIC_ROOT = '/opt/heartcare/staticfiles'

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'
EOF

# Collect static files
cd /opt/heartcare
/opt/venv/bin/python manage.py collectstatic --noinput 2>/dev/null || true
/opt/venv/bin/python manage.py migrate --run-syncdb 2>/dev/null || true

# Configure nginx on port 8000
cat > /etc/nginx/sites-available/default << 'ENDNGINX'
server {
    listen 8000 default_server;
    server_name _;

    location /static/ {
        alias /opt/heartcare/staticfiles/;
    }

    location /media/ {
        alias /opt/heartcare/media/;
    }

    location /health/ {
        access_log off;
        return 200 "OK";
        add_header Content-Type text/plain;
    }

    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
ENDNGINX

# Start gunicorn as a service
cat > /etc/systemd/system/heartcare.service << 'ENDSVC'
[Unit]
Description=Heart Care Django App
After=network.target

[Service]
User=www-data
WorkingDirectory=/opt/heartcare
ExecStart=/opt/venv/bin/gunicorn --workers 3 --bind 127.0.0.1:8001 heartcare.wsgi:application
Restart=always

[Install]
WantedBy=multi-user.target
ENDSVC

# Fix permissions
chown -R www-data:www-data /opt/heartcare

# Start services
systemctl daemon-reload
systemctl enable heartcare
systemctl start heartcare
systemctl enable nginx
systemctl restart nginx

echo "=== Heart Care deployed successfully ==="
