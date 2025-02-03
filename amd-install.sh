#!/bin/bash

# Atualiza o sistema
echo "Atualizando o sistema..."
if ! sudo pacman -Syu --noconfirm; then
    echo "Erro ao atualizar o sistema. Verifique sua conexão com a internet."
    exit 1
fi

# Instala dependências básicas
basic_packages="git base-devel file-roller p7zip unrar unzip pacman-contrib sssd firefox-i18n-pt-br"
gui_packages="discord telegram-desktop qbittorrent bluez-utils kcalc clamav ttf-dejavu-nerd ttf-hack-nerd fwupd libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau lib32-mesa-vdpau showtime papers geary gnome-firmware amf-headers opencl-rusticl-mesa power-profiles-daemon neofetch"

for package_group in "$basic_packages" "$gui_packages"; do
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
aur_packages="google-chrome aic94xx-firmware qed-git ast-firmware wd719x-firmware upd72020x-fw onlyoffice-bin teamviewer extension-manager"
for package in $aur_packages; do
    if ! paru -S --noconfirm --skipreview $package; then
        echo "Erro ao instalar o pacote do AUR: $package"
    fi
done

# Habilita e inicia serviços
services=("fwupd-refresh.timer" "bluetooth.service" "teamviewerd.service")
for service in "${services[@]}"; do
    if ! sudo systemctl enable --now $service; then
        echo "Erro ao ativar o serviço: $service"
        exit 1
    fi
done

# Adiciona o módulo amdgpu ao /etc/mkinitcpio.conf
if ! grep -q "MODULES=(.*amdgpu.*)" /etc/mkinitcpio.conf; then
    sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 amdgpu)/' /etc/mkinitcpio.conf
    echo "Módulo amdgpu adicionado ao /etc/mkinitcpio.conf."
fi

# Regenera a imagem do initramfs
if ! sudo mkinitcpio -P; then
    echo "Erro ao regenerar a imagem do initramfs."
    exit 1
fi

# Adiciona parâmetros ao /etc/cmdline
desired_params="amdgpu.dcdebugmask=0x10 quiet splash radeon.si_support=0 radeon.cik_support=0 iommu=pt"
if [ -f /etc/cmdline ]; then
    current_cmdline=$(cat /etc/cmdline | xargs)
    added_params=false
    for param in $desired_params; do
        if ! echo "$current_cmdline" | grep -q "$param"; then
            current_cmdline="$current_cmdline $param"
            added_params=true
        fi
    done
    current_cmdline=$(echo "$current_cmdline" | xargs)
    if $added_params; then
        echo "$current_cmdline" | sudo tee /etc/cmdline > /dev/null
        echo "Parâmetros adicionados ao /etc/cmdline."
    else
        echo "Todos os parâmetros já estão presentes no /etc/cmdline."
    fi
else
    echo "Arquivo /etc/cmdline não encontrado. Nenhuma alteração foi feita."
fi

# Regenera a imagem do initramfs novamente
if ! sudo mkinitcpio -P; then
    echo "Erro ao regenerar a imagem do initramfs."
    exit 1
fi

# Mensagem final
echo "Instalação concluída!"
