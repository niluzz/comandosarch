#!/bin/bash
set -e

echo ">>> Atualizando pacotes do sistema..."
sudo pacman -Syu --noconfirm

echo ">>> Instalando pacotes oficiais..."
echo ">>> Ferramentas básicas..."
sudo pacman -S --needed --noconfirm \
  git zsh base-devel pacman-contrib \
  file-roller p7zip unrar unzip \
  fwupd tuned-ppd mesa-utils \
  systemd-ukify

echo ">>> Input methods..."
sudo pacman -S --needed --noconfirm \
  ibus dialect

echo ">>> Navegadores e comunicação..."
sudo pacman -S --needed --noconfirm \
  firefox-i18n-pt-br discord telegram-desktop

echo ">>> Mídia e multimídia..."
sudo pacman -S --needed --noconfirm \
  ffmpeg \
  gstreamer gst-plugins-base gst-plugins-good \
  gst-plugins-bad gst-plugins-ugly gst-libav \
  libdvdread libdvdnav libdvdcss ffmpegthumbnailer

echo ">>> Drive NVIDIA..."
sudo pacman -S --needed --noconfirm \
  nvidia-utils nvidia-settings lib32-nvidia-utils

echo ">>> Jellyfin..."
sudo pacman -S --needed --noconfirm \
  jellyfin-ffmpeg jellyfin-server jellyfin-web

echo ">>> Fontes..."
sudo pacman -S --needed --noconfirm \
  ttf-firacode-nerd ttf-dejavu-nerd ttf-hack-nerd \
  inter-font noto-fonts noto-fonts-emoji \
  ttf-montserrat ttf-opensans ttf-roboto \
  noto-fonts-cjk

echo ">>> Outros..."
sudo pacman -S --needed --noconfirm \
  qbittorrent newsflash amf-headers openrgb \
  handbrake gufw directx-headers lib32-directx-headers \
  directx-shader-compiler

echo "Ferramentas de Backup..."
sudo pacman -S --needed --noconfirm \
btrfs-assistant btrfsmaintenance snapper

echo ">>> Instalando Paru (AUR helper)..."
if ! command -v paru &>/dev/null; then
  git clone https://aur.archlinux.org/paru.git /tmp/paru
  cd /tmp/paru
  makepkg -si --noconfirm
  cd
  rm -rf /tmp/paru
else
  echo "Paru já está instalado."
fi

echo ">>> Instalando pacotes do AUR com paru..."
paru -S --needed --noconfirm \
  google-chrome onlyoffice-bin extension-manager \
  mangojuice phinger-cursors protonplus \
  ttf-ms-fonts

echo ">>> Verificando e ajustando /etc/mkinitcpio.conf..."
MKINIT_FILE="/etc/mkinitcpio.conf"
if ! grep -q "nvidia" "$MKINIT_FILE" 2>/dev/null; then
  sudo sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' "$MKINIT_FILE"
  echo "Parâmetros 'nvidia*' adicionados em MODULES."
  sudo mkinitcpio -P
else
  echo "Parâmetros NVIDIA já estão em MODULES."
fi

echo ">>> Verificando e ajustando parâmetros do kernel..."
CMDLINE_FILE="/etc/kernel/cmdline"
if [ ! -f "$CMDLINE_FILE" ]; then
  echo "Arquivo $CMDLINE_FILE não encontrado. Criando..."
  sudo mkdir -p /etc/kernel
  echo "quiet splash nvidia-drm.modeset=1 nvidia-drm.fbdev=1 iommu=pt nvidia.NVreg_PreserveVideoMemoryAllocations=1 nvidia.NVreg_TemporaryFilePath=/var/tmp" | sudo tee "$CMDLINE_FILE"
else
  for param in quiet splash nvidia-drm.modeset=1 nvidia-drm.fbdev=1 iommu=pt nvidia.NVreg_PreserveVideoMemoryAllocations=1 nvidia.NVreg_TemporaryFilePath=/var/tmp; do
    if ! grep -qw "$param" "$CMDLINE_FILE"; then
      sudo sed -i "1s|$| $param|" "$CMDLINE_FILE"
      echo "Parâmetro '$param' adicionado ao kernel cmdline."
    fi
  done
fi

echo ">>> Habilitando serviços..."
sudo systemctl enable --now fwupd-refresh.timer
sudo systemctl enable --now bluetooth.service
sudo systemctl enable --now jellyfin.service

echo ">>> Instalação concluída com sucesso para NVIDIA + Jellyfin! 🚀"
