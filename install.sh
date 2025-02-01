#!/bin/bash

# Atualiza o sistema
echo "Atualizando o sistema..."
sudo pacman -Syu --noconfirm

# Instala dependências básicas
echo "Instalando dependências básicas..."
sudo pacman -S --noconfirm git base-devel 

# Instala pacotes do repositório oficial (pacman)
echo "Instalando pacotes do repositório oficial..."
sudo pacman -S --noconfirm \
    file-roller \
    p7zip \
    unrar \
    unzip \ 
    pacman-contrib \
    sssd \
    firefox-i18n-pt-br \
    discord \
    telegram-desktop \
    qbittorrent \
    bluez-utils \
    kcalc \
    clamav \
    ttf-dejavu-nerd \
    ttf-hack-nerd \
    fwupd \
    libva-mesa-driver \
    lib32-libva-mesa-driver \
    mesa-vdpau \
    lib32-mesa-vdpau \
    showtime \
    papers \
    geary \
    gnome-firmware \
    amf-headers \
    power-profiles-daemon \
    gnome-boxes \
    neofetch

# Instala pacotes do AUR (paru)
echo "Instalando pacotes do AUR..."
paru -S --noconfirm \
    google-chrome \
    aic94xx-firmware \
    qed-git ast-firmware \
    wd719x-firmware \
    upd72020x-fw \
    onlyoffice-bin \
    teamviewer \
    extension-manager

# Habilita e inicia o timer do fwupd
echo "Ativando o fwupd-refresh.timer..."
sudo systemctl enable --now fwupd-refresh.timer

# Habilitando bluetooth
echo "Ativando o bluetooth"
sudo systemctl enable --now bluetooth.service

# Habilitando teamview
echo "Ativando o teamview"
sudo systemctl enable --now teamviewerd.service

# Mensagem final
echo "Instalação concluída!"
