sudo -iu edge bash -lc '
mkdir -p $HOME/.cloudflared
podman pull cloudflare/cloudflared:latest
podman run -d --name cloudflared --restart=always --net=host \
  -v $HOME/.cloudflared:/etc/cloudflared:Z \
  cloudflare/cloudflared:latest tunnel --no-autoupdate run --token <TOKEN>
podman logs --tail=50 cloudflared
'
