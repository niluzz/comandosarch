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
    else
        echo -e "  ❌ ${RED}systemd-boot NÃO detectado${NC}"
    fi
    
    # 7. Verificar zswap
    if [[ -d /sys/module/zswap ]]; then
        local zswap_status=$(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo "N/A")
        echo -e "  🔄 ${CYAN}Zswap: $zswap_status${NC}"
    fi
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
    
    echo "$option_number. 🛠️  Configuração MANUAL Avançada"
    AVAILABLE_OPTIONS+=("manual_mode")
    ((option_number++))
    
    echo "$option_number. 🧪 Verificar configuração atual"
    AVAILABLE_OPTIONS+=("check_config")
    
    echo ""
    echo "0. ❌ Sair"
    echo ""
}

# CONFIGURAÇÃO PARA SUSPENSÃO APENAS
configure_suspend_only() {
    step "Configurando modo SUSPENSÃO APENAS..."
    
    # Kernel parameters
    if [[ -f /etc/kernel/cmdline ]]; then
        local current_cmdline=$(cat /etc/kernel/cmdline)
        local clean_cmdline=$(echo "$current_cmdline" | sed -E 's/resume=[^ ]*//g')
        
        # Adicionar parâmetros para GPU se necessário
        if [[ "$GPU_DRIVER" == "amdgpu" ]]; then
            clean_cmdline="$clean_cmdline amdgpu.runpm=0"
        fi
        
        echo "$clean_cmdline" > /etc/kernel/cmdline
        info "Parâmetros do kernel configurados para suspensão"
    fi
    
    # Mkinitcpio (manter resume para segurança)
    if grep -q "HOOKS=.*resume" /etc/mkinitcpio.conf; then
        info "Hooks do mkinitcpio já incluem resume"
    else
        warn "Adicionando hook resume para compatibilidade..."
        sed -i 's/^HOOKS=.*/& resume/' /etc/mkinitcpio.conf
    fi
    
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
    
    # Kernel parameters
    if [[ -f /etc/kernel/cmdline && -n "$SWAP_UUID" ]]; then
        local current_cmdline=$(cat /etc/kernel/cmdline)
        local clean_cmdline=$(echo "$current_cmdline" | sed -E 's/resume=[^ ]*//g')
        local new_cmdline="$clean_cmdline resume=UUID=$SWAP_UUID"
        
        echo "$new_cmdline" > /etc/kernel/cmdline
        info "Parâmetros do kernel configurados para hibernação"
    fi
    
    # Mkinitcpio
    if ! grep -q "HOOKS=.*resume" /etc/mkinitcpio.conf; then
        warn "Adicionando hook resume..."
        sed -i 's/^HOOKS=.*/& resume/' /etc/mkinitcpio.conf
    fi
    
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
    
    # Kernel parameters
    if [[ -f /etc/kernel/cmdline && -n "$SWAP_UUID" ]]; then
        local current_cmdline=$(cat /etc/kernel/cmdline)
        local clean_cmdline=$(echo "$current_cmdline" | sed -E 's/resume=[^ ]*//g')
        local new_cmdline="$clean_cmdline resume=UUID=$SWAP_UUID"
        
        if [[ "$GPU_DRIVER" == "amdgpu" ]]; then
            new_cmdline="$new_cmdline amdgpu.runpm=0"
        fi
        
        echo "$new_cmdline" > /etc/kernel/cmdline
        info "Parâmetros do kernel configurados"
    fi
    
    # Mkinitcpio
    if ! grep -q "HOOKS=.*resume" /etc/mkinitcpio.conf; then
        warn "Adicionando hook resume..."
        sed -i 's/^HOOKS=.*/& resume/' /etc/mkinitcpio.conf
    fi
    
    # Systemd com script personalizado
    cat > /usr/local/bin/smart-suspend-hibernate.sh << 'EOF'
#!/bin/bash
# Script inteligente: suspende primeiro, depois hiberna
logger "Modo Misto: Suspender → Hibernar após 30min"
systemctl suspend
sleep 30m
systemctl hibernate
EOF

    chmod +x /usr/local/bin/smart-suspend-hibernate.sh

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
    
    # Kernel parameters
    if [[ -f /etc/kernel/cmdline && -n "$SWAP_UUID" ]]; then
        local current_cmdline=$(cat /etc/kernel/cmdline)
        local clean_cmdline=$(echo "$current_cmdline" | sed -E 's/resume=[^ ]*//g')
        local new_cmdline="$clean_cmdline resume=UUID=$SWAP_UUID zswap.enabled=0"
        
        if [[ "$GPU_DRIVER" == "amdgpu" ]]; then
            new_cmdline="$new_cmdline amdgpu.runpm=0"
        fi
        
        echo "$new_cmdline" > /etc/kernel/cmdline
        info "Parâmetros do kernel configurados"
    fi
    
    # Mkinitcpio
    if ! grep -q "HOOKS=.*resume" /etc/mkinitcpio.conf; then
        warn "Adicionando hook resume..."
        sed -i 's/^HOOKS=.*/& resume/' /etc/mkinitcpio.conf
    fi
    
    # Systemd inteligente
    cat > /etc/systemd/logind.conf << 'EOF'
[Login]
# Modo INTELIGENTE
HandlePowerKey=poweroff
HandleSuspendKey=suspend
HandleHibernateKey=hibernate
HandleLidSwitch=suspend-then-hibernate
HandleLidSwitchExternalPower=suspend
IdleAction=ignore
HoldoffTimeoutSec=5s
PowerKeyIgnoreInhibited=yes
SuspendKeyIgnoreInhibited=yes
HibernateKeyIgnoreInhibited=yes
LidSwitchIgnoreInhibited=yes
EOF

    cat > /etc/systemd/sleep.conf << 'EOF'
[Sleep]
# Modo INTELIGENTE
AllowSuspend=yes
AllowHibernation=yes
AllowHybridSleep=no
AllowSuspendThenHibernate=yes
SuspendState=freeze
#SuspendThenHibernateDelaySec=20min
HibernateDelaySec=50m
HibernateOnACPower=no
EOF

    success "Modo INTELIGENTE configurado!"
}

# VERIFICAR CONFIGURAÇÃO ATUAL
check_current_config() {
    step "Verificando configuração atual..."
    
    echo -e "\n${CYAN}=== CONFIGURAÇÃO ATUAL ===${NC}"
    
    # Kernel parameters
    if [[ -f /etc/kernel/cmdline ]]; then
        echo -e "\n${BLUE}Kernel Parameters:${NC}"
        cat /etc/kernel/cmdline
    fi
    
    # Mkinitcpio hooks
    echo -e "\n${BLUE}Mkinitcpio Hooks:${NC}"
    grep "^HOOKS=" /etc/mkinitcpio.conf
    
    # Systemd logind
    echo -e "\n${BLUE}Systemd Logind:${NC}"
    grep -v "^#" /etc/systemd/logind.conf | grep -v "^$" | head -10
    
    # Systemd sleep
    echo -e "\n${BLUE}Systemd Sleep:${NC}"
    grep -v "^#" /etc/systemd/sleep.conf 2>/dev/null | grep -v "^$" || echo "Arquivo não configurado"
    
    # Swap
    echo -e "\n${BLUE}Swap:${NC}"
    swapon --show 2>/dev/null || echo "Nenhum swap ativo"
}

# APLICAR CONFIGURAÇÕES
apply_configurations() {
    step "Aplicando configurações..."
    
    # Regenerar initramfs se mkinitcpio foi modificado
    if [[ -f /etc/mkinitcpio.conf ]]; then
        info "Regenerando initramfs..."
        mkinitcpio -P
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
            "manual_mode") configure_manual_mode ;;
            "check_config") check_current_config ;;
        esac
        
        # Aplicar configurações (sem reiniciar serviços)
        if [[ "$selected_option" != "check_config" ]]; then
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
