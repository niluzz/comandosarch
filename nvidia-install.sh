#!/bin/bash

set -eu  # Interrompe a execução em caso de erro e variáveis não definidas

# Verificar se o script está sendo executado com permissões de root
if [[ $EUID -ne 0 ]]; then
  echo "Este script deve ser executado com permissões de root. Use sudo." >&2
  exit 1
fi

# Função para tratamento de erros
handle_error() {
    echo "❌ Erro: $1" >&2
    exit 1
}

# Verifica conexão antes de atualizar
echo "🔄 Verificando conexão com a internet..."
if ! curl -s --head https://archlinux.org | grep "200 OK" > /dev/null; then
    handle_error "Sem conexão com a internet. Verifique sua rede."
fi

# Atualiza o sistema
echo "⬆️  Atualizando o sistema..."
pacman -Syyu --noconfirm || handle_error "Falha ao atualizar o sistema."

# Lista de pacotes
basic_packages=(
    zsh base-devel file-roller p7zip unrar unzip pacman-contrib sssd ntfs-3g firefox-i18n-pt-br
)

gui_packages=(
    discord telegram-desktop qbittorrent bluez-utils kcalc clamav ttf-dejavu-nerd 
    ttf-hack-nerd inter-font fwupd showtime papers geary gnome-firmware 
    power-profiles-daemon neofetch
)

nvidia_packages=(
    nvidia-utils lib32-nvidia-utils nvidia-settings 
)

# Instala pacotes usando um loop
for package_group in basic_packages gui_packages nvidia_packages; do
    declare -n group="$package_group"
    for package in "${group[@]}"; do
        echo "📦 Instalando $package..."
        pacman -S --needed --noconfirm "$package" || echo "⚠️  Aviso: Falha ao instalar $package"
    done
done

# Verifica se o paru já está instalado
if ! command -v paru &>/dev/null; then
    echo "📥 Instalando o paru (AUR helper)..."
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    git clone https://aur.archlinux.org/paru.git "$temp_dir/paru" || handle_error "Falha ao clonar o repositório do paru."
    
    cd "$temp_dir/paru"
    makepkg -si --noconfirm || handle_error "Falha ao instalar o paru."
    cd -
else
    echo "✅ Paru já está instalado. Pulando instalação."
fi

# Instala pacotes do AUR
aur_packages=(
    google-chrome aic94xx-firmware qed-git ast-firmware wd719x-firmware 
    upd72020x-fw onlyoffice-bin teamviewer extension-manager coolercontrol
)

for package in "${aur_packages[@]}"; do
    echo "📦 Instalando pacote do AUR: $package..."
    paru -S --needed --noconfirm "$package" || echo "⚠️  Aviso: Falha ao instalar $package"
done

# Habilita e inicia serviços
services=(
    fwupd-refresh.timer
    bluetooth.service
    teamviewerd.service
)

for service in "${services[@]}"; do
    if ! systemctl is-enabled --quiet "$service"; then
        echo "🔧 Ativando serviço: $service..."
        systemctl enable --now "$service" || handle_error "Falha ao ativar o serviço $service"
    else
        echo "✅ Serviço $service já está ativo."
    fi
done

# Modificação segura no /etc/mkinitcpio.conf
if [ -f /etc/mkinitcpio.conf ]; then
    echo "🔧 Configurando NVIDIA no mkinitcpio.conf..."
    
    if ! grep -q 'nvidia' /etc/mkinitcpio.conf; then
        sed -i '/^MODULES=/s/(/(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
    fi

    sed -i '/^HOOKS=/s/\bkms\b//' /etc/mkinitcpio.conf
    mkinitcpio -P || handle_error "Falha ao regenerar initramfs."
else
    echo "⚠️  Aviso: /etc/mkinitcpio.conf não encontrado. Pulando configuração da NVIDIA."
fi

# Mensagem final
echo "🎉 Instalação concluída com sucesso!"
