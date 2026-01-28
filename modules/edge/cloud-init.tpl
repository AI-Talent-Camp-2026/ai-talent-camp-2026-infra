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
%{ for key in team_jump_keys ~}
      - ${key}
%{ endfor ~}

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
            - NET_RAW
      
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

  # ==========================================================================
  # NAT Configuration (masquerade for private subnet)
  # ==========================================================================
  - iptables -t nat -A POSTROUTING -s ${private_subnet_cidr} -o eth0 -j MASQUERADE
  - iptables -A FORWARD -i eth0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
  - iptables -A FORWARD -s ${private_subnet_cidr} -o eth0 -j ACCEPT

  # ==========================================================================
  # TPROXY Configuration for transparent proxy through Xray
  # ==========================================================================
  
  # Policy routing for TPROXY - route marked packets to loopback
  - ip rule add fwmark 1 table 100
  - ip route add local 0.0.0.0/0 dev lo table 100

  # Create XRAY chain in mangle table
  - iptables -t mangle -N XRAY

  # Exclude private networks from TPROXY (don't proxy local traffic)
  - iptables -t mangle -A XRAY -d 10.0.0.0/8 -j RETURN
  - iptables -t mangle -A XRAY -d 172.16.0.0/12 -j RETURN
  - iptables -t mangle -A XRAY -d 192.168.0.0/16 -j RETURN
  - iptables -t mangle -A XRAY -d 127.0.0.0/8 -j RETURN

  # Exclude VLESS server IP to avoid routing loop
%{ if vless_server_ip != "" ~}
  - iptables -t mangle -A XRAY -d ${vless_server_ip} -j RETURN
%{ endif ~}

  # TPROXY rules - redirect TCP and UDP to Xray on port 12345
  - iptables -t mangle -A XRAY -p tcp -j TPROXY --on-port 12345 --tproxy-mark 1
  - iptables -t mangle -A XRAY -p udp -j TPROXY --on-port 12345 --tproxy-mark 1

  # Apply XRAY chain to traffic from private subnet
  - iptables -t mangle -A PREROUTING -s ${private_subnet_cidr} -j XRAY

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
