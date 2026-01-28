#cloud-config

# =============================================================================
# AI Camp Team VM - Minimal Configuration
# =============================================================================
# Teams will install their own software (docker, nginx, etc.) as needed.
# =============================================================================

package_update: true
package_upgrade: true

# =============================================================================
# Users Configuration
# =============================================================================
users:
  - name: ${team_user}
    groups: [sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
%{ for key in public_keys ~}
      - ${key}
%{ endfor ~}

# =============================================================================
# Run Commands
# =============================================================================
runcmd:
  # Create workspace directory for the team
  - mkdir -p /home/${team_user}/workspace
  - chown -R ${team_user}:${team_user} /home/${team_user}/workspace
