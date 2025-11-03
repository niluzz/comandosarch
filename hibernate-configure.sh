#!/bin/bash

# SCRIPT INTELIGENTE DE CONFIGURAÇÃO DE ENERGIA - ARCH LINUX
# Analisa o sistema e oferece APENAS opções possíveis

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Variáveis de capacidade do sistema
CAN_SUSPEND=false
CAN_HIBERNATE=false
SWAP_UUID=""
GPU_DRIVER=""
MEM_SLEEP_MODE=""

# Funções de logging
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error() { echo -e "${RED}[ERRO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCESSO]${NC} $1"; }
step() { echo -e "${MAGENTA}>>>${NC} $1"; }

check_root() {
    [[ $EUID -eq 0 ]] || { error "Este script precisa ser executado como root!"; exit 1; }
}

show_header() {
    echo -e "${MAGENTA}"
    echo "=================================================="
    echo "   CONFIGURAÇÃO INTELIGENTE DE ENERGIA"
    echo "     Analisa e configura baseado no seu hardware"
    echo "=================================================="
    echo -e "${NC}"
}

# VERIFICAR E CORRIGIR mkinitcpio.conf SE NECESSÁRIO
fix_mkinitcpio_conf() {
    [[ -f /etc/mkinitcpio.conf ]] || { warn "Arquivo /etc/mkinitcpio.conf não encontrado"; return 1; }
    
    grep -q "^resume" /etc/mkinitcpio.conf && {
        warn "Arquivo mkinitcpio.conf corrompido detectado. Corrigindo..."
        sed -i '/^resume/d' /etc/mkinitcpio.conf
        info "Linhas 'resume' soltas removidas"
    }
}

# VERIFICAR SE HOOK JÁ EXISTE
hook_exists() {
    grep -q "HOOKS=.*resume" /etc/mkinitcpio.conf 2>/dev/null
}

# Função para adicionar hooks ao mkinitcpio corretamente
add_mkinitcpio_hook() {
    fix_mkinitcpio_conf
    
    hook_exists && { info "Hook resume já existe no mkinitcpio"; return 0; }
    
    local hooks_line=$(grep "^HOOKS=" /etc/mkinitcpio.conf 2>/dev/null)
    [[ -n "$hooks_line" ]] || { error "Linha HOOKS não encontrada"; return 1; }
    
    if [[ $hooks_line =~ HOOKS=\((.*)\) ]]; then
        local current_hooks="${BASH_REMATCH[1]}"
        if [[ $current_hooks =~ (.*fsck)(.*) ]]; then
            sed -i "s/^HOOKS=($current_hooks)/HOOKS=(${BASH_REMATCH[1]} resume${BASH_REMATCH[2]})/" /etc/mkinitcpio.conf
        else
            sed -i "s/^HOOKS=($current_hooks)/HOOKS=($current_hooks resume)/" /etc/mkinitcpio.conf
        fi
        info "Hook resume adicionado ao mkinitcpio"
    else
        sed -i '/^HOOKS=/ s/)/ resume)/' /etc/mkinitcpio.conf
        info "Hook resume adicionado (formato alternativo)"
    fi
}

# VERIFICAR SE PARÂMETRO JÁ EXISTE NO KERNEL CMDLINE
kernel_param_exists() {
    [[ -f /etc/kernel/cmdline ]] && grep -q "$1" /etc/kernel/cmdline
}

# ADICIONAR PARÂMETRO NO KERNEL CMDLINE SE NÃO EXISTIR
add_kernel_param() {
    [[ -f /etc/kernel/cmdline ]] || { error "Arquivo /etc/kernel/cmdline não encontrado!"; return 1; }
    
    kernel_param_exists "$1" && { info "Parâmetro $1 já existe"; return 0; }
    
    local current_cmdline=$(cat /etc/kernel/cmdline)
    echo "$current_cmdline $1=$2" > /etc/kernel/cmdline
    info "Parâmetro $1=$2 adicionado"
}

# CONFIGURAR GDM/WAYLAND
configure_gdm_wayland() {
    step "Configurando GDM para Wayland..."
    
    if [[ ! -f /etc/gdm/custom.conf ]]; then
        mkdir -p /etc/gdm
        echo -e "[daemon]\nWaylandEnable=true" > /etc/gdm/custom.conf
        success "Arquivo /etc/gdm/custom.conf criado"
        return
    fi
    
    if grep -q "^WaylandEnable" /etc/gdm/custom.conf; then
        sed -i 's/^WaylandEnable.*/WaylandEnable=true/' /etc/gdm/custom.conf
        info "WaylandEnable atualizado para true"
    else
        sed -i '/\[daemon\]/a WaylandEnable=true' /etc/gdm/custom.conf
        info "WaylandEnable adicionado"
    fi
    
    success "GDM configurado para Wayland"
}

# RESUMO DAS CONFIGURAÇÕES ATIVAS
show_current_config_summary() {
    echo -e "\n${CYAN}=== RESUMO DAS CONFIGURAÇÕES ATIVAS ===${NC}"
    
    local has_config=false
    
    kernel_param_exists "resume" && {
        echo -e "  ✅ ${GREEN}Kernel: Hibernação configurada (resume=UUID)$NC"
        has_config=true
    }
    
    kernel_param_exists "zswap.enabled" && {
        local zswap_value=$(grep -o 'zswap.enabled=[^ ]*' /etc/kernel/cmdline | cut -d= -f2)
        echo -e "  ✅ ${GREEN}Kernel: Zswap $zswap_value$NC"
        has_config=true
    }
    
    hook_exists && {
        echo -e "  ✅ ${GREEN}Initramfs: Hook resume ativo$NC"
        has_config=true
    }
    
    [[ -f /etc/systemd/logind.conf ]] && {
        local lid_switch=$(grep "^HandleLidSwitch=" /etc/systemd/logind.conf 2>/dev/null | tail -1)
        local lid_external=$(grep "^HandleLidSwitchExternalPower=" /etc/systemd/logind.conf 2>/dev/null | tail -1)
        
        [[ -n "$lid_switch" ]] && {
            echo -e "  ✅ ${GREEN}Logind: Tampa (bateria) = ${lid_switch#*=}$NC"
            has_config=true
        }
        [[ -n "$lid_external" ]] && {
            echo -e "  ✅ ${GREEN}Logind: Tampa (tomada) = ${lid_external#*=}$NC"
            has_config=true
        }
    }
    
    [[ -f /etc/gdm/custom.conf ]] && grep -q "^WaylandEnable=true" /etc/gdm/custom.conf && {
        echo -e "  ✅ ${GREEN}GDM: Wayland ativo$NC"
        has_config=true
    }
    
    $has_config || echo -e "  ℹ️  ${YELLOW}Nenhuma configuração de energia específica detectada$NC"
}

# ANÁLISE DO SISTEMA
analyze_system() {
    step "Analisando capacidades do sistema..."
    
    echo -e "\n${CYAN}=== DETECÇÃO DE HARDWARE ===${NC}"
    
    [[ -f /sys/power/state ]] && grep -q "freeze\|mem" /sys/power/state && {
        CAN_SUSPEND=true
        echo -e "  ✅ ${GREEN}Suspensão suportada${NC}"
    } || echo -e "  ❌ ${RED}Suspensão NÃO suportada${NC}"
    
    [[ -f /sys/power/disk ]] && swapon --show &>/dev/null && {
        CAN_HIBERNATE=true
        SWAP_UUID=$(blkid -s UUID -o value $(swapon --show=name --noheadings | head -1) 2>/dev/null)
        local swap_size=$(swapon --show=SIZE --noheadings | head -1)
        local ram_size=$(free -g | awk '/Mem:/{print $2}')
        echo -e "  ✅ ${GREEN}Hibernação suportada${NC}"
        echo -e "     💾 Swap: $swap_size | RAM: ${ram_size}GB"
        [[ -n "$SWAP_UUID" ]] && echo -e "     🔑 UUID: $SWAP_UUID"
    } || echo -e "  ❌ ${RED}Hibernação NÃO suportada${NC}"
    
    GPU_DRIVER=$(lspci -k 2>/dev/null | grep -A 2 "VGA" | grep "Kernel driver in use" | cut -d: -f2 | tr -d ' ' | head -1)
    [[ -n "$GPU_DRIVER" ]] && echo -e "  🎮 ${CYAN}GPU: $GPU_DRIVER${NC}"
    
    [[ -f /sys/power/mem_sleep ]] && {
        MEM_SLEEP_MODE=$(grep -o '\[[^]]*\]' /sys/power/mem_sleep | tr -d '[]' | head -1)
        echo -e "  💤 ${CYAN}Modo de suspensão: $MEM_SLEEP_MODE${NC}"
    }
    
    [[ -f /etc/kernel/cmdline ]] && {
        echo -e "  🐧 ${CYAN}Bootloader: systemd-boot detectado${NC}"
        echo -e "     📋 $(cat /etc/kernel/cmdline)"
    } || echo -e "  ❌ ${RED}systemd-boot NÃO detectado${NC}"
    
    [[ -f /etc/gdm/custom.conf ]] && {
        grep -q "WaylandEnable=true" /etc/gdm/custom.conf && \
        echo -e "  🖥️  ${GREEN}GDM: Wayland habilitado${NC}" || \
        echo -e "  🖥️  ${YELLOW}GDM: Wayland não configurado${NC}"
    } || echo -e "  🖥️  ${YELLOW}GDM: /etc/gdm/custom.conf não encontrado${NC}"
    
    show_current_config_summary
}

# MOSTRAR OPÇÕES
show_available_options() {
    echo -e "\n${CYAN}=== OPÇÕES DISPONÍVEIS ===${NC}"
    
    local i=1
    AVAILABLE_OPTIONS=()
    
    $CAN_SUSPEND && {
        echo "$i. ⚡ SUSPENSÃO (Básica)"
        AVAILABLE_OPTIONS+=("suspend_only")
        ((i++))
    }
    
    $CAN_SUSPEND && $CAN_HIBERNATE && {
        echo "$i. 🔄 SUSPENSÃO E HIBERNAÇÃO (Inteligente - Recomendado)"
        AVAILABLE_OPTIONS+=("smart_mode")
        ((i++))
    }
    
    echo "$i. 🖥️  Configurar GDM/Wayland APENAS"
    AVAILABLE_OPTIONS+=("gdm_only")
    ((i++))
    
    echo "$i. 🔧 Corrigir mkinitcpio.conf"
    AVAILABLE_OPTIONS+=("fix_mkinitcpio")
    ((i++))
    
    echo "$i. 🧪 Verificar configuração atual"
    AVAILABLE_OPTIONS+=("check_config")
    
    echo -e "\n0. ❌ Sair"
}

# CONFIGURAÇÃO SUSPENSÃO BÁSICA
configure_suspend_only() {
    step "Configurando modo SUSPENSÃO BÁSICA..."
    configure_gdm_wayland
    [[ -n "$SWAP_UUID" ]] && add_kernel_param "resume" "UUID=$SWAP_UUID"
    add_mkinitcpio_hook
    
    # Configurar logind.conf - APENAS ADICIONAR NO FINAL
    echo -e "\n# === CONFIGURAÇÃO DE ENERGIA - SUSPENSÃO BÁSICA ===" >> /etc/systemd/logind.conf
    echo "HandlePowerKey=suspend" >> /etc/systemd/logind.conf
    echo "HandleSuspendKey=suspend" >> /etc/systemd/logind.conf
    echo "HandleHibernateKey=suspend" >> /etc/systemd/logind.conf
    echo "HandleLidSwitch=suspend" >> /etc/systemd/logind.conf
    echo "HandleLidSwitchExternalPower=suspend" >> /etc/systemd/logind.conf
    echo "IdleAction=suspend" >> /etc/systemd/logind.conf
    echo "IdleActionSec=30m" >> /etc/systemd/logind.conf
    
    # Configurar sleep.conf - APENAS ADICIONAR NO FINAL
    echo -e "\n# === CONFIGURAÇÃO DE SUSPENSÃO BÁSICA ===" >> /etc/systemd/sleep.conf
    echo "AllowSuspend=yes" >> /etc/systemd/sleep.conf
    echo "AllowHibernation=no" >> /etc/systemd/sleep.conf
    echo "AllowHybridSleep=no" >> /etc/systemd/sleep.conf
    echo "AllowSuspendThenHibernate=no" >> /etc/systemd/sleep.conf
    echo "SuspendState=mem" >> /etc/systemd/sleep.conf
    
    success "Modo SUSPENSÃO BÁSICA configurado!"
}

# CONFIGURAÇÃO SUSPENSÃO E HIBERNAÇÃO INTELIGENTE
configure_smart_mode() {
    step "Configurando modo SUSPENSÃO E HIBERNAÇÃO INTELIGENTE..."
    configure_gdm_wayland
    [[ -n "$SWAP_UUID" ]] && {
        add_kernel_param "resume" "UUID=$SWAP_UUID"
        add_kernel_param "zswap.enabled" "0"
    }
    add_mkinitcpio_hook
    
    # Configurar logind.conf - APENAS ADICIONAR NO FINAL
    echo -e "\n# TAMPA - Comportamento principal" >> /etc/systemd/logind.conf
    echo "HandleLidSwitch=suspend-then-hibernate" >> /etc/systemd/logind.conf
    echo "HandleLidSwitchExternalPower=suspend-then-hibernate" >> /etc/systemd/logind.conf
    echo "HandleLidSwitchDocked=ignore" >> /etc/systemd/logind.conf
    echo "# BOTÕES DE ENERGIA" >> /etc/systemd/logind.conf
    echo "HandlePowerKey=suspend-then-hibernate" >> /etc/systemd/logind.conf
    echo "HandleSuspendKey=suspend" >> /etc/systemd/logind.conf
    echo "HandleHibernateKey=hibernate" >> /etc/systemd/logind.conf
    echo "# TEMPOS para suspend-then-hibernate (2 horas = 7200 segundos)" >> /etc/systemd/logind.conf
    echo "HoldoffTimeoutSec=30s" >> /etc/systemd/logind.conf
    echo "IdleAction=hibernate" >> /etc/systemd/logind.conf
    echo "IdleActionSec=1800" >> /etc/systemd/logind.conf
    echo "# BATERIA CRÍTICA" >> /etc/systemd/logind.conf
    echo "HandleBatteryCriticalLevel=5%" >> /etc/systemd/logind.conf
    echo "HandleBatteryCriticalAction=hibernate" >> /etc/systemd/logind.conf
    
    # Configurar sleep.conf - APENAS ADICIONAR NO FINAL
    echo -e "\n# CONFIGURAÇÃO INTELIGENTE DE SUSPENSÃO" >> /etc/systemd/sleep.conf
    echo "AllowSuspend=yes" >> /etc/systemd/sleep.conf
    echo "AllowHibernation=yes" >> /etc/systemd/sleep.conf
    echo "AllowHybridSleep=yes" >> /etc/systemd/sleep.conf
    echo "AllowSuspendThenHibernate=yes" >> /etc/systemd/sleep.conf
    echo "SuspendState=mem" >> /etc/systemd/sleep.conf
    echo "HibernateDelaySec=7200" >> /etc/systemd/sleep.conf
    
    success "Modo SUSPENSÃO E HIBERNAÇÃO INTELIGENTE configurado!"
}

configure_gdm_only() {
    step "Configurando GDM/Wayland..."
    configure_gdm_wayland
    success "GDM configurado!"
}

fix_mkinitcpio_manual() {
    step "Corrigindo mkinitcpio.conf..."
    sed -i '/^resume/d' /etc/mkinitcpio.conf
    add_mkinitcpio_hook
    success "mkinitcpio corrigido!"
}

check_current_config() {
    step "Verificando configuração atual..."
    
    echo -e "\n${CYAN}=== CONFIGURAÇÃO ATUAL DETALHADA ===${NC}"
    
    [[ -f /etc/kernel/cmdline ]] && {
        echo -e "\n${BLUE}Kernel Parameters:${NC}"
        cat /etc/kernel/cmdline
        echo -e "\n${BLUE}Parâmetros de Energia:${NC}"
        kernel_param_exists "resume" && {
            local resume_uuid=$(grep -o 'resume=UUID=[^ ]*' /etc/kernel/cmdline | cut -d= -f3)
            echo -e "  ✅ ${GREEN}resume: CONFIGURADO (UUID=$resume_uuid)$NC"
        } || echo -e "  ❌ ${RED}resume: NÃO CONFIGURADO$NC"
        
        kernel_param_exists "zswap.enabled" && {
            local zswap_value=$(grep -o 'zswap.enabled=[^ ]*' /etc/kernel/cmdline | cut -d= -f2)
            echo -e "  ✅ ${GREEN}zswap.enabled: $zswap_value$NC"
        } || echo -e "  ❌ ${RED}zswap.enabled: NÃO CONFIGURADO$NC"
    }
    
    echo -e "\n${BLUE}Mkinitcpio Hooks:${NC}"
    local hooks_line=$(grep "^HOOKS=" /etc/mkinitcpio.conf 2>/dev/null || echo "Não encontrado")
    echo "$hooks_line"
    hook_exists && echo -e "  ✅ ${GREEN}resume hook: PRESENTE$NC" || echo -e "  ❌ ${RED}resume hook: AUSENTE$NC"
    
    echo -e "\n${BLUE}Systemd Logind:${NC}"
    [[ -f /etc/systemd/logind.conf ]] && {
        tail -20 /etc/systemd/logind.conf | while read -r line; do
            [[ -n "$line" ]] && echo "  📝 $line"
        done
    } || echo "  ❌ Arquivo não encontrado"
    
    echo -e "\n${BLUE}Systemd Sleep:${NC}"
    [[ -f /etc/systemd/sleep.conf ]] && {
        tail -20 /etc/systemd/sleep.conf | while read -r line; do
            [[ -n "$line" ]] && echo "  📝 $line"
        done
    } || echo "  ❌ Arquivo não encontrado"
}

apply_configurations() {
    step "Aplicando configurações..."
    
    [[ -f /etc/mkinitcpio.conf ]] && {
        mkinitcpio -P && success "Initramfs regenerado!" || error "Falha ao regenerar initramfs!"
    }
    
    echo -e "\n${YELLOW}=== ⚠️  REINICIE O SISTEMA ===${NC}"
    echo "Comando: ${GREEN}reboot${NC}"
    echo "Após reiniciar, teste com: ${CYAN}systemctl suspend${NC}"
}

# FUNÇÃO PRINCIPAL
main() {
    check_root
    show_header
    analyze_system
    show_available_options
    
    read -p "Selecione uma opção (0-${#AVAILABLE_OPTIONS[@]}): " choice
    
    [[ $choice -eq 0 ]] && { info "Saindo..."; exit 0; }
    
    if [[ $choice -gt 0 && $choice -le ${#AVAILABLE_OPTIONS[@]} ]]; then
        case "${AVAILABLE_OPTIONS[$((choice-1))]}" in
            suspend_only) configure_suspend_only ;;
            smart_mode) configure_smart_mode ;;
            gdm_only) configure_gdm_only ;;
            fix_mkinitcpio) fix_mkinitcpio_manual ;;
            check_config) check_current_config ;;
        esac
        
        [[ ${AVAILABLE_OPTIONS[$((choice-1))]} != "check_config" ]] && \
        [[ ${AVAILABLE_OPTIONS[$((choice-1))]} != "fix_mkinitcpio" ]] && apply_configurations
    else
        error "Opção inválida!"
        exit 1
    fi
}

trap 'echo -e "\n${YELLOW}[AVISO] Script interrompido.${NC}"; exit 1' INT
main "$@"
