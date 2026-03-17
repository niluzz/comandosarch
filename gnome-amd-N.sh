#!/bin/bash
set -e

echo ">>> Atualizando pacotes do sistema..."
sudo pacman -Syu --noconfirm

echo ">>> Instalando pacotes oficiais..."

echo ">>> Ferramentas básicas..."
sudo pacman -S --needed --noconfirm \
  git zsh systemd-ukify pacman-contrib \
  file-roller p7zip unrar unzip \
  fwupd mesa-utils ibus base-devel \
  tuned-ppd

echo ">>> Navegadores e comunicação..."
sudo pacman -S --needed --noconfirm \
  firefox-i18n-pt-br

echo ">>> Mídia e multimídia..."
sudo pacman -S --needed --noconfirm \
  ffmpeg \
  gstreamer gst-plugins-base gst-plugins-good \
  gst-plugins-bad gst-plugins-ugly gst-libav \
  libdvdread libdvdnav libdvdcss \
  ffmpegthumbnailer

echo ">>> Fontes..."
sudo pacman -S --needed --noconfirm \
  ttf-firacode-nerd ttf-dejavu-nerd ttf-hack-nerd \
  inter-font noto-fonts noto-fonts-emoji \
  ttf-opensans ttf-roboto noto-fonts-cjk

echo ">>> Outros..."
sudo pacman -S --needed --noconfirm \
  gufw thunderbird-i18n-pt-br playerctl \
  expac fastfetch

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
  google-chrome phinger-cursors ttf-ms-fonts 

echo ">>> Verificando e ajustando parâmetros do kernel..."
CMDLINE_FILE="/etc/kernel/cmdline"
if [ ! -f "$CMDLINE_FILE" ]; then
  echo "Arquivo $CMDLINE_FILE não encontrado. Criando..."
  sudo mkdir -p /etc/kernel
  echo "quiet splash iommu=pt amdgpu.dcdebugmask=0x10 amdgpu.gpu_recovery=1 pcie_aspm=off" | sudo tee "$CMDLINE_FILE"
else
  for param in quiet splash iommu=pt amdgpu.dcdebugmask=0x10 amdgpu.gpu_recovery=1; do
    if ! grep -qw "$param" "$CMDLINE_FILE"; then
      sudo sed -i "1s|$| $param|" "$CMDLINE_FILE"
      echo "Parâmetro '$param' adicionado ao kernel cmdline."
    fi
  done
fi

echo ">>> Habilitando serviços..."
sudo systemctl enable --now fwupd-refresh.timer
sudo systemctl enable --now bluetooth.service

echo ">>> Instalação concluída com sucesso! 🚀"
