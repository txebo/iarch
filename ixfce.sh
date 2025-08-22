sudo pacman -Syu --needed \
  xorg-server mesa \
  xfce4 xfce4-goodies \
  lightdm lightdm-gtk-greeter \
  gvfs gvfs-smb thunar-volman thunar-archive-plugin file-roller \
  pipewire wireplumber pipewire-pulse pavucontrol alsa-utils \
  noto-fonts ttf-dejavu xdg-user-dirs

# activar el display manager
sudo systemctl enable lightdm

# (opcional) crea carpetas de usuario (Documentos, Descargas, etc.)
xdg-user-dirs-update
