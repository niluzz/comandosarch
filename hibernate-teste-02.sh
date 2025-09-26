#!/bin/bash

# Script 2: TESTES DE HIBERNAÇÃO APÓS REINÍCIO (COM NOVAS VERIFICAÇÕES)

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
    echo -e "${CYAN}"
    echo "=================================================="
    echo "  SCRIPT 2: TESTES DE HIBERNAÇÃO APÓS REINÍCIO"
    echo "  Incluindo verificações de sleep.conf"
    echo "=================================================="
    echo -e "${NC}"
}

# NOVA FUNÇÃO: Verificar sleep.conf
verify_sleep_conf() {
    step "Verificando /etc/systemd/sleep.conf..."
    
    if [[ -f /etc/systemd/sleep.conf ]]; then
        if grep -q "SuspendThenHibernateDelaySec=20min" /etc/systemd/sleep.conf; then
            success "✅ sleep.conf configurado corretamente"
            echo -e "\n${CYAN}--- Configurações do sleep.conf ---${NC}"
            grep -E "(SuspendThenHibernateDelaySec|RESUME=|HibernateMode)" /etc/systemd/sleep.conf | head -5
        else
            warn "⚠️  sleep.conf não configurado ou incompleto"
        fi
    else
        warn "⚠️  sleep.conf não encontrado"
    fi
}

# NOVA FUNÇÃO: Verificar se resume UUID está correto
verify_resume_uuid() {
    step "Verificando UUID de resume..."
    
    local root_uuid=$(findmnt -n -o UUID /)
    local sleep_uuid=$(grep "RESUME=UUID=" /etc/systemd/sleep.conf 2>/dev/null | cut -d= -f3)
    local kernel_uuid=$(grep -o "resume=UUID=[^ ]*" /proc/cmdline 2>/dev/null | cut -d= -f3)
    
    if [[ "$root_uuid" == "$sleep_uuid" ]] && [[ "$root_uuid" == "$kernel_uuid" ]]; then
        success "✅ UUIDs consistentes em todos os lugares"
        info "UUID da partição raiz: $root_uuid"
    else
        warn "⚠️  UUIDs inconsistentes:"
        echo "  Root: $root_uuid"
        echo "  Sleep.conf: $sleep_uuid" 
        echo "  Kernel: $kernel_uuid"
    fi
}

check_if_rebooted() {
    step "Verificando se o sistema foi reiniciado..."
    
    local uptime_seconds=$(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1)
    local uptime_minutes=$((uptime_seconds / 60))
    
    if [[ $uptime_minutes -lt 10 ]]; then
        success "Sistema reiniciado recentemente (uptime: ${uptime_minutes}min)"
    else
        warn "Sistema não foi reiniciado recentemente (uptime: ${uptime_minutes}min)"
        echo -e "\n${YELLOW}Deseja continuar mesmo assim? (s/N)${NC}"
        read -p "> " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            info "Execute: reboot"
            exit 0
        fi
    fi
}

verify_kernel_config() {
    step "Verificando configuração do kernel..."
    
    echo -e "\n${CYAN}--- Parâmetros atuais ---${NC}"
    if grep -q "resume=" /proc/cmdline; then
        success "✅ Parâmetros carregados no kernel"
        grep -o "resume=[^ ]*" /proc/cmdline
    else
        error "❌ Parâmetros NÃO carregados no kernel"
        exit 1
    fi
}

verify_swap() {
    step "Verificando swap..."
    
    if swapon --show | grep -q "swapfile"; then
        success "✅ Swapfile ativo"
        echo -e "\n${CYAN}--- Status do swap ---${NC}"
        swapon --show
    else
        error "❌ Swapfile NÃO ativo"
        exit 1
    fi
}

verify_systemd() {
    step "Verificando systemd..."
    
    if systemctl is-enabled systemd-hibernate.service &>/dev/null; then
        success "✅ Serviço de hibernação habilitado"
    else
        warn "⚠️  Serviço de hibernação não habilitado"
    fi
    
    if [[ -f /etc/systemd/logind.conf ]]; then
        if grep -q "HandleLidSwitch=hibernate" /etc/systemd/logind.conf; then
            success "✅ Configurações de energia aplicadas"
        else
            warn "⚠️  Configurações de energia incompletas"
        fi
    fi
}

run_safe_tests() {
    step "Executando testes seguros..."
    
    echo -e "\n${YELLOW}⚠️  TESTES SEGUROS (não hibernam de verdade)${NC}"
    
    if grep -q "disk" /sys/power/state; then
        success "✅ Kernel suporta hibernação"
    else
        error "❌ Kernel não suporta hibernação"
    fi
    
    if [[ -w /sys/power/state ]]; then
        success "✅ Permissões de energia OK"
    else
        warn "⚠️  Permissões de energia limitadas"
    fi
}

show_hibernate_instructions() {
    step "Instruções para teste real"
    
    echo -e "\n${GREEN}"
    echo "#############################################"
    echo "#  SISTEMA CONFIGURADO COM SUCESSO!        #"
    echo "#  Incluindo suspensão+hibernação          #"
    echo "#############################################"
    echo -e "${NC}"
    
    echo -e "\n${CYAN}=== NOVAS FUNCIONALIDADES ===${NC}"
    echo "🆕 ${GREEN}Suspensão + Hibernação Automática${NC}"
    echo "   - Feche a tampa: suspende"
    echo "   - Após 20min: hiberna automaticamente"
    echo "   - Ideal para economia de bateria"
    
    echo -e "\n${CYAN}=== TESTES RECOMENDADOS ===${NC}"
    echo "1. ${GREEN}Teste simples de hibernação:${NC}"
    echo "   systemctl hibernate"
    echo ""
    echo "2. ${GREEN}Teste suspensão+hibernação:${NC}"
    echo "   - Feche a tampa do notebook"
    echo "   - Aguarde 20 minutos"
    echo "   - Deve hibernar automaticamente"
    echo ""
    echo "3. ${GREEN}Teste na bateria e tomada${NC}"
    
    echo -e "\n${YELLOW}⚠️  LEMBRETE:${NC}"
    echo "   - Suspensão+hibernação: 20min de delay"
    echo "   - Hibernação direta: imediata"
    echo "   - Teste com bateria carregada"
}

show_summary() {
    step "Resumo final"
    
    echo -e "\n${CYAN}=== STATUS DO SISTEMA ===${NC}"
    
    local checks=(
        "Kernel:suporte:hibernate" "grep -q disk /sys/power/state"
        "Kernel:parâmetros:resume" "grep -q resume= /proc/cmdline"
        "Swap:ativo:swapfile" "swapon --show | grep -q swapfile"
        "Sleep.conf:configurado:suspend+hibernate" "grep -q SuspendThenHibernateDelaySec /etc/systemd/sleep.conf 2>/dev/null"
        "Logind.conf:configurado:energy" "grep -q HandleLidSwitch=hibernate /etc/systemd/logind.conf 2>/dev/null"
    )
    
    local all_ok=true
    
    for check in "${checks[@]}"; do
        IFS=':' read -r name type cmd <<< "$check"
        
        if eval "$cmd" 2>/dev/null; then
            success "✅ $name: OK"
        else
            error "❌ $name: FALHA"
            all_ok=false
        fi
    done
    
    echo -e "\n${CYAN}=== CONCLUSÃO ===${NC}"
    if $all_ok; then
        success "🎉 SISTEMA 100% CONFIGURADO PARA HIBERNAÇÃO!"
        echo "Incluindo suspensão+hibernação automática."
    else
        error "⚠️  Alguns problemas detectados."
        echo "Verifique os logs acima."
    fi
}

main() {
    check_root
    show_header
    check_if_rebooted
    verify_kernel_config
    verify_swap
    verify_systemd
    verify_sleep_conf      # NOVA VERIFICAÇÃO
    verify_resume_uuid     # NOVA VERIFICAÇÃO
    run_safe_tests
    show_summary
    show_hibernate_instructions
}

trap 'echo -e "\n${YELLOW}[AVISO] Testes interrompidos.${NC}"; exit 1' INT
main "$@"