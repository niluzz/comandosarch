#!/bin/bash

# =============================================
# TLP MANAGER - DELL INSPIRON 15 3535 AMD
# Com correções automáticas de governadores
# =============================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funções de log
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Menu principal
show_menu() {
    echo -e "${GREEN}"
    echo "============================================="
    echo "           TLP MANAGER - AMD OPTIMIZED"
    echo "     Com correções automáticas de governadores"
    echo "============================================="
    echo -e "${NC}"
    echo "1) Instalação Completa do TLP"
    echo "2) Verificação Rápida do Sistema"
    echo "3) Sair"
    echo
    read -p "Selecione uma opção [1-3]: " choice
}

# Verificar se é root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Execute como usuário normal, senha será solicitada quando necessário."
        exit 1
    fi
}

# Detectar sistema
detect_system() {
    log_info "Detectando hardware..."
    CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
    GPU_MODEL=$(lspci | grep -i vga | head -1 | cut -d: -f3 | xargs)
    
    log_info "CPU: $CPU_MODEL"
    log_info "GPU: $GPU_MODEL"
}

# Verificar e corrigir governadores automaticamente
check_and_fix_governors() {
    log_info "Verificando e corrigindo governadores de CPU..."
    
    if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors" ]; then
        AVAILABLE_GOVERNORS=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)
        log_info "Governadores disponíveis: $AVAILABLE_GOVERNORS"
        
        # Determinar melhores governadores baseados na disponibilidade
        if echo "$AVAILABLE_GOVERNORS" | grep -q "ondemand"; then
            GOV_AC="ondemand"
        elif echo "$AVAILABLE_GOVERNORS" | grep -q "performance"; then
            GOV_AC="performance"
        else
            GOV_AC=$(echo "$AVAILABLE_GOVERNORS" | cut -d' ' -f1)
        fi
        
        if echo "$AVAILABLE_GOVERNORS" | grep -q "powersave"; then
            GOV_BAT="powersave"
        elif echo "$AVAILABLE_GOVERNORS" | grep -q "conservative"; then
            GOV_BAT="conservative"
        else
            GOV_BAT="$GOV_AC"  # Usa o mesmo que AC se não encontrar opção melhor
        fi
        
        log_success "Governadores configurados: AC=$GOV_AC | BAT=$GOV_BAT"
        return 0
    else
        log_warning "Não foi possível acessar governadores, usando configuração padrão"
        GOV_AC="ondemand"
        GOV_BAT="powersave"
        return 1
    fi
}

# Instalar pacotes necessários
install_packages() {
    log_info "Instalando pacotes TLP..."
    sudo pacman -S --noconfirm tlp tlp-rdw
    log_success "Pacotes TLP instalados!"
}

# Configurar TLP com governadores corrigidos
configure_tlp() {
    log_info "Configurando TLP com governadores corrigidos..."
    
    # Verificar e corrigir governadores
    check_and_fix_governors
    
    # Backup do arquivo original
    if [ -f "/etc/tlp.conf" ]; then
        sudo cp /etc/tlp.conf /etc/tlp.conf.backup.$(date +%Y%m%d_%H%M%S)
        log_info "Backup do tlp.conf criado"
    fi
    
    # Configuração TLP com governadores corrigidos
    sudo tee /etc/tlp.conf > /dev/null << EOF
# ============================================================================
# TLP CONFIGURAÇÃO - DELL INSPIRON 15 3535 AMD
# Governadores corrigidos automaticamente
# ============================================================================

# --- CONFIGURAÇÃO BÁSICA ---
TLP_ENABLE=1
TLP_DEFAULT_MODE=AC
TLP_PERSISTENT_DEFAULT=0

# --- CPU AMD RYZEN 5 7520U ---
CPU_SCALING_GOVERNOR_ON_AC=$GOV_AC
CPU_SCALING_GOVERNOR_ON_BAT=$GOV_BAT
CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=power
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0

# AMD P-State para Zen 2
AMD_PSTATE_ENABLE=1
AMD_PSTATE_MODE=guided

# Limites de performance
CPU_MIN_PERF_ON_AC=0
CPU_MAX_PERF_ON_AC=100
CPU_MIN_PERF_ON_BAT=0
CPU_MAX_PERF_ON_BAT=80

# --- GPU AMD RADEON 610M ---
RADEON_DPM_STATE_ON_AC=performance
RADEON_DPM_STATE_ON_BAT=battery
RADEON_DPM_PERF_LEVEL_ON_AC=auto
RADEON_DPM_PERF_LEVEL_ON_BAT=low
RADEON_POWER_PROFILE_ON_AC=high
RADEON_POWER_PROFILE_ON_BAT=low

# --- SSD NVMe ---
DISK_DEVICES="nvme0n1"
DISK_APM_LEVEL_ON_AC="254"
DISK_APM_LEVEL_ON_BAT="128"
DISK_IOSCHED="none"
NVME_POWERMGMT_ON_AC=medium
NVME_POWERMGMT_ON_BAT=minimal

# --- PLATFORM PROFILE ---
PLATFORM_PROFILE_ON_AC=balanced
PLATFORM_PROFILE_ON_BAT=low-power

# --- REDE WIFI ---
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

    log_success "Configuração TLP aplicada com governadores corrigidos!"
}

# Configurar serviços
setup_services() {
    log_info "Configurando serviços TLP..."
    
    sudo systemctl mask systemd-rfkill.service 2>/dev/null || true
    sudo systemctl mask systemd-rfkill.socket 2>/dev/null || true
    sudo systemctl enable tlp.service
    
    # Verificar se tlp-sleep existe antes de habilitar
    if systemctl list-unit-files | grep -q tlp-sleep.service; then
        sudo systemctl enable tlp-sleep.service
    fi
    
    sudo systemctl restart tlp.service
    log_success "Serviços TLP configurados!"
}

# Criar aliases de verificação
create_aliases() {
    log_info "Criando aliases de verificação..."
    
    if ! grep -q "TLP Verification Aliases" ~/.bashrc; then
        cat >> ~/.bashrc << 'EOF'

# ============================================================================
# TLP VERIFICATION ALIASES
# ============================================================================
alias tlp-status='sudo tlp-stat -s'
alias tlp-battery='sudo tlp-stat -b'
alias tlp-check='echo "=== TLP Service ===" && systemctl is-active tlp; echo "=== Power Source ===" && cat /sys/class/power_supply/AC/online 2>/dev/null | sed "s/1/AC/;s/0/Battery/"; echo "=== CPU Governors ===" && cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u | tr "\n" " "; echo ""'
alias system-stats='echo "=== System Status ==="; tlp-check; echo "=== Battery Info ==="; cat /sys/class/power_supply/BAT1/capacity 2>/dev/null | awk "{print \"Battery: \" \$1 \"%\"}" || echo "Battery: N/A"; echo "=== Power Consumption ==="; cat /sys/class/power_supply/BAT1/power_now 2>/dev/null | awk "{print \"Consumption: \" \$1/1000000 \" W\"}" || echo "Consumption: N/A"'
EOF
    fi
    
    log_success "Aliases criados! Execute 'source ~/.bashrc' para carregar."
}

# Verificação completa do sistema
system_verification() {
    echo -e "${GREEN}"
    echo "🔍 VERIFICAÇÃO COMPLETA DO SISTEMA"
    echo "=================================="
    echo -e "${NC}"
    
    # Serviço TLP
    log_info "=== SERVIÇO TLP ==="
    if systemctl is-active tlp >/dev/null 2>&1; then
        log_success "✓ TLP service: ATIVO"
    else
        log_error "✗ TLP service: INATIVO"
    fi
    
    # Status TLP
    log_info "=== STATUS TLP ==="
    sudo tlp-stat -s 2>/dev/null | grep -E "(TLP enable|Mode|Power source)" | head -3 | while read line; do
        log_info "$line"
    done
    
    # Governadores de CPU
    log_info "=== CPU GOVERNORS ==="
    if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" ]; then
        CURRENT_GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
        log_success "✓ Governador atual: $CURRENT_GOV"
        
        # Verificar se há erros nos logs
        log_info "=== VERIFICAÇÃO DE ERROS ==="
        ERRORS=$(sudo journalctl -u tlp.service -n 10 2>/dev/null | grep -i "error\|fail" | tail -3)
        if [ -n "$ERRORS" ]; then
            log_error "Erros encontrados:"
            echo "$ERRORS"
        else
            log_success "✓ Nenhum erro encontrado nos logs"
        fi
    else
        log_warning "✗ Governadores não disponíveis"
    fi
    
    # Bateria
    log_info "=== BATERIA ==="
    if [ -f "/sys/class/power_supply/BAT1/capacity" ]; then
        BATTERY=$(cat /sys/class/power_supply/BAT1/capacity)
        STATUS=$(cat /sys/class/power_supply/BAT1/status 2>/dev/null || echo "unknown")
        log_success "✓ Bateria: $BATTERY% ($STATUS)"
    else
        log_warning "✗ Informações da bateria não disponíveis"
    fi
    
    # Fonte de energia
    log_info "=== FONTE DE ENERGIA ==="
    if [ -f "/sys/class/power_supply/AC/online" ]; then
        AC_STATUS=$(cat /sys/class/power_supply/AC/online)
        if [ "$AC_STATUS" = "1" ]; then
            log_info "✓ Conectado na tomada (AC)"
        else
            log_info "✓ Modo bateria (BAT)"
        fi
    fi
    
    echo
    log_success "Verificação concluída!"
}

# Instalação completa
install_complete() {
    echo -e "${GREEN}"
    echo "============================================="
    echo "        INSTALAÇÃO COMPLETA DO TLP"
    echo "   Com correções automáticas de governadores"
    echo "============================================="
    echo -e "${NC}"
    
    check_root
    detect_system
    install_packages
    configure_tlp
    setup_services
    create_aliases
    
    echo
    log_success "✅ INSTALAÇÃO CONCLUÍDA!"
    log_info "📋 Comandos disponíveis após executar: source ~/.bashrc"
    log_info "   system-stats    - Status completo do sistema"
    log_info "   tlp-check       - Verificação rápida do TLP"
    log_info "   tlp-status      - Status detalhado do TLP"
    echo
}

# Execução principal
main() {
    while true; do
        show_menu
        
        case $choice in
            1)
                install_complete
                ;;
            2)
                system_verification
                ;;
            3)
                log_info "Saindo..."
                exit 0
                ;;
            *)
                log_error "Opção inválida!"
                ;;
        esac
        
        echo
        read -p "Pressione Enter para continuar..."
        clear
    done
}

# Executar
main "$@"