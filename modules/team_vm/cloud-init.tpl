#cloud-config

# =============================================================================
# Package Management
# =============================================================================
package_update: true
package_upgrade: true

packages:
  - docker.io
  - docker-compose
  - nginx
  - certbot
  - python3-certbot-nginx
  - curl
  - wget
  - htop
  - jq
  - git
  - unzip
  - make

# =============================================================================
# Users Configuration
# =============================================================================
users:
  - name: ${team_user}
    groups: [sudo, docker]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
%{ for key in public_keys ~}
      - ${key}
%{ endfor ~}

# =============================================================================
# File Configuration
# =============================================================================
write_files:
  # Default nginx configuration
  - path: /etc/nginx/sites-available/default
    permissions: '0644'
    content: |
      server {
          listen 80 default_server;
          listen [::]:80 default_server;
          
          server_name team${team_id}.${domain};
          
          root /var/www/html;
          index index.html index.htm;
          
          location / {
              try_files $uri $uri/ =404;
          }
          
          # Health check endpoint
          location /health {
              return 200 'OK';
              add_header Content-Type text/plain;
          }
      }

  # Welcome page
  - path: /var/www/html/index.html
    permissions: '0644'
    content: |
      <!DOCTYPE html>
      <html lang="en">
      <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Team ${team_id} - AI Camp</title>
          <style>
              body {
                  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                  max-width: 800px;
                  margin: 0 auto;
                  padding: 2rem;
                  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                  min-height: 100vh;
                  color: white;
              }
              .container {
                  background: rgba(255,255,255,0.1);
                  border-radius: 16px;
                  padding: 2rem;
                  backdrop-filter: blur(10px);
              }
              h1 { margin-bottom: 0.5rem; }
              code {
                  background: rgba(0,0,0,0.2);
                  padding: 0.2rem 0.5rem;
                  border-radius: 4px;
                  font-family: monospace;
              }
              .info { margin-top: 2rem; }
          </style>
      </head>
      <body>
          <div class="container">
              <h1>Welcome, Team ${team_id}!</h1>
              <p>Your AI Camp server is ready.</p>
              <div class="info">
                  <h3>Quick Start:</h3>
                  <ul>
                      <li>Domain: <code>team${team_id}.${domain}</code></li>
                      <li>Web root: <code>/var/www/html</code></li>
                      <li>Docker is ready to use</li>
                  </ul>
              </div>
          </div>
      </body>
      </html>

  # Docker daemon configuration
  - path: /etc/docker/daemon.json
    permissions: '0644'
    content: |
      {
        "log-driver": "json-file",
        "log-opts": {
          "max-size": "10m",
          "max-file": "3"
        }
      }

# =============================================================================
# Run Commands
# =============================================================================
runcmd:
  # Enable and start Docker
  - systemctl enable docker
  - systemctl start docker

  # Enable and start nginx
  - systemctl enable nginx
  - systemctl start nginx

  # Set correct permissions
  - chown -R ${team_user}:${team_user} /var/www/html
  
  # Create workspace directory for the team
  - mkdir -p /home/${team_user}/workspace
  - chown -R ${team_user}:${team_user} /home/${team_user}/workspace

  # Add team user to docker group (ensure it's applied)
  - usermod -aG docker ${team_user}
