#!/bin/bash

set -e  # Interrompe a execução em caso de erro
trap 'echo "Erro inesperado. Saindo..."; exit 1' ERR

# Função para tratamento de erros
handle_error() {
    echo "❌ Erro: $1" >&2
    exit 1
}

# Atualiza o sistema
echo "🔄 Atualizando o sistema..."
sudo pacman -Syu --noconfirm --needed || handle_error "Falha ao atualizar o sistema."

# Listas de pacotes
basic_packages=(
    zsh base-devel file-roller p7zip unrar unzip pacman-contrib sssd firefox-i18n-pt-br
    mesa libva-mesa-driver libva-utils
)

gui_packages=(
    discord telegram-desktop qbittorrent bluez-utils clamav ttf-dejavu-nerd 
    ttf-hack-nerd fwupd libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau 
    lib32-mesa-vdpau showtime papers geary gnome-firmware amf-headers opencl-rusticl-mesa 
    power-profiles-daemon neofetch
)

# Instala pacotes oficiais
echo "📦 Instalando pacotes do repositório oficial..."
sudo pacman -S --noconfirm --needed "${basic_packages[@]}" "${gui_packages[@]}" || handle_error "Falha ao instalar pacotes oficiais."

# Verifica e instala o Paru (AUR helper)
if ! command -v paru &>/dev/null; then
    echo "⚙️ Instalando Paru (AUR helper)..."
    temp_dir=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$temp_dir/paru" || handle_error "Falha ao clonar o repositório do Paru."
    cd "$temp_dir/paru"
    makepkg -si --noconfirm || handle_error "Falha ao instalar Paru."
    cd - &>/dev/null
    rm -rf "$temp_dir"
else
    echo "✅ Paru já está instalado."
fi

# Instala pacotes do AUR
aur_packages=(
    google-chrome onlyoffice-bin teamviewer extension-manager 
)

echo "📦 Instalando pacotes do AUR..."
paru -S --noconfirm --needed "${aur_packages[@]}" || handle_error "Falha ao instalar pacotes do AUR."

# Habilita e inicia serviços
services=(fwupd-refresh.timer bluetooth.service teamviewerd.service)
echo "⚙️ Ativando serviços..."
sudo systemctl enable --now "${services[@]}" || handle_error "Falha ao ativar serviços."

# Configura o mkinitcpio.conf
mkinitcpio_conf="/etc/mkinitcpio.conf"
if [ -f "$mkinitcpio_conf" ]; then
    echo "🔧 Configurando AMDGPU no mkinitcpio.conf..."
    sudo sed -i '/^MODULES=/ s/)$/ amdgpu)/' "$mkinitcpio_conf"
    sudo mkinitcpio -P || handle_error "Falha ao regenerar initramfs."
else
    echo "⚠️ Aviso: $mkinitcpio_conf não encontrado. Pulando configuração."
fi

# Adiciona parâmetros AMDGPU ao kernel
kernel_cmdline="/etc/kernel/cmdline"
desired_param="amdgpu.dcdebugmask=0x10 quiet splash iommu=pt"
if [ -f "$kernel_cmdline" ]; then
    echo "🔧 Adicionando parâmetros AMDGPU ao kernel..."
    if ! grep -q "$desired_param" "$kernel_cmdline"; then
        echo "$desired_param" | sudo tee -a "$kernel_cmdline" > /dev/null
    else
        echo "✅ Parâmetros AMDGPU já configurados."
    fi
else
    echo "⚠️ Aviso: $kernel_cmdline não encontrado. Pulando configuração do kernel."
fi

# Regenera initramfs novamente
echo "🔄 Regenerando initramfs..."
sudo mkinitcpio -P || handle_error "Falha ao regenerar initramfs."

# Mensagem final
echo "✅ Instalação concluída com sucesso!"

