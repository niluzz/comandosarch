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
CAN_HYBRID=false
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
    
    # Remover linhas "resume" soltas se existirem
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
    
    # Extrair e adicionar hook mantendo a formatação original
    if [[ $hooks_line =~ HOOKS=\((.*)\) ]]; then
        local current_hooks="${BASH_REMATCH[1]}"
        # Adicionar resume após fsck ou no final
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

# ADICIONAR CONFIGURAÇÃO COM COMENTÁRIO
add_config() {
    local file="$1" config="$2" comment="$3"
    
    # Criar arquivo se não existir
    [[ -f "$file" ]] || touch "$file"
    
    # Remover configuração existente se houver
    [[ -n "$config" ]] && grep -q "^$config" "$file" 2>/dev/null && sed -i "/^$config/d" "$file"
    
    # Adicionar comentário e configuração
    [[ -n "$comment" ]] && echo "# $comment" >> "$file"
    [[ -n "$config" ]] && echo "$config" >> "$file"
}

# CONFIGURAR GDM/WAYLAND
configure_gdm_wayland() {
    step "Configurando GDM para Wayland..."
    
    if [[ ! -f /etc/gdm/custom.conf ]]; then
        mkdir -p /etc/gdm
        cat > /etc/gdm/custom.conf << 'EOF'
[daemon]
WaylandEnable=true
EOF
        success "Arquivo /etc/gdm/custom.conf criado"
        return
    fi
    
    # Apenas modificar o parâmetro WaylandEnable
    if grep -q "^WaylandEnable" /etc/gdm/custom.conf; then
        sed -i 's/^WaylandEnable.*/WaylandEnable=true/' /etc/gdm/custom.conf
        info "WaylandEnable atualizado para true"
    else
        # Adicionar após [daemon]
        sed -i '/\[daemon\]/a WaylandEnable=true' /etc/gdm/custom.conf
        info "WaylandEnable adicionado"
    fi
    
    success "GDM configurado para Wayland"
}

# RESUMO DAS CONFIGURAÇÕES ATIVAS
show_current_config_summary() {
    echo -e "\n${CYAN}=== RESUMO DAS CONFIGURAÇÕES ATIVAS ===${NC}"
    
    local has_config=false
    
    # Verificar kernel parameters
    if kernel_param_exists "resume"; then
        echo -e "  ✅ ${GREEN}Kernel: Hibernação configurada (resume=UUID)$NC"
        has_config=true
    fi
    
    if kernel_param_exists "zswap.enabled"; then
        local zswap_value=$(grep -o 'zswap.enabled=[^ ]*' /etc/kernel/cmdline | cut -d= -f2)
        echo -e "  ✅ ${GREEN}Kernel: Zswap $zswap_value$NC"
        has_config=true
    fi
    
    # Verificar mkinitcpio
    if hook_exists; then
        echo -e "  ✅ ${GREEN}Initramfs: Hook resume ativo$NC"
        has_config=true
    fi
    
    # Verificar systemd logind
    if [[ -f /etc/systemd/logind.conf ]]; then
        local lid_switch=$(grep "^HandleLidSwitch=" /etc/systemd/logind.conf 2>/dev/null | tail -1)
        local lid_external=$(grep "^HandleLidSwitchExternalPower=" /etc/systemd/logind.conf 2>/dev/null | tail -1)
        
        if [[ -n "$lid_switch" ]]; then
            echo -e "  ✅ ${GREEN}Logind: Tampa (bateria) = ${lid_switch#*=}$NC"
            has_config=true
        fi
        if [[ -n "$lid_external" ]]; then
            echo -e "  ✅ ${GREEN}Logind: Tampa (tomada) = ${lid_external#*=}$NC"
            has_config=true
        fi
    fi
    
    # Verificar systemd sleep
    if [[ -f /etc/systemd/sleep.conf ]]; then
        local allow_suspend=$(grep "^AllowSuspend=" /etc/systemd/sleep.conf 2>/dev/null | tail -1)
        local allow_hibernate=$(grep "^AllowHibernation=" /etc/systemd/sleep.conf 2>/dev/null | tail -1)
        
        if [[ -n "$allow_suspend" ]]; then
            echo -e "  ✅ ${GREEN}Sleep: Suspensão = ${allow_suspend#*=}$NC"
            has_config=true
        fi
        if [[ -n "$allow_hibernate" ]]; then
            echo -e "  ✅ ${GREEN}Sleep: Hibernação = ${allow_hibernate#*=}$NC"
            has_config=true
        fi
    fi
    
    # Verificar GDM
    if [[ -f /etc/gdm/custom.conf ]] && grep -q "^WaylandEnable=true" /etc/gdm/custom.conf; then
        echo -e "  ✅ ${GREEN}GDM: Wayland ativo$NC"
        has_config=true
    fi
    
    if ! $has_config; then
        echo -e "  ℹ️  ${YELLOW}Nenhuma configuração de energia específica detectada$NC"
    fi
}

# ANÁLISE DO SISTEMA
analyze_system() {
    step "Analisando capacidades do sistema..."
    
    echo -e "\n${CYAN}=== DETECÇÃO DE HARDWARE ===${NC}"
    
    # Verificar suspensão
    if [[ -f /sys/power/state ]] && grep -q "freeze\|mem" /sys/power/state; then
        CAN_SUSPEND=true
        echo -e "  ✅ ${GREEN}Suspensão suportada${NC}"
    else
        echo -e "  ❌ ${RED}Suspensão NÃO suportada${NC}"
    fi
    
    # Verificar hibernação
    if [[ -f /sys/power/disk ]] && swapon --show &>/dev/null; then
        CAN_HIBERNATE=true
        SWAP_UUID=$(blkid -s UUID -o value $(swapon --show=name --noheadings | head -1) 2>/dev/null)
        local swap_size=$(swapon --show=SIZE --noheadings | head -1)
        local ram_size=$(free -g | awk '/Mem:/{print $2}')
        echo -e "  ✅ ${GREEN}Hibernação suportada${NC}"
        echo -e "     💾 Swap: $swap_size | RAM: ${ram_size}GB"
        [[ -n "$SWAP_UUID" ]] && echo -e "     🔑 UUID: $SWAP_UUID"
    else
        echo -e "  ❌ ${RED}Hibernação NÃO suportada${NC}"
    fi
    
    # Hybrid sleep
    if $CAN_SUSPEND && $CAN_HIBERNATE; then
        CAN_HYBRID=true
        echo -e "  ✅ ${GREEN}Hybrid Sleep suportado${NC}"
    else
        echo -e "  ❌ ${RED}Hybrid Sleep NÃO suportado${NC}"
    fi
    
    # Detectar GPU
    GPU_DRIVER=$(lspci -k 2>/dev/null | grep -A 2 "VGA" | grep "Kernel driver in use" | cut -d: -f2 | tr -d ' ' | head -1)
    [[ -n "$GPU_DRIVER" ]] && echo -e "  🎮 ${CYAN}GPU: $GPU_DRIVER${NC}"
    
    # Modo de suspensão
    if [[ -f /sys/power/mem_sleep ]]; then
        MEM_SLEEP_MODE=$(grep -o '\[[^]]*\]' /sys/power/mem_sleep | tr -d '[]' | head -1)
        echo -e "  💤 ${CYAN}Modo de suspensão: $MEM_SLEEP_MODE${NC}"
    fi
    
    # Systemd-boot
    if [[ -f /etc/kernel/cmdline ]]; then
        echo -e "  🐧 ${CYAN}Bootloader: systemd-boot detectado${NC}"
        local current_params=$(cat /etc/kernel/cmdline)
        echo -e "     📋 $current_params"
    else
        echo -e "  ❌ ${RED}systemd-boot NÃO detectado${NC}"
    fi
    
    # GDM
    if [[ -f /etc/gdm/custom.conf ]]; then
        if grep -q "WaylandEnable=true" /etc/gdm/custom.conf; then
            echo -e "  🖥️  ${GREEN}GDM: Wayland habilitado${NC}"
        else
            echo -e "  🖥️  ${YELLOW}GDM: Wayland não configurado${NC}"
        fi
    else
        echo -e "  🖥️  ${YELLOW}GDM: /etc/gdm/custom.conf não encontrado${NC}"
    fi
    
    # Mostrar resumo das configurações ativas
    show_current_config_summary
}

# MOSTRAR OPÇÕES
show_available_options() {
    echo -e "\n${CYAN}=== OPÇÕES DISPONÍVEIS ===${NC}"
    
    local i=1
    AVAILABLE_OPTIONS=()
    
    # Modo MISTO
    if $CAN_SUSPEND && $CAN_HIBERNATE; then
        echo "$i. 🔄 Modo MISTO (Suspender → Hibernar)"
        AVAILABLE_OPTIONS+=("mixed_mode")
        ((i++))
    fi
    
    # Modo INTELIGENTE
    if $CAN_SUSPEND && $CAN_HIBERNATE; then
        echo "$i. 🎯 Modo INTELIGENTE (Recomendado)"
        AVAILABLE_OPTIONS+=("smart_mode")
        ((i++))
    fi
    
    # Modo HYBRID SLEEP
    if $CAN_HYBRID; then
        echo "$i. 🔋 Modo HYBRID SLEEP"
        AVAILABLE_OPTIONS+=("hybrid_mode")
        ((i++))
    fi
    
    # Opções básicas
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

# CONFIGURAÇÕES ESPECÍFICAS
configure_suspend_only() {
    step "Configurando SUSPENSÃO APENAS..."
    configure_gdm_wayland
    [[ -n "$SWAP_UUID" ]] && add_kernel_param "resume" "UUID=$SWAP_UUID"
    add_mkinitcpio_hook
    
    add_config "/etc/systemd/logind.conf" "" "=== CONFIGURAÇÃO DE ENERGIA - SUSPENSÃO ==="
    add_config "/etc/systemd/logind.conf" "HandlePowerKey=poweroff" "Botão de energia: desligar"
    add_config "/etc/systemd/logind.conf" "HandleSuspendKey=suspend" "Botão de suspensão: suspender"
    add_config "/etc/systemd/logind.conf" "HandleHibernateKey=suspend" "Botão de hibernação: suspender"
    add_config "/etc/systemd/logind.conf" "HandleLidSwitch=suspend" "Fechar tampa (bateria): suspender"
    add_config "/etc/systemd/logind.conf" "HandleLidSwitchExternalPower=suspend" "Fechar tampa (tomada): suspender"
    add_config "/etc/systemd/logind.conf" "IdleAction=suspend" "Inatividade: suspender após 30min"
    add_config "/etc/systemd/logind.conf" "IdleActionSec=30m" ""
    
    add_config "/etc/systemd/sleep.conf" "" "=== CONFIGURAÇÃO DE SUSPENSÃO ==="
    add_config "/etc/systemd/sleep.conf" "AllowSuspend=yes" "Permitir suspensão: SIM"
    add_config "/etc/systemd/sleep.conf" "AllowHibernation=no" "Permitir hibernação: NÃO"
    add_config "/etc/systemd/sleep.conf" "AllowHybridSleep=no" "Permitir hybrid sleep: NÃO"
    add_config "/etc/systemd/sleep.conf" "AllowSuspendThenHibernate=no" "Permitir suspender→hibernar: NÃO"
    add_config "/etc/systemd/sleep.conf" "SuspendState=freeze" "Modo de suspensão: freeze"
    
    success "Modo SUSPENSÃO configurado!"
}

configure_hibernate_only() {
    step "Configurando HIBERNAÇÃO APENAS..."
    configure_gdm_wayland
    [[ -n "$SWAP_UUID" ]] && add_kernel_param "resume" "UUID=$SWAP_UUID"
    add_mkinitcpio_hook
    
    add_config "/etc/systemd/logind.conf" "" "=== CONFIGURAÇÃO DE ENERGIA - HIBERNAÇÃO ==="
    add_config "/etc/systemd/logind.conf" "HandlePowerKey=poweroff" "Botão de energia: desligar"
    add_config "/etc/systemd/logind.conf" "HandleSuspendKey=hibernate" "Botão de suspensão: hibernar"
    add_config "/etc/systemd/logind.conf" "HandleHibernateKey=hibernate" "Botão de hibernação: hibernar"
    add_config "/etc/systemd/logind.conf" "HandleLidSwitch=hibernate" "Fechar tampa (bateria): hibernar"
    add_config "/etc/systemd/logind.conf" "HandleLidSwitchExternalPower=suspend" "Fechar tampa (tomada): suspender"
    add_config "/etc/systemd/logind.conf" "IdleAction=hibernate" "Inatividade: hibernar após 60min"
    add_config "/etc/systemd/logind.conf" "IdleActionSec=60m" ""
    
    add_config "/etc/systemd/sleep.conf" "" "=== CONFIGURAÇÃO DE HIBERNAÇÃO ==="
    add_config "/etc/systemd/sleep.conf" "AllowSuspend=no" "Permitir suspensão: NÃO"
    add_config "/etc/systemd/sleep.conf" "AllowHibernation=yes" "Permitir hibernação: SIM"
    add_config "/etc/systemd/sleep.conf" "AllowHybridSleep=no" "Permitir hybrid sleep: NÃO"
    add_config "/etc/systemd/sleep.conf" "AllowSuspendThenHibernate=no" "Permitir suspender→hibernar: NÃO"
    
    success "Modo HIBERNAÇÃO configurado!"
}

configure_smart_mode() {
    step "Configurando MODO INTELIGENTE..."
    configure_gdm_wayland
    [[ -n "$SWAP_UUID" ]] && {
        add_kernel_param "resume" "UUID=$SWAP_UUID"
        add_kernel_param "zswap.enabled" "0"
    }
    add_mkinitcpio_hook
    
    add_config "/etc/systemd/logind.conf" "" "=== CONFIGURAÇÃO INTELIGENTE DE ENERGIA ==="
    add_config "/etc/systemd/logind.conf" "HandleLidSwitch=suspend-then-hibernate" "Fechar tampa: suspender→hibernar (2h)"
    add_config "/etc/systemd/logind.conf" "HandleLidSwitchExternalPower=suspend-then-hibernate" "Fechar tampa (tomada): suspender→hibernar"
    add_config "/etc/systemd/logind.conf" "HandleLidSwitchDocked=ignore" "Fechar tampa (dock): ignorar"
    add_config "/etc/systemd/logind.conf" "HandlePowerKey=suspend-then-hibernate" "Botão de energia: suspender→hibernar"
    add_config "/etc/systemd/logind.conf" "HandleSuspendKey=suspend" "Botão de suspensão: suspender"
    add_config "/etc/systemd/logind.conf" "HandleHibernateKey=hibernate" "Botão de hibernação: hibernar"
    add_config "/etc/systemd/logind.conf" "HoldoffTimeoutSec=30s" "Tempo espera suspend→hibernate: 30s"
    add_config "/etc/systemd/logind.conf" "IdleAction=suspend-then-hibernate" "Inatividade: suspender→hibernar após 30min"
    add_config "/etc/systemd/logind.conf" "IdleActionSec=1800" ""
    add_config "/etc/systemd/logind.conf" "HandleBatteryCriticalLevel=5%" "Bateria crítica: 5%"
    add_config "/etc/systemd/logind.conf" "HandleBatteryCriticalAction=hibernate" "Ação bateria crítica: hibernar"
    
    add_config "/etc/systemd/sleep.conf" "" "=== CONFIGURAÇÃO INTELIGENTE DE SUSPENSÃO ==="
    add_config "/etc/systemd/sleep.conf" "HandleLidSwitch=suspend" "Fechar tampa: suspensão instantânea"
    add_config "/etc/systemd/sleep.conf" "HandleLidSwitchExternalPower=suspend" "Fechar tampa (tomada): suspensão"
    add_config "/etc/systemd/sleep.conf" "HandleLidSwitchDocked=ignore" "Fechar tampa (dock): ignorar"
    add_config "/etc/systemd/sleep.conf" "HibernateDelaySec=7200" "Hibernar após suspensão: 2 horas"
    add_config "/etc/systemd/sleep.conf" "AllowSuspend=yes" "Permitir suspensão: SIM"
    add_config "/etc/systemd/sleep.conf" "AllowHibernation=yes" "Permitir hibernação: SIM"
    add_config "/etc/systemd/sleep.conf" "AllowHybridSleep=yes" "Permitir hybrid sleep: SIM"
    add_config "/etc/systemd/sleep.conf" "SuspendMode=suspend" "Modo suspensão: suspend"
    add_config "/etc/systemd/sleep.conf" "SuspendState=mem" "Estado suspensão: mem"
    add_config "/etc/systemd/sleep.conf" "HibernateMode=platform" "Modo hibernação: platform"
    add_config "/etc/systemd/sleep.conf" "HibernateState=disk" "Estado hibernação: disk"
    
    success "Modo INTELIGENTE configurado!"
}

configure_mixed_mode() {
    step "Configurando MODO MISTO..."
    configure_gdm_wayland
    [[ -n "$SWAP_UUID" ]] && add_kernel_param "resume" "UUID=$SWAP_UUID"
    add_mkinitcpio_hook
    
    # Criar script para modo misto
    cat > /usr/local/bin/smart-suspend-hibernate.sh << 'EOF'
#!/bin/bash
logger "Modo Misto: Suspender → Hibernar após 30min"
systemctl suspend
sleep 30m
systemctl hibernate
EOF
    chmod +x /usr/local/bin/smart-suspend-hibernate.sh
    
    add_config "/etc/systemd/logind.conf" "" "=== MODO MISTO (Suspender → Hibernar) ==="
    add_config "/etc/systemd/logind.conf" "HandlePowerKey=poweroff" "Botão de energia: desligar"
    add_config "/etc/systemd/logind.conf" "HandleSuspendKey=suspend" "Botão de suspensão: suspender"
    add_config "/etc/systemd/logind.conf" "HandleHibernateKey=hibernate" "Botão de hibernação: hibernar"
    add_config "/etc/systemd/logind.conf" "HandleLidSwitch=exec /usr/local/bin/smart-suspend-hibernate.sh" "Fechar tampa: suspender→hibernar (30min)"
    add_config "/etc/systemd/logind.conf" "HandleLidSwitchExternalPower=suspend" "Fechar tampa (tomada): suspender"
    add_config "/etc/systemd/logind.conf" "IdleAction=suspend" "Inatividade: suspender após 30min"
    add_config "/etc/systemd/logind.conf" "IdleActionSec=30m" ""
    
    add_config "/etc/systemd/sleep.conf" "" "=== MODO MISTO ==="
    add_config "/etc/systemd/sleep.conf" "AllowSuspend=yes" "Permitir suspensão: SIM"
    add_config "/etc/systemd/sleep.conf" "AllowHibernation=yes" "Permitir hibernação: SIM"
    add_config "/etc/systemd/sleep.conf" "AllowHybridSleep=no" "Permitir hybrid sleep: NÃO"
    add_config "/etc/systemd/sleep.conf" "AllowSuspendThenHibernate=no" "Permitir suspender→hibernar: NÃO"
    add_config "/etc/systemd/sleep.conf" "SuspendState=freeze" "Modo de suspensão: freeze"
    
    success "Modo MISTO configurado!"
}

configure_hybrid_mode() {
    step "Configurando HYBRID SLEEP..."
    configure_gdm_wayland
    [[ -n "$SWAP_UUID" ]] && add_kernel_param "resume" "UUID=$SWAP_UUID"
    add_mkinitcpio_hook
    
    add_config "/etc/systemd/logind.conf" "" "=== HYBRID SLEEP ==="
    add_config "/etc/systemd/logind.conf" "HandlePowerKey=poweroff" "Botão de energia: desligar"
    add_config "/etc/systemd/logind.conf" "HandleSuspendKey=hybrid-sleep" "Botão de suspensão: hybrid-sleep"
    add_config "/etc/systemd/logind.conf" "HandleHibernateKey=hibernate" "Botão de hibernação: hibernar"
    add_config "/etc/systemd/logind.conf" "HandleLidSwitch=hybrid-sleep" "Fechar tampa: hybrid-sleep"
    add_config "/etc/systemd/logind.conf" "HandleLidSwitchExternalPower=hybrid-sleep" "Fechar tampa (tomada): hybrid-sleep"
    add_config "/etc/systemd/logind.conf" "IdleAction=hybrid-sleep" "Inatividade: hybrid-sleep após 30min"
    add_config "/etc/systemd/logind.conf" "IdleActionSec=30m" ""
    
    add_config "/etc/systemd/sleep.conf" "" "=== HYBRID SLEEP ==="
    add_config "/etc/systemd/sleep.conf" "AllowSuspend=yes" "Permitir suspensão: SIM"
    add_config "/etc/systemd/sleep.conf" "AllowHibernation=yes" "Permitir hibernação: SIM"
    add_config "/etc/systemd/sleep.conf" "AllowHybridSleep=yes" "Permitir hybrid sleep: SIM"
    add_config "/etc/systemd/sleep.conf" "AllowSuspendThenHibernate=no" "Permitir suspender→hibernar: NÃO"
    add_config "/etc/systemd/sleep.conf" "SuspendState=freeze" "Modo suspensão: freeze"
    add_config "/etc/systemd/sleep.conf" "HibernateState=disk" "Estado hibernação: disk"
    add_config "/etc/systemd/sleep.conf" "HybridSleepState=disk" "Estado hybrid sleep: disk"
    
    success "Modo HYBRID SLEEP configurado!"
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
    
    # Kernel parameters
    if [[ -f /etc/kernel/cmdline ]]; then
        echo -e "\n${BLUE}Kernel Parameters:${NC}"
        cat /etc/kernel/cmdline
        echo -e "\n${BLUE}Parâmetros de Energia:${NC}"
        if kernel_param_exists "resume"; then
            local resume_uuid=$(grep -o 'resume=UUID=[^ ]*' /etc/kernel/cmdline | cut -d= -f3)
            echo -e "  ✅ ${GREEN}resume: CONFIGURADO (UUID=$resume_uuid)$NC"
        else
            echo -e "  ❌ ${RED}resume: NÃO CONFIGURADO$NC"
        fi
        
        if kernel_param_exists "zswap.enabled"; then
            local zswap_value=$(grep -o 'zswap.enabled=[^ ]*' /etc/kernel/cmdline | cut -d= -f2)
            echo -e "  ✅ ${GREEN}zswap.enabled: $zswap_value$NC"
        else
            echo -e "  ❌ ${RED}zswap.enabled: NÃO CONFIGURADO$NC"
        fi
    fi
    
    # Mkinitcpio
    echo -e "\n${BLUE}Mkinitcpio Hooks:${NC}"
    local hooks_line=$(grep "^HOOKS=" /etc/mkinitcpio.conf 2>/dev/null || echo "Não encontrado")
    echo "$hooks_line"
    if hook_exists; then
        echo -e "  ✅ ${GREEN}resume hook: PRESENTE$NC"
    else
        echo -e "  ❌ ${RED}resume hook: AUSENTE$NC"
    fi
    
    # Systemd logind
    echo -e "\n${BLUE}Systemd Logind:${NC}"
    if [[ -f /etc/systemd/logind.conf ]]; then
        grep -E "^(Handle|IdleAction|HoldoffTimeout|HandleBattery)" /etc/systemd/logind.conf 2>/dev/null | while read -r line; do
            echo "  📝 $line"
        done || echo "  ℹ️  Nenhuma configuração específica"
    else
        echo "  ❌ Arquivo não encontrado"
    fi
    
    # Systemd sleep
    echo -e "\n${BLUE}Systemd Sleep:${NC}"
    if [[ -f /etc/systemd/sleep.conf ]]; then
        grep -E "^(Allow|Handle|HibernateDelay|Suspend|Hibernate)" /etc/systemd/sleep.conf 2>/dev/null | while read -r line; do
            echo "  📝 $line"
        done || echo "  ℹ️  Nenhuma configuração específica"
    else
        echo "  ❌ Arquivo não encontrado"
    fi
    
    # GDM
    echo -e "\n${BLUE}GDM Config:${NC}"
    if [[ -f /etc/gdm/custom.conf ]]; then
        grep -E "^(WaylandEnable|\[daemon\])" /etc/gdm/custom.conf 2>/dev/null | while read -r line; do
            echo "  📝 $line"
        done || echo "  ℹ️  Configuração padrão"
    else
        echo "  ❌ Arquivo não encontrado"
    fi
}

apply_configurations() {
    step "Aplicando configurações..."
    
    # Regenerar initramfs
    if [[ -f /etc/mkinitcpio.conf ]]; then
        if mkinitcpio -P; then
            success "Initramfs regenerado com sucesso!"
        else
            error "Falha ao regenerar initramfs!"
            return 1
        fi
    fi
    
    echo -e "\n${YELLOW}=== ⚠️  REINICIE O SISTEMA ===${NC}"
    echo "Comando: ${GREEN}reboot${NC}"
    echo "Após reiniciar, teste com: ${CYAN}systemctl suspend${NC}"
    echo "Monitore os logs: ${CYAN}journalctl -f -u systemd-logind${NC}"
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
            hibernate_only) configure_hibernate_only ;;
            mixed_mode) configure_mixed_mode ;;
            smart_mode) configure_smart_mode ;;
            hybrid_mode) configure_hybrid_mode ;;
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
