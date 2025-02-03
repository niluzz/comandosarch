#!/bin/bash

# Atualiza o sistema
echo "Atualizando o sistema..."
if ! sudo pacman -Syu --noconfirm; then
    echo "Erro ao atualizar o sistema. Verifique sua conexão com a internet."
    exit 1
fi

# Instala dependências básicas
echo "Instalando dependências básicas..."
if ! sudo pacman -S --noconfirm git base-devel file-roller p7zip unrar unzip pacman-contrib sssd ntfs-3g firefox-i18n-pt-br discord telegram-desktop qbittorrent bluez-utils kcalc clamav ttf-dejavu-nerd ttf-hack-nerd inter-font fwupd  showtime papers geary gnome-firmware power-profiles-daemon neofetch nvidia-utils lib32-nvidia-utils nvidia-settings vulkan-icd-loader lib32-vulkan-icd-loader opencl-nvidia cuda clinfo vulkan-tools; then
    echo "Erro ao instalar dependências básicas."
    exit 1
fi

# Instala o paru (AUR helper)
echo "Instalando o paru..."
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
rm -rf paru

# Instala pacotes do AUR (paru)
echo "Instalando pacotes do AUR..."
if ! paru -S --noconfirm google-chrome aic94xx-firmware qed-git ast-firmware wd719x-firmware upd72020x-fw onlyoffice-bin teamviewer extension-manager coolercontrol ; then
    echo "Erro ao instalar pacotes do AUR."
    exit 1
fi

# Habilita e inicia o timer do fwupd
echo "Ativando o fwupd-refresh.timer..."
if ! sudo systemctl enable --now fwupd-refresh.timer; then
    echo "Erro ao ativar o fwupd-refresh.timer."
    exit 1
fi

# Habilita o Bluetooth
echo "Ativando o bluetooth..."
if ! sudo systemctl enable --now bluetooth.service; then
    echo "Erro ao ativar o bluetooth."
    exit 1
fi

# Habilita o TeamViewer
echo "Ativando o teamviewer..."
if ! sudo systemctl enable --now teamviewerd.service; then
    echo "Erro ao ativar o teamviewer."
    exit 1
fi

# Adiciona o parâmetro ao /etc/kernel/cmdline (se o arquivo existir)
echo "Adicionando o parâmetro ao /etc/kernel/cmdline..."

# Parâmetro desejado
desired_param="nvidia-drm.modeset=1 nvidia_drm.fbdev=1 nouveau.modeset=0 loglevel=3 quiet splash"

if [ -f /etc/kernel/cmdline ]; then
    # Lê o conteúdo atual do arquivo
    current_cmdline=$(cat /etc/kernel/cmdline)

    # Verifica se o parâmetro já está presente
    if ! echo "$current_cmdline" | grep -q "nvidia-drm.modeset=1"; then
        # Adiciona o parâmetro ao final da linha
        new_cmdline="$current_cmdline $desired_param"

        # Sobrescreve o arquivo com o novo conteúdo
        echo "$new_cmdline" | sudo tee /etc/kernel/cmdline > /dev/null
        echo "Parâmetro adicionado ao /etc/kernel/cmdline."
    else
        echo "O parâmetro já está presente no /etc/kernel/cmdline."
    fi
else
    echo "Arquivo /etc/kernel/cmdline não encontrado. Nenhuma alteração foi feita."
fi

# Adiciona os módulos da NVIDIA e remove o kms do /etc/mkinitcpio.conf
echo "Configurando o /etc/mkinitcpio.conf para NVIDIA..."

# Módulos da NVIDIA
nvidia_modules="nvidia nvidia_modeset nvidia_uvm nvidia_drm"

# Verifica se os módulos já estão presentes
if grep -q "MODULES=(.*nvidia.*)" /etc/mkinitcpio.conf; then
    echo "Os módulos da NVIDIA já estão presentes no /etc/mkinitcpio.conf."
else
    # Adiciona os módulos da NVIDIA dentro dos parênteses de MODULES
    sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 '"$nvidia_modules"')/' /etc/mkinitcpio.conf
    echo "Módulos da NVIDIA adicionados ao /etc/mkinitcpio.conf."
fi

# Remove o kms da linha HOOKS
if grep -q "HOOKS=(.*kms.*)" /etc/mkinitcpio.conf; then
    sudo sed -i 's/\(HOOKS=(.*\)kms\(.*)\)/\1\2/' /etc/mkinitcpio.conf
    echo "kms removido da linha HOOKS no /etc/mkinitcpio.conf."
else
    echo "kms não está presente na linha HOOKS do /etc/mkinitcpio.conf."
fi

# Desabilita o driver nouveau
echo "Desabilitando o driver nouveau..."
if [ -f /etc/modprobe.d/blacklist-nouveau.conf ]; then
    if ! grep -q "blacklist nouveau" /etc/modprobe.d/blacklist-nouveau.conf; then
        echo "blacklist nouveau" | sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf > /dev/null
        echo "options nouveau modeset=0" | sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf > /dev/null
        echo "Driver nouveau desabilitado no /etc/modprobe.d/blacklist-nouveau.conf."
    else
        echo "O driver nouveau já está desabilitado no /etc/modprobe.d/blacklist-nouveau.conf."
    fi
else
    echo "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null
    echo "options nouveau modeset=0" | sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf > /dev/null
    echo "Arquivo /etc/modprobe.d/blacklist-nouveau.conf criado e o driver nouveau desabilitado."
fi

# Regenera a imagem do initramfs
echo "Regenerando a imagem do initramfs..."
sudo mkinitcpio -P
echo "Imagem do initramfs regenerada com sucesso."

# Configura o arquivo /etc/environment
echo "Configurando o arquivo /etc/environment..."

# Variáveis desejadas
environment_vars="GBM_BACKEND=nvidia-drm\n__GLX_VENDOR_LIBRARY_NAME=nvidia"

# Verifica se o arquivo existe
if [ -f /etc/environment ]; then
    # Verifica se as variáveis já estão presentes
    if ! grep -q "GBM_BACKEND=nvidia-drm" /etc/environment; then
        echo -e "GBM_BACKEND=nvidia-drm" | sudo tee -a /etc/environment > /dev/null
        echo "GBM_BACKEND=nvidia-drm adicionado ao /etc/environment."
    else
        echo "GBM_BACKEND=nvidia-drm já está presente no /etc/environment."
    fi

    if ! grep -q "__GLX_VENDOR_LIBRARY_NAME=nvidia" /etc/environment; then
        echo -e "__GLX_VENDOR_LIBRARY_NAME=nvidia" | sudo tee -a /etc/environment > /dev/null
        echo "__GLX_VENDOR_LIBRARY_NAME=nvidia adicionado ao /etc/environment."
    else
        echo "__GLX_VENDOR_LIBRARY_NAME=nvidia já está presente no /etc/environment."
    fi
else
    # Cria o arquivo /etc/environment com as variáveis
    echo -e "GBM_BACKEND=nvidia-drm\n__GLX_VENDOR_LIBRARY_NAME=nvidia" | sudo tee /etc/environment > /dev/null
    echo "Arquivo /etc/environment criado com as variáveis."
fi

# Mensagem final
echo "Instalação concluída!"
