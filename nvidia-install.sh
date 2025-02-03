#!/bin/bash

# Função para tratar erros
handle_error() {
    echo "Erro: $1"
    exit 1
}

# Atualiza o sistema
echo "Atualizando o sistema..."
if ! sudo pacman -Syyu --noconfirm; then
    handle_error "Falha ao atualizar o sistema. Verifique sua conexão com a internet."
fi

# Instala dependências básicas
basic_packages=(
    git base-devel file-roller p7zip unrar unzip pacman-contrib sssd ntfs-3g firefox-i18n-pt-br
)

gui_packages=(
    discord telegram-desktop qbittorrent bluez-utils kcalc clamav ttf-dejavu-nerd 
    ttf-hack-nerd inter-font fwupd showtime papers geary gnome-firmware 
    power-profiles-daemon neofetch
)

nvidia_packages=(
    nvidia-utils lib32-nvidia-utils nvidia-settings vulkan-icd-loader 
    lib32-vulkan-icd-loader opencl-nvidia cuda clinfo vulkan-tools
)

for package_group in basic_packages gui_packages nvidia_packages; do
    if ! sudo pacman -S --noconfirm ${!package_group}; then
        handle_error "Falha ao instalar pacotes: $package_group"
    fi
done

# Instala o paru (AUR helper)
echo "Instalando o paru (AUR helper)..."
temp_dir=$(mktemp -d)
trap "rm -rf $temp_dir" EXIT

if ! git clone https://aur.archlinux.org/paru.git "$temp_dir/paru"; then
    handle_error "Falha ao clonar o repositório do paru."
fi

cd "$temp_dir/paru"
if ! makepkg -si --noconfirm; then
    handle_error "Falha ao instalar o paru."
fi
cd -

# Instala pacotes do AUR
aur_packages=(
    google-chrome aic94xx-firmware qed-git ast-firmware wd719x-firmware 
    upd72020x-fw onlyoffice-bin teamviewer extension-manager coolercontrol
)

for package in "${aur_packages[@]}"; do
    if ! paru -S --noconfirm --skipreview "$package"; then
        echo "Aviso: Falha ao instalar o pacote do AUR: $package"
    fi
done

# Habilita e inicia serviços
services=(
    fwupd-refresh.timer
    bluetooth.service
    teamviewerd.service
)

for service in "${services[@]}"; do
    if ! sudo systemctl enable --now "$service"; then
        handle_error "Falha ao ativar o serviço: $service"
    fi
done

# Configura o /etc/mkinitcpio.conf
nvidia_modules="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
if ! grep -q "MODULES=(.*nvidia.*)" /etc/mkinitcpio.conf; then
    sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 '"$nvidia_modules"')/' /etc/mkinitcpio.conf
    echo "Módulos da NVIDIA adicionados ao /etc/mkinitcpio.conf."
fi

if grep -q "HOOKS=(.*kms.*)" /etc/mkinitcpio.conf; then
    sudo sed -i 's/\(HOOKS=(.*\)kms\(.*)\)/\1\2/' /etc/mkinitcpio.conf
    echo "kms removido da linha HOOKS no /etc/mkinitcpio.conf."
fi

# Regenera a imagem do initramfs
if ! sudo mkinitcpio -p linux-zen; then
    handle_error "Falha ao regenerar a imagem do initramfs."
fi

# Adiciona o parâmetro ao /etc/kernel/cmdline (se o arquivo existir)
echo "Adicionando o parâmetro ao /etc/kernel/cmdline..."

desired_param="nvidia-drm.modeset=1 nvidia_drm.fbdev=1 nouveau.modeset=0 loglevel=3 quiet splash"

if [ -f /etc/kernel/cmdline ]; then
    current_cmdline=$(cat /etc/kernel/cmdline)

    if ! echo "$current_cmdline" | grep -q "nvidia-drm.modeset=1"; then
        new_cmdline="$current_cmdline $desired_param"
        echo "$new_cmdline" | sudo tee /etc/kernel/cmdline > /dev/null
        echo "Parâmetro adicionado ao /etc/kernel/cmdline."
    else
        echo "O parâmetro já está presente no /etc/kernel/cmdline."
    fi
else
    echo "Arquivo /etc/kernel/cmdline não encontrado. Nenhuma alteração foi feita."
fi

# Regenera a imagem do initramfs novamente
if ! sudo mkinitcpio -p linux-zen; then
    handle_error "Falha ao regenerar a imagem do initramfs."
fi

# Configura o /etc/environment
environment_vars="GBM_BACKEND=nvidia-drm\n__GLX_VENDOR_LIBRARY_NAME=nvidia"
if ! grep -qE "GBM_BACKEND=nvidia-drm|__GLX_VENDOR_LIBRARY_NAME=nvidia" /etc/environment; then
    echo -e "$environment_vars" | sudo tee -a /etc/environment > /dev/null
    echo "Variáveis adicionadas ao /etc/environment."
fi

# Mensagem final
echo "Instalação concluída com sucesso!"
