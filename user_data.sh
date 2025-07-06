#!/bin/bash

# Log all output for debugging
exec > >(tee /var/log/opensearch-proxy-setup.log) 2>&1
echo "Starting OpenSearch proxy setup at $(date)"

# Update system
yum update -y

# Install Nginx using amazon-linux-extras
amazon-linux-extras install -y nginx1

# Create SSL certificates directory
mkdir -p /etc/nginx/ssl

# Generate self-signed SSL certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/cert.key \
    -out /etc/nginx/ssl/cert.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

# Set proper permissions for SSL files
chmod 600 /etc/nginx/ssl/cert.key
chmod 644 /etc/nginx/ssl/cert.crt

# Create Nginx configuration
cat > /etc/nginx/conf.d/opensearch-proxy.conf << 'EOF'
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name localhost;

    ssl_certificate /etc/nginx/ssl/cert.crt;
    ssl_certificate_key /etc/nginx/ssl/cert.key;
    ssl_session_cache builtin:1000 shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Proxy settings for OpenSearch
    location / {
        proxy_pass https://${opensearch_endpoint};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Important for WebSocket connections (if needed)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeout settings
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # SSL verification for backend
        proxy_ssl_verify off;
        proxy_ssl_server_name on;
    }

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name _;
    return 301 https://$host$request_uri;
}
EOF

# Test Nginx configuration
nginx -t

# Start and enable Nginx
systemctl start nginx
systemctl enable nginx

# Check if Nginx is running
systemctl status nginx

echo "OpenSearch proxy setup completed at $(date)"
echo "Nginx status:"
systemctl is-active nginx
echo "OpenSearch endpoint: ${opensearch_endpoint}"
