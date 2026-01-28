# =============================================================================
# Traefik Dynamic Configuration Template
# AI Camp Infrastructure - Team Routing
# =============================================================================

# TCP Routers for TLS Passthrough
tcp:
  routers:
%{ for team_id, team_config in teams ~}
    team${team_id}-router:
      entryPoints:
        - websecure
      rule: "HostSNI(`team${team_id}.${domain}`)"
      service: team${team_id}-service
      tls:
        passthrough: true
%{ endfor ~}

  services:
%{ for team_id, team_config in teams ~}
    team${team_id}-service:
      loadBalancer:
        servers:
          - address: "${team_config.private_ip}:443"
%{ endfor ~}

# HTTP Routers for non-TLS traffic
http:
  routers:
%{ for team_id, team_config in teams ~}
    team${team_id}-http:
      entryPoints:
        - web
      rule: "Host(`team${team_id}.${domain}`)"
      service: team${team_id}-http-service
%{ endfor ~}

    # Default router for unmatched hosts
    catch-all:
      entryPoints:
        - web
      rule: "PathPrefix(`/`)"
      service: default-service
      priority: 1

  services:
%{ for team_id, team_config in teams ~}
    team${team_id}-http-service:
      loadBalancer:
        servers:
          - url: "http://${team_config.private_ip}:80"
%{ endfor ~}

    default-service:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:8080"

  # Middlewares
  middlewares:
    secure-headers:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        forceSTSHeader: true
        customFrameOptionsValue: "SAMEORIGIN"
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: "strict-origin-when-cross-origin"

    rate-limit:
      rateLimit:
        average: 100
        burst: 50
