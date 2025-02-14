#!/bin/bash

set -e  # Interrompe a execução em caso de erro

# Função para tratamento de erros
handle_error() {
    echo "Erro: $1" >&2
    exit 1
}

# Atualiza o sistema
echo "Atualizando o sistema..."
sudo pacman -Syu --needed || handle_error "Falha ao atualizar o sistema."

# Listas de pacotes
basic_packages=(
    zsh base-devel file-roller p7zip unrar unzip pacman-contrib sssd firefox-i18n-pt-br
    mesa libva-mesa-driver libva-utils
)

gui_packages=(
    discord telegram-desktop qbittorrent bluez-utils clamav ttf-dejavu-nerd 
    ttf-hack-nerd fwupd libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau 
    lib32-mesa-vdpau showtime papers geary gnome-firmware amf-headers opencl-rusticl-mesa 
    power-profiles-daemon neofetch ttf-fira-code
)

# Instala pacotes do repositório oficial
for package in "${basic_packages[@]}" "${gui_packages[@]}"; do
    echo "Instalando $package..."
    sudo pacman -S --needed "$package" || echo "Aviso: Falha ao instalar $package"
done

# Verifica se o paru já está instalado antes de compilar
if ! command -v paru &>/dev/null; then
    echo "Instalando o paru (AUR helper)..."
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    git clone https://aur.archlinux.org/paru.git "$temp_dir/paru" || handle_error "Falha ao clonar o repositório do paru."
    
    cd "$temp_dir/paru"
    makepkg -si || handle_error "Falha ao instalar o paru."
    cd -
else
    echo "Paru já está instalado. Pulando instalação."
fi

# Instala pacotes do AUR
aur_packages=(
    google-chrome onlyoffice-bin teamviewer extension-manager
)

for package in "${aur_packages[@]}"; do
    echo "Instalando pacote do AUR: $package..."
    paru -S --needed "$package" || echo "Aviso: Falha ao instalar $package"
done

# Habilita e inicia serviços
services=(
    fwupd-refresh.timer
    bluetooth.service
    teamviewerd.service
)

for service in "${services[@]}"; do
    echo "Ativando serviço: $service..."
    sudo systemctl enable --now "$service" || handle_error "Falha ao ativar o serviço $service"
done

# Configura o /etc/mkinitcpio.conf de forma segura
if [ -f /etc/mkinitcpio.conf ]; then
    echo "Configurando AMDGPU no mkinitcpio.conf..."
    if ! grep -q "^MODULES=.*amdgpu" /etc/mkinitcpio.conf; then
        sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 amdgpu)/' /etc/mkinitcpio.conf
        echo "Módulo amdgpu adicionado ao /etc/mkinitcpio.conf."
    else
        echo "AMDGPU já está configurado no mkinitcpio.conf."
    fi
    sudo mkinitcpio -P || handle_error "Falha ao regenerar initramfs."
else
    echo "Aviso: /etc/mkinitcpio.conf não encontrado. Pulando configuração da AMDGPU."
fi

# Adicionando parâmetros AMDGPU ao kernel
if [ -f /etc/kernel/cmdline ]; then
    echo "Adicionando parâmetros AMDGPU ao kernel..."
    desired_param="amdgpu.dcdebugmask=0x10 quiet splash iommu=pt"

    if ! grep -q "amdgpu.dcdebugmask=0x10" /etc/kernel/cmdline; then
        echo "$desired_param" | sudo tee -a /etc/kernel/cmdline > /dev/null
    else
        echo "Parâmetros AMDGPU já configurados."
    fi
else
    echo "Aviso: /etc/kernel/cmdline não encontrado. Pulando configuração do kernel."
fi

# Regenera initramfs novamente
sudo mkinitcpio -P || handle_error "Falha ao regenerar initramfs."

# Mensagem final
echo "✅ Instalação concluída com sucesso!"
