#!/bin/bash

# SELinux Arch Installer - Versão REALISTA baseada no wiki do Arch Linux

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_warning() {
    echo -e "${RED}"
    echo "=================================================="
    echo "          AVISO IMPORTANTE - SELINUX"
    echo "=================================================="
    echo ""
    echo "SELinux no Arch Linux é:"
    echo "• Experimental e não oficialmente suportado"
    echo "• Pode causar instabilidade no sistema"
    echo "• Pode impedir que aplicativos funcionem"
    echo "• Requer manutenção constante"
    echo ""
    echo "Recomendado apenas para:"
    echo "• Sistemas de teste/desenvolvimento"
    echo "• Usuários avançados que entendem os riscos"
    echo ""
    echo "NÃO USE EM SISTEMAS DE PRODUÇÃO!"
    echo -e "${NC}"
    
    read -p "Continuar mesmo assim? (s/N): " confirm
    if [[ $confirm != "s" && $confirm != "S" ]]; then
        exit 1
    fi
}

check_arch_wiki_info() {
    log "Verificando compatibilidade com Arch Linux..."
    
    # Verificar se estamos no Arch Linux
    if [[ ! -f "/etc/arch-release" ]]; then
        error "Este script é específico para Arch Linux"
        exit 1
    fi
    
    warn "AVISO: SELinux no Arch Linux tem suporte limitado"
    echo ""
    echo "Problemas conhecidos:"
    echo "• Políticas incompletas para muitos pacotes"
    echo "• Possíveis conflitos com systemd"
    echo "• Necessidade de configuração manual extensiva"
    echo "• Alto risco de quebrar o sistema"
    echo ""
}

install_selinux_packages_arch() {
    log "Instalando pacotes SELinux do repositório oficial Arch..."
    
    # Pacotes disponíveis oficialmente no Arch
    pacman -S --noconfirm \
        libselinux \
        selinux-python \
        selinux-python-gui \
        setools \
        checkpolicy \
        secilc \
        policycoreutils \
        restorecond
    
    # Pacotes do AUR (com aviso)
    warn "Pacotes do AUR podem não ser mantidos adequadamente"
    if command -v paru >/dev/null 2>&1; then
        read -p "Instalar pacotes do AUR? (s/N): " install_aur
        if [[ $install_aur == "s" || $install_aur == "S" ]]; then
            paru -S --noconfirm selinux-refpolicy
        fi
    fi
}

configure_selinux_arch() {
    log "Configurando SELinux seguindo o wiki do Arch..."
    
    # Configuração mínima e segura
    mkdir -p /etc/selinux
    
    cat > /etc/selinux/config << 'EOF'
# Configuração SELinux para Arch Linux
# AVISO: Configuração experimental - use por sua conta e risco

SELINUX=permissive
SELINUXTYPE=targeted

# Desativar recursos problemáticos no Arch
SETLOCALDEFS=0
AUDITD=none
EOF

    # Configurar kernel parameters de forma conservadora
    if [[ -f "/etc/kernel/cmdline" ]]; then
        cp /etc/kernel/cmdline /etc/kernel/cmdline.backup
        echo "selinux=1 security=selinux audit=0" > /etc/kernel/cmdline
    fi
}

setup_selinux_policies_arch() {
    log "Configurando políticas (approach conservador)..."
    
    # Política mínima para evitar quebrar o sistema
    mkdir -p /etc/selinux/targeted/policy
    
    cat > /etc/selinux/targeted/policy/arch-minimal.te << 'EOF'
policy_module(arch-minimal, 1.0.0)

# Política mínima para Arch Linux
# Foca em não quebrar o sistema ao invés de segurança máxima

type arch_t;
type arch_exec_t;

# Permissões básicas muito amplas para compatibilidade
allow arch_t self:capability *;
allow arch_t self:process *;
allow arch_t self:filesystem *;
allow arch_t self:fd *;

# Acesso amplo a dispositivos e sistema de arquivos
allow arch_t device_t:chr_file *;
allow arch_t device_t:blk_file *;
allow arch_t proc_t:filesystem *;
allow arch_t sysfs_t:filesystem *;
allow arch_t tmpfs_t:filesystem *;

# Network amplo
allow arch_t node_t:tcp_socket *;
allow arch_t node_t:udp_socket *;
allow arch_t port_t:tcp_socket *;
allow arch_t port_t:udp_socket *;

# DBus amplo
allow arch_t system_dbusd_t:unix_stream_socket *;

# Foco: Não quebrar o sistema no Arch
dontaudit arch_t *:*;
EOF
}

enable_selinux_services_arch() {
    log "Configurando serviços (approach mínimo)..."
    
    # Habilitar apenas serviços essenciais
    systemctl enable auditd.service --now 2>/dev/null || warn "Auditd não disponível"
    
    # Não habilitar serviços problemáticos no Arch
    warn "Alguns serviços SELinux são desativados para evitar problemas"
}

show_recovery_instructions() {
    echo -e "${YELLOW}"
    echo "=================================================="
    echo "          INSTRUÇÕES DE RECUPERAÇÃO"
    echo "=================================================="
    echo ""
    echo "Se o sistema ficar inacessível:"
    echo ""
    echo "1. Na tela de boot, edite os parâmetros do kernel:"
    echo "   Adicione: selinux=0"
    echo ""
    echo "2. Ou boote com uma mídia live e:"
    echo "   mount /dev/sdXY /mnt"
    echo "   arch-chroot /mnt"
    echo "   nano /etc/selinux/config → SELINUX=disabled"
    echo "   nano /etc/kernel/cmdline → remova parâmetros selinux"
    echo ""
    echo "3. Desinstalar completamente:"
    echo "   pacman -Rs selinux-python libselinux setools"
    echo -e "${NC}"
}

main_menu() {
    while true; do
        echo -e "\n${GREEN}=== SELinux no Arch Linux (EXPERIMENTAL) ===${NC}"
        echo ""
        echo "1. Instalação MÍNIMA e SEGURA"
        echo "2. Verificar compatibilidade"
        echo "3. Instalar apenas pacotes"
        echo "4. Mostrar instruções de recuperação"
        echo "5. Sair"
        echo ""
        echo -n "Escolha [1-5]: "
        
        read choice
        case $choice in
            1)
                show_warning
                check_arch_wiki_info
                install_selinux_packages_arch
                configure_selinux_arch
                setup_selinux_policies_arch
                enable_selinux_services_arch
                show_recovery_instructions
                ;;
            2)
                check_arch_wiki_info
                ;;
            3)
                install_selinux_packages_arch
                ;;
            4)
                show_recovery_instructions
                ;;
            5)
                exit 0
                ;;
            *)
                error "Opção inválida"
                ;;
        esac
    done
}

# Verificar se é root
if [[ $EUID -ne 0 ]]; then
    error "Este script deve ser executado como root"
    exit 1
fi

main_menu
