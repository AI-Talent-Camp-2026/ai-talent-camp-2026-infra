# =============================================================================
# Traefik Dynamic Configuration Template
# AI Talent Camp Infrastructure - Team Routing
# =============================================================================
#
# How to add custom domains:
# 1. User creates issue requesting custom domain
# 2. Admin adds domain to the team's router rule below
# 3. User configures DNS (CNAME or A record)
# 4. User updates Nginx on their VM to handle the domain
# 5. User obtains SSL certificate for the domain
#
# Example for custom domain:
#   Change: rule: "HostSNI(`team01.camp.aitalenthub.ru`)"
#   To:     rule: "HostSNI(`team01.camp.aitalenthub.ru`) || HostSNI(`app.mydomain.com`)"
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
    
    # Wildcard router for unmatched HTTPS (optional custom domains)
    # Note: Custom domains should be added explicitly above for proper routing
    # This is a fallback that will reject unmatched SNI with error
    wildcard-https:
      entryPoints:
        - websecure
      rule: "HostSNI(`*`)"
      service: default-service
      priority: 1
      tls:
        passthrough: true

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
