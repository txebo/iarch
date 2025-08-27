dos2unix snet.sh
chmod +x snet.sh
sudo ./snet.sh                 # autodetecta: prueba 192.168.68.x y luego 192.168.1.x
sudo PROFILE=A ./snet.sh       # forzar 192.168.68.x
sudo PROFILE=B ./snet.sh       # forzar 192.168.1.x
# Puedes pasar SMB_USER/SMB_PASS por entorno si no quieres prompts
