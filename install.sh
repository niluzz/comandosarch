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

# Instala pacotes do AUR (yay)
echo "Instalando pacotes do AUR..."
paru -S --noconfirm \
    google-chrome \
    aic94xx-firmware \
    qed-git ast-firmware \
    wd719x-firmware \
    upd72020x-fw \
    onlyoffice-bin \
    teamviewer

# Mensagem final
echo "Instalação concluída!"
