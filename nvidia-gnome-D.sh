#!/bin/bash
set -e

echo ">>> Atualizando pacotes do sistema..."
sudo pacman -Syu --noconfirm

echo ">>> Instalando pacotes oficiais..."
sudo pacman -S --needed --noconfirm \
  # Ferramentas básicas
  git zsh base-devel pacman-contrib \
  file-roller p7zip unrar unzip \
  fwupd power-profiles-daemon mesa-utils \
  ibus dialect showtime papers \
  \
  # Navegadores e comunicação
  firefox-i18n-pt-br discord telegram-desktop \
  \
  # Mídia e multimídia
  ffmpeg \
  gstreamer gst-plugins-base gst-plugins-good \
  gst-plugins-bad gst-plugins-ugly gst-libav \
  libdvdread libdvdnav libdvdcss \
  \
  # Drive NVIDIA
  nvidia-utils nvidia-settings lib32-nvidia-utils \
  \
  # Jellyfin
  jellyfin-ffmpeg jellyfin-server jellyfin-web\
  \
  # Fontes
  ttf-firacode-nerd ttf-dejavu-nerd ttf-hack-nerd \
  inter-font noto-fonts noto-fonts-emoji \
  \
  # Outros
  qbittorrent newsflash amf-headers openrgb \
  handbrake

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
paru -S --needed --noconfirm \
  google-chrome onlyoffice-bin extension-manager \
  auto-cpufreq mangojuice phinger-cursors \
  protonplus

echo ">>> Verificando e ajustando /etc/mkinitcpio.conf..."
MKINIT_FILE="/etc/mkinitcpio.conf"
if ! grep -E "^MODULES=.*nvidia" "$MKINIT_FILE"; then
  sudo sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' "$MKINIT_FILE"
  echo "Parâmetros 'nvidia*' adicionados em MODULES."
else
  echo "Parâmetros NVIDIA já estão em MODULES."
fi
sudo mkinitcpio -P

echo ">>> Verificando e ajustando /etc/kernel/cmdline..."
CMDLINE_FILE="/etc/kernel/cmdline"
for param in quiet splash nvidia-drm.modeset=1 nvidia-drm.fbdev=1 iommu=pt; do
  if ! grep -qw "$param" "$CMDLINE_FILE"; then
    sudo sed -i "1s|\$| $param|" "$CMDLINE_FILE"
    echo "Parâmetro '$param' adicionado ao kernel cmdline."
  fi
done
sudo mkinitcpio -P

echo ">>> Habilitando serviços..."
sudo systemctl enable --now fwupd-refresh.timer
sudo systemctl enable --now bluetooth.service
sudo systemctl enable --now jellyfin.service

echo ">>> Instalação concluída com sucesso para NVIDIA + Jellyfin! 🚀"
