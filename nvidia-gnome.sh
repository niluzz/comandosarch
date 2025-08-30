#!/bin/bash
set -e

echo ">>> Atualizando pacotes do sistema..."
sudo pacman -Syu --noconfirm

echo ">>> Instalando pacotes oficiais..."
sudo pacman -S --noconfirm \
  git zsh base-devel file-roller p7zip unrar unzip pacman-contrib \
  firefox-i18n-pt-br discord telegram-desktop fwupd showtime papers \
  amf-headers power-profiles-daemon transmission-gtk \
  ttf-firacode-nerd ttf-dejavu-nerd ttf-hack-nerd inter-font \
  jellyfin-ffmpeg jellyfin-server jellyfin-web goverlay \
  mangohud ntfs-3g nvidia-utils lib32-nvidia-utils \
  nvidia-settings opencl-nvidia nvidia-utils \
  libva-nvidia-driver ibus

echo ">>> Habilitando serviços..."
sudo systemctl enable --now fwupd-refresh.timer
sudo systemctl enable --now bluetooth.service
sudo systemctl enable --now jellyfin.service

echo ">>> Instalando Paru (AUR helper)..."
if ! command -v paru &>/dev/null; then
  git clone https://aur.archlinux.org/paru.git /tmp/paru
  cd /tmp/paru
  makepkg -si --noconfirm
  cd -
else
  echo "Paru já está instalado."
fi

echo ">>> Instalando pacotes do AUR com paru..."
paru -S --noconfirm google-chrome onlyoffice-bin extension-manager coolercontrol

echo ">>> Verificando e ajustando /etc/mkinitcpio.conf..."
MKINIT_FILE="/etc/mkinitcpio.conf"
if ! grep -q "nvidia" "$MKINIT_FILE"; then
  sudo sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' "$MKINIT_FILE"
  echo "Parâmetro 'nvidia' adicionado em MODULES."
else
  echo "Parâmetro 'nvidia' já existe em MODULES."
fi
sudo mkinitcpio -P

echo ">>> Verificando e ajustando /etc/kernel/cmdline..."
CMDLINE_FILE="/etc/kernel/cmdline"
for param in quiet splash iommu=pt; do
  if ! grep -qw "$param" "$CMDLINE_FILE"; then
    echo "Adicionando parâmetro: $param"
    sudo sed -i "s|\$| $param|" "$CMDLINE_FILE"
  else
    echo "Parâmetro '$param' já existe no kernel cmdline."
  fi
done
sudo mkinitcpio -P

echo ">>> Instalação concluída com sucesso! 🚀"
