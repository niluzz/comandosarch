#!/bin/bash
set -e

echo ">>> Atualizando pacotes do sistema..."
sudo pacman -Syu --noconfirm

echo ">>> Instalando pacotes oficiais..."

# Ferramentas básicas
sudo pacman -S --needed --noconfirm \
  git zsh base-devel pacman-contrib \
  file-roller p7zip unrar unzip \
  fwupd power-profiles-daemon mesa-utils \
  ibus showtime papers

# Navegadores e comunicação
sudo pacman -S --needed --noconfirm \
  firefox-i18n-pt-br discord telegram-desktop

# Mídia e multimídia
sudo pacman -S --needed --noconfirm \
  ffmpeg \
  gstreamer gst-plugins-base gst-plugins-good \
  gst-plugins-bad gst-plugins-ugly gst-libav \
  libdvdread libdvdnav libdvdcss \
  handbrake ffmpegthumbnailer

# Fontes
sudo pacman -S --needed --noconfirm \
  ttf-firacode-nerd ttf-dejavu-nerd ttf-hack-nerd \
  inter-font noto-fonts noto-fonts-emoji \
  ttf-montserrat ttf-opensans ttf-roboto

# Outros
sudo pacman -S --needed --noconfirm \
  qbittorrent newsflash amf-headers dialect \
  gufw

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
  auto-cpufreq mangojuice phinger-cursors

echo ">>> Verificando e ajustando /etc/mkinitcpio.conf..."
MKINIT_FILE="/etc/mkinitcpio.conf"
if ! grep -E "^MODULES=.*amdgpu" "$MKINIT_FILE"; then
  sudo sed -i 's/^MODULES=(/MODULES=(amdgpu /' "$MKINIT_FILE"
  echo "Parâmetro 'amdgpu' adicionado em MODULES."
else
  echo "Parâmetro 'amdgpu' já existe em MODULES."
fi
sudo mkinitcpio -P

echo ">>> Verificando e ajustando /etc/kernel/cmdline..."
CMDLINE_FILE="/etc/kernel/cmdline"
for param in quiet splash iommu=pt; do
  if ! grep -qw "$param" "$CMDLINE_FILE"; then
    sudo sed -i "1s|\$| $param|" "$CMDLINE_FILE"
    echo "Parâmetro '$param' adicionado ao kernel cmdline."
  fi
done
sudo mkinitcpio -P

echo ">>> Habilitando serviços..."
sudo systemctl enable --now fwupd-refresh.timer
sudo systemctl enable --now bluetooth.service
sudo systemctl enable --now auto-cpufreq.service

echo ">>> Instalação concluída com sucesso! 🚀"
