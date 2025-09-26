#!/bin/bash

# Script 1: CONFIGURAÇÃO COMPLETA DA HIBERNAÇÃO (COM MELHORIAS)
# Execute este PRIMEIRO, depois REINICIE

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script precisa ser executado como root!"
        exit 1
    fi
}

show_header() {
    echo -e "${MAGENTA}"
    echo "=================================================="
    echo "  SCRIPT 1: CONFIGURAÇÃO COMPLETA DA HIBERNAÇÃO"
    echo "  Incluindo sleep.conf e logind.conf otimizados"
    echo "=================================================="
    echo -e "${NC}"
}

verify_system() {
    step "Verificando sistema..."
    
    if ! grep -q "disk" /sys/power/state; then
        error "Kernel não suporta hibernação!"
        exit 1
    fi
    success "Kernel suporta hibernação."
    
    if [[ ! -f /etc/kernel/cmdline ]]; then
        error "systemd-boot não encontrado!"
        exit 1
    fi
    success "Systemd-boot detectado."
    
    if findmnt -n -o FSTYPE / | grep -q "btrfs"; then
        success "Btrfs detectado."
    else
        warn "Sistema de arquivos não é Btrfs."
    fi
}

configure_mkinitcpio() {
    step "Configurando mkinitcpio..."
    
    local mkinitcpio_file="/etc/mkinitcpio.conf"
    local backup_file="${mkinitcpio_file}.backup.$(date +%Y%m%d-%H%M%S)"
    
    cp "$mkinitcpio_file" "$backup_file"
    info "Backup criado: $backup_file"
    
    local current_hooks=$(grep "^HOOKS=" "$mkinitcpio_file" | cut -d= -f2 | tr -d '()"')
    local hooks_modified=false
    
    if ! echo "$current_hooks" | grep -q "systemd"; then
        warn "Adicionando hook 'systemd'..."
        current_hooks=$(echo "$current_hooks" | sed 's/udev/systemd/')
        if ! echo "$current_hooks" | grep -q "systemd"; then
            current_hooks="systemd $current_hooks"
        fi
        hooks_modified=true
    fi
    
    if ! echo "$current_hooks" | grep -q "resume"; then
        warn "Adicionando hook 'resume'..."
        current_hooks=$(echo "$current_hooks" | sed 's/systemd/& resume/')
        hooks_modified=true
    fi
    
    if $hooks_modified; then
        current_hooks=$(echo "$current_hooks" | sed 's/  / /g')
        sed -i "s|^HOOKS=.*|HOOKS=(${current_hooks})|" "$mkinitcpio_file"
        success "Hooks atualizados."
    fi
    
    if findmnt -n -o FSTYPE / | grep -q "btrfs"; then
        local current_modules=$(grep "^MODULES=" "$mkinitcpio_file" | cut -d= -f2 | tr -d '()"')
        if ! echo "$current_modules" | grep -q "btrfs"; then
            warn "Adicionando módulo Btrfs..."
            if [[ -z "$current_modules" ]]; then
                sed -i "s|^MODULES=.*|MODULES=(btrfs)|" "$mkinitcpio_file"
            else
                sed -i "s|^MODULES=.*|MODULES=(${current_modules} btrfs)|" "$mkinitcpio_file"
            fi
        fi
    fi
    
    info "Regenerando initramfs..."
    if mkinitcpio -P; then
        success "Initramfs regenerado."
    else
        error "Falha ao regenerar initramfs!"
        exit 1
    fi
}

create_swapfile() {
    step "Criando swapfile..."
    
    local swapfile_path="/swapfile"
    local mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_total_gb=$(( (mem_total_kb + 1024*1024 - 1) / (1024*1024) ))
    local swap_size_gb=$((mem_total_gb + 2))
    [[ $swap_size_gb -lt 8 ]] && swap_size_gb=8
    [[ $swap_size_gb -gt 32 ]] && swap_size_gb=32
    
    info "Memória RAM: ${mem_total_gb}GB"
    info "Tamanho do swapfile: ${swap_size_gb}GB"
    
    if [[ -f "$swapfile_path" ]]; then
        warn "Removendo swapfile existente..."
        swapoff "$swapfile_path" 2>/dev/null || true
        rm -f "$swapfile_path"
        sleep 2
    fi
    
    info "Criando swapfile de ${swap_size_gb}GB..."
    truncate -s 0 "$swapfile_path"
    chattr +C "$swapfile_path"
    chmod 600 "$swapfile_path"
    
    info "Alocando espaço... (pode demorar)"
    dd if=/dev/zero of="$swapfile_path" bs=1M count=$((swap_size_gb * 1024)) status=progress 2>/dev/null
    
    info "Formatando swapfile..."
    mkswap -f "$swapfile_path"
    
    info "Ativando swapfile..."
    swapon "$swapfile_path"
    
    if ! grep -q "$swapfile_path" /etc/fstab; then
        echo "$swapfile_path none swap defaults 0 0" >> /etc/fstab
        success "Swapfile adicionado ao fstab."
    fi
    
    success "Swapfile criado e ativado."
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

configure_kernel() {
    step "Configurando parâmetros do kernel..."
    
    local cmdline_file="/etc/kernel/cmdline"
    local backup_file="${cmdline_file}.backup.$(date +%Y%m%d-%H%M%S)"
    
    cp "$cmdline_file" "$backup_file"
    info "Backup criado: $backup_file"
    
    local root_uuid=$(findmnt -n -o UUID /)
    local resume_offset=$(get_swapfile_offset)
    
    local resume_param="resume=UUID=${root_uuid}"
    if [[ -n "$resume_offset" ]]; then
        resume_param="${resume_param} resume_offset=${resume_offset}"
        info "Offset do swapfile: $resume_offset"
    else
        warn "Offset não detectado. Hibernação pode ser menos confiável."
    fi
    
    resume_param="${resume_param} resume_force=1 acpi_sleep=nonvs mem_sleep_default=deep"
    
    local current_cmdline=$(cat "$cmdline_file")
    local new_cmdline=$(echo "$current_cmdline" | sed -E 's/resume=[^ ]*//g')
    new_cmdline="${new_cmdline} ${resume_param}"
    new_cmdline=$(echo "$new_cmdline" | sed 's/  / /g' | sed 's/^ //' | sed 's/ $//')
    
    echo "$new_cmdline" > "$cmdline_file"
    
    if ! grep -q "resume=" "$cmdline_file"; then
        error "Falha ao configurar parâmetros do kernel!"
        exit 1
    fi
    
    info "Atualizando bootloader..."
    if bootctl update 2>/dev/null; then
        success "Bootloader atualizado."
    else
        warn "Bootctl retornou aviso (pode ser normal)."
    fi
    
    success "Parâmetros do kernel configurados."
}

# MELHORIA 1: Configuração otimizada do logind.conf
configure_systemd_logind() {
    step "Configurando /etc/systemd/logind.conf (otimizado)..."
    
    if [[ ! -f /etc/systemd/logind.conf ]]; then
        warn "Arquivo logind.conf não encontrado. Criando..."
        touch /etc/systemd/logind.conf
    fi
    
    local backup_file="/etc/systemd/logind.conf.backup.$(date +%Y%m%d-%H%M%S)"
    cp /etc/systemd/logind.conf "$backup_file"
    
    info "Aplicando configurações otimizadas..."
    
    # Limpar configurações existentes
    sed -i '/^#/!{/HandlePowerKey/d;/HandleSuspendKey/d;/HandleHibernateKey/d;/HandleLidSwitch/d;/HoldoffTimeoutSec/d;/IdleAction/d}' /etc/systemd/logind.conf
    
    # Adicionar configurações otimizadas
    cat > /tmp/logind_config.txt << 'EOF'
# =============================================================================
# CONFIGURAÇÃO OTIMIZADA DE HIBERNAÇÃO - Arch Linux
# Configurado automaticamente por script de hibernação
# =============================================================================

# 🔋 AÇÕES DE ENERGIA NA BATERIA
HandlePowerKey=hibernate
HandleSuspendKey=hibernate
HandleHibernateKey=hibernate
HandleLidSwitch=hibernate

# 🔌 AÇÕES DE ENERGIA NA TOMADA
HandleLidSwitchExternalPower=hibernate
HandleLidSwitchDocked=hibernate

# ⏰ TEMPOS DE ESPERA
HoldoffTimeoutSec=30s
IdleAction=hibernate
IdleActionSec=60min

# 🔧 COMPORTAMENTO DE INIBIÇÃO
PowerKeyIgnoreInhibited=no
SuspendKeyIgnoreInhibited=no
HibernateKeyIgnoreInhibited=no
LidSwitchIgnoreInhibited=no
EOF

    # Adicionar ao arquivo se não existir
    if ! grep -q "CONFIGURAÇÃO OTIMIZADA" /etc/systemd/logind.conf; then
        cat /tmp/logind_config.txt >> /etc/systemd/logind.conf
        success "Configurações otimizadas adicionadas."
    else
        warn "Configurações já existem. Atualizando..."
        # Remover seção antiga e adicionar nova
        sed -i '/CONFIGURAÇÃO OTIMIZADA/,/EOF/d' /etc/systemd/logind.conf
        cat /tmp/logind_config.txt >> /etc/systemd/logind.conf
        success "Configurações atualizadas."
    fi
    
    rm -f /tmp/logind_config.txt
    systemctl restart systemd-logind
    systemctl enable systemd-hibernate.service 2>/dev/null || true
    
    success "logind.conf configurado otimizado."
}

# NOVA FUNÇÃO: Configurar sleep.conf
configure_systemd_sleep() {
    step "Configurando /etc/systemd/sleep.conf..."
    
    local root_uuid=$(findmnt -n -o UUID /)
    
    if [[ ! -f /etc/systemd/sleep.conf ]]; then
        warn "Arquivo sleep.conf não encontrado. Criando..."
        touch /etc/systemd/sleep.conf
    fi
    
    local backup_file="/etc/systemd/sleep.conf.backup.$(date +%Y%m%d-%H%M%S)"
    cp /etc/systemd/sleep.conf "$backup_file"
    
    info "Aplicando configurações de sleep otimizadas..."
    
    # Criar configuração completa
    cat > /tmp/sleep_config.txt << EOF
# =============================================================================
# CONFIGURAÇÃO OTIMIZADA DE SLEEP/HIBERNAÇÃO - Arch Linux
# Configurado automaticamente por script de hibernação
# =============================================================================

[Sleep]
# ⏰ TEMPO PARA HIBERNAR APÓS SUSPENDER (20 MINUTOS)
SuspendThenHibernateDelaySec=20min

# 🔧 MÉTODOS DE HIBERNAÇÃO/POWER
HibernateMode=platform
HybridSleepMode=suspend

# 💾 DISPOSITIVO DE RESUME (HIBERNAÇÃO)
RESUME=UUID=${root_uuid}

# 🔋 COMPORTAMENTO DE ENERGIA
AllowSuspend=yes
AllowHibernation=yes
AllowSuspendThenHibernate=yes
AllowHybridSleep=yes
EOF

    # Substituir ou adicionar configuração
    if grep -q "CONFIGURAÇÃO OTIMIZADA" /etc/systemd/sleep.conf; then
        warn "Atualizando configurações existentes..."
        sed -i '/CONFIGURAÇÃO OTIMIZADA/,/EOF/d' /etc/systemd/sleep.conf
    fi
    
    cat /tmp/sleep_config.txt >> /etc/systemd/sleep.conf
    rm -f /tmp/sleep_config.txt
    
    success "sleep.conf configurado com:"
    echo -e "  ${CYAN}SuspendThenHibernateDelaySec=20min${NC}"
    echo -e "  ${CYAN}RESUME=UUID=${root_uuid}${NC}"
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
        
        # Configuração adicional para suspensão+hibernação
        sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_id}/bus" \
            gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'hibernate' 2>/dev/null || true
            
        sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_id}/bus" \
            gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
        
        success "GNOME configurado com suporte a suspensão+hibernação."
    else
        warn "GNOME não detectado. Pulando..."
    fi
}

show_final_instructions() {
    echo -e "\n${GREEN}"
    echo "#############################################"
    echo "#  CONFIGURAÇÃO COMPLETA COM SUCESSO!      #"
    echo "#  Incluindo sleep.conf e logind.conf      #"
    echo "#############################################"
    echo -e "${NC}"
    
    echo -e "\n${CYAN}=== NOVAS FUNCIONALIDADES CONFIGURADAS ===${NC}"
    echo "✅ ${GREEN}SuspendThenHibernateDelaySec=20min${NC}"
    echo "   - Suspende primeiro, hiberna após 20min"
    echo "✅ ${GREEN}Configurações otimizadas de energia${NC}"
    echo "   - Comportamento diferente bateria/tomada"
    echo "✅ ${GREEN}RESUME=UUID configurado no sleep.conf${NC}"
    
    echo -e "\n${CYAN}=== PRÓXIMOS PASSOS ===${NC}"
    echo "1. ${GREEN}REINICIE O SISTEMA:${NC}"
    echo "   comando: reboot"
    echo ""
    echo "2. ${GREEN}APÓS REINICIAR, execute o Script 2:${NC}"
    echo "   comando: sudo ./testar_hibernacao.sh"
    echo ""
    echo "3. ${GREEN}Teste a nova funcionalidade:${NC}"
    echo "   - Feche a tampa (suspende)"
    echo "   - Após 20min, hiberna automaticamente"
    
    echo -e "\n${YELLOW}⚠️  IMPORTANTE: Reinicie antes de testar!${NC}"
    
    echo -e "\n${YELLOW}Deseja reiniciar agora? (s/N)${NC}"
    read -p "> " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        warn "Reiniciando em 10 segundos... Ctrl+C para cancelar"
        for i in {10..1}; do
            echo -ne "Reiniciando em $i segundos...\r"
            sleep 1
        done
        reboot
    else
        info "Execute manualmente: reboot"
    fi
}

main() {
    check_root
    show_header
    verify_system
    configure_mkinitcpio
    create_swapfile
    configure_kernel
    configure_systemd_logind    # Substitui a função antiga
    configure_systemd_sleep     # NOVA FUNÇÃO
    configure_gnome
    show_final_instructions
}

trap 'echo -e "\n${YELLOW}[AVISO] Script interrompido.${NC}"; exit 1' INT
main "$@"