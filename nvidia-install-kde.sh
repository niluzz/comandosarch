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

# Atualiza o sistema
echo "⬆️  Atualizando o sistema..."
pacman -Syyu --noconfirm || handle_error "Falha ao atualizar o sistema."

# Lista de pacotes
basic_packages=(
    zsh base-devel file-roller p7zip unrar unzip pacman-contrib sssd ntfs-3g firefox-i18n-pt-br
)

gui_packages=(
    discord telegram-desktop qbittorrent bluez-utils clamav ttf-dejavu-nerd 
    ttf-hack-nerd inter-font fwupd gwenview okular kcalc power-profiles-daemon
    neofetch ttf-fira-code jellyfin-ffmpeg jellyfin-server jellyfin-web steam
    goverlay spectacle
)

nvidia_packages=(
    nvidia-utils lib32-nvidia-utils nvidia-settings opencl-nvidia nvidia-utils libva-nvidia-driver
)

# Instala pacotes usando um loop
for package_group in basic_packages gui_packages nvidia_packages; do
    declare -n group="$package_group"
    for package in "${group[@]}"; do
        echo "📦 Instalando $package..."
        pacman -S --needed "$package" || echo "⚠️  Aviso: Falha ao instalar $package"
    done
done

# Adicionando parâmetros QUIET ao kernel
if [ -f /etc/kernel/cmdline ]; then
    echo "Adicionando parâmetros no kernel..."
    desired_param="quiet splash iommu=pt"

    if ! grep -q "quiet" /etc/kernel/cmdline; then
        echo "$desired_param" | sudo tee -a /etc/kernel/cmdline > /dev/null
    else
        echo "Parâmetros quiet já configurados."
    fi
else
    echo "Aviso: /etc/kernel/cmdline não encontrado. Pulando configuração do kernel."
fi

# Modificação segura no /etc/mkinitcpio.conf
if [ -f /etc/mkinitcpio.conf ]; then
    echo "🔧 Configurando NVIDIA no mkinitcpio.conf..."
    
    if ! grep -q 'nvidia' /etc/mkinitcpio.conf; then
        sed -i '/^MODULES=/s/(/(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf
    fi

    sed -i '/^HOOKS=/s/\bkms\b//' /etc/mkinitcpio.conf
    mkinitcpio -p linux-zen || handle_error "Falha ao regenerar initramfs."
else
    echo "⚠️  Aviso: /etc/mkinitcpio.conf não encontrado. Pulando configuração da NVIDIA."
fi

# Mensagem final
echo "🎉 Instalação concluída com sucesso!"
