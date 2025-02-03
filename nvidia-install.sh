#!/bin/bash

# Atualiza o sistema
echo "Atualizando o sistema..."
if ! sudo pacman -Syyu --noconfirm; then
    echo "Erro ao atualizar o sistema. Verifique sua conexão com a internet."
    exit 1
fi

# Instala dependências básicas
basic_packages="git base-devel file-roller p7zip unrar unzip pacman-contrib sssd ntfs-3g firefox-i18n-pt-br"
gui_packages="discord telegram-desktop qbittorrent bluez-utils kcalc clamav ttf-dejavu-nerd ttf-hack-nerd inter-font fwupd showtime papers geary gnome-firmware power-profiles-daemon neofetch"
nvidia_packages="nvidia-utils lib32-nvidia-utils nvidia-settings vulkan-icd-loader lib32-vulkan-icd-loader opencl-nvidia cuda clinfo vulkan-tools"

for package_group in "$basic_packages" "$gui_packages" "$nvidia_packages"; do
    if ! sudo pacman -S --noconfirm $package_group; then
        echo "Erro ao instalar pacotes: $package_group"
        exit 1
    fi
done

# Instala o paru (AUR helper)
trap "rm -rf paru" EXIT
if ! git clone https://aur.archlinux.org/paru.git; then
    echo "Erro ao clonar o repositório do paru."
    exit 1
fi
cd paru
if ! makepkg -si --noconfirm; then
    echo "Erro ao instalar o paru."
    exit 1
fi
cd ..

# Instala pacotes do AUR
aur_packages="google-chrome aic94xx-firmware qed-git ast-firmware wd719x-firmware upd72020x-fw onlyoffice-bin teamviewer extension-manager coolercontrol"
if ! paru -S --noconfirm $aur_packages; then
    echo "Erro ao instalar pacotes do AUR."
    exit 1
fi

# Habilita e inicia serviços
services=("fwupd-refresh.timer" "bluetooth.service" "teamviewerd.service")
for service in "${services[@]}"; do
    if ! sudo systemctl enable --now $service; then
        echo "Erro ao ativar o serviço: $service."
        exit 1
    fi
done

# Configura o /etc/kernel/cmdline
desired_param="nvidia-drm.modeset=1 nvidia_drm.fbdev=1 loglevel=3 quiet splash"
if [ -f /etc/kernel/cmdline ]; then
    current_cmdline=$(cat /etc/kernel/cmdline | xargs)
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
if ! sudo mkinitcpio -P; then
    echo "Erro ao regenerar a imagem do initramfs."
    exit 1
fi

# Configura o /etc/environment
environment_vars="GBM_BACKEND=nvidia-drm\n__GLX_VENDOR_LIBRARY_NAME=nvidia"
if ! grep -qE "GBM_BACKEND=nvidia-drm|__GLX_VENDOR_LIBRARY_NAME=nvidia" /etc/environment; then
    echo -e "$environment_vars" | sudo tee -a /etc/environment > /dev/null
    echo "Variáveis adicionadas ao /etc/environment."
fi

# Mensagem final
echo "Instalação concluída!"
