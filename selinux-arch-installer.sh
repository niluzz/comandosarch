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

# Função para verificar AUR helper
check_aur_helper() {
    log "Verificando AUR helper..."
    
    if command -v paru &> /dev/null; then
        log "✓ Paru encontrado"
        AUR_HELPER="paru"
    elif command -v yay &> /dev/null; then
        warn "Paru não encontrado, usando yay como fallback"
        AUR_HELPER="yay"
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
            error "AUR helper é necessário para instalar o kernel SELinux"
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
    
    if command -v paru &> /dev/null; then
        log "✓ Paru instalado com sucesso"
        AUR_HELPER="paru"
        return 0
    else
        error "Falha na instalação do paru"
        return 1
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
        
        # Verificar se o kernel foi realmente instalado
        if pacman -Q linux-selinux &> /dev/null; then
            log "✓ Pacote linux-selinux confirmado"
            return 0
        else
            warn "Pacote linux-selinux não encontrado após instalação"
            return 1
        fi
    else
        error "Falha na instalação do kernel SELinux via $AUR_HELPER"
        
        # Tentar método alternativo
        warn "Tentando método alternativo de instalação..."
        install_selinux_kernel_alternative
        return $?
    fi
}

# Função alternativa para instalar kernel SELinux
install_selinux_kernel_alternative() {
    log "Tentando método alternativo para instalar kernel SELinux..."
    
    cd /tmp
    git clone https://aur.archlinux.org/linux-selinux.git
    cd linux-selinux
    
    # Instalar dependências necessárias
    pacman -S --needed --noconfirm base-devel git bc libelf pahole cpio perl tar xz
    
    # Construir manualmente
    if makepkg -si --noconfirm; then
        log "✓ Kernel SELinux instalado manualmente com sucesso"
        return 0
    else
        error "Falha na instalação manual do kernel SELinux"
        
        # Oferecer opção de usar kernel padrão com patches
        warn "Deseja tentar configurar o kernel padrão com SELinux?"
        read -p "Isso habilitará SELinux no kernel atual (s/N): " use_current
        if [[ $use_current == "s" || $use_current == "S" ]]; then
            configure_current_kernel_selinux
            return $?
        else
            return 1
        fi
    fi
}

# Função para configurar kernel atual com SELinux
configure_current_kernel_selinux() {
    log "Configurando kernel atual para suporte SELinux..."
    
    # Verificar se o kernel atual já suporta SELinux
    if check_kernel_support; then
        log "✓ Kernel atual já suporta SELinux"
        return 0
    else
        warn "Kernel atual não suporta SELinux completamente"
        warn "Algumas funcionalidades podem ser limitadas"
        
        # Verificar módulos carregáveis
        if lsmod | grep -q selinux; then
            log "✓ Módulo SELinux carregado"
        else
            warn "Módulo SELinux não está carregado"
        fi
        
        return 0
    fi
}

# Função para instalar pacotes SELinux (atualizada para paru)
install_selinux_packages() {
    log "Instalando pacotes SELinux..."
    
    # Pacotes principais do repositório oficial
    pacman -S --noconfirm selinux libselinux python-sepolicy python-sepolib \
        setools checkpolicy secilc policycoreutils setools-console
    
    # Utilitários adicionais
    pacman -S --noconfirm audit semodule-utils setroubleshoot \
        restorcond policycoreutils-restorecond
    
    # Ferramentas para GNOME
    pacman -S --noconfirm selinux-gnome-config sepolgen
    
    # Pacotes do AUR usando paru
    check_aur_helper
    
    log "Instalando pacotes SELinux do AUR..."
    
    if [[ $AUR_HELPER == "paru" ]]; then
        paru -S --noconfirm selinux-refpolicy-arch selinux-python
    else
        yay -S --noconfirm selinux-refpolicy-arch selinux-python
    fi
    
    # Verificar instalação dos pacotes AUR
    if pacman -Q selinux-refpolicy-arch &> /dev/null; then
        log "✓ selinux-refpolicy-arch instalado"
    else
        warn "selinux-refpolicy-arch não instalado - usando políticas genéricas"
    fi
    
    log "Pacotes SELinux instalados com sucesso"
}

# Função para configurar kernel unificado (atualizada)
configure_unified_kernel() {
    log "Configurando kernel unificado para SELinux..."
    
    # Verificar se o arquivo de cmdline existe
    if [[ ! -f "$UNIFIED_KERNEL_CMDLINE" ]]; then
        warn "Arquivo $UNIFIED_KERNEL_CMDLINE não existe. Criando..."
        mkdir -p /etc/kernel
        touch "$UNIFIED_KERNEL_CMDLINE"
    fi
    
    # Fazer backup do cmdline atual
    cp "$UNIFIED_KERNEL_CMDLINE" "$UNIFIED_KERNEL_CMDLINE.backup"
    
    # Ler cmdline atual
    local current_cmdline=""
    if [[ -s "$UNIFIED_KERNEL_CMDLINE" ]]; then
        current_cmdline=$(cat "$UNIFIED_KERNEL_CMDLINE" | tr -s ' ')
    else
        # Se vazio, usar cmdline atual do kernel
        current_cmdline=$(cat /proc/cmdline 2>/dev/null || echo "")
    fi
    
    log "Cmdline atual: $current_cmdline"
    
    # Remover parâmetros SELinux existentes para evitar duplicatas
    current_cmdline=$(echo "$current_cmdline" | sed -e 's/selinux=[0-1]//g' -e 's/security=selinux//g' -e 's/audit=[0-1]//g')
    
    # Adicionar parâmetros SELinux
    current_cmdline="$current_cmdline selinux=1 security=selinux audit=1"
    
    # Remover espaços extras e escrever novo cmdline
    echo "$current_cmdline" | tr -s ' ' | sed 's/^[ \t]*//;s/[ \t]*$//' > "$UNIFIED_KERNEL_CMDLINE"
    
    # Atualizar configurações do kernel unificado
    if command -v kernel-install &> /dev/null; then
        log "Atualizando configuração do kernel unificado..."
        kernel-install add "$(uname -r)" /boot/vmlinuz-linux
    fi
    
    # Verificar se o kernel SELinux está instalado e adicionar entrada específica
    if pacman -Q linux-selinux &> /dev/null; then
        log "Configurando entrada para kernel SELinux..."
        local selinux_kernel_version=$(pacman -Q linux-selinux | awk '{print $2}')
        
        # Criar entrada específica para kernel SELinux
        local selinux_cmdline_file="/etc/kernel/cmdline-selinux"
        echo "$current_cmdline" > "$selinux_cmdline_file"
        
        # Atualizar entrada do kernel SELinux se existir
        if [[ -d "/boot/loader/entries" ]]; then
            local selinux_entry="/boot/loader/entries/arch-selinux.conf"
            cat > "$selinux_entry" << EOF
title Arch Linux SELinux
linux /vmlinuz-linux-selinux
initrd /initramfs-linux-selinux.img
options $(cat "$UNIFIED_KERNEL_CMDLINE")
EOF
            log "Entrada do bootloader para kernel SELinux criada"
        fi
    fi
    
    log "✓ Kernel unificado configurado: $(cat $UNIFIED_KERNEL_CMDLINE)"
}

# Função de diagnóstico atualizada
diagnostic_mode() {
    log "Executando diagnóstico do sistema..."
    
    echo -e "\n${BLUE}=== DIAGNÓSTICO SELINUX ===${NC}"
    echo "Kernel: $(uname -r)"
    echo "AUR Helper: $AUR_HELPER"
    echo "SELinux: $(sestatus 2>/dev/null || echo 'Não instalado')"
    echo "Modo: $(getenforce 2>/dev/null || echo 'Desconhecido')"
    
    echo -e "\n${BLUE}=== AUR PACKAGES ===${NC}"
    if pacman -Q linux-selinux &> /dev/null; then
        echo "✓ linux-selinux: $(pacman -Q linux-selinux)"
    else
        echo "✗ linux-selinux: Não instalado"
    fi
    
    if pacman -Q selinux-refpolicy-arch &> /dev/null; then
        echo "✓ selinux-refpolicy-arch: $(pacman -Q selinux-refpolicy-arch)"
    else
        echo "✗ selinux-refpolicy-arch: Não instalado"
    fi
    
    echo -e "\n${BLUE}=== KERNEL PARAMETERS ===${NC}"
    if [[ -f "$UNIFIED_KERNEL_CMDLINE" ]]; then
        echo "Cmdline: $(cat $UNIFIED_KERNEL_CMDLINE)"
    else
        echo "Cmdline: Arquivo não encontrado"
    fi
    
    echo "Proc cmdline: $(cat /proc/cmdline 2>/dev/null || echo 'N/A')"
    
    echo -e "\n${BLUE}=== SELINUX SERVICES ===${NC}"
    systemctl status auditd 2>/dev/null | head -3 || echo "Auditd não disponível"
    systemctl status selinux 2>/dev/null | head -3 || echo "Serviço SELinux não disponível"
    
    echo -e "\n${BLUE}=== POLICIES ===${NC}"
    seinfo 2>/dev/null | head -5 || echo "Políticas não carregadas"
}

# Função para mostrar informações de uso
show_usage() {
    echo -e "${GREEN}Modo de uso do script SELinux Arch Linux:${NC}"
    echo "Este script usa $AUR_HELPER para instalação de pacotes do AUR"
    echo ""
    echo "Opções disponíveis:"
    echo "1. Instalação Completa - Usa $AUR_HELPER para kernel SELinux"
    echo "2. Apenas Pacotes - Instala apenas pacotes oficiais"
    echo "3. Configurar Boot - Configura kernel unificado"
    echo "4. Políticas - Cria políticas customizadas"
    echo "5. Diagnóstico - Mostra informações do sistema"
    echo ""
    echo "Certifique-se de que o $AUR_HELPER está configurado corretamente."
}

# Menu principal atualizado
show_menu() {
    echo -e "\n${BLUE}=== INSTALADOR SELINUX ARCH LINUX ===${NC}"
    echo "AUR Helper detectado: ${GREEN}$AUR_HELPER${NC}"
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

# Main loop atualizado
main() {
    check_root
    check_aur_helper  # Verificar AUR helper no início
    check_system_config
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1)
                complete_installation
                ;;
            2)
                install_selinux_packages
                ;;
            3)
                configure_unified_kernel
                ;;
            4)
                create_refined_policies
                compile_policies
                ;;
            5)
                diagnostic_mode
                ;;
            6)
                install_paru_helper
                ;;
            7)
                restore_backup
                ;;
            8)
                log "Saindo..."
                exit 0
                ;;
            *)
                error "Opção inválida"
                ;;
        esac
        
        echo -e "\nPressione Enter para continuar..."
        read
    done
}

# Executar script
main "$@"