#!/bin/bash

# Script de Configuração de Hibernação para Arch Linux
# Correção do bug do [INFO] no cmdline

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funções de logging
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error() { echo -e "${RED}[ERRO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCESSO]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script precisa ser executado como root!"
        exit 1
    fi
}

verify_kernel_support() {
    info "Verificando suporte do kernel à hibernação..."
    if grep -q "disk" /sys/power/state; then
        success "Kernel suporta hibernação."
    else
        error "Kernel não suporta hibernação!"
        exit 1
    fi
}

verify_systemd_boot() {
    info "Verificando systemd-boot..."
    if [[ -f /etc/kernel/cmdline ]]; then
        success "Systemd-boot detectado."
    else
        error "Arquivo /etc/kernel/cmdline não encontrado!"
        exit 1
    fi
}

configure_mkinitcpio() {
    info "Configurando mkinitcpio para hibernação..."
    
    local mkinitcpio_file="/etc/mkinitcpio.conf"
    local backup_file="${mkinitcpio_file}.backup.$(date +%Y%m%d-%H%M%S)"
    
    cp "$mkinitcpio_file" "$backup_file"
    info "Backup criado: $backup_file"
    
    # Obter hooks atuais
    local current_hooks=$(grep "^HOOKS=" "$mkinitcpio_file" | cut -d= -f2 | tr -d '()"')
    
    # Adicionar systemd se não existir
    if ! echo "$current_hooks" | grep -q "systemd"; then
        warn "Adicionando hook 'systemd'"
        current_hooks=$(echo "$current_hooks" | sed 's/udev/systemd/')
        if ! echo "$current_hooks" | grep -q "systemd"; then
            current_hooks="systemd $current_hooks"
        fi
    fi
    
    # Adicionar resume se não existir
    if ! echo "$current_hooks" | grep -q "resume"; then
        warn "Adicionando hook 'resume'"
        current_hooks=$(echo "$current_hooks" | sed 's/systemd/& resume/')
    fi
    
    # Limpar espaços extras
    current_hooks=$(echo "$current_hooks" | sed 's/  / /g')
    
    # Atualizar arquivo
    sed -i "s|^HOOKS=.*|HOOKS=(${current_hooks})|" "$mkinitcpio_file"
    
    # Adicionar suporte Btrfs se necessário
    if findmnt -n -o FSTYPE / | grep -q "btrfs"; then
        info "Adicionando suporte Btrfs aos módulos..."
        local current_modules=$(grep "^MODULES=" "$mkinitcpio_file" | cut -d= -f2 | tr -d '()"')
        if ! echo "$current_modules" | grep -q "btrfs"; then
            if [[ -z "$current_modules" ]]; then
                sed -i "s|^MODULES=.*|MODULES=(btrfs)|" "$mkinitcpio_file"
            else
                sed -i "s|^MODULES=.*|MODULES=(${current_modules} btrfs)|" "$mkinitcpio_file"
            fi
        fi
    fi
    
    # Regenerar initramfs
    info "Regenerando initramfs..."
    if mkinitcpio -P; then
        success "mkinitcpio configurado com sucesso!"
    else
        error "Falha ao regenerar initramfs!"
        exit 1
    fi
}

create_btrfs_swapfile() {
    info "Criando swapfile no Btrfs para hibernação..."
    
    local swapfile_path="/swapfile"
    local mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_total_gb=$(( (mem_total_kb + 1024*1024 - 1) / (1024*1024) ))
    local swap_size_gb=$((mem_total_gb + 2))
    [[ $swap_size_gb -lt 8 ]] && swap_size_gb=8
    [[ $swap_size_gb -gt 32 ]] && swap_size_gb=32
    
    info "Memória RAM: ${mem_total_gb}GB"
    info "Tamanho do swapfile: ${swap_size_gb}GB"
    
    # Remover swapfile existente se necessário
    if [[ -f "$swapfile_path" ]]; then
        warn "Swapfile existente encontrado. Removendo..."
        swapoff "$swapfile_path" 2>/dev/null || true
        rm -f "$swapfile_path"
        sleep 2
    fi
    
    # Criar swapfile corretamente
    info "Criando swapfile de ${swap_size_gb}GB..."
    truncate -s 0 "$swapfile_path"
    chattr +C "$swapfile_path"
    chmod 600 "$swapfile_path"
    
    info "Alocando espaço fisicamente (pode demorar)..."
    dd if=/dev/zero of="$swapfile_path" bs=1M count=$((swap_size_gb * 1024)) status=progress 2>/dev/null
    
    info "Formatando swapfile..."
    mkswap -f "$swapfile_path"
    
    info "Ativando swapfile..."
    swapon "$swapfile_path"
    
    if ! grep -q "$swapfile_path" /etc/fstab; then
        echo "$swapfile_path none swap defaults 0 0" >> /etc/fstab
        success "Swapfile adicionado ao fstab."
    fi
    
    success "Swapfile de ${swap_size_gb}GB criado e ativado com sucesso!"
}

# CORREÇÃO: Função silenciosa para obter offset (sem output)
get_swapfile_offset() {
    local swapfile_path="/swapfile"
    
    if [[ ! -f "$swapfile_path" ]]; then
        return 1
    fi
    
    # Método preferencial (silencioso)
    if command -v btrfs-inspect-internal &> /dev/null; then
        btrfs-inspect-internal map-swapfile -r "$swapfile_path" 2>/dev/null && return
    fi
    
    # Método alternativo (silencioso)
    if command -v filefrag &> /dev/null; then
        filefrag -v "$swapfile_path" 2>/dev/null | grep "0:" | awk '{print $4}' | sed 's/\.\.//' | head -1
    fi
}

# CORREÇÃO PRINCIPAL: Função sem output misturado
configure_kernel_parameters() {
    info "Configurando parâmetros do kernel para hibernação..."
    
    local cmdline_file="/etc/kernel/cmdline"
    local backup_file="${cmdline_file}.backup.$(date +%Y%m%d-%H%M%S)"
    
    # Backup
    cp "$cmdline_file" "$backup_file"
    info "Backup criado: $backup_file"
    
    # Obter UUID da partição raiz
    local root_uuid=$(findmnt -n -o UUID /)
    if [[ -z "$root_uuid" ]]; then
        error "Não foi possível obter UUID da partição raiz!"
        exit 1
    fi
    
    info "UUID da partição raiz: $root_uuid"
    
    # CORREÇÃO: Obter offset SILENCIOSAMENTE
    info "Calculando offset do swapfile no Btrfs..."
    local resume_offset=$(get_swapfile_offset)
    
    if [[ -n "$resume_offset" ]]; then
        info "Offset do swapfile: $resume_offset"
    else
        warn "Não foi possível determinar o offset do swapfile."
        warn "A hibernação funcionará, mas pode ser menos confiável."
    fi
    
    # Construir parâmetro resume
    local resume_param="resume=UUID=${root_uuid}"
    if [[ -n "$resume_offset" ]]; then
        resume_param="${resume_param} resume_offset=${resume_offset}"
    fi
    
    # Ler configuração atual
    local current_cmdline=$(cat "$cmdline_file")
    info "Linha de comando atual: $current_cmdline"
    
    # Remover parâmetros resume existentes
    local new_cmdline=$(echo "$current_cmdline" | sed -E 's/resume=[^ ]*//g')
    new_cmdline="${new_cmdline} ${resume_param}"
    
    # Limpar espaços extras
    new_cmdline=$(echo "$new_cmdline" | sed 's/  / /g' | sed 's/^ //' | sed 's/ $//')
    
    # CORREÇÃO: Escrever SILENCIOSAMENTE no arquivo
    echo "$new_cmdline" > "$cmdline_file"
    
    # Verificar se foi escrito corretamente
    if grep -q "resume=" "$cmdline_file"; then
        success "Parâmetros escritos no cmdline."
    else
        error "Falha ao escrever parâmetros no cmdline!"
        exit 1
    fi
    
    # Atualizar bootloader (com tratamento de erro)
    info "Atualizando bootloader..."
    if bootctl update 2>/dev/null; then
        success "Bootloader atualizado!"
    else
        warn "Bootctl retornou erro, mas a configuração foi aplicada."
        warn "Isso é normal se o bootloader já estiver atualizado."
    fi
    
    info "Nova linha de comando aplicada:"
    cat "$cmdline_file"
}

configure_systemd() {
    info "Configurando systemd para hibernação..."
    
    if [[ -f /etc/systemd/logind.conf ]]; then
        # Fazer backup
        cp /etc/systemd/logind.conf /etc/systemd/logind.conf.backup.$(date +%Y%m%d)
        
        # Configurar ações de energia
        sed -i 's/^#*HandleLidSwitch=.*/HandleLidSwitch=hibernate/' /etc/systemd/logind.conf
        sed -i 's/^#*HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=hibernate/' /etc/systemd/logind.conf
        
        # Recarregar systemd
        systemctl restart systemd-logind
    fi
    
    # Habilitar serviço de hibernação
    systemctl enable systemd-hibernate.service 2>/dev/null || true
    success "Systemd configurado para hibernação!"
}

configure_gnome() {
    info "Configurando GNOME para mostrar opção de hibernação..."
    
    local user=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
    local user_id=$(id -u "$user" 2>/dev/null)
    
    if [[ -n "$user_id" ]] && command -v gsettings &> /dev/null && [[ -S "/run/user/${user_id}/bus" ]]; then
        sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_id}/bus" \
            gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'interactive' 2>/dev/null || true
        
        sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${user_id}/bus" \
            gsettings set org.gnome.settings-daemon.plugins.power hibernate-button-action 'hibernate' 2>/dev/null || true
        success "GNOME configurado!"
    else
        warn "GNOME não detectado ou sessão não disponível."
    fi
}

final_verification() {
    info "=== VERIFICAÇÃO FINAL ==="
    
    echo
    info "1. Suporte do kernel: $(grep -q disk /sys/power/state && echo '✅ OK' || echo '❌ FALHA')"
    info "2. Swap ativo: $(swapon --show | grep -q swapfile && echo '✅ OK' || echo '❌ FALHA')"
    info "3. Parâmetros no cmdline: $(grep -q resume /etc/kernel/cmdline && echo '✅ OK' || echo '❌ FALHA')"
    
    echo
    info "Swap ativo:"
    swapon --show
    
    echo
    info "Parâmetros do kernel:"
    cat /etc/kernel/cmdline
    
    echo
    warn "REINICIE O SISTEMA para aplicar as configurações: reboot"
    echo
}

main() {
    echo "=================================================="
    echo "  CONFIGURADOR DE HIBERNAÇÃO - ARCH LINUX"
    echo "  (Bug do [INFO] no cmdline CORRIGIDO)"
    echo "=================================================="
    echo
    
    check_root
    verify_kernel_support
    verify_systemd_boot
    
    info ">>> Passo 1/6: Configurando mkinitcpio"
    configure_mkinitcpio
    
    info ">>> Passo 2/6: Criando swapfile no Btrfs"
    create_btrfs_swapfile
    
    info ">>> Passo 3/6: Configurando parâmetros do kernel"
    configure_kernel_parameters
    
    info ">>> Passo 4/6: Configurando systemd"
    configure_systemd
    
    info ">>> Passo 5/6: Configurando GNOME"
    configure_gnome
    
    info ">>> Passo 6/6: Verificação final"
    final_verification
    
    echo
    success "CONFIGURAÇÃO DE HIBERNAÇÃO CONCLUÍDA!"
    echo
    info "PRÓXIMOS PASSOS:"
    info "1. REINICIE: reboot"
    info "2. Verifique: cat /proc/cmdline | grep resume"
    info "3. Teste: systemctl hibernate"
    echo
    warn "Execute o teste de hibernação apenas após reiniciar!"
    echo
}

# Tratamento de interrupção
trap 'echo -e "\n${YELLOW}[AVISO] Script interrompido pelo usuário${NC}"; exit 1' INT

# Executar
main "$@"