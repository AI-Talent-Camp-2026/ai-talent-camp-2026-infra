#cloud-config

# =============================================================================
# Package Management
# =============================================================================
package_update: true
package_upgrade: true

packages:
  - docker.io
  - docker-compose
  - iptables-persistent
  - netfilter-persistent
  - curl
  - wget
  - htop
  - jq
  - unzip

# =============================================================================
# Users Configuration
# =============================================================================
users:
  - name: ${jump_user}
    groups: [sudo, docker]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${jump_public_key}

# =============================================================================
# File Configuration
# =============================================================================
write_files:
  # Traefik configuration
  - path: /opt/traefik/traefik.yml
    permissions: '0644'
    content: |
      ${indent(6, traefik_config)}

  # Traefik dynamic configuration directory marker
  - path: /opt/traefik/dynamic/.gitkeep
    permissions: '0644'
    content: ""

  # Xray configuration
  - path: /opt/xray/config.json
    permissions: '0644'
    content: |
      ${indent(6, xray_config)}

  # Docker Compose for services
  - path: /opt/docker-compose.yml
    permissions: '0644'
    content: |
      version: '3.8'
      
      services:
        traefik:
          image: traefik:v3.0
          container_name: traefik
          restart: unless-stopped
          ports:
            - "80:80"
            - "443:443"
          volumes:
            - /opt/traefik/traefik.yml:/etc/traefik/traefik.yml:ro
            - /opt/traefik/dynamic:/etc/traefik/dynamic:ro
            - /opt/traefik/acme:/acme
          networks:
            - proxy
      
        xray:
          image: teddysun/xray:latest
          container_name: xray
          restart: unless-stopped
          network_mode: host
          volumes:
            - /opt/xray/config.json:/etc/xray/config.json:ro
          cap_add:
            - NET_ADMIN
      
      networks:
        proxy:
          name: proxy
          driver: bridge

  # Sysctl configuration for IP forwarding
  - path: /etc/sysctl.d/99-ip-forward.conf
    permissions: '0644'
    content: |
      net.ipv4.ip_forward = 1
      net.ipv4.conf.all.forwarding = 1

  # SSH server configuration
  - path: /etc/ssh/sshd_config.d/99-jump-host.conf
    permissions: '0644'
    content: |
      AllowTcpForwarding yes
      GatewayPorts no
      PermitTunnel no
      X11Forwarding no
      PasswordAuthentication no
      PubkeyAuthentication yes

# =============================================================================
# Run Commands
# =============================================================================
runcmd:
  # Enable IP forwarding
  - sysctl -p /etc/sysctl.d/99-ip-forward.conf

  # Configure NAT (masquerade) for private subnet
  - iptables -t nat -A POSTROUTING -s ${private_subnet_cidr} -o eth0 -j MASQUERADE
  - iptables -A FORWARD -i eth0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
  - iptables -A FORWARD -s ${private_subnet_cidr} -o eth0 -j ACCEPT
  
  # Save iptables rules
  - netfilter-persistent save

  # Enable and start Docker
  - systemctl enable docker
  - systemctl start docker

  # Create necessary directories
  - mkdir -p /opt/traefik/acme
  - mkdir -p /opt/traefik/dynamic

  # Start services with Docker Compose
  - cd /opt && docker-compose up -d

  # Restart SSH to apply new config
  - systemctl restart sshd
