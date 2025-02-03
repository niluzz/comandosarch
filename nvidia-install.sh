#!/bin/bash
set -e  # Encerra o script imediatamente se algum comando falhar
set -u  # Encerra o script se uma variável não definida for usada

# Função para limpeza em caso de interrupção
cleanup() {
    echo "Limpando recursos..."
    if [ -d "paru" ]; then
        rm -rf paru
        echo "Diretório 'paru' removido."
    fi
}

# Configura o trap para chamar a função cleanup em caso de interrupção
trap cleanup EXIT

# Função para atualizar o sistema
update_system() {
    echo "Atualizando o sistema..."
    if ! sudo pacman -Syu --noconfirm; then
        echo "Erro ao atualizar o sistema. Verifique sua conexão com a internet."
        exit 1
    fi
    echo "Sistema atualizado com sucesso."
}

# Função para instalar dependências básicas
install_dependencies() {
    echo "Instalando dependências básicas..."

    # Pacotes essenciais e ferramentas de desenvolvimento
    local development_tools=(
        git base-devel pacman-contrib
    )

    # Ferramentas de compactação e manipulação de arquivos
    local compression_tools=(
        file-roller p7zip unrar unzip
    )

    # Ferramentas de sistema e utilitários
    local system_tools=(
        sssd ntfs-3g bluez-utils fwupd gnome-firmware power-profiles-daemon
    )

    # Aplicativos de produtividade e comunicação
    local productivity_tools=(
        firefox-i18n-pt-br discord telegram-desktop qbittorrent kcalc geary
    )

    # Fontes e suporte a gráficos
    local fonts_and_graphics=(
        ttf-dejavu-nerd ttf-hack-nerd inter-font
    )

    # Segurança e antivírus
    local security_tools=(
        clamav
    )

    # Ferramentas de rede e conectividade
    local network_tools=(
        showtime
    )

    # Ferramentas de monitoramento e diagnóstico
    local monitoring_tools=(
        neofetch
    )

    # Pacotes relacionados à NVIDIA
    local nvidia_packages=(
        nvidia-utils lib32-nvidia-utils nvidia-settings vulkan-icd-loader
        lib32-vulkan-icd-loader opencl-nvidia cuda clinfo vulkan-tools
    )

    # Combina todas as categorias em um único array
    local packages=(
        "${development_tools[@]}"
        "${compression_tools[@]}"
        "${system_tools[@]}"
        "${productivity_tools[@]}"
        "${fonts_and_graphics[@]}"
        "${security_tools[@]}"
        "${network_tools[@]}"
        "${monitoring_tools[@]}"
        "${nvidia_packages[@]}"
    )

    for pkg in "${packages[@]}"; do
        if ! sudo pacman -S --noconfirm "$pkg"; then
            echo "Erro ao instalar o pacote $pkg."
            exit 1
        fi
    done
    echo "Dependências básicas instaladas com sucesso."
}

# Função para instalar o paru (AUR helper)
install_paru() {
    echo "Instalando o paru..."
    if [ ! -d "paru" ]; then
        if ! git clone https://aur.archlinux.org/paru.git; then
            echo "Erro ao clonar o repositório do paru."
            exit 1
        fi
    fi

    cd paru
    if ! makepkg -si --noconfirm; then
        echo "Erro ao instalar o paru."
        exit 1
    fi
    cd ..
    rm -rf paru
    echo "Paru instalado com sucesso."
}

# Função para instalar pacotes do AUR usando o paru
install_aur_packages() {
    echo "Instalando pacotes do AUR..."

    # Pacotes do AUR
    local aur_packages=(
        google-chrome aic94xx-firmware qed-git ast-firmware wd719x-firmware
        upd72020x-fw onlyoffice-bin teamviewer extension-manager coolercontrol
    )

    for pkg in "${aur_packages[@]}"; do
        if ! paru -S --noconfirm "$pkg"; then
            echo "Erro ao instalar o pacote AUR $pkg."
            exit 1
        fi
    done
    echo "Pacotes do AUR instalados com sucesso."
}

# Função para habilitar serviços
enable_services() {
    echo "Ativando o fwupd-refresh.timer..."
    if ! sudo systemctl enable --now fwupd-refresh.timer; then
        echo "Erro ao ativar o fwupd-refresh.timer."
        exit 1
    fi

    echo "Ativando o bluetooth..."
    if ! sudo systemctl enable --now bluetooth.service; then
        echo "Erro ao ativar o bluetooth."
        exit 1
    fi

    echo "Ativando o teamviewer..."
    if ! sudo systemctl enable --now teamviewerd.service; then
        echo "Erro ao ativar o teamviewer."
        exit 1
    fi
    echo "Serviços ativados com sucesso."
}

# Função para configurar o /etc/kernel/cmdline
configure_kernel_cmdline() {
    echo "Configurando o /etc/kernel/cmdline..."
    local desired_param="nvidia-drm.modeset=1 nvidia_drm.fbdev=1 nouveau.modeset=0 loglevel=3 quiet splash"

    if [ -f /etc/kernel/cmdline ]; then
        local current_cmdline
        current_cmdline=$(cat /etc/kernel/cmdline)

        if ! echo "$current_cmdline" | grep -q "nvidia-drm.modeset=1"; then
            local new_cmdline="$current_cmdline $desired_param"
            if ! echo "$new_cmdline" | sudo tee /etc/kernel/cmdline > /dev/null; then
                echo "Erro ao adicionar o parâmetro ao /etc/kernel/cmdline."
                exit 1
            fi
            echo "Parâmetro adicionado ao /etc/kernel/cmdline."
        else
            echo "O parâmetro já está presente no /etc/kernel/cmdline."
        fi
    else
        echo "Arquivo /etc/kernel/cmdline não encontrado. Nenhuma alteração foi feita."
    fi
}

# Função para configurar o /etc/mkinitcpio.conf para NVIDIA
configure_mkinitcpio() {
    echo "Configurando o /etc/mkinitcpio.conf para NVIDIA..."
    local nvidia_modules="nvidia nvidia_modeset nvidia_uvm nvidia_drm"

    if ! grep -q "MODULES=(.*nvidia.*)" /etc/mkinitcpio.conf; then
        if ! sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 '"$nvidia_modules"')/' /etc/mkinitcpio.conf; then
            echo "Erro ao adicionar módulos da NVIDIA ao /etc/mkinitcpio.conf."
            exit 1
        fi
        echo "Módulos da NVIDIA adicionados ao /etc/mkinitcpio.conf."
    else
        echo "Os módulos da NVIDIA já estão presentes no /etc/mkinitcpio.conf."
    fi

    if grep -q "HOOKS=(.*kms.*)" /etc/mkinitcpio.conf; then
        if ! sudo sed -i 's/\(HOOKS=(.*\)kms\(.*)\)/\1\2/' /etc/mkinitcpio.conf; then
            echo "Erro ao remover kms da linha HOOKS no /etc/mkinitcpio.conf."
            exit 1
        fi
        echo "kms removido da linha HOOKS no /etc/mkinitcpio.conf."
    else
        echo "kms não está presente na linha HOOKS do /etc/mkinitcpio.conf."
    fi
}

# Função para desabilitar o driver nouveau
disable_nouveau() {
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
}

# Função para regenerar a imagem do initramfs
regenerate_initramfs() {
    echo "Regenerando a imagem do initramfs..."
    if ! sudo mkinitcpio -P; then
        echo "Erro ao regenerar a imagem do initramfs."
        exit 1
    fi
    echo "Imagem do initramfs regenerada com sucesso."
}

# Função para configurar o arquivo /etc/environment
configure_environment() {
    echo "Configurando o arquivo /etc/environment..."
    local environment_vars=(
        "GBM_BACKEND=nvidia-drm"
        "__GLX_VENDOR_LIBRARY_NAME=nvidia"
    )

    for var in "${environment_vars[@]}"; do
        if ! grep -q "$var" /etc/environment; then
            if ! echo "$var" | sudo tee -a /etc/environment > /dev/null; then
                echo "Erro ao adicionar $var ao /etc/environment."
                exit 1
            fi
            echo "$var adicionado ao /etc/environment."
        else
            echo "$var já está presente no /etc/environment."
        fi
    done
}

# Função principal
main() {
    update_system
    install_dependencies
    install_paru
    install_aur_packages
    enable_services
    configure_kernel_cmdline
    configure_mkinitcpio
    disable_nouveau
    regenerate_initramfs
    configure_environment

    echo "Instalação concluída com sucesso!"
}

# Executa a função principal
main
