# =============================================================================
# AI Camp SSH Config for ${team_user}
# =============================================================================
# Usage:
#   1. Copy this folder to ~/.ssh/ai-camp/
#   2. chmod 600 ~/.ssh/ai-camp/*-key
#   3. ssh -F ~/.ssh/ai-camp/ssh-config ${team_user}
# Alternatively, you can copy content of this file into your ~/.ssh/config
# And use it as a regular SSH config.
#   - ssh ${team_user}
# =============================================================================

Host bastion
  HostName bastion.${domain}
  User ${jump_user}
  IdentityFile ~/.ssh/ai-camp/${team_user}-jump-key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host ${team_user}
  HostName ${team_private_ip}
  User ${team_user}
  ProxyJump bastion
  IdentityFile ~/.ssh/ai-camp/${team_user}-key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
