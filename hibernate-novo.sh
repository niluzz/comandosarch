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
    if [[ $EUID -ne 0 ]]; then
        error "Este script precisa ser executado como root!"
        exit 1
    fi
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
    if [[ ! -f /etc/mkinitcpio.conf ]]; then
        warn "Arquivo /etc/mkinitcpio.conf não encontrado"
        return 1
    fi
    
    # Verificar se o arquivo está corrompido (com "resume" fora dos hooks)
    if grep -q "^resume" /etc/mkinitcpio.conf; then
        warn "Arquivo mkinitcpio.conf corrompido detectado. Corrigindo..."
        # Remover linhas "resume" soltas
        sed -i '/^resume/d' /etc/mkinitcpio.conf
        info "Linhas 'resume' soltas removidas"
    fi
    
    return 0
}

# VERIFICAR SE HOOK JÁ EXISTE
hook_exists() {
    local hook=$1
    if grep -q "HOOKS=.*$hook" /etc/mkinitcpio.conf; then
        return 0
    else
        return 1
    fi
}

# Função CORRETA para adicionar hooks ao mkinitcpio
add_mkinitcpio_hook() {
    local hook=$1
    
    # Primeiro verificar e corrigir se necessário
    fix_mkinitcpio_conf
    
    if ! hook_exists "$hook"; then
        # Encontrar a linha HOOKS ativa (não comentada)
        local hooks_line=$(grep "^HOOKS=" /etc/mkinitcpio.conf)
        
        if [[ -n "$hooks_line" ]]; then
            # Extrair o conteúdo dentro dos parênteses
            if [[ $hooks_line =~ HOOKS=\((.*)\) ]]; then
                local current_hooks="${BASH_REMATCH[1]}"
                
                # Adicionar o hook após o fsck (se existir) ou no final
                if [[ $current_hooks =~ (.*fsck)(.*) ]]; then
                    # Se fsck existe, adicionar resume depois dele
                    local new_hooks="${BASH_REMATCH[1]} $hook${BASH_REMATCH[2]}"
                else
                    # Se fsck não existe, adicionar no final
                    local new_hooks="$current_hooks $hook"
                fi
                
                # Substituir apenas a parte dentro dos parênteses
                sed -i "s/^HOOKS=($current_hooks)/HOOKS=($new_hooks)/" /etc/mkinitcpio.conf
                info "Hook $hook adicionado após fsck no mkinitcpio"
            else
                # Formato inválido, adicionar de forma segura
                warn "Formato HOOKS inválido, adicionando de forma segura..."
                sed -i '/^HOOKS=/ s/)/ resume)/' /etc/mkinitcpio.conf
                info "Hook $hook adicionado ao mkinitcpio"
            fi
        else
            error "Linha HOOKS não encontrada em /etc/mkinitcpio.conf"
            return 1
        fi
    else
        info "Hook $hook já existe no mkinitcpio"
    fi
    
    return 0
}

# VERIFICAR SINTAXE do mkinitcpio.conf
check_mkinitcpio_syntax() {
    if [[ ! -f /etc/mkinitcpio.conf ]]; then
        error "Arquivo /etc/mkinitcpio.conf não encontrado!"
        return 1
    fi
    
    # Verificar se há comandos soltos (linhas que não são comentários, variáveis ou hooks válidos)
    local invalid_lines=$(grep -E '^[^#][^=]*$' /etc/mkinitcpio.conf | grep -v "^HOOKS=" | grep -v "^MODULES=" | grep -v "^BINARIES=" | grep -v "^FILES=" | grep -v "^COMPRESSION=" | grep -v "^COMPRESSION_OPTIONS=" || true)
    
    if [[ -n "$invalid_lines" ]]; then
        warn "Possível sintaxe inválida detectada no mkinitcpio.conf:"
        echo "$invalid_lines"
        return 1
    fi
    
    return 0
}

# VERIFICAR SE PARÂMETRO JÁ EXISTE NO KERNEL CMDLINE
kernel_param_exists() {
    local param=$1
    if [[ -f /etc/kernel/cmdline ]]; then
        if grep -q "$param" /etc/kernel/cmdline; then
            return 0
        fi
    fi
    return 1
}

# ADICIONAR PARÂMETRO NO KERNEL CMDLINE SE NÃO EXISTIR
add_kernel_param() {
    local param=$1
    local value=$2
    local full_param="$param=$value"
    
    if [[ ! -f /etc/kernel/cmdline ]]; then
        error "Arquivo /etc/kernel/cmdline não encontrado!"
        return 1
    fi
    
    if kernel_param_exists "$param"; then
        info "Parâmetro $param já existe"
    else
        # Parâmetro não existe, adicionar
        info "Adicionando parâmetro $full_param"
        local current_cmdline=$(cat /etc/kernel/cmdline)
        echo "$current_cmdline $full_param" > /etc/kernel/cmdline
    fi
}

# VERIFICAR SE CONFIGURAÇÃO JÁ EXISTE
check_existing_config() {
    step "Verificando configurações existentes..."
    
    local existing_configs=()
    
    # Verificar kernel parameters
    if [[ -f /etc/kernel/cmdline ]]; then
        if kernel_param_exists "resume"; then
            existing_configs+=("resume parameter in kernel cmdline")
        fi
        if kernel_param_exists "zswap.enabled"; then
            existing_configs+=("zswap parameter in kernel cmdline")
        fi
    fi
    
    # Verificar hooks do mkinitcpio
    if hook_exists "resume"; then
        existing_configs+=("resume hook in mkinitcpio")
    fi
    
    # Verificar arquivos de configuração do systemd
    if [[ -f /etc/systemd/logind.conf ]] && grep -q "HandleLidSwitch" /etc/systemd/logind.conf 2>/dev/null; then
        existing_configs+=("systemd logind configuration")
    fi
    
    if [[ -f /etc/systemd/sleep.conf ]] && grep -q "Allow" /etc/systemd/sleep.conf 2>/dev/null; then
        existing_configs+=("systemd sleep configuration")
    fi
    
    # Verificar GDM
    if [[ -f /etc/gdm/custom.conf ]] && grep -q "WaylandEnable=true" /etc/gdm/custom.conf 2>/dev/null; then
        existing_configs+=("GDM Wayland configuration")
    fi
    
    if [[ ${#existing_configs[@]} -gt 0 ]]; then
        echo -e "\n${YELLOW}=== CONFIGURAÇÕES EXISTENTES DETECTADAS ===${NC}"
        for config in "${existing_configs[@]}"; do
            echo "  ✅ $config"
        done
        return 0
    else
        echo -e "\n${GREEN}=== NENHUMA CONFIGURAÇÃO PRÉVIA DETECTADA ===${NC}"
        return 1
    fi
}

# CONFIGURAR GDM/WAYLAND
configure_gdm_wayland() {
    step "Configurando GDM para Wayland..."
    
    if [[ ! -f /etc/gdm/custom.conf ]]; then
        warn "Arquivo /etc/gdm/custom.conf não encontrado, criando..."
        mkdir -p /etc/gdm
        cat > /etc/gdm/custom.conf << 'EOF'
# Configuração do GDM - Gerenciador de Display do GNOME
[daemon]
# Habilita Wayland para melhor performance e compatibilidade
WaylandEnable=true

[security]

[xdmcp]

[chooser]

[debug]
EOF
        success "Arquivo /etc/gdm/custom.conf criado com Wayland habilitado"
        return
    fi
    
    # Verificar se WaylandEnable já está configurado corretamente
    if grep -q "^WaylandEnable=true" /etc/gdm/custom.conf; then
        info "WaylandEnable já está configurado como true"
        return
    fi
    
    # Verificar se WaylandEnable existe no arquivo
    if grep -q "WaylandEnable" /etc/gdm/custom.conf; then
        # Se existe, substituir por true (descomentando se necessário)
        sed -i 's/^#*\s*WaylandEnable.*/WaylandEnable=true/' /etc/gdm/custom.conf
        info "WaylandEnable configurado para true"
    else
        # Se não existe, adicionar
        if grep -q "\[daemon\]" /etc/gdm/custom.conf; then
            # Adicionar após [daemon]
            sed -i '/\[daemon\]/a WaylandEnable=true' /etc/gdm/custom.conf
        else
            # Adicionar seção [daemon] completa
            echo -e "\n[daemon]\nWaylandEnable=true" >> /etc/gdm/custom.conf
        fi
        info "WaylandEnable adicionado e configurado para true"
    fi
    
    success "GDM configurado para usar Wayland"
}

# ANÁLISE COMPLETA DO SISTEMA
analyze_system() {
    step "Analisando capacidades do sistema..."
    
    echo -e "\n${CYAN}=== DETECÇÃO DE HARDWARE ===${NC}"
    
    # 1. Verificar suspensão
    if [[ -f /sys/power/state ]]; then
        local sleep_states=$(cat /sys/power/state)
        if echo "$sleep_states" | grep -q "freeze\|mem"; then
            CAN_SUSPEND=true
            echo -e "  ✅ ${GREEN}Suspensão suportada${NC}"
        else
            echo -e "  ❌ ${RED}Suspensão NÃO suportada${NC}"
        fi
    else
        echo -e "  ❌ ${RED}Interface de energia não encontrada${NC}"
    fi
    
    # 2. Verificar hibernação
    if [[ -f /sys/power/disk ]]; then
        if swapon --show &>/dev/null; then
            CAN_HIBERNATE=true
            SWAP_UUID=$(blkid -s UUID -o value $(swapon --show=name --noheadings | head -1) 2>/dev/null)
            local swap_size=$(swapon --show=SIZE --noheadings | head -1)
            local ram_size=$(free -g | grep Mem: | awk '{print $2}')
            echo -e "  ✅ ${GREEN}Hibernação suportada${NC}"
            echo -e "     💾 Swap: $swap_size | RAM: ${ram_size}GB"
            [[ -n "$SWAP_UUID" ]] && echo -e "     🔑 UUID: $SWAP_UUID"
            
            # Verificar se swap é suficiente
            if [[ "$swap_size" =~ ^([0-9]+)G$ ]]; then
                local swap_gb=${BASH_REMATCH[1]}
                if [[ $swap_gb -lt $ram_size ]]; then
                    warn "     ⚠️  Swap menor que RAM - hibernação pode falhar"
                fi
            fi
        else
            echo -e "  ❌ ${RED}Hibernação NÃO suportada (sem swap ativo)${NC}"
        fi
    fi
    
    # 3. Verificar hybrid sleep
    if $CAN_SUSPEND && $CAN_HIBERNATE; then
        CAN_HYBRID=true
        echo -e "  ✅ ${GREEN}Hybrid Sleep suportado${NC}"
    else
        echo -e "  ❌ ${RED}Hybrid Sleep NÃO suportado${NC}"
    fi
    
    # 4. Detectar GPU
    GPU_DRIVER=$(lspci -k | grep -A 2 "VGA" | grep "Kernel driver in use" | cut -d: -f2 | tr -d ' ' | head -1)
    if [[ -n "$GPU_DRIVER" ]]; then
        echo -e "  🎮 ${CYAN}GPU: $GPU_DRIVER${NC}"
    fi
    
    # 5. Verificar modo de suspensão
    if [[ -f /sys/power/mem_sleep ]]; then
        MEM_SLEEP_MODE=$(cat /sys/power/mem_sleep | cut -d'[' -f2 | cut -d']' -f1)
        echo -e "  💤 ${CYAN}Modo de suspensão: $MEM_SLEEP_MODE${NC}"
    fi
    
    # 6. Verificar systemd-boot
    if [[ -f /etc/kernel/cmdline ]]; then
        echo -e "  🐧 ${CYAN}Bootloader: systemd-boot detectado${NC}"
        # Mostrar parâmetros atuais
        local current_params=$(cat /etc/kernel/cmdline)
        echo -e "     📋 Parâmetros: $current_params"
    else
        echo -e "  ❌ ${RED}systemd-boot NÃO detectado${NC}"
    fi
    
    # 7. Verificar zswap
    if [[ -d /sys/module/zswap ]]; then
        local zswap_status=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo "N/A")
        echo -e "  🔄 ${CYAN}Zswap: $zswap_status${NC}"
    fi
    
    # 8. Verificar GDM
    if [[ -f /etc/gdm/custom.conf ]]; then
        local wayland_status=$(grep -i "WaylandEnable" /etc/gdm/custom.conf | tail -1)
        if [[ "$wayland_status" == *"true"* ]]; then
            echo -e "  🖥️  ${GREEN}GDM: Wayland habilitado${NC}"
        else
            echo -e "  🖥️  ${YELLOW}GDM: Wayland não configurado${NC}"
        fi
    else
        echo -e "  🖥️  ${YELLOW}GDM: /etc/gdm/custom.conf não encontrado${NC}"
    fi
    
    # 9. Verificar configurações existentes
    check_existing_config
}

# MOSTRAR OPÇÕES BASEADAS NA ANÁLISE
show_available_options() {
    echo -e "\n${CYAN}=== OPÇÕES DISPONÍVEIS PARA SEU SISTEMA ===${NC}"
    
    local option_number=1
    AVAILABLE_OPTIONS=()
    
    if $CAN_SUSPEND; then
        echo "$option_number. ⚡ Modo SUSPENSÃO APENAS"
        AVAILABLE_OPTIONS+=("suspend_only")
        ((option_number++))
    fi
    
    if $CAN_HIBERNATE; then
        echo "$option_number. 💾 Modo HIBERNAÇÃO APENAS" 
        AVAILABLE_OPTIONS+=("hibernate_only")
        ((option_number++))
    fi
    
    if $CAN_SUSPEND && $CAN_HIBERNATE; then
        echo "$option_number. 🔄 Modo MISTO (Suspender → Hibernar)"
        AVAILABLE_OPTIONS+=("mixed_mode")
        ((option_number++))
        
        echo "$option_number. 🎯 Modo INTELIGENTE (Recomendado)"
        AVAILABLE_OPTIONS+=("smart_mode")
        ((option_number++))
    fi
    
    if $CAN_HYBRID; then
        echo "$option_number. 🔋 Modo HYBRID SLEEP"
        AVAILABLE_OPTIONS+=("hybrid_mode")
        ((option_number++))
    fi
    
    echo "$option_number. 🖥️  Configurar GDM/Wayland APENAS"
    AVAILABLE_OPTIONS+=("gdm_only")
    ((option_number++))
    
    echo "$option_number. 🔧 Corrigir mkinitcpio.conf"
    AVAILABLE_OPTIONS+=("fix_mkinitcpio")
    ((option_number++))
    
    echo "$option_number. 🧪 Verificar configuração atual"
    AVAILABLE_OPTIONS+=("check_config")
    
    echo ""
    echo "0. ❌ Sair"
    echo ""
}

# CORRIGIR MKINITCPIO
fix_mkinitcpio_manual() {
    step "Corrigindo mkinitcpio.conf manualmente..."
    
    # Remover qualquer linha "resume" solta
    sed -i '/^resume/d' /etc/mkinitcpio.conf
    
    # Adicionar o hook resume corretamente se não existir
    if ! hook_exists "resume"; then
        add_mkinitcpio_hook "resume"
    else
        info "Hook resume já existe"
    fi
    
    success "mkinitcpio.conf verificado e corrigido!"
}

# CONFIGURAÇÃO PARA SUSPENSÃO APENAS
configure_suspend_only() {
    step "Configurando modo SUSPENSÃO APENAS..."
    
    # Configurar GDM primeiro
    configure_gdm_wayland
    
    # Kernel parameters - apenas adicionar se não existir
    if [[ -n "$SWAP_UUID" ]]; then
        add_kernel_param "resume" "UUID=$SWAP_UUID"
    fi
    
    info "Parâmetros do kernel verificados para suspensão"
    
    # Mkinitcpio (manter resume para segurança)
    add_mkinitcpio_hook "resume"
    
    # Systemd
    cat > /etc/systemd/logind.conf << 'EOF'
[Login]
# Modo SUSPENSÃO APENAS
HandlePowerKey=poweroff
HandleSuspendKey=suspend
HandleHibernateKey=suspend
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
IdleAction=suspend
IdleActionSec=30m
PowerKeyIgnoreInhibited=yes
SuspendKeyIgnoreInhibited=yes
HibernateKeyIgnoreInhibited=yes
LidSwitchIgnoreInhibited=yes
EOF

    cat > /etc/systemd/sleep.conf << 'EOF'
[Sleep]
# Modo SUSPENSÃO APENAS
AllowSuspend=yes
AllowHibernation=no
AllowHybridSleep=no
AllowSuspendThenHibernate=no
SuspendState=freeze
EOF

    success "Modo SUSPENSÃO APENAS configurado!"
}

# CONFIGURAÇÃO PARA HIBERNAÇÃO APENAS
configure_hibernate_only() {
    step "Configurando modo HIBERNAÇÃO APENAS..."
    
    # Configurar GDM primeiro
    configure_gdm_wayland
    
    # Kernel parameters - apenas adicionar se não existir
    if [[ -n "$SWAP_UUID" ]]; then
        add_kernel_param "resume" "UUID=$SWAP_UUID"
    fi
    
    # Mkinitcpio
    add_mkinitcpio_hook "resume"
    
    # Systemd
    cat > /etc/systemd/logind.conf << 'EOF'
[Login]
# Modo HIBERNAÇÃO APENAS
HandlePowerKey=poweroff
HandleSuspendKey=hibernate
HandleHibernateKey=hibernate
HandleLidSwitch=hibernate
HandleLidSwitchExternalPower=suspend
IdleAction=hibernate
IdleActionSec=60m
PowerKeyIgnoreInhibited=yes
SuspendKeyIgnoreInhibited=yes
HibernateKeyIgnoreInhibited=yes
LidSwitchIgnoreInhibited=yes
EOF

    cat > /etc/systemd/sleep.conf << 'EOF'
[Sleep]
# Modo HIBERNAÇÃO APENAS
AllowSuspend=no
AllowHibernation=yes
AllowHybridSleep=no
AllowSuspendThenHibernate=no
EOF

    success "Modo HIBERNAÇÃO APENAS configurado!"
}

# CONFIGURAÇÃO MODO MISTO
configure_mixed_mode() {
    step "Configurando modo MISTO (Suspender → Hibernar)..."
    
    # Configurar GDM primeiro
    configure_gdm_wayland
    
    # Kernel parameters - apenas adicionar se não existir
    if [[ -n "$SWAP_UUID" ]]; then
        add_kernel_param "resume" "UUID=$SWAP_UUID"
    fi
    
    # Mkinitcpio
    add_mkinitcpio_hook "resume"
    
    # Systemd com script personalizado
    if [[ ! -f /usr/local/bin/smart-suspend-hibernate.sh ]]; then
        cat > /usr/local/bin/smart-suspend-hibernate.sh << 'EOF'
#!/bin/bash
# Script inteligente: suspende primeiro, depois hiberna
logger "Modo Misto: Suspender → Hibernar após 30min"
systemctl suspend
sleep 30m
systemctl hibernate
EOF
        chmod +x /usr/local/bin/smart-suspend-hibernate.sh
    fi

    cat > /etc/systemd/logind.conf << 'EOF'
[Login]
# Modo MISTO (Suspender → Hibernar)
HandlePowerKey=poweroff
HandleSuspendKey=suspend
HandleHibernateKey=hibernate
HandleLidSwitch=exec /usr/local/bin/smart-suspend-hibernate.sh
HandleLidSwitchExternalPower=suspend
IdleAction=suspend
IdleActionSec=30m
PowerKeyIgnoreInhibited=yes
SuspendKeyIgnoreInhibited=yes
HibernateKeyIgnoreInhibited=yes
LidSwitchIgnoreInhibited=yes
EOF

    cat > /etc/systemd/sleep.conf << 'EOF'
[Sleep]
# Modo MISTO
AllowSuspend=yes
AllowHibernation=yes
AllowHybridSleep=no
AllowSuspendThenHibernate=no
SuspendState=freeze
EOF

    success "Modo MISTO configurado (Suspender → Hibernar após 30min)!"
}

# CONFIGURAÇÃO MODO INTELIGENTE
configure_smart_mode() {
    step "Configurando modo INTELIGENTE (Recomendado)..."
    
    # Configurar GDM primeiro
    configure_gdm_wayland
    
    # Kernel parameters - apenas adicionar se não existir
    if [[ -n "$SWAP_UUID" ]]; then
        add_kernel_param "resume" "UUID=$SWAP_UUID"
        add_kernel_param "zswap.enabled" "0"
    fi
    
    # Mkinitcpio
    add_mkinitcpio_hook "resume"
    
    # Systemd inteligente
    cat > /etc/systemd/logind.conf << 'EOF'
[Login]
# TAMPA - Comportamento principal
HandleLidSwitch=suspend-then-hibernate
HandleLidSwitchExternalPower=suspend-then-hibernate
HandleLidSwitchDocked=ignore

# BOTÕES DE ENERGIA
HandlePowerKey=suspend-then-hibernate
HandleSuspendKey=suspend
HandleHibernateKey=hibernate

# TEMPOS para suspend-then-hibernate (2 horas = 7200 segundos)
HoldoffTimeoutSec=30s
IdleAction=suspend-then-hibernate
IdleActionSec=1800

# BATERIA CRÍTICA
HandleBatteryCriticalLevel=5%
HandleBatteryCriticalAction=hibernate

# CONFIGURAÇÕES GLOBAIS
NAutoVTs=6
ReserveVT=6
KillUserProcesses=no
KillOnlyUsers=
KillExcludeUsers=root
InhibitDelayMaxSec=5
UserStopDelaySec=10
EOF

    cat > /etc/systemd/sleep.conf << 'EOF'
[Sleep]
# Suspender ao fechar tampa (instantâneo)
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
HandleLidSwitchDocked=ignore

# Hibernar após 2 horas de suspensão (segurança)
HibernateDelaySec=7200

# Modo de suspensão confiável (evita tela preta)
AllowSuspend=yes
AllowHibernation=yes
AllowHybridSleep=yes
SuspendMode=suspend
SuspendState=mem
HibernateMode=platform
HibernateState=disk
EOF

    success "Modo INTELIGENTE configurado!"
}

# CONFIGURAR HYBRID SLEEP
configure_hybrid_mode() {
    step "Configurando modo HYBRID SLEEP..."
    
    # Configurar GDM primeiro
    configure_gdm_wayland
    
    # Kernel parameters - apenas adicionar se não existir
    if [[ -n "$SWAP_UUID" ]]; then
        add_kernel_param "resume" "UUID=$SWAP_UUID"
    fi
    
    # Mkinitcpio
    add_mkinitcpio_hook "resume"
    
    # Systemd
    cat > /etc/systemd/logind.conf << 'EOF'
[Login]
# Modo HYBRID SLEEP
HandlePowerKey=poweroff
HandleSuspendKey=hybrid-sleep
HandleHibernateKey=hibernate
HandleLidSwitch=hybrid-sleep
HandleLidSwitchExternalPower=hybrid-sleep
IdleAction=hybrid-sleep
IdleActionSec=30m
PowerKeyIgnoreInhibited=yes
SuspendKeyIgnoreInhibited=yes
HibernateKeyIgnoreInhibited=yes
LidSwitchIgnoreInhibited=yes
EOF

    cat > /etc/systemd/sleep.conf << 'EOF'
[Sleep]
# Modo HYBRID SLEEP
AllowSuspend=yes
AllowHibernation=yes
AllowHybridSleep=yes
AllowSuspendThenHibernate=no
SuspendState=freeze
HibernateState=disk
HybridSleepState=disk
EOF

    success "Modo HYBRID SLEEP configurado!"
}

# CONFIGURAR APENAS GDM
configure_gdm_only() {
    step "Configurando apenas GDM/Wayland..."
    configure_gdm_wayland
    success "GDM configurado com Wayland habilitado!"
}

# VERIFICAR CONFIGURAÇÃO ATUAL
check_current_config() {
    step "Verificando configuração atual..."
    
    echo -e "\n${CYAN}=== CONFIGURAÇÃO ATUAL ===${NC}"
    
    # Kernel parameters
    if [[ -f /etc/kernel/cmdline ]]; then
        echo -e "\n${BLUE}Kernel Parameters:${NC}"
        cat /etc/kernel/cmdline
        
        # Verificar parâmetros específicos
        echo -e "\n${BLUE}Parâmetros de Energia:${NC}"
        if kernel_param_exists "resume"; then
            echo -e "  ✅ ${GREEN}resume: CONFIGURADO${NC}"
        else
            echo -e "  ❌ ${RED}resume: NÃO CONFIGURADO${NC}"
        fi
        
        if kernel_param_exists "zswap.enabled"; then
            echo -e "  ✅ ${GREEN}zswap.enabled: CONFIGURADO${NC}"
        else
            echo -e "  ❌ ${RED}zswap.enabled: NÃO CONFIGURADO${NC}"
        fi
    fi
    
    # Mkinitcpio hooks
    echo -e "\n${BLUE}Mkinitcpio Hooks:${NC}"
    local hooks_line=$(grep "^HOOKS=" /etc/mkinitcpio.conf)
    echo "$hooks_line"
    
    if hook_exists "resume"; then
        echo -e "  ✅ ${GREEN}resume hook: PRESENTE${NC}"
    else
        echo -e "  ❌ ${RED}resume hook: AUSENTE${NC}"
    fi
    
    # Systemd logind
    echo -e "\n${BLUE}Systemd Logind:${NC}"
    grep -v "^#" /etc/systemd/logind.conf | grep -v "^$" | head -10
    
    # Systemd sleep
    echo -e "\n${BLUE}Systemd Sleep:${NC}"
    grep -v "^#" /etc/systemd/sleep.conf 2>/dev/null | grep -v "^$" || echo "Arquivo não configurado"
    
    # Swap
    echo -e "\n${BLUE}Swap:${NC}"
    swapon --show 2>/dev/null || echo "Nenhum swap ativo"
    
    # GDM
    echo -e "\n${BLUE}GDM Config:${NC}"
    if [[ -f /etc/gdm/custom.conf ]]; then
        grep -v "^#" /etc/gdm/custom.conf | grep -v "^$" || echo "Arquivo vazio ou apenas comentários"
    else
        echo "Arquivo /etc/gdm/custom.conf não encontrado"
    fi
}

# APLICAR CONFIGURAÇÕES
apply_configurations() {
    step "Aplicando configurações..."
    
    # Primeiro verificar se o mkinitcpio.conf está válido
    if ! check_mkinitcpio_syntax; then
        error "mkinitcpio.conf contém erros de sintaxe. Não é possível continuar."
        echo "Use a opção 'Corrigir mkinitcpio.conf' primeiro."
        return 1
    fi
    
    # Regenerar initramfs se mkinitcpio foi modificado
    if [[ -f /etc/mkinitcpio.conf ]]; then
        info "Regenerando initramfs..."
        if mkinitcpio -P; then
            success "Initramfs regenerado com sucesso!"
        else
            error "Falha ao regenerar initramfs!"
            return 1
        fi
    fi
    
    success "Configurações aplicadas!"
    
    echo -e "\n${YELLOW}=== ⚠️  IMPORTANTE ===${NC}"
    echo "Para que todas as configurações entrem em vigor,"
    echo "você DEVE REINICIAR o sistema manualmente."
    echo ""
    echo "Comando para reiniciar: ${GREEN}reboot${NC}"
    echo ""
    echo "Após reiniciar:"
    echo "- Teste a configuração escolhida"
    echo "- Verifique os logs com: journalctl -f -u systemd-logind"
    echo ""
    echo "O sistema NÃO reiniciará automaticamente."
}

# FUNÇÃO PRINCIPAL
main() {
    check_root
    show_header
    
    # Primeiro: análise completa do sistema
    analyze_system
    
    # Mostrar opções baseadas na análise
    show_available_options
    
    # Ler escolha do usuário
    read -p "Selecione uma opção (0-${#AVAILABLE_OPTIONS[@]}): " choice
    
    if [[ $choice -eq 0 ]]; then
        info "Saindo..."
        exit 0
    fi
    
    if [[ $choice -gt 0 && $choice -le ${#AVAILABLE_OPTIONS[@]} ]]; then
        selected_option=${AVAILABLE_OPTIONS[$((choice-1))]}
        
        case $selected_option in
            "suspend_only") configure_suspend_only ;;
            "hibernate_only") configure_hibernate_only ;;
            "mixed_mode") configure_mixed_mode ;;
            "smart_mode") configure_smart_mode ;;
            "hybrid_mode") configure_hybrid_mode ;;
            "gdm_only") configure_gdm_only ;;
            "fix_mkinitcpio") fix_mkinitcpio_manual ;;
            "check_config") check_current_config ;;
        esac
        
        # Aplicar configurações (sem reiniciar serviços)
        if [[ "$selected_option" != "check_config" && "$selected_option" != "fix_mkinitcpio" ]]; then
            apply_configurations
        fi
    else
        error "Opção inválida!"
        exit 1
    fi
}

# Executar
trap 'echo -e "\n${YELLOW}[AVISO] Script interrompido.${NC}"; exit 1' INT
main "$@"
