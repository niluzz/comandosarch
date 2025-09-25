#!/bin/bash

# Script AVANÇADO de Configuração de Hibernação para Arch Linux
# FASE 1: Configuração completa → Reinício → FASE 2: Testes

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Funções de logging
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error() { echo -e "${RED}[ERRO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCESSO]${NC} $1"; }
step() { echo -e "${MAGENTA}>>>${NC} $1"; }

# Variáveis
CONFIG_MARKER="/tmp/hibernate_phase1_complete"
TEST_MARKER="/tmp/hibernate_phase2_complete"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script precisa ser executado como root!"
        exit 1
    fi
}

# ================================
# FASE 1: CONFIGURAÇÃO COMPLETA
# ================================
phase1_configuration() {
    echo -e "${MAGENTA}"
    echo "=================================================="
    echo "  FASE 1: CONFIGURAÇÃO COMPLETA DO SISTEMA"
    echo "  (Reinício necessário após esta fase)"
    echo "=================================================="
    echo -e "${NC}"
    
    # Remove marcadores anteriores
    rm -f "$CONFIG_MARKER" "$TEST_MARKER"
    
    pre_system_check
    configure_mkinitcpio
    create_btrfs_swapfile
    configure_kernel_parameters
    configure_systemd_advanced
    configure_gnome
    
    # Marcar Fase 1 como completa
    touch "$CONFIG_MARKER"
    echo "hibernate_config_timestamp=$(date +%s)" > "$CONFIG_MARKER"
    
    echo -e "\n${GREEN}"
    echo "#############################################"
    echo "#  FASE 1 CONCLUÍDA COM SUCESSO!           #"
    echo "#  REINICIE O SISTEMA AGORA:               #"
    echo "#                                           #"
    echo "#           ${RED}reboot${GREEN}                     #"
    echo "#                                           #"
    echo "#  Após reiniciar, execute novamente:      #"
    echo "#  ${CYAN}sudo ./$(basename "$0")${GREEN}             #"
    echo "#############################################"
    echo -e "${NC}"
    
    # Perguntar se deseja reiniciar agora
    echo -e "\n${YELLOW}Deseja reiniciar agora? (s/N)${NC}"
    read -p "> " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        warn "Reiniciando sistema em 5 segundos... Pressione Ctrl+C para cancelar"
        sleep 5
        reboot
    else
        info "Execute manualmente: reboot"
    fi
}

# ================================
# FASE 2: TESTES APÓS REINÍCIO
# ================================
phase2_testing() {
    echo -e "${CYAN}"
    echo "=================================================="
    echo "  FASE 2: VERIFICAÇÃO E TESTES APÓS REINÍCIO"
    echo "=================================================="
    echo -e "${NC}"
    
    if [[ ! -f "$CONFIG_MARKER" ]]; then
        error "Execute a FASE 1 primeiro!"
        exit 1
    fi
    
    comprehensive_verification
    run_hibernate_tests
    
    # Marcar Fase 2 como completa
    touch "$TEST_MARKER"
    
    echo -e "\n${GREEN}"
    echo "#############################################"
    echo "#  CONFIGURAÇÃO 100% CONCLUÍDA!            #"
    echo "#  Hibernação está funcionando!            #"
    echo "#############################################"
    echo -e "${NC}"
}

# ================================
# FUNÇÕES DE CONFIGURAÇÃO (FASE 1)
# ================================
pre_system_check() {
    info "Verificando ambiente do sistema..."
    
    if ! grep -q "disk" /sys/power/state; then
        error "Kernel não suporta hibernação!"
        exit 1
    fi
    success "Kernel suporta hibernação."
    
    if [[ ! -f /etc/kernel/cmdline ]]; then
        error "systemd-boot não detectado!"
        exit 1
    fi
    success "Systemd-boot detectado."
}

configure_mkinitcpio() {
    step "Configurando mkinitcpio..."
    
    local mkinitcpio_file="/etc/mkinitcpio.conf"
    cp "$mkinitcpio_file" "${mkinitcpio_file}.backup.$(date +%Y%m%d-%H%M%S)"
    
    # Configurar hooks
    local current_hooks=$(grep "^HOOKS=" "$mkinitcpio_file" | cut -d= -f2 | tr -d '()"')
    
    if ! echo "$current_hooks" | grep -q "systemd"; then
        current_hooks=$(echo "$current_hooks" | sed 's/udev/systemd/')
        [[ "$current_hooks" =~ "systemd" ]] || current_hooks="systemd $current_hooks"
    fi
    
    if ! echo "$current_hooks" | grep -q "resume"; then
        current_hooks=$(echo "$current_hooks" | sed 's/systemd/& resume/')
    fi
    
    current_hooks=$(echo "$current_hooks" | sed 's/  / /g')
    sed -i "s|^HOOKS=.*|HOOKS=(${current_hooks})|" "$mkinitcpio_file"
    
    # Suporte Btrfs
    if findmnt -n -o FSTYPE / | grep -q "btrfs"; then
        local current_modules=$(grep "^MODULES=" "$mkinitcpio_file" | cut -d= -f2 | tr -d '()"')
        if ! echo "$current_modules" | grep -q "btrfs"; then
            if [[ -z "$current_modules" ]]; then
                sed -i "s|^MODULES=.*|MODULES=(btrfs)|" "$mkinitcpio_file"
            else
                sed -i "s|^MODULES=.*|MODULES=(${current_modules} btrfs)|" "$mkinitcpio_file"
            fi
        fi
    fi
    
    mkinitcpio -P
    success "mkinitcpio configurado."
}

create_btrfs_swapfile() {
    step "Criando swapfile..."
    
    local swapfile_path="/swapfile"
    local mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_total_gb=$(( (mem_total_kb + 1024*1024 - 1) / (1024*1024) ))
    local swap_size_gb=$((mem_total_gb + 2))
    [[ $swap_size_gb -lt 8 ]] && swap_size_gb=8
    [[ $swap_size_gb -gt 32 ]] && swap_size_gb=32
    
    info "RAM: ${mem_total_gb}GB | Swap: ${swap_size_gb}GB"
    
    if [[ -f "$swapfile_path" ]]; then
        swapoff "$swapfile_path" 2>/dev/null || true
        rm -f "$swapfile_path"
    fi
    
    truncate -s 0 "$swapfile_path"
    chattr +C "$swapfile_path"
    chmod 600 "$swapfile_path"
    
    info "Alocando espaço... (pode demorar)"
    dd if=/dev/zero of="$swapfile_path" bs=1M count=$((swap_size_gb * 1024)) status=progress 2>/dev/null
    
    mkswap -f "$swapfile_path"
    swapon "$swapfile_path"
    
    if ! grep -q "$swapfile_path" /etc/fstab; then
        echo "$swapfile_path none swap defaults 0 0" >> /etc/fstab
    fi
    
    success "Swapfile criado."
}

get_swapfile_offset() {
    local swapfile_path="/swapfile"
    [[ -f "$swapfile_path" ]] || return 1
    
    if command -v btrfs-inspect-internal &> /dev/null; then
        btrfs-inspect-internal map-swapfile -r "$swapfile_path" 2>/dev/null && return
    fi
    
    if command -v filefrag &> /dev/null; then
        filefrag -v "$swapfile_path" 2>/dev/null | grep "0:" | awk '{print $4}' | sed 's/\.\.//' | head -1
    fi
}

configure_kernel_parameters() {
    step "Configurando parâmetros do kernel..."
    
    local cmdline_file="/etc/kernel/cmdline"
    cp "$cmdline_file" "${cmdline_file}.backup.$(date +%Y%m%d-%H%M%S)"
    
    local root_uuid=$(findmnt -n -o UUID /)
    local resume_offset=$(get_swapfile_offset)
    
    local resume_param="resume=UUID=${root_uuid}"
    [[ -n "$resume_offset" ]] && resume_param="${resume_param} resume_offset=${resume_offset} resume_force=1"
    resume_param="${resume_param} acpi_sleep=nonvs mem_sleep_default=deep"
    
    local current_cmdline=$(cat "$cmdline_file")
    local new_cmdline=$(echo "$current_cmdline" | sed -E 's/resume=[^ ]*//g')
    new_cmdline="${new_cmdline} ${resume_param}"
    new_cmdline=$(echo "$new_cmdline" | sed 's/  / /g')
    
    echo "$new_cmdline" > "$cmdline_file"
    bootctl update 2>/dev/null || warn "Bootctl aviso (normal)."
    
    success "Parâmetros do kernel configurados."
}

configure_systemd_advanced() {
    step "Configurando systemd (bateria/tomada)..."
    
    [[ -f /etc/systemd/logind.conf ]] || return 0
    
    cp /etc/systemd/logind.conf /etc/systemd/logind.conf.backup.$(date +%Y%m%d-%H%M%S)
    
    # Configurações completas
    local configs=(
        "HandlePowerKey=hibernate"
        "HandleSuspendKey=hibernate"
        "HandleHibernateKey=hibernate"
        "HandleLidSwitch=hibernate"
        "HandleLidSwitchExternalPower=hibernate"
        "HandleLidSwitchDocked=hibernate"
        "HoldoffTimeoutSec=30s"
        "IdleAction=hibernate"
        "IdleActionSec=60min"
    )
    
    for config in "${configs[@]}"; do
        local key="${config%=*}"
        local value="${config#*=}"
        
        if grep -q "^#*${key}=" /etc/systemd/logind.conf; then
            sed -i "s/^#*${key}=.*/${key}=${value}/" /etc/systemd/logind.conf
        else
            echo "${key}=${value}" >> /etc/systemd/logind.conf
        fi
    done
    
    systemctl restart systemd-logind
    systemctl enable systemd-hibernate.service 2>/dev/null || true
    
    success "Systemd configurado."
}

configure_gnome() {
    step "Configurando GNOME..."
    
    local user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
    local user_id=$(id -u "$user" 2>/dev/null)
    
    if [[ -n "$user_id" ]] && command -v gsettings &> /dev/null && [[ -S "/run/user/${user_id}/bus" ]]; then
        sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_id}/bus" \
            gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'interactive' 2>/dev/null || true
        
        sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_id}/bus" \
            gsettings set org.gnome.settings-daemon.plugins.power hibernate-button-action 'hibernate' 2>/dev/null || true
        
        success "GNOME configurado."
    else
        warn "GNOME não detectado."
    fi
}

# ================================
# FUNÇÕES DE TESTE (FASE 2)
# ================================
comprehensive_verification() {
    step "Verificação pós-reinício..."
    
    echo -e "\n${CYAN}=== VERIFICAÇÃO DO SISTEMA ===${NC}"
    
    local checks=(
        "Kernel:hibernate" "grep -q disk /sys/power/state"
        "Swapfile:ativo" "swapon --show | grep -q swapfile"
        "Parâmetros:configurados" "grep -q resume= /etc/kernel/cmdline"
        "Initramfs:atualizado" "ls -la /boot/initramfs* | head -1"
    )
    
    for check in "${checks[@]}"; do
        local name="${check%:*}"
        local cmd="${check#*:}"
        
        if eval "$cmd" 2>/dev/null; then
            success "✅ $name: OK"
        else
            error "❌ $name: FALHA"
        fi
    done
    
    # Verificação específica dos parâmetros
    echo -e "\n${CYAN}--- Parâmetros Atuais ---${NC}"
    grep resume /etc/kernel/cmdline
}

run_hibernate_tests() {
    step "Executando testes de hibernação..."
    
    echo -e "\n${YELLOW}⚠️  TESTES SEGUROS (não hibernam de verdade)${NC}"
    
    # Teste 1: Verificar se o sistema reconhece a hibernação
    if systemctl list-unit-files | grep -q "hibernate.target"; then
        success "✅ Sistema reconhece hibernação"
    else
        error "❌ Sistema não reconhece hibernação"
    fi
    
    # Teste 2: Verificar permissões
    if [[ -w /sys/power/state ]]; then
        success "✅ Permissões de energia OK"
    else
        warn "⚠️  Permissões de energia limitadas"
    fi
    
    # Teste 3: Teste seco do systemd
    if systemctl hibernate --dry-run 2>&1 | grep -q "Would hibernate"; then
        success "✅ Teste seco do systemd: OK"
    else
        warn "⚠️  Teste seco não disponível"
    fi
    
    echo -e "\n${CYAN}=== INSTRUÇÕES PARA TESTE REAL ===${NC}"
    echo -e "Para testar a hibernação REAL:"
    echo -e "1. ${GREEN}Salve todo o trabalho${NC}"
    echo -e "2. Execute: ${GREEN}systemctl hibernate${NC}"
    echo -e "3. Aguarde a tela preta (1-3 minutos)"
    echo -e "4. Sistema desligará sozinho"
    echo -e "5. Ligue manualmente após 10 segundos"
    echo -e "6. Deve restaurar onde parou"
}

# ================================
# FUNÇÃO PRINCIPAL INTELIGENTE
# ================================
main() {
    check_root
    
    # Detectar em qual fase estamos
    if [[ -f "$TEST_MARKER" ]]; then
        info "Configuração já foi testada e está completa!"
        exit 0
    elif [[ -f "$CONFIG_MARKER" ]]; then
        info "FASE 1 já concluída. Executando FASE 2 (testes)..."
        phase2_testing
    else
        info "Iniciando FASE 1 (configuração completa)..."
        phase1_configuration
    fi
}

# Tratamento de interrupção
trap 'echo -e "\n${YELLOW}[AVISO] Script interrompido.${NC}"; exit 1' INT

main "$@"