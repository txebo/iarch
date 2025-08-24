# START HERE (ASCII)
Order (run as Administrator on Windows for .ps1):
1) scripts/windows/kit_selfcheck.ps1
2) scripts/windows/print_env.ps1 -ConfigPath ../../config/homelab.env
3) scripts/windows/host_restorepoint.ps1  (optional)
4) scripts/windows/preflight.ps1 -ConfigPath ../../config/homelab.env
5) scripts/windows/hyperv_setup_network.ps1 -ConfigPath ../../config/homelab.env
6) scripts/windows/setup_windows_host.ps1 -ConfigPath ../../config/homelab.env
7) scripts/windows/verify_state.ps1 -ConfigPath ../../config/homelab.env
Then on VMs:
- txedgevm: scripts/edge/edge_traefik_install.sh
- txbkendvm: scripts/backend/backend_prepare.sh
Cloudflare API (optional):
- scripts/cloudflare/cf_apply.sh then cf_verify.sh
Logs are written to: d:\hyperv\homelab\logs
