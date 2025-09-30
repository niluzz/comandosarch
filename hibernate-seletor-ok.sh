#!/bin/bash

# Script 1: CONFIGURAÇÃO COMPLETA DA HIBERNAÇÃO (COM MENU INTERATIVO E TESTES)
# Execute este PRIMEIRO, depois REINICIE manualmente

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Variáveis globais
SELECTED_OPTIONS=()

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
    echo "        COM MENU INTERATIVO E TESTES"
    echo "=================================================="
    echo -e "${NC}"
}

show_menu() {
    echo -e "\n${CYAN}=== MENU DE CONFIGURAÇÃO DE HIBERNAÇÃO ===${NC}"
    echo ""
    echo "1.  ✅ Verificar sistema"
    echo "2.  ⚙️  Configurar mkinitcpio"
    echo "3.  💾 Criar PARTIÇÃO SWAP"
    echo "4.  🐧 Configurar parâmetros do kernel"
    echo "5.  🔋 Configurar systemd logind (otimizado)"
    echo "6.  ⏰ Configurar systemd sleep"
    echo "7.  🖥️  Configurar GNOME (se aplicável)"
    echo "8.  🔄 Executar TODAS as configurações acima"
    echo "9.  🔍 TESTAR configurações aplicadas"
    echo "0.  ❌ Sair"
    echo ""
}

get_user_choice() {
    local choice
    read -p "Selecione uma opção (0-9): " choice
    echo "$choice"
}

verify_system() {
    step "Verificando sistema..."
    
    if ! grep -q "disk" /sys/power/state; then
        error "Kernel não suporta hibernação!"
        return 1
    fi
    success "Kernel suporta hibernação."
    
    if [[ ! -f /etc/kernel/cmdline ]]; then
        error "systemd-boot não encontrado!"
        return 1
    fi
    success "Systemd-boot detectado."
    
    if findmnt -n -o FSTYPE / | grep -q "btrfs"; then
        success "Btrfs detectado."
    else
        warn "Sistema de arquivos não é Btrfs."
    fi
    
    return 0
}

configure_mkinitcpio() {
    step "Configurando mkinitcpio..."
    
    local mkinitcpio_file="/etc/mkinitcpio.conf"
    local backup_file="${mkinitcpio_file}.backup.$(date +%Y%m%d-%H%M%S)"
    
    if [[ ! -f "$mkinitcpio_file" ]]; then
        error "Arquivo mkinitcpio.conf não encontrado!"
        return 1
    fi
    
    cp "$mkinitcpio_file" "$backup_file"
    info "Backup criado: $backup_file"
    
    local current_hooks=$(grep "^HOOKS=" "$mkinitcpio_file" | cut -d= -f2 | tr -d '()"')
    local hooks_modified=false
    
    # Verificar e adicionar systemd se necessário
    if ! echo "$current_hooks" | grep -q "systemd"; then
        warn "Adicionando hook 'systemd'..."
        # Substituir udev por systemd se existir, ou adicionar no início
        if echo "$current_hooks" | grep -q "udev"; then
            current_hooks=$(echo "$current_hooks" | sed 's/udev/systemd/')
        else
            current_hooks="systemd $current_hooks"
        fi
        hooks_modified=true
    fi
    
    # Verificar e adicionar resume se necessário
    if ! echo "$current_hooks" | grep -q "resume"; then
        warn "Adicionando hook 'resume'..."
        # Adicionar resume após systemd
        if echo "$current_hooks" | grep -q "systemd"; then
            current_hooks=$(echo "$current_hooks" | sed 's/systemd/& resume/')
        else
            current_hooks="$current_hooks resume"
        fi
        hooks_modified=true
    fi
    
    if $hooks_modified; then
        current_hooks=$(echo "$current_hooks" | sed 's/  / /g')
        sed -i "s|^HOOKS=.*|HOOKS=(${current_hooks})|" "$mkinitcpio_file"
        success "Hooks atualizados: $current_hooks"
    else
        info "Hooks já estão configurados corretamente."
    fi
    
    # Configurar módulos Btrfs se necessário
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
        return 0
    else
        error "Falha ao regenerar initramfs!"
        return 1
    fi
}

# FUNÇÃO MODIFICADA: Criar partição swap ao invés de swapfile
create_swap_partition() {
    step "Configurando PARTIÇÃO SWAP..."
    
    # Verificar se já existe uma partição swap ativa
    if swapon --show | grep -q "/dev/"; then
        local current_swap=$(swapon --show=name --noheadings | head -1)
        warn "Partição swap já existe: $current_swap"
        read -p "Deseja usar a partição swap existente? (s/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            info "Usando partição swap existente: $current_swap"
            return 0
        else
            info "Você pode criar uma nova partição swap manualmente usando:"
            echo "   fdisk /dev/sdX  (substitua sdX pelo disco desejado)"
            echo "   mkswap /dev/sdXN (substitua sdXN pela partição criada)"
            echo "   swapon /dev/sdXN"
            echo ""
            read -p "Pressione Enter para continuar sem alterar o swap..."
            return 1
        fi
    fi
    
    # Mostrar discos disponíveis
    echo -e "\n${CYAN}=== DISCOS DISPONÍVEIS ===${NC}"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE | grep -v "loop"
    
    echo -e "\n${YELLOW}INSTRUÇÕES PARA CRIAR PARTIÇÃO SWAP:${NC}"
    echo "1. Escolha um disco (ex: /dev/sda, /dev/nvme0n1)"
    echo "2. Execute: fdisk /dev/sdX"
    echo "3. Digite 'n' para nova partição"
    echo "4. Escolha o tipo 'Linux swap' (código 82)"
    echo "5. Defina o tamanho (recomendado: RAM + 2GB)"
    echo "6. Execute: mkswap /dev/sdXN"
    echo "7. Execute: swapon /dev/sdXN"
    echo "8. Adicione ao /etc/fstab: /dev/sdXN none swap defaults 0 0"
    echo ""
    
    read -p "Digite o dispositivo da partição swap (ex: /dev/sda2) ou Enter para pular: " swap_device
    
    if [[ -n "$swap_device" && -b "$swap_device" ]]; then
        # Formatar como swap se necessário
        if ! blkid "$swap_device" | grep -q "swap"; then
            warn "Formatando $swap_device como swap..."
            mkswap "$swap_device"
        fi
        
        # Ativar swap
        warn "Ativando swap $swap_device..."
        swapon "$swap_device"
        
        # Adicionar ao fstab (remover entradas duplicadas primeiro)
        sed -i '\|'"$swap_device"'|d' /etc/fstab
        echo "$swap_device none swap defaults 0 0" >> /etc/fstab
        
        success "Partição swap configurada: $swap_device"
        return 0
    else
        warn "Nenhuma partição swap válida fornecida."
        warn "Você precisará criar uma partição swap manualmente para usar hibernação."
        return 1
    fi
}

# FUNÇÃO AUXILIAR: Obter UUID da partição swap ativa
get_swap_uuid() {
    local swap_device=$(swapon --show=name --noheadings | head -1)
    if [[ -n "$swap_device" ]]; then
        blkid -s UUID -o value "$swap_device"
    else
        return 1
    fi
}

# FUNÇÃO MELHORADA: Configurar kernel para usar partição swap
configure_kernel() {
    step "Configurando parâmetros do kernel..."
    
    local cmdline_file="/etc/kernel/cmdline"
    local backup_file="${cmdline_file}.backup.$(date +%Y%m%d-%H%M%S)"
    
    if [[ ! -f "$cmdline_file" ]]; then
        error "Arquivo cmdline não encontrado!"
        return 1
    fi
    
    cp "$cmdline_file" "$backup_file"
    info "Backup criado: $backup_file"
    
    local swap_uuid=$(get_swap_uuid)
    
    if [[ -z "$swap_uuid" ]]; then
        error "Nenhuma partição swap ativa encontrada!"
        warn "Execute a opção 3 para configurar uma partição swap primeiro."
        return 1
    fi
    
    # Ler cmdline atual
    local current_cmdline=$(cat "$cmdline_file")
    info "Cmdline atual: $current_cmdline"
    
    # Remover parâmetros de hibernação existentes
    local clean_cmdline=$(echo "$current_cmdline" | sed -E 's/resume=[^ ]*//g' | sed -E 's/resume_offset=[^ ]*//g' | sed -E 's/resume_force=[^ ]*//g' | sed -E 's/acpi_sleep=[^ ]*//g' | sed -E 's/mem_sleep_default=[^ ]*//g')
    
    # Construir novos parâmetros (sem resume_offset para partição swap)
    local new_params="resume=UUID=${swap_uuid} resume_force=1 acpi_sleep=nonvs mem_sleep_default=deep"
    
    # Combinar cmdline limpo com novos parâmetros
    local new_cmdline="${clean_cmdline} ${new_params}"
    new_cmdline=$(echo "$new_cmdline" | sed 's/  / /g' | sed 's/^ //' | sed 's/ $//')
    
    echo "$new_cmdline" > "$cmdline_file"
    info "Novo cmdline: $new_cmdline"
    
    if ! grep -q "resume=UUID=${swap_uuid}" "$cmdline_file"; then
        error "Falha ao configurar parâmetros do kernel!"
        return 1
    fi
    
    info "Atualizando bootloader..."
    if bootctl update 2>/dev/null; then
        success "Bootloader atualizado."
    else
        warn "Bootctl retornou aviso (pode ser normal)."
    fi
    
    success "Parâmetros do kernel configurados para partição swap."
    return 0
}

# FUNÇÃO CORRIGIDA: Configurar logind.conf com suas configurações específicas
configure_systemd_logind() {
    step "Configurando /etc/systemd/logind.conf (configurações personalizadas)..."
    
    if [[ ! -f /etc/systemd/logind.conf ]]; then
        warn "Arquivo logind.conf não encontrado. Criando..."
        touch /etc/systemd/logind.conf
    fi
    
    local backup_file="/etc/systemd/logind.conf.backup.$(date +%Y%m%d-%H%M%S)"
    cp /etc/systemd/logind.conf "$backup_file"
    
    info "Aplicando configurações personalizadas..."
    
    # Limpar configurações existentes (apenas as que vamos modificar)
    sed -i '/^#/!{/HandlePowerKey/d;/HandleSuspendKey/d;/HandleHibernateKey/d;/HandleLidSwitch/d;/HandleLidSwitchExternalPower/d;/HandleLidSwitchDocked/d;/PowerKeyIgnoreInhibited/d;/SuspendKeyIgnoreInhibited/d;/HibernateKeyIgnoreInhibited/d;/LidSwitchIgnoreInhibited/d;/HoldoffTimeoutSec/d;/IdleAction/d;/IdleActionSec/d}' /etc/systemd/logind.conf
    
    # Adicionar configurações personalizadas
    cat >> /etc/systemd/logind.conf << 'EOF'

# =============================================================================
# CONFIGURAÇÃO PERSONALIZADA DE HIBERNAÇÃO - Arch Linux
# Configurado automaticamente por script de hibernação
# =============================================================================

# 🔋 AÇÕES DE ENERGIA
HandlePowerKey=poweroff
HandleSuspendKey=suspend
HandleHibernateKey=hibernate
HandleLidSwitch=suspend-then-hibernate

# 🔌 AÇÕES NA TOMADA/DOCK
HandleLidSwitchExternalPower=suspend
HandleLidSwitchDocked=ignore

# ⏰ TEMPOS DE ESPERA
HoldoffTimeoutSec=10s
IdleAction=hibernate
IdleActionSec=30min

# 🔧 COMPORTAMENTO DE INIBIÇÃO
PowerKeyIgnoreInhibited=no
SuspendKeyIgnoreInhibited=no
HibernateKeyIgnoreInhibited=no
LidSwitchIgnoreInhibited=yes
EOF

    success "logind.conf configurado com configurações personalizadas."
    systemctl restart systemd-logind
    systemctl enable systemd-hibernate.service 2>/dev/null || true
    
    return 0
}

# FUNÇÃO CORRIGIDA: Configurar sleep.conf com suas configurações específicas
configure_systemd_sleep() {
    step "Configurando /etc/systemd/sleep.conf (configurações personalizadas)..."
    
    # Obter UUID da partição swap automaticamente
    local swap_uuid=$(get_swap_uuid)
    
    if [[ ! -f /etc/systemd/sleep.conf ]]; then
        warn "Arquivo sleep.conf não encontrado. Criando..."
        touch /etc/systemd/sleep.conf
    fi
    
    local backup_file="/etc/systemd/sleep.conf.backup.$(date +%Y%m%d-%H%M%S)"
    cp /etc/systemd/sleep.conf "$backup_file"
    
    info "Aplicando configurações de sleep personalizadas..."
    
    # Limpar configurações existentes
    sed -i '/^#/!{/AllowSuspend/d;/AllowHibernation/d;/AllowHybridSleep/d;/SuspendState/d;/HybridSleepMode/d;/Resume/d;/HibernateMode/d;/SuspendThenHibernateDelaySec/d}' /etc/systemd/sleep.conf
    
    # Adicionar configurações personalizadas
    cat >> /etc/systemd/sleep.conf << EOF

# =============================================================================
# CONFIGURAÇÃO PERSONALIZADA DE SLEEP/HIBERNAÇÃO - Arch Linux
# Configurado automaticamente por script de hibernação
# =============================================================================

[Sleep]
# 🔋 COMPORTAMENTO DE ENERGIA
AllowSuspend=yes
AllowHibernation=yes
AllowHybridSleep=yes
AllowSuspendThenHibernate=yes

# 💤 ESTADOS DE SUSPENSÃO
SuspendState=mem
HybridSleepMode=suspend

# 💾 DISPOSITIVO DE RESUME (HIBERNAÇÃO) - CONFIGURADO AUTOMATICAMENTE
Resume=UUID=${swap_uuid}
HibernateMode=platform

# ⏰ TEMPO PARA HIBERNAR APÓS SUSPENDER (20 MINUTOS)
SuspendThenHibernateDelaySec=20min
HibernateDelaySec=60min
HibernateOnACPower=no
EOF

    success "sleep.conf configurado com configurações personalizadas:"
    echo -e "  ${CYAN}SuspendThenHibernateDelaySec=20min${NC}"
    echo -e "  ${CYAN}Resume=UUID=${swap_uuid}${NC}"
    echo -e "  ${CYAN}HandleLidSwitch=suspend-then-hibernate${NC}"
    
    return 0
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
        
        sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_id}/bus" \
            gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'hibernate' 2>/dev/null || true
            
        sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_id}/bus" \
            gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
        
        success "GNOME configurado com suporte a suspensão+hibernação."
        return 0
    else
        warn "GNOME não detectado. Pulando..."
        return 1
    fi
}

# FUNÇÃO ATUALIZADA: Testar configurações com partição swap
test_configurations() {
    step "TESTANDO configurações aplicadas..."
    
    echo -e "\n${CYAN}=== VERIFICAÇÃO DE CONFIGURAÇÕES ===${NC}"
    
    local all_ok=true
    
    # Teste 1: Verificar hooks do mkinitcpio
    echo -e "\n${BLUE}1. Verificando mkinitcpio hooks:${NC}"
    if grep -q "HOOKS=.*resume" /etc/mkinitcpio.conf; then
        echo -e "   ✅ ${GREEN}Hook 'resume' encontrado${NC}"
    else
        echo -e "   ❌ ${RED}Hook 'resume' NÃO encontrado${NC}"
        all_ok=false
    fi
    
    if grep -q "HOOKS=.*systemd" /etc/mkinitcpio.conf; then
        echo -e "   ✅ ${GREEN}Hook 'systemd' encontrado${NC}"
    else
        echo -e "   ❌ ${RED}Hook 'systemd' NÃO encontrado${NC}"
        all_ok=false
    fi
    
    # Teste 2: Verificar parâmetros do kernel
    echo -e "\n${BLUE}2. Verificando parâmetros do kernel:${NC}"
    if grep -q "resume=UUID=" /etc/kernel/cmdline; then
        echo -e "   ✅ ${GREEN}Parâmetro 'resume' configurado${NC}"
        local resume_param=$(grep -o "resume=UUID=[^ ]*" /etc/kernel/cmdline)
        echo -e "   📋 ${CYAN}$resume_param${NC}"
    else
        echo -e "   ❌ ${RED}Parâmetro 'resume' NÃO configurado${NC}"
        all_ok=false
    fi
    
    # Verificar se há parâmetros duplicados
    local resume_count=$(grep -o "resume=" /etc/kernel/cmdline | wc -l)
    if [[ $resume_count -gt 1 ]]; then
        echo -e "   ⚠️  ${YELLOW}AVISO: Parâmetros 'resume' duplicados encontrados${NC}"
        all_ok=false
    fi
    
    # Teste 3: Verificar partição swap
    echo -e "\n${BLUE}3. Verificando partição swap:${NC}"
    local swap_device=$(swapon --show=name --noheadings | head -1)
    if [[ -n "$swap_device" ]]; then
        echo -e "   ✅ ${GREEN}Partição swap encontrada: $swap_device${NC}"
        local swap_size=$(swapon --show=size --noheadings | head -1)
        echo -e "   📊 Tamanho: ${CYAN}$swap_size${NC}"
        
        # Verificar se é partição (não swapfile)
        if [[ $swap_device == /dev/* ]]; then
            echo -e "   ✅ ${GREEN}É uma partição swap (recomendado)${NC}"
        else
            echo -e "   ⚠️  ${YELLOW}É um swapfile (menos confiável para hibernação)${NC}"
        fi
    else
        echo -e "   ❌ ${RED}Nenhuma partição swap ativa encontrada${NC}"
        all_ok=false
    fi
    
    # Teste 4: Verificar logind.conf
    echo -e "\n${BLUE}4. Verificando logind.conf:${NC}"
    if grep -q "HandleLidSwitch=suspend-then-hibernate" /etc/systemd/logind.conf; then
        echo -e "   ✅ ${GREEN}Configuração lid switch encontrada${NC}"
    else
        echo -e "   ❌ ${RED}Configuração lid switch NÃO encontrada${NC}"
        all_ok=false
    fi
    
    # Teste 5: Verificar sleep.conf
    echo -e "\n${BLUE}5. Verificando sleep.conf:${NC}"
    if grep -q "SuspendThenHibernateDelaySec=20min" /etc/systemd/sleep.conf; then
        echo -e "   ✅ ${GREEN}SuspendThenHibernate configurado${NC}"
    else
        echo -e "   ❌ ${RED}SuspendThenHibernate NÃO configurado${NC}"
        all_ok=false
    fi
    
    local swap_uuid=$(get_swap_uuid)
    if grep -q "Resume=UUID=${swap_uuid}" /etc/systemd/sleep.conf; then
        echo -e "   ✅ ${GREEN}Resume UUID configurado corretamente no sleep.conf${NC}"
    else
        echo -e "   ❌ ${RED}Resume UUID NÃO configurado corretamente no sleep.conf${NC}"
        all_ok=false
    fi
    
    # Teste 6: Verificar suporte do kernel
    echo -e "\n${BLUE}6. Verificando suporte do kernel:${NC}"
    if grep -q "disk" /sys/power/state; then
        echo -e "   ✅ ${GREEN}Kernel suporta hibernação${NC}"
    else
        echo -e "   ❌ ${RED}Kernel NÃO suporta hibernação${NC}"
        all_ok=false
    fi
    
    # Resumo final
    echo -e "\n${CYAN}=== RESUMO DOS TESTES ===${NC}"
    if $all_ok; then
        echo -e "✅ ${GREEN}Todas as configurações básicas estão OK!${NC}"
        echo -e "✅ ${GREEN}Partição swap configurada - hibernação mais confiável${NC}"
    else
        echo -e "⚠️  ${YELLOW}Algumas configurações precisam de atenção${NC}"
    fi
    
    echo -e "\n${YELLOW}=== PRÓXIMOS PASSOS ===${NC}"
    echo "1. Reinicie o sistema: reboot"
    echo "2. Após reiniciar, teste a hibernação: systemctl hibernate"
    echo "3. Para suspensão+hibernação automática: feche a tampa e aguarde 20min"
}

execute_option() {
    local option=$1
    local option_name=""
    
    case $option in
        1) option_name="Verificar sistema"; verify_system ;;
        2) option_name="Configurar mkinitcpio"; configure_mkinitcpio ;;
        3) option_name="Criar PARTIÇÃO SWAP"; create_swap_partition ;;
        4) option_name="Configurar kernel"; configure_kernel ;;
        5) option_name="Configurar logind"; configure_systemd_logind ;;
        6) option_name="Configurar sleep"; configure_systemd_sleep ;;
        7) option_name="Configurar GNOME"; configure_gnome ;;
        8) option_name="TODAS as configurações"; execute_all_configurations ;;
        9) option_name="TESTAR configurações"; test_configurations ;;
        *) return 1 ;;
    esac
    
    if [[ $? -eq 0 ]]; then
        SELECTED_OPTIONS+=("✅ $option_name")
        return 0
    else
        SELECTED_OPTIONS+=("❌ $option_name")
        return 1
    fi
}

execute_all_configurations() {
    local functions=("verify_system" "configure_mkinitcpio" "create_swap_partition" 
                    "configure_kernel" "configure_systemd_logind" "configure_systemd_sleep" "configure_gnome")
    
    for func in "${functions[@]}"; do
        step "Executando: $func"
        if $func; then
            success "$func concluído com sucesso"
        else
            error "$func falhou"
            warn "Continuando com as próximas configurações..."
        fi
        echo
    done
}

show_final_instructions() {
    echo -e "\n${GREEN}"
    echo "#############################################"
    echo "#         CONFIGURAÇÃO CONCLUÍDA!          #"
    echo "#############################################"
    echo -e "${NC}"
    
    echo -e "\n${CYAN}=== OPÇÕES EXECUTADAS ===${NC}"
    for option in "${SELECTED_OPTIONS[@]}"; do
        echo "  $option"
    done
    
    local swap_device=$(swapon --show=name --noheadings | head -1)
    local swap_uuid=$(get_swap_uuid)
    
    echo -e "\n${CYAN}=== CONFIGURAÇÃO SWAP ===${NC}"
    if [[ -n "$swap_device" ]]; then
        echo "✅ Partição swap: $swap_device"
        echo "✅ UUID: $swap_uuid"
    else
        echo "❌ Nenhuma partição swap configurada"
    fi
    
    echo -e "\n${CYAN}=== FUNCIONALIDADES CONFIGURADAS ===${NC}"
    echo "✅ SuspendThenHibernateDelaySec=20min"
    echo "   - Suspende primeiro, hiberna após 20min"
    echo "✅ HandleLidSwitch=suspend-then-hibernate"
    echo "   - Fechar tampa: suspende → hiberna em 20min"
    echo "✅ HandleLidSwitchExternalPower=suspend"
    echo "   - Na tomada: apenas suspende"
    echo "✅ Resume=UUID configurado automaticamente"
    
    echo -e "\n${YELLOW}=== ⚠️  IMPORTANTE ===${NC}"
    echo "Para que todas as configurações entrem em vigor,"
    echo "você DEVE reiniciar o sistema manualmente."
    echo ""
    echo "Comando para reiniciar: reboot"
    echo ""
    echo "Após reiniciar:"
    echo "- Use a opção 9 para testar as configurações"
    echo "- Execute: systemctl hibernate para testar hibernação"
    echo "- Feche a tampa e aguarde 20min para testar suspensão+hibernação"
    echo ""
    echo "O sistema NÃO reiniciará automaticamente."
    echo "Reinicie manualmente quando for conveniente."
}

main() {
    check_root
    show_header
    
    while true; do
        show_menu
        choice=$(get_user_choice)
        
        case $choice in
            1|2|3|4|5|6|7|9)
                execute_option "$choice"
                echo
                read -p "Pressione Enter para continuar..."
                ;;
            8)
                warn "Executando TODAS as configurações..."
                execute_option "$choice"
                show_final_instructions
                break
                ;;
            0)
                info "Saindo do script."
                exit 0
                ;;
            *)
                error "Opção inválida! Tente novamente."
                ;;
        esac
    done
}

trap 'echo -e "\n${YELLOW}[AVISO] Script interrompido.${NC}"; exit 1' INT
main "$@"