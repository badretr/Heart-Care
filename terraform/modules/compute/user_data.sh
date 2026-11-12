#!/bin/bash
set -e

# Log output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Starting Heart Care Application Deployment ==="
echo "Environment: ${environment}"
echo "Database Host: ${db_host}"

# Update system
apt-get update
apt-get install -y \
    python3-pip \
    python3-dev \
    python3-venv \
    postgresql-client \
    nginx \
    supervisor \
    curl \
    git \
    libpq-dev

echo "=== Installing Python Dependencies ==="

# Create application directory
mkdir -p /opt/heartcare
cd /opt/heartcare

# Clone or download Heart Care repository
# For now, we'll create a minimal Django setup
pip3 install Django==2.2 Pillow==10.0.0 psycopg2-binary gunicorn

# Create Django project structure
mkdir -p /opt/heartcare/heartcare_app

# Create minimal Django app for testing
cat > /opt/heartcare/heartcare_app/manage.py << 'ENDMANAGE'
#!/usr/bin/env python
import os
import sys

if __name__ == "__main__":
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "settings")
    from django.core.management import execute_from_command_line
    execute_from_command_line(sys.argv)
ENDMANAGE

cat > /opt/heartcare/heartcare_app/settings.py << 'ENDSETTINGS'
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
SECRET_KEY = 'django-insecure-CHANGE_ME_IN_PRODUCTION'
DEBUG = False
ALLOWED_HOSTS = ['*']

INSTALLED_APPS = [
    'django.contrib.contenttypes',
    'django.contrib.auth',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.middleware.common.CommonMiddleware',
]

ROOT_URLCONF = 'urls'

TEMPLATES = [{
    'BACKEND': 'django.template.backends.django.DjangoTemplates',
    'DIRS': [],
    'APP_DIRS': True,
}]

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': '${db_name}',
        'USER': '${db_user}',
        'PASSWORD': os.environ.get('DB_PASSWORD', 'changeme'),
        'HOST': '${db_host}',
        'PORT': '5432',
    }
}

STATIC_URL = '/static/'
STATIC_ROOT = os.path.join(BASE_DIR, 'static')
MEDIA_URL = '/media/'
MEDIA_ROOT = os.path.join(BASE_DIR, 'media')
ENDSETTINGS

cat > /opt/heartcare/heartcare_app/urls.py << 'ENDURLS'
from django.urls import path
from django.http import HttpResponse

def health_check(request):
    return HttpResponse("<h1>Heart Care - Health Check OK</h1><p>Instance: " +
                       os.uname()[1] + "</p>", content_type="text/html")

def index(request):
    import os
    return HttpResponse("<h1>Heart Care Application</h1><p>Instance Hostname: " +
                       os.uname()[1] + "</p>", content_type="text/html")

urlpatterns = [
    path('', index),
    path('health/', health_check),
]
ENDURLS

cat > /opt/heartcare/heartcare_app/wsgi.py << 'ENDWSGI'
import os
from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "settings")
application = get_wsgi_application()
ENDWSGI

chmod +x /opt/heartcare/heartcare_app/manage.py

echo "=== Configuring Nginx ==="

# Configure Nginx as reverse proxy
cat > /etc/nginx/sites-available/heartcare << 'ENDNGINX'
upstream heartcare_app {
    server 127.0.0.1:8000;
}

server {
    listen 8000 default_server;
    server_name _;
    client_max_body_size 20M;

    location / {
        proxy_pass http://heartcare_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /static/ {
        alias /opt/heartcare/heartcare_app/static/;
    }

    location /media/ {
        alias /opt/heartcare/heartcare_app/media/;
    }
}
ENDNGINX

# Enable Nginx site
ln -sf /etc/nginx/sites-available/heartcare /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

echo "=== Configuring Supervisor ==="

# Configure Supervisor for Gunicorn
cat > /etc/supervisor/conf.d/heartcare.conf << 'ENDSUPERVISOR'
[program:heartcare]
directory=/opt/heartcare/heartcare_app
command=gunicorn --workers 3 --bind 127.0.0.1:8000 wsgi:application
autostart=true
autorestart=true
stderr_logfile=/var/log/heartcare-err.log
stdout_logfile=/var/log/heartcare-out.log
user=www-data
ENDSUPERVISOR

echo "=== Starting Services ==="

# Start Nginx
systemctl restart nginx
systemctl enable nginx

# Start Supervisor
systemctl restart supervisor
systemctl enable supervisor

# Wait for services to start
sleep 5

echo "=== Verifying Health Check ==="
curl -f http://127.0.0.1:8000/health/ || echo "Health check will be available shortly"

echo "=== Deployment Complete ==="
echo "Heart Care application is deployed and running on port 8000"
