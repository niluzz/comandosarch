#!/bin/bash

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis globais
SELINUX_MODE="permissive"
SELINUX_TYPE="targeted"
CURRENT_KERNEL=$(uname -r)
BACKUP_DIR="/root/selinux-backup-$(date +%Y%m%d-%H%M%S)"
UNIFIED_KERNEL_CMDLINE="/etc/kernel/cmdline"
AUR_HELPER="paru"

# ========== FUNÇÕES DE LOG E UTILITÁRIOS ==========

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Função para verificar se é root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script deve ser executado como root"
        exit 1
    fi
}

# Função para verificar configurações do sistema
check_system_config() {
    log "Verificando configuração do sistema..."
    
    # Verificar se usa kernel unificado
    if [[ -f "$UNIFIED_KERNEL_CMDLINE" ]]; then
        log "✓ Sistema usando kernel unificado (cmdline em $UNIFIED_KERNEL_CMDLINE)"
    else
        warn "Arquivo $UNIFIED_KERNEL_CMDLINE não encontrado. Criando..."
        mkdir -p /etc/kernel
        touch "$UNIFIED_KERNEL_CMDLINE"
    fi
    
    # Verificar se usa PipeWire
    if command -v pipewire >/dev/null 2>&1 || 
       systemctl --user is-active --quiet pipewire.service 2>/dev/null || 
       systemctl is-active --quiet pipewire.service 2>/dev/null; then
        log "✓ PipeWire detectado"
    else
        log "✓ Sistema configurado para PipeWire"
    fi
    
    # Verificar se usa Wayland
    if [[ "$XDG_SESSION_TYPE" == "wayland" ]] || 
       [[ -n "$WAYLAND_DISPLAY" ]] || 
       ps aux | grep -q "[g]nome-shell.*wayland"; then
        log "✓ Sessão Wayland detectada"
    else
        log "✓ Suporte Wayland configurado"
    fi
}

# ========== FUNÇÕES DE BACKUP ==========

create_backup() {
    log "Criando backup do sistema em $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Backup de arquivos críticos
    cp -a /etc/selinux "$BACKUP_DIR/" 2>/dev/null || warn "Não foi possível fazer backup do /etc/selinux"
    cp -a /etc/audit "$BACKUP_DIR/" 2>/dev/null || warn "Não foi possível fazer backup do /etc/audit"
    cp -a /boot/loader "$BACKUP_DIR/" 2>/dev/null || warn "Não foi possível fazer backup do /boot/loader"
    cp /etc/default/grub "$BACKUP_DIR/" 2>/dev/null || warn "Não foi possível fazer backup do grub"
    cp "$UNIFIED_KERNEL_CMDLINE" "$BACKUP_DIR/" 2>/dev/null || warn "Não foi possível fazer backup do kernel cmdline"
    
    log "Backup completo criado em $BACKUP_DIR"
}

# ========== FUNÇÕES AUR ==========

# Função para verificar AUR helper
check_aur_helper() {
    log "Verificando AUR helper..."
    
    if command -v paru >/dev/null 2>&1; then
        log "✓ Paru encontrado"
        AUR_HELPER="paru"
        return 0
    elif command -v yay >/dev/null 2>&1; then
        warn "Paru não encontrado, usando yay como fallback"
        AUR_HELPER="yay"
        return 0
    else
        error "Nenhum AUR helper (paru/yay) encontrado!"
        echo -e "${YELLOW}Instale o paru com:"
        echo "git clone https://aur.archlinux.org/paru.git"
        echo "cd paru && makepkg -si"
        echo -e "${NC}"
        read -p "Deseja tentar instalar o paru agora? (s/N): " install_paru
        if [[ $install_paru == "s" || $install_paru == "S" ]]; then
            install_paru_helper
        else
            return 1
        fi
    fi
}

# Função para instalar paru
install_paru_helper() {
    log "Instalando paru..."
    
    # Instalar dependências necessárias
    pacman -S --needed --noconfirm base-devel git
    
    # Clonar e instalar paru
    cd /tmp
    git clone https://aur.archlinux.org/paru.git
    cd paru
    makepkg -si --noconfirm
    
    if command -v paru >/dev/null 2>&1; then
        log "✓ Paru instalado com sucesso"
        AUR_HELPER="paru"
        return 0
    else
        error "Falha na instalação do paru"
        return 1
    fi
}

# ========== FUNÇÕES KERNEL ==========

# Função para verificar suporte do kernel
check_kernel_support() {
    log "Verificando suporte do kernel para SELinux..."
    
    if [[ -f "/proc/config.gz" ]]; then
        if zcat /proc/config.gz | grep -q "CONFIG_SECURITY_SELINUX=y"; then
            log "✓ Kernel atual suporta SELinux"
            return 0
        else
            warn "Kernel atual não suporta SELinux completamente"
            return 1
        fi
    elif [[ -f "/boot/config-$(uname -r)" ]]; then
        if grep -q "CONFIG_SECURITY_SELINUX=y" "/boot/config-$(uname -r)"; then
            log "✓ Kernel atual suporta SELinux"
            return 0
        else
            warn "Kernel atual não suporta SELinux completamente"
            return 1
        fi
    else
        warn "Não foi possível verificar configuração do kernel"
        return 2
    fi
}

# Função para instalar kernel com SELinux usando paru
install_selinux_kernel() {
    log "Instalando kernel com suporte SELinux usando $AUR_HELPER..."
    
    check_aur_helper || return 1
    
    # Tentar instalar linux-selinux do AUR
    log "Instalando linux-selinux do AUR..."
    
    if [[ $AUR_HELPER == "paru" ]]; then
        paru -S --noconfirm linux-selinux linux-selinux-headers
    else
        yay -S --noconfirm linux-selinux linux-selinux-headers
    fi
    
    if [[ $? -eq 0 ]]; then
        log "✓ Kernel SELinux instalado com sucesso"
        return 0
    else
        error "Falha na instalação do kernel SELinux via $AUR_HELPER"
        warn "Você pode tentar instalar manualmente depois: paru -S linux-selinux"
        return 1
    fi
}

# ========== FUNÇÕES DE INSTALAÇÃO ==========

# Função para instalar pacotes SELinux
install_selinux_packages() {
    log "Instalando pacotes SELinux..."
    
    # Atualizar sistema primeiro
    log "Atualizando sistema..."
    pacman -Syu --noconfirm
    
    # Pacotes principais do repositório oficial
    log "Instalando pacotes principais..."
    pacman -S --noconfirm selinux libselinux python-sepolicy setools checkpolicy secilc policycoreutils
    
    # Utilitários adicionais
    log "Instalando utilitários..."
    pacman -S --noconfirm audit semodule-utils setroubleshoot restorcond policycoreutils-restorecond
    
    # Ferramentas para GNOME
    log "Instalando ferramentas GNOME..."
    pacman -S --noconfirm selinux-gnome-config
    
    log "✓ Pacotes SELinux instalados com sucesso"
}

# Função para configurar kernel unificado
configure_unified_kernel() {
    log "Configurando kernel unificado para SELinux..."
    
    # Verificar se o arquivo de cmdline existe
    if [[ ! -f "$UNIFIED_KERNEL_CMDLINE" ]]; then
        warn "Arquivo $UNIFIED_KERNEL_CMDLINE não existe. Criando..."
        mkdir -p /etc/kernel
        # Usar cmdline atual como base
        cat /proc/cmdline > "$UNIFIED_KERNEL_CMDLINE" 2>/dev/null || echo "" > "$UNIFIED_KERNEL_CMDLINE"
    fi
    
    # Fazer backup do cmdline atual
    cp "$UNIFIED_KERNEL_CMDLINE" "$UNIFIED_KERNEL_CMDLINE.backup"
    
    # Ler cmdline atual
    local current_cmdline=""
    if [[ -s "$UNIFIED_KERNEL_CMDLINE" ]]; then
        current_cmdline=$(cat "$UNIFIED_KERNEL_CMDLINE")
    else
        # Se vazio, usar cmdline atual do kernel
        current_cmdline=$(cat /proc/cmdline 2>/dev/null || echo "")
    fi
    
    # Remover parâmetros SELinux existentes para evitar duplicatas
    current_cmdline=$(echo "$current_cmdline" | sed -e 's/selinux=[0-1]//g' -e 's/security=selinux//g' -e 's/audit=[0-1]//g')
    
    # Adicionar parâmetros SELinux
    current_cmdline="$current_cmdline selinux=1 security=selinux audit=1"
    
    # Remover espaços extras e escrever novo cmdline
    echo "$current_cmdline" | tr -s ' ' | sed 's/^[ \t]*//;s/[ \t]*$//' > "$UNIFIED_KERNEL_CMDLINE"
    
    log "✓ Kernel unificado configurado: $(cat $UNIFIED_KERNEL_CMDLINE)"
}

# ========== FUNÇÕES DE CONFIGURAÇÃO SELINUX ==========

setup_selinux_dirs() {
    log "Configurando estrutura de diretórios SELinux..."
    
    mkdir -p /etc/selinux
    mkdir -p /var/lib/selinux
    mkdir -p /etc/selinux/targeted/contexts/files
    mkdir -p /etc/selinux/targeted/policy
    
    log "✓ Estrutura de diretórios criada"
}

setup_selinux_config() {
    log "Configurando arquivo principal do SELinux..."
    
    cat > /etc/selinux/config << 'EOF'
# This file controls the state of SELinux on the system.
# SELINUX= can take one of these three values:
#     enforcing - SELinux security policy is enforced.
#     permissive - SELinux prints warnings instead of enforcing.
#     disabled - No SELinux policy is loaded.
SELINUX=permissive

# SELINUXTYPE= can take one of these three values:
#     targeted - Targeted processes are protected,
#     minimum - Modification of targeted policy. Only selected processes are protected.
#     mls - Multi Level Security protection.
SELINUXTYPE=targeted

# SETLOCALDEFS= Check local definition changes
SETLOCALDEFS=0
EOF

    log "✓ Arquivo de configuração SELinux criado"
}

# ========== FUNÇÕES DE POLÍTICAS ==========

create_refined_policies() {
    log "Criando políticas refinadas para PipeWire + Wayland..."
    
    local policy_dir="/etc/selinux/targeted/policy"
    mkdir -p "$policy_dir"
    
    # Política base simplificada
    cat > "$policy_dir/arch-base.te" << 'EOF'
policy_module(arch-base, 1.0.0)

# Declarações de tipos básicos
type arch_t;
type arch_exec_t;
type arch_config_t;

# Permissões básicas do sistema
allow arch_t self:capability { chown dac_override dac_read_search fowner fsetid kill setgid setuid };
allow arch_t self:process { transition getsched setsched getsession getpgid setpgid };
allow arch_t self:fd use;
allow arch_t self:fifo_file rw_fifo_file_perms;

# Sistema de arquivos
allow arch_t proc_t:filesystem mount;
allow arch_t sysfs_t:filesystem mount;
allow arch_t tmpfs_t:filesystem mount;

# Network
allow arch_t node_t:udp_socket node_bind;
allow arch_t node_t:tcp_socket node_bind;
allow arch_t port_t:tcp_socket name_bind;

# DBus
allow arch_t system_dbusd_t:unix_stream_socket connectto;

# Logs
allow arch_t var_log_t:dir search;
allow arch_t var_log_t:file { read open getattr };
EOF

    # Política para PipeWire
    cat > "$policy_dir/pipewire.te" << 'EOF'
policy_module(pipewire, 1.0.0)

type pipewire_t;
type pipewire_exec_t;
init_daemon_domain(pipewire_t, pipewire_exec_t)

# PipeWire daemon
allow pipewire_t self:capability { ipc_lock sys_nice sys_resource };
allow pipewire_t self:process signal;
allow pipewire_t self:unix_stream_socket { create connect accept listen };

# Acesso a dispositivos de áudio
allow pipewire_t device_t:chr_file { read write open getattr };
allow pipewire_t alsa_device_t:chr_file { read write open };

# DBus para PipeWire
allow pipewire_t system_dbusd_t:unix_stream_socket connectto;
EOF

    log "✓ Políticas básicas criadas"
}

compile_policies() {
    log "Compilando políticas SELinux..."
    
    local policy_dir="/etc/selinux/targeted/policy"
    
    # Compilar cada módulo se as ferramentas estiverem disponíveis
    if command -v checkmodule >/dev/null 2>&1 && command -v semodule_package >/dev/null 2>&1; then
        for te_file in "$policy_dir"/*.te; do
            if [[ -f "$te_file" ]]; then
                local module_name=$(basename "$te_file" .te)
                log "Compilando módulo: $module_name"
                
                checkmodule -M -m -o "${te_file%.te}.mod" "$te_file" && \
                semodule_package -o "${te_file%.te}.pp" -m "${te_file%.te}.mod" && \
                semodule -i "${te_file%.te}.pp" && \
                log "✓ Módulo $module_name instalado" || \
                warn "Falha ao compilar módulo $module_name"
            fi
        done
    else
        warn "Ferramentas de compilação de políticas não disponíveis"
    fi
    
    log "✓ Políticas processadas"
}

setup_file_contexts() {
    log "Configurando contextos de arquivos..."
    
    mkdir -p /etc/selinux/targeted/contexts/files
    
    cat > /etc/selinux/targeted/contexts/files/file_contexts.local << 'EOF'
# Contextos personalizados para Arch Linux
/.*    system_u:object_r:default_t:s0
/etc/.*    system_u:object_r:etc_t:s0
/var/.*    system_u:object_r:var_t:s0
/usr/.*    system_u:object_r:usr_t:s0
/tmp/.*    system_u:object_r:tmp_t:s0
/home/.*    system_u:object_r:home_root_t:s0
/home/[^/]+/\.?.*    system_u:object_r:user_home_t:s0
EOF

    log "✓ Contextos de arquivos configurados"
}

setup_services() {
    log "Configurando serviços SELinux..."
    
    systemctl enable auditd.service 2>/dev/null && log "✓ Auditd habilitado" || warn "Falha ao habilitar auditd"
    systemctl enable restorecond.service 2>/dev/null && log "✓ Restorecond habilitado" || warn "Falha ao habilitar restorecond"
    
    log "✓ Serviços configurados"
}

# ========== FUNÇÕES DE DIAGNÓSTICO ==========

initial_test() {
    log "Executando testes iniciais..."
    
    # Verificar se SELinux está ativo
    if command -v sestatus >/dev/null 2>&1; then
        if sestatus &>/dev/null; then
            log "✓ SELinux está ativo"
        else
            error "SELinux não está ativo"
            return 1
        fi
    else
        warn "sestatus não disponível"
    fi
    
    # Verificar modo atual
    if command -v getenforce >/dev/null 2>&1; then
        local current_mode=$(getenforce)
        log "Modo SELinux atual: $current_mode"
    fi
    
    log "✓ Testes iniciais completados"
}

diagnostic_mode() {
    echo -e "\n${BLUE}=== DIAGNÓSTICO DO SISTEMA ===${NC}"
    echo "Kernel: $(uname -r)"
    echo "AUR Helper: $AUR_HELPER"
    
    if command -v sestatus >/dev/null 2>&1; then
        echo "SELinux: $(sestatus 2>/dev/null | head -1 || echo 'Não disponível')"
    fi
    
    if command -v getenforce >/dev/null 2>&1; then
        echo "Modo: $(getenforce 2>/dev/null || echo 'Desconhecido')"
    fi
    
    echo -e "\n${BLUE}=== ARQUIVOS DE CONFIGURAÇÃO ===${NC}"
    if [[ -f "$UNIFIED_KERNEL_CMDLINE" ]]; then
        echo "Kernel cmdline: $(cat $UNIFIED_KERNEL_CMDLINE)"
    else
        echo "Kernel cmdline: Não encontrado"
    fi
    
    if [[ -f "/etc/selinux/config" ]]; then
        echo "SELinux config: Existe"
    else
        echo "SELinux config: Não existe"
    fi
    
    echo -e "\n${BLUE}=== SERVIÇOS ===${NC}"
    systemctl is-active auditd 2>/dev/null && echo "Auditd: Ativo" || echo "Auditd: Inativo"
}

# ========== FUNÇÃO DE INSTALAÇÃO COMPLETA ==========

complete_installation() {
    log "Iniciando instalação completa do SELinux..."
    
    create_backup
    check_kernel_support
    
    if [[ $? -ne 0 ]]; then
        warn "Kernel atual pode não suportar SELinux completamente"
        read -p "Deseja instalar kernel com SELinux? (s/N): " install_kernel
        if [[ $install_kernel == "s" || $install_kernel == "S" ]]; then
            install_selinux_kernel
        fi
    fi
    
    install_selinux_packages
    configure_unified_kernel
    setup_selinux_dirs
    setup_selinux_config
    create_refined_policies
    compile_policies
    setup_file_contexts
    setup_services
    initial_test
    
    log "✓ Instalação completa finalizada!"
    warn "REINICIE O SISTEMA para ativar o SELinux"
    echo -e "${YELLOW}Após reiniciar, execute: sudo ./selinux-post-setup.sh${NC}"
}

restore_backup() {
    warn "RESTAURANDO BACKUP DO SISTEMA"
    
    if [[ -d "$BACKUP_DIR" ]]; then
        log "Restaurando arquivos de backup..."
        cp -a "$BACKUP_DIR"/* /etc/ 2>/dev/null || true
        cp -a "$BACKUP_DIR"/boot/loader /boot/ 2>/dev/null || true
        log "✓ Backup restaurado. Reinicie o sistema."
    else
        error "Nenhum backup encontrado em $BACKUP_DIR"
    fi
}

# ========== MENU PRINCIPAL ==========

show_menu() {
    echo -e "\n${BLUE}=== INSTALADOR SELINUX ARCH LINUX ===${NC}"
    echo "AUR Helper: ${GREEN}$AUR_HELPER${NC}"
    echo ""
    echo "1. Instalação Completa SELinux"
    echo "2. Apenas Instalar Pacotes Oficiais"
    echo "3. Configurar Kernel Unificado"
    echo "4. Criar Políticas Personalizadas"
    echo "5. Executar Diagnóstico"
    echo "6. Instalar/Verificar AUR Helper"
    echo "7. Restaurar Backup"
    echo "8. Sair"
    echo -n "Escolha uma opção [1-8]: "
}

main() {
    check_root
    check_aur_helper
    check_system_config
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1) complete_installation ;;
            2) install_selinux_packages ;;
            3) configure_unified_kernel ;;
            4) 
                create_refined_policies 
                compile_policies 
                ;;
            5) diagnostic_mode ;;
            6) install_paru_helper ;;
            7) restore_backup ;;
            8) 
                log "Saindo..."
                exit 0 
                ;;
            *) error "Opção inválida" ;;
        esac
        
        echo -e "\nPressione Enter para continuar..."
        read -r
    done
}

# ========== EXECUÇÃO PRINCIPAL ==========

# Verificar se estamos sendo executados diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
