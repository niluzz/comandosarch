#!/bin/bash
set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Arquivo de configuração para pacotes adicionais
CONFIG_FILE="$HOME/.arch-setup-packages.conf"

# =============================================================================
# FUNÇÕES PRINCIPAIS
# =============================================================================

print_header() {
    echo -e "${CYAN}"
    echo "=========================================="
    echo "   ARCH LINUX SETUP - AMD & NVIDIA"
    echo "=========================================="
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# =============================================================================
# CONFIGURAÇÃO DE PACOTES
# =============================================================================

initialize_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << 'EOF'
# Arquivo de configuração para pacotes adicionais
# Adicone pacotes aqui no formato: PACOTES_ADICIONAIS="pacote1 pacote2"

# Pacotes adicionais do repositório oficial
PACOTES_ADICIONAIS_OFICIAIS=""

# Pacotes adicionais do AUR
PACOTES_ADICIONAIS_AUR=""

# Configuração de GPU (amd/nvidia/auto)
GPU_CONFIG="auto"
EOF
    fi
    source "$CONFIG_FILE"
}

save_config() {
    cat > "$CONFIG_FILE" << EOF
# Arquivo de configuração para pacotes adicionais
# Adicone pacotes aqui no formato: PACOTES_ADICIONAIS="pacote1 pacote2"

# Pacotes adicionais do repositório oficial
PACOTES_ADICIONAIS_OFICIAIS="$PACOTES_ADICIONAIS_OFICIAIS"

# Pacotes adicionais do AUR
PACOTES_ADICIONAIS_AUR="$PACOTES_ADICIONAIS_AUR"

# Configuração de GPU (amd/nvidia/auto)
GPU_CONFIG="$GPU_CONFIG"
EOF
}

add_custom_packages() {
    echo -e "${CYAN}"
    echo "=========================================="
    echo "   ADICIONAR PACOTES PERSONALIZADOS"
    echo "=========================================="
    echo -e "${NC}"
    
    echo -e "${YELLOW}Pacotes oficiais atuais: $PACOTES_ADICIONAIS_OFICIAIS${NC}"
    echo -e "${YELLOW}Pacotes AUR atuais: $PACOTES_ADICIONAIS_AUR${NC}"
    echo
    
    read -p "Deseja adicionar pacotes oficiais? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        read -p "Digite os pacotes oficiais (separados por espaço): " oficiais
        if [ ! -z "$oficiais" ]; then
            PACOTES_ADICIONAIS_OFICIAIS="$PACOTES_ADICIONAIS_OFICIAIS $oficiais"
        fi
    fi
    
    read -p "Deseja adicionar pacotes AUR? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        read -p "Digite os pacotes AUR (separados por espaço): " aur
        if [ ! -z "$aur" ]; then
            PACOTES_ADICIONAIS_AUR="$PACOTES_ADICIONAIS_AUR $aur"
        fi
    fi
    
    save_config
    print_success "Pacotes personalizados atualizados!"
}

# =============================================================================
# DETECÇÃO E SELEÇÃO DE GPU
# =============================================================================

detect_gpu() {
    if lspci | grep -i "nvidia" > /dev/null; then
        echo "nvidia"
    elif lspci | grep -i "amd" > /dev/null || lspci | grep -i "radeon" > /dev/null; then
        echo "amd"
    else
        echo "unknown"
    fi
}

select_gpu_type() {
    local detected=$(detect_gpu)
    
    echo -e "${CYAN}"
    echo "=========================================="
    echo "        SELEÇÃO DE CONFIGURAÇÃO GPU"
    echo "=========================================="
    echo -e "${NC}"
    
    case $detected in
        "nvidia")
            echo -e "${GREEN}GPU detectada: NVIDIA${NC}"
            ;;
        "amd")
            echo -e "${GREEN}GPU detectada: AMD${NC}"
            ;;
        "unknown")
            echo -e "${YELLOW}GPU não detectada automaticamente${NC}"
            ;;
    esac
    
    echo
    echo "1. Configuração AMD"
    echo "2. Configuração NVIDIA" 
    echo "3. Detecção automática"
    echo "4. Voltar ao menu principal"
    echo
    
    read -p "Selecione uma opção [1-4]: " choice
    
    case $choice in
        1)
            GPU_CONFIG="amd"
            ;;
        2)
            GPU_CONFIG="nvidia"
            ;;
        3)
            GPU_CONFIG="auto"
            ;;
        4)
            return 1
            ;;
        *)
            print_error "Opção inválida!"
            return 1
            ;;
    esac
    
    save_config
    print_success "Configuração GPU definida para: $GPU_CONFIG"
    return 0
}

# =============================================================================
# LISTAS DE PACOTES MODULARES
# =============================================================================

get_base_packages() {
    echo "git zsh base-devel pacman-contrib file-roller p7zip unrar unzip"
    echo "fwupd power-profiles-daemon mesa-utils ibus showtime papers"
}

get_browser_packages() {
    echo "firefox-i18n-pt-br discord telegram-desktop"
}

get_media_packages() {
    echo "ffmpeg gstreamer gst-plugins-base gst-plugins-good"
    echo "gst-plugins-bad gst-plugins-ugly gst-libav"
    echo "libdvdread libdvdnav libdvdcss handbrake ffmpegthumbnailer"
}

get_font_packages() {
    echo "ttf-firacode-nerd ttf-dejavu-nerd ttf-hack-nerd inter-font"
    echo "noto-fonts noto-fonts-emoji ttf-montserrat ttf-opensans ttf-roboto"
}

get_amd_packages() {
    echo "vulkan-radeon lib32-vulkan-radeon mesa-vdpau libva-mesa-driver"
}

get_nvidia_packages() {
    echo "nvidia nvidia-utils nvidia-settings lib32-nvidia-utils nvidia-prime"
    echo "jellyfin-ffmpeg jellyfin-server jellyfin-web openrgb"
}

get_extra_packages() {
    echo "qbittorrent newsflash amf-headers dialect gufw"
}

get_aur_packages() {
    echo "google-chrome onlyoffice-bin extension-manager"
    echo "auto-cpufreq mangojuice phinger-cursors"
}

get_nvidia_aur_packages() {
    echo "protonplus"
}

# =============================================================================
# INSTALAÇÃO DE PACOTES
# =============================================================================

install_paru() {
    if ! command -v paru &>/dev/null; then
        print_info "Instalando Paru (AUR helper)..."
        git clone https://aur.archlinux.org/paru.git /tmp/paru
        cd /tmp/paru
        makepkg -si --noconfirm
        cd -
        print_success "Paru instalado com sucesso!"
    else
        print_info "Paru já está instalado."
    fi
}

install_official_packages() {
    local gpu_type=$1
    print_info "Instalando pacotes oficiais..."
    
    # Pacotes base
    local packages="$(get_base_packages) $(get_browser_packages) $(get_media_packages) $(get_font_packages) $(get_extra_packages)"
    
    # Pacotes específicos da GPU
    case $gpu_type in
        "amd")
            packages="$packages $(get_amd_packages)"
            ;;
        "nvidia")  
            packages="$packages $(get_nvidia_packages)"
            ;;
    esac
    
    # Adicionar pacotes personalizados
    packages="$packages $PACOTES_ADICIONAIS_OFICIAIS"
    
    # Instalar pacotes
    sudo pacman -S --needed --noconfirm $packages
}

install_aur_packages() {
    local gpu_type=$1
    print_info "Instalando pacotes do AUR..."
    
    # Pacotes base AUR
    local aur_packages="$(get_aur_packages)"
    
    # Pacotes específicos da GPU AUR
    case $gpu_type in
        "nvidia")
            aur_packages="$aur_packages $(get_nvidia_aur_packages)"
            ;;
    esac
    
    # Adicionar pacotes personalizados AUR
    aur_packages="$aur_packages $PACOTES_ADICIONAIS_AUR"
    
    # Instalar pacotes AUR
    paru -S --needed --noconfirm $aur_packages
}

# =============================================================================
# CONFIGURAÇÃO DO SISTEMA
# =============================================================================

configure_kernel() {
    local gpu_type=$1
    print_info "Configurando parâmetros do kernel..."
    
    MKINIT_FILE="/etc/mkinitcpio.conf"
    CMDLINE_FILE="/etc/kernel/cmdline"
    
    # Configurar mkinitcpio.conf
    case $gpu_type in
        "amd")
            if ! grep -E "^MODULES=.*amdgpu" "$MKINIT_FILE"; then
                sudo sed -i 's/^MODULES=(/MODULES=(amdgpu /' "$MKINIT_FILE"
                print_success "Parâmetro 'amdgpu' adicionado em MODULES."
            fi
            ;;
        "nvidia")
            if ! grep -E "^MODULES=.*nvidia" "$MKINIT_FILE"; then
                sudo sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' "$MKINIT_FILE"
                print_success "Parâmetros 'nvidia*' adicionados em MODULES."
            fi
            ;;
    esac
    
    # Configurar kernel cmdline
    case $gpu_type in
        "amd")
            local params="quiet splash iommu=pt"
            ;;
        "nvidia")
            local params="quiet splash nvidia-drm.modeset=1 nvidia-drm.fbdev=1 iommu=pt"
            ;;
        *)
            local params="quiet splash iommu=pt"
            ;;
    esac
    
    for param in $params; do
        if ! grep -qw "$param" "$CMDLINE_FILE" 2>/dev/null; then
            sudo sh -c "echo '$param' >> '$CMDLINE_FILE'"
            print_success "Parâmetro '$param' adicionado ao kernel cmdline."
        fi
    done
    
    # Recriar initramfs
    sudo mkinitcpio -P
    print_success "Configuração do kernel concluída!"
}

enable_services() {
    local gpu_type=$1
    print_info "Habilitando serviços..."
    
    # Serviços comuns
    sudo systemctl enable --now fwupd-refresh.timer
    sudo systemctl enable --now bluetooth.service
    sudo systemctl enable --now auto-cpufreq.service
    
    # Serviços específicos
    case $gpu_type in
        "nvidia")
            sudo systemctl enable --now jellyfin.service
            ;;
    esac
    
    print_success "Serviços habilitados!"
}

# =============================================================================
# INSTALAÇÃO PRINCIPAL
# =============================================================================

run_installation() {
    local gpu_type=$1
    
    if [ "$gpu_type" = "auto" ]; then
        gpu_type=$(detect_gpu)
        if [ "$gpu_type" = "unknown" ]; then
            print_error "Não foi possível detectar a GPU automaticamente!"
            return 1
        fi
    fi
    
    echo -e "${CYAN}"
    echo "=========================================="
    echo "  INICIANDO INSTALAÇÃO PARA GPU: ${gpu_type^^}"
    echo "=========================================="
    echo -e "${NC}"
    
    # Atualizar sistema
    print_info "Atualizando sistema..."
    sudo pacman -Syu --noconfirm
    
    # Instalar pacotes
    install_official_packages "$gpu_type"
    install_paru
    install_aur_packages "$gpu_type"
    
    # Configurar sistema
    configure_kernel "$gpu_type"
    enable_services "$gpu_type"
    
    print_success "Instalação concluída com sucesso! 🚀"
    echo -e "${YELLOW}GPU configurada: ${gpu_type^^}${NC}"
}

# =============================================================================
# MENU PRINCIPAL
# =============================================================================

show_main_menu() {
    while true; do
        echo -e "${CYAN}"
        echo "=========================================="
        echo "    ARCH LINUX SETUP - MENU PRINCIPAL"
        echo "=========================================="
        echo -e "${NC}"
        
        echo -e "${YELLOW}Configuração atual:${NC}"
        echo -e "  GPU: $GPU_CONFIG"
        echo -e "  Pacotes oficiais adicionais: $PACOTES_ADICIONAIS_OFICIAIS"
        echo -e "  Pacotes AUR adicionais: $PACOTES_ADICIONAIS_AUR"
        echo
        
        echo "1. 🔧  Selecionar tipo de GPU (Atual: $GPU_CONFIG)"
        echo "2. 📦  Adicionar pacotes personalizados"
        echo "3. 🚀  Executar instalação completa"
        echo "4. 🔍  Verificar configuração atual"
        echo "5. 🗑️   Limpar pacotes personalizados"
        echo "6. ❌  Sair"
        echo
        
        read -p "Selecione uma opção [1-6]: " choice
        
        case $choice in
            1)
                select_gpu_type
                ;;
            2)
                add_custom_packages
                ;;
            3)
                run_installation "$GPU_CONFIG"
                ;;
            4)
                show_current_config
                ;;
            5)
                clear_custom_packages
                ;;
            6)
                print_success "Saindo... Até logo! 👋"
                exit 0
                ;;
            *)
                print_error "Opção inválida!"
                ;;
        esac
        
        echo
        read -p "Pressione Enter para continuar..."
        clear
    done
}

show_current_config() {
    echo -e "${CYAN}"
    echo "=========================================="
    echo "        CONFIGURAÇÃO ATUAL"
    echo "=========================================="
    echo -e "${NC}"
    
    echo -e "${YELLOW}Configuração GPU:${NC} $GPU_CONFIG"
    echo -e "${YELLOW}Pacotes oficiais adicionais:${NC} $PACOTES_ADICIONAIS_OFICIAIS"
    echo -e "${YELLOW}Pacotes AUR adicionais:${NC} $PACOTES_ADICIONAIS_AUR"
    echo
    echo -e "${GREEN}Pacotes base incluídos:${NC}"
    echo -e "  📦 $(get_base_packages | tr '\n' ' ')"
    echo -e "  🌐 $(get_browser_packages | tr '\n' ' ')"
    echo -e "  🎵 $(get_media_packages | tr '\n' ' ')"
    echo -e "  🔤 $(get_font_packages | tr '\n' ' ')"
    echo
    echo -e "${BLUE}Pacotes AMD:${NC} $(get_amd_packages | tr '\n' ' ')"
    echo -e "${BLUE}Pacotes NVIDIA:${NC} $(get_nvidia_packages | tr '\n' ' ')"
}

clear_custom_packages() {
    PACOTES_ADICIONAIS_OFICIAIS=""
    PACOTES_ADICIONAIS_AUR=""
    save_config
    print_success "Pacotes personalizados limpos!"
}

# =============================================================================
# INICIALIZAÇÃO
# =============================================================================

main() {
    # Verificar se é root
    if [ "$EUID" -eq 0 ]; then
        print_error "Não execute este script como root!"
        exit 1
    fi
    
    # Verificar se é Arch Linux
    if ! grep -q "Arch Linux" /etc/os-release 2>/dev/null; then
        print_error "Este script é apenas para Arch Linux!"
        exit 1
    fi
    
    clear
    print_header
    initialize_config
    show_main_menu
}

# Executar script principal
main "$@"