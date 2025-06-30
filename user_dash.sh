#!/bin/bash

# Update the system
yum update -y

# Install Nginx
amazon-linux-extras install nginx1 -y

# Enable and start Nginx
systemctl enable nginx
systemctl start nginx

# Generate self-signed SSL certificate
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/cert.key \
    -out /etc/nginx/ssl/cert.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

# Create Nginx configuration for OpenSearch proxy
cat > /etc/nginx/conf.d/opensearch.conf << 'EOF'
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name localhost;

    ssl_certificate /etc/nginx/ssl/cert.crt;
    ssl_certificate_key /etc/nginx/ssl/cert.key;
    ssl_session_cache builtin:1000 shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!eNULL:!EXPORT:!CAMELLIA:!DES:!MD5:!PSK:!RC4;
    ssl_prefer_server_ciphers on;

    # Proxy settings for OpenSearch
    location / {
        proxy_pass https://${opensearch_endpoint};
        proxy_ssl_verify off;
        proxy_ssl_server_name on;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Handle WebSocket connections for real-time features
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Increase timeout values
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name localhost;
    return 301 https://$server_name$request_uri;
}
EOF

# Test Nginx configuration
nginx -t

# Restart Nginx to apply configuration
systemctl restart nginx

# Set up log rotation for Nginx
cat > /etc/logrotate.d/nginx << 'EOF'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 640 nginx adm
    sharedscripts
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            kill -USR1 `cat /var/run/nginx.pid`
        fi
    endscript
}
EOF

# Install useful tools for troubleshooting
yum install -y curl wget htop

# Create a simple status page
cat > /var/log/opensearch-proxy-setup.log << 'EOF'
OpenSearch Nginx Proxy Setup Complete
=====================================
- Nginx installed and configured
- SSL certificate generated
- Proxy configuration applied
- Service started and enabled

Access the OpenSearch Dashboard at:
https://[EC2_PUBLIC_IP]/_dashboards

To view logs:
- Nginx access logs: /var/log/nginx/access.log
- Nginx error logs: /var/log/nginx/error.log
- Setup log: /var/log/opensearch-proxy-setup.log
EOF

echo "$(date): OpenSearch Nginx proxy setup completed successfully" >> /var/log/opensearch-proxy-setup.log
