#!/bin/bash

# Atualiza o sistema
echo "Atualizando o sistema..."
if ! sudo pacman -Syu --noconfirm; then
    echo "Erro ao atualizar o sistema. Verifique sua conexão com a internet."
    exit 1
fi

# Instala dependências básicas
echo "Instalando dependências básicas..."
if ! sudo pacman -S --noconfirm git base-devel file-roller p7zip unrar unzip pacman-contrib sssd firefox-i18n-pt-br discord telegram-desktop qbittorrent bluez-utils kcalc clamav ttf-dejavu-nerd ttf-hack-nerd fwupd libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau lib32-mesa-vdpau showtime papers geary gnome-firmware amf-headers power-profiles-daemon neofetch; then
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
if ! paru -S --noconfirm google-chrome aic94xx-firmware qed-git ast-firmware wd719x-firmware upd72020x-fw onlyoffice-bin teamviewer extension-manager; then
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

# Verifica e completa os parâmetros no /etc/cmdline
echo "Verificando e completando os parâmetros no /etc/cmdline..."

# Parâmetros desejados
desired_params="rootfstype=btrfs amdgpu.dcdebugmask=0x10 quiet splash"

if [ -f /etc/cmdline ]; then
    # Lê o conteúdo atual do arquivo
    current_cmdline=$(cat /etc/cmdline)

    # Verifica e adiciona os parâmetros que faltam
    for param in $desired_params; do
        if ! echo "$current_cmdline" | grep -q "$param"; then
            current_cmdline="$current_cmdline $param"
        fi
    done

    # Sobrescreve o arquivo com o novo conteúdo
    echo "$current_cmdline" | sudo tee /etc/cmdline > /dev/null
    echo "Parâmetros verificados e completados no /etc/cmdline."
else
    # Cria o arquivo /etc/cmdline se ele não existir
    echo "$desired_params" | sudo tee /etc/cmdline > /dev/null
    echo "Arquivo /etc/cmdline criado com os parâmetros."
fi

# Adiciona o módulo amdgpu ao /etc/mkinitcpio.conf
echo "Adicionando o módulo amdgpu ao /etc/mkinitcpio.conf..."
if grep -q "MODULES=(.*amdgpu.*)" /etc/mkinitcpio.conf; then
    echo "O módulo amdgpu já está presente no /etc/mkinitcpio.conf."
else
    # Adiciona o módulo amdgpu dentro dos parênteses de MODULES
    sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 amdgpu)/' /etc/mkinitcpio.conf
    echo "Módulo amdgpu adicionado ao /etc/mkinitcpio.conf."
fi

# Regenera a imagem do initramfs
echo "Regenerando a imagem do initramfs..."
sudo mkinitcpio -P
echo "Imagem do initramfs regenerada com sucesso."

# Mensagem final
echo "Instalação concluída!"
