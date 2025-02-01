#!/bin/bash

# Atualiza o sistema
echo "Atualizando o sistema..."
sudo pacman -Syu --noconfirm

# Instala dependências básicas
echo "Instalando dependências básicas..."
sudo pacman -S --noconfirm git base-devel file-roller p7zip unrar unzip pacman-contrib sssd firefox-i18n-pt-br discord telegram-desktop qbittorrent bluez-utils kcalc clamav 
ttf-dejavu-nerd ttf-hack-nerd fwupd libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau lib32-mesa-vdpau showtime papers geary gnome-firmware amf-headers power-profiles-daemon
neofetch

# Instala o paru (AUR helper)
echo "Instalando o paru..."
git clone https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru
makepkg -si --noconfirm

# Instala pacotes do AUR (paru)
echo "Instalando pacotes do AUR..."
paru -S --noconfirm google-chrome aic94xx-firmware qed-git ast-firmware wd719x-firmware upd72020x-fw onlyoffice-bin teamviewer extension-manager

# Habilita e inicia o timer do fwupd
echo "Ativando o fwupd-refresh.timer..."
sudo systemctl enable --now fwupd-refresh.timer

# Habilitando bluetooth
echo "Ativando o bluetooth"
sudo systemctl enable --now bluetooth.service

# Habilitando teamview
echo "Ativando o teamview"
sudo systemctl enable --now teamviewerd.service

# Instala o ZSH
echo "Instalando o ZSH..."
sudo pacman -S --noconfirm zsh

# Instala o Oh My Zsh
echo "Instalando o Oh My Zsh..."
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Instala o tema Powerlevel10k
echo "Instalando o tema Powerlevel10k..."
git clone https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k

# Configura o tema Powerlevel10k no ~/.zshrc
echo "Configurando o tema Powerlevel10k..."
sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc

# Instala plugins para ZSH
echo "Instalando plugins para ZSH..."
git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search

# Instala o fzf (Fuzzy Finder)
echo "Instalando o fzf..."
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install --all --no-update-rc

# Configura os plugins no ~/.zshrc
echo "Configurando plugins no ~/.zshrc..."
sed -i 's/^plugins=.*/plugins=(git zsh-syntax-highlighting zsh-autosuggestions fzf zsh-history-substring-search)/' ~/.zshrc

# Recarrega o ZSH
echo "Recarregando o ZSH..."
source ~/.zshrc

# Mensagem final
echo "Instalação concluída!"
