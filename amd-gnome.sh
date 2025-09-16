#!/bin/bash
set -e

echo ">>> Atualizando pacotes do sistema..."
sudo pacman -Syu --noconfirm

echo ">>> Instalando pacotes oficiais..."
sudo pacman -S --needed --noconfirm \
  git zsh base-devel file-roller p7zip unrar unzip pacman-contrib \
  firefox-i18n-pt-br discord telegram-desktop fwupd showtime papers \
  amf-headers power-profiles-daemon qbittorrent \
  ttf-firacode-nerd ttf-dejavu-nerd ttf-hack-nerd inter-font \
  noto-fonts noto-fonts-emoji ibus mesa-utils dialect

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
paru -S --needed --noconfirm google-chrome onlyoffice-bin extension-manager auto-cpufreq mangojuice phinger-cursors

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
