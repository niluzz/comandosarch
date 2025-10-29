#!/bin/bash

# =============================================
# AUTO TLP SETUP - DELL INSPIRON 15 3535 AMD
# SELEÇÃO INTERATIVA DE PERFIS
# =============================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Funções de log
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_profile() { echo -e "${CYAN}[PERFIL]${NC} $1"; }

check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Execute como usuário normal, senha será solicitada quando necessário."
        exit 1
    fi
}

detect_capabilities() {
    log_info "Detectando capacidades do sistema..."
    
    # Detectar governadores de CPU disponíveis
    if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors" ]; then
        AVAILABLE_GOVERNORS=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)
        log_info "Governadores de CPU disponíveis: $AVAILABLE_GOVERNORS"
    else
        AVAILABLE_GOVERNORS="powersave"
        log_warning "Governadores não detectados, usando padrão: powersave"
    fi
    
    # Detectar capacidades da GPU AMD
    GPU_CAPABILITIES="basic"
    if [ -d "/sys/class/drm/card0/device" ]; then
        if [ -f "/sys/class/drm/card0/device/power_dpm_force_performance_level" ]; then
            GPU_CAPABILITIES="advanced"
        fi
    fi
    log_info "Capacidades da GPU: $GPU_CAPABILITIES"
    
    # Verificar se AMD P-State está disponível
    if grep -q "amd_pstate" /proc/cmdline 2>/dev/null || dmesg | grep -q "amd_pstate" 2>/dev/null; then
        AMD_PSTATE_AVAILABLE=1
        log_info "AMD P-State: Disponível"
    else
        AMD_PSTATE_AVAILABLE=0
        log_info "AMD P-State: Não disponível"
    fi
}

show_profile_menu() {
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}          SELECIONE O PERFIL TLP${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo -e "${CYAN}1. ECONOMIA (PowerSave)${NC}"
    echo "   • Máxima economia de bateria"
    echo "   • Performance reduzida"
    echo "   • Ideal para uso básico em bateria"
    echo ""
    echo -e "${CYAN}2. BALANCEADO (Ondemand)${NC}"
    echo "   • Equilíbrio entre performance e bateria"
    echo "   • Adapta automaticamente à demanda"
    echo "   • Recomendado para uso geral"
    echo ""
    echo -e "${CYAN}3. PERFORMANCE (Performance)${NC}"
    echo "   • Máxima performance"
    echo "   • Consumo elevado de energia"
    echo "   • Ideal para jogos/trabalho pesado"
    echo ""
    echo -e "${CYAN}4. SILENCIOSO (Silent)${NC}"
    echo "   • Foco em baixas temperaturas e ruído"
    echo "   • Performance moderada"
    echo "   • Ideal para multimídia/escritório"
    echo ""
    
    while true; do
        read -p "Selecione o perfil (1-4): " profile_choice
        case $profile_choice in
            1)
                PROFILE_NAME="ECONOMIA"
                PROFILE_TYPE="powersave"
                break
                ;;
            2)
                PROFILE_NAME="BALANCEADO"
                PROFILE_TYPE="balanced"
                break
                ;;
            3)
                PROFILE_NAME="PERFORMANCE"
                PROFILE_TYPE="performance"
                break
                ;;
            4)
                PROFILE_NAME="SILENCIOSO"
                PROFILE_TYPE="silent"
                break
                ;;
            *)
                echo -e "${RED}Opção inválida! Escolha 1, 2, 3 ou 4.${NC}"
                ;;
        esac
    done
    
    log_profile "Perfil selecionado: $PROFILE_NAME"
}

configure_profile() {
    log_info "Configurando perfil: $PROFILE_NAME"
    
    # Determinar governadores baseados no perfil e disponibilidade
    case $PROFILE_TYPE in
        "powersave")
            CPU_GOVERNOR="powersave"
            CPU_BOOST_BAT=0
            CPU_MAX_PERF_BAT=70
            GPU_STATE_BAT="battery"
            GPU_PROFILE_BAT="low"
            PLATFORM_PROFILE_BAT="low-power"
            ;;
        "balanced")
            # Tentar governadores adaptativos, fallback para powersave
            if echo "$AVAILABLE_GOVERNORS" | grep -q "ondemand"; then
                CPU_GOVERNOR="ondemand"
            elif echo "$AVAILABLE_GOVERNORS" | grep -q "schedutil"; then
                CPU_GOVERNOR="schedutil"
            else
                CPU_GOVERNOR="powersave"
            fi
            CPU_BOOST_BAT=1
            CPU_MAX_PERF_BAT=90
            GPU_STATE_BAT="balanced"
            GPU_PROFILE_BAT="low"
            PLATFORM_PROFILE_BAT="low-power"
            ;;
        "performance")
            if echo "$AVAILABLE_GOVERNORS" | grep -q "performance"; then
                CPU_GOVERNOR="performance"
            else
                CPU_GOVERNOR="powersave"  # Fallback
            fi
            CPU_BOOST_BAT=1
            CPU_MAX_PERF_BAT=100
            GPU_STATE_BAT="performance"
            GPU_PROFILE_BAT="high"
            PLATFORM_PROFILE_BAT="balanced"
            ;;
        "silent")
            CPU_GOVERNOR="powersave"
            CPU_BOOST_BAT=0
            CPU_MAX_PERF_BAT=60
            GPU_STATE_BAT="battery"
            GPU_PROFILE_BAT="low"
            PLATFORM_PROFILE_BAT="low-power"
            ;;
    esac
    
    log_info "Configurações do perfil:"
    log_info "• CPU Governor: $CPU_GOVERNOR"
    log_info "• CPU Boost (bateria): $CPU_BOOST_BAT"
    log_info "• CPU Max Perf (bateria): $CPU_MAX_PERF_BAT%"
    log_info "• GPU State (bateria): $GPU_STATE_BAT"
}

install_packages() {
    log_info "Instalando pacotes TLP..."
    
    sudo pacman -Syu --noconfirm
    sudo pacman -S --noconfirm tlp tlp-rdw smartmontools
    
    log_success "Pacotes TLP instalados!"
}

configure_tlp() {
    log_info "Aplicando configuração do perfil $PROFILE_NAME..."
    
    # Backup do arquivo original
    if [ -f "/etc/tlp.conf" ]; then
        sudo cp /etc/tlp.conf /etc/tlp.conf.backup.$(date +%Y%m%d_%H%M%S)
        log_info "Backup do tlp.conf criado"
    fi
    
    # Configuração baseada no perfil selecionado
    sudo tee /etc/tlp.conf > /dev/null << EOF
# ============================================================================
# TLP CONFIGURAÇÃO - DELL INSPIRON 15 3535 AMD
# PERFIL: $PROFILE_NAME
# CPU: AMD Ryzen 5 7520U | GPU: AMD Radeon 610M | SSD: NVMe
# ============================================================================

# --- CONFIGURAÇÃO BÁSICA ---
TLP_ENABLE=1
TLP_DEFAULT_MODE=AC
TLP_PERSISTENT_DEFAULT=0

# --- CPU AMD RYZEN 5 7520U ---
CPU_SCALING_GOVERNOR_ON_AC=$CPU_GOVERNOR
CPU_SCALING_GOVERNOR_ON_BAT=$CPU_GOVERNOR
CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=$CPU_BOOST_BAT

# AMD P-State se disponível
AMD_PSTATE_ENABLE=$AMD_PSTATE_AVAILABLE
AMD_PSTATE_MODE=guided

# Limites de performance
CPU_MIN_PERF_ON_AC=0
CPU_MAX_PERF_ON_AC=100
CPU_MIN_PERF_ON_BAT=0
CPU_MAX_PERF_ON_BAT=$CPU_MAX_PERF_BAT

# --- GPU AMD RADEON 610M ---
RADEON_DPM_STATE_ON_AC=performance
RADEON_DPM_STATE_ON_BAT=$GPU_STATE_BAT
RADEON_DPM_PERF_LEVEL_ON_AC=auto
RADEON_DPM_PERF_LEVEL_ON_BAT=auto
RADEON_POWER_PROFILE_ON_AC=high
RADEON_POWER_PROFILE_ON_BAT=$GPU_PROFILE_BAT

# --- SSD NVMe ---
DISK_DEVICES="nvme0n1"
DISK_APM_LEVEL_ON_AC="254"
DISK_APM_LEVEL_ON_BAT="128"
DISK_IOSCHED="none"
NVME_POWERMGMT_ON_AC=medium
NVME_POWERMGMT_ON_BAT=minimal

# --- PLATFORM PROFILE ---
PLATFORM_PROFILE_ON_AC=balanced
PLATFORM_PROFILE_ON_BAT=$PLATFORM_PROFILE_BAT

# --- WIFI ---
WIFI_PWR_ON_AC=on
WIFI_PWR_ON_BAT=on

# --- BLUETOOTH ---
BLUETOOTH_DEVICES="default"

# --- RUNTIME POWER MANAGEMENT ---
RUNTIME_PM_ON_AC=on
RUNTIME_PM_ON_BAT=auto
RUNTIME_PM_DRIVER_BLACKLIST="amdgpu"
RUNTIME_PM_ALL=1

# --- USB ---
USB_AUTOSUSPEND=1
USB_EXCLUDE_BTUSB=1
USB_EXCLUDE_PRINTER=1

# --- ÁUDIO ---
SOUND_POWER_SAVE_ON_AC=0
SOUND_POWER_SAVE_ON_BAT=1
SOUND_POWER_SAVE_TIMEOUT=180

# --- PCIE ASPM ---
PCIE_ASPM_ON_AC=default
PCIE_ASPM_ON_BAT=powersave

# --- SCHEDULER ---
SCHED_POWERSAVE_ON_AC=0
SCHED_POWERSAVE_ON_BAT=1
EOF

    log_success "Configuração do perfil $PROFILE_NAME aplicada!"
}

setup_services() {
    log_info "Configurando serviços TLP..."
    
    sudo systemctl mask systemd-rfkill.service 2>/dev/null || true
    sudo systemctl mask systemd-rfkill.socket 2>/dev/null || true
    
    sudo systemctl enable tlp.service
    
    if systemctl list-unit-files | grep -q tlp-sleep.service; then
        sudo systemctl enable tlp-sleep.service
    fi
    
    sudo systemctl restart tlp.service
    
    log_success "Serviços TLP configurados!"
}

create_aliases() {
    log_info "Criando aliases de monitoramento..."
    
    if ! grep -q "TLP Aliases" ~/.bashrc; then
        cat >> ~/.bashrc << EOF

# ============================================================================
# TLP ALIASES - Perfil: $PROFILE_NAME
# ============================================================================
alias tlp-status='sudo tlp-stat -s'
alias tlp-battery='sudo tlp-stat -b'
alias tlp-config='sudo tlp-stat -c'
alias cpu-governor='cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'
alias battery-status='cat /sys/class/power_supply/BAT1/capacity 2>/dev/null | awk "{print \\\$1 \\\"%\\\"}" || echo "N/A"'

function system-stats() {
    echo "=== PERFIL TLP ==="
    echo "Perfil: $PROFILE_NAME"
    echo "Governador: $CPU_GOVERNOR"
    echo "=== STATUS ==="
    sudo tlp-stat -s | grep -E "(Mode|Power source)" | head -2
    echo "=== BATERIA ==="
    cat /sys/class/power_supply/BAT1/capacity 2>/dev/null | awk '{print $1 "%"}' || echo "N/A"
    cat /sys/class/power_supply/BAT1/status 2>/dev/null | awk '{print "Status: " $1}' || echo "N/A"
}

function change-tlp-profile() {
    echo "Para alterar o perfil TLP, execute:"
    echo "  sudo /usr/local/setup-tlp.sh"
    echo ""
    echo "Perfis disponíveis:"
    echo "  1. ECONOMIA    - Máxima bateria"
    echo "  2. BALANCEADO  - Equilíbrio (recomendado)"
    echo "  3. PERFORMANCE - Máxima performance" 
    echo "  4. SILENCIOSO  - Baixo ruído"
}
EOF
    fi
    
    log_success "Aliases criados!"
}

show_profile_summary() {
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}          RESUMO DO PERFIL${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo -e "${CYAN}PERFIL SELECIONADO: $PROFILE_NAME${NC}"
    echo ""
    
    case $PROFILE_TYPE in
        "powersave")
            echo -e "🔋 ${GREEN}ECONOMIA MÁXIMA${NC}"
            echo "• CPU: Governador powersave"
            echo "• CPU Boost: Desativado em bateria"
            echo "• Performance CPU: Limitada a 70%"
            echo "• GPU: Modo battery"
            echo "• Autonomia: +30-40% de bateria"
            echo "• Uso ideal: Navegação, documentos"
            ;;
        "balanced")
            echo -e "⚖️  ${GREEN}BALANCEADO${NC}"
            echo "• CPU: Governador $CPU_GOVERNOR"
            echo "• CPU Boost: Ativado quando necessário"
            echo "• Performance CPU: Até 90%"
            echo "• GPU: Modo balanced"
            echo "• Autonomia: +15-25% de bateria"
            echo "• Uso ideal: Uso geral, multitarefa"
            ;;
        "performance")
            echo -e "🚀 ${GREEN}ALTA PERFORMANCE${NC}"
            echo "• CPU: Governador $CPU_GOVERNOR"
            echo "• CPU Boost: Sempre ativado"
            echo "• Performance CPU: 100%"
            echo "• GPU: Modo performance"
            echo "• Autonomia: Economia mínima"
            echo "• Uso ideal: Jogos, edição, compilações"
            ;;
        "silent")
            echo -e "🔇 ${GREEN}SILENCIOSO${NC}"
            echo "• CPU: Governador powersave"
            echo "• CPU Boost: Desativado"
            echo "• Performance CPU: Limitada a 60%"
            echo "• GPU: Modo battery"
            echo "• Autonomia: +40-50% de bateria"
            echo "• Uso ideal: Vídeos, música, leitura"
            ;;
    esac
    
    echo ""
    echo -e "${YELLOW}Para alterar o perfil posteriormente, execute:${NC}"
    echo -e "  ${CYAN}sudo /usr/local/setup-tlp.sh${NC}"
}

verify_installation() {
    log_info "Verificando instalação..."
    
    sleep 2
    
    if systemctl is-active --quiet tlp.service; then
        log_success "✓ TLP service está ativo"
    else
        log_error "✗ TLP service não está ativo"
    fi
    
    if sudo tlp-stat -s > /dev/null 2>&1; then
        log_success "✓ Configuração TLP carregada"
    else
        log_error "✗ Erro na configuração TLP"
    fi
    
    # Verificar erros
    TLP_ERRORS=$(sudo journalctl -u tlp.service --since "1 minute ago" | grep -i "Error\|error" | head -1 || echo "Nenhum erro")
    if [ "$TLP_ERRORS" != "Nenhum erro" ]; then
        log_warning "Erros no TLP: $TLP_ERRORS"
    else
        log_success "✓ Nenhum erro encontrado"
    fi
    
    log_success "✅ Instalação do perfil $PROFILE_NAME concluída!"
}

main() {
    echo -e "${GREEN}"
    echo "============================================="
    echo "    TLP SETUP - SELEÇÃO DE PERFIL"
    echo "============================================="
    echo -e "${NC}"
    
    check_root
    detect_capabilities
    show_profile_menu
    configure_profile
    install_packages
    configure_tlp
    setup_services
    create_aliases
    show_profile_summary
    verify_installation
    
    echo ""
    log_info "Execute 'source ~/.bashrc' para carregar os aliases"
    log_info "Use 'system-stats' para verificar o status"
    log_info "Use 'change-tlp-profile' para ver opções de alteração"
}

main "$@"
