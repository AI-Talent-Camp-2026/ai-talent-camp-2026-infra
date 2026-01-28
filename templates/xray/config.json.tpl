{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "tproxy-in",
      "port": 12345,
      "protocol": "dokodemo-door",
      "settings": {
        "network": "tcp,udp",
        "followRedirect": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"],
        "routeOnly": false
      },
      "streamSettings": {
        "sockopt": {
          "tproxy": "tproxy"
        }
      }
    },
    {
      "tag": "dns-in",
      "port": 5353,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "8.8.8.8",
        "port": 53,
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [
%{ if vless_server != "" ~}
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${vless_server}",
            "port": ${vless_port},
            "users": [
              {
                "id": "${vless_uuid}",
                "flow": "xtls-rprx-vision",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "${vless_fingerprint}",
          "serverName": "${vless_sni}",
          "publicKey": "${vless_public_key}",
          "shortId": "${vless_short_id}",
          "spiderX": ""
        }
      }
    },
%{ endif ~}
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {
        "response": {
          "type": "http"
        }
      }
    },
    {
      "tag": "dns-out",
      "protocol": "dns"
    }
  ],
  "dns": {
    "servers": [
      {
        "address": "8.8.8.8",
        "port": 53,
        "domains": ["geosite:geolocation-!cn"]
      },
      {
        "address": "1.1.1.1",
        "port": 53
      }
    ]
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "domainMatcher": "hybrid",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["dns-in"],
        "outboundTag": "dns-out"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      },
%{ if vless_server != "" && vless_server_ip != "" ~}
      {
        "type": "field",
        "ip": ["${vless_server_ip}"],
        "outboundTag": "direct"
      },
%{ endif ~}
%{ if vless_server != "" ~}
      {
        "type": "field",
        "domain": [
          "geosite:category-ai-!cn",
          "geosite:notion",
          "geosite:youtube",
          "geosite:instagram",
          "geosite:tiktok",
          "geosite:linkedin",
          "geosite:telegram"
        ],
        "outboundTag": "proxy"
      },
%{ endif ~}
      {
        "type": "field",
        "ip": ["0.0.0.0/0", "::/0"],
        "outboundTag": "direct"
      }
    ]
  }
}
