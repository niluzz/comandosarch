#!/bin/bash

# SELinux Post-Setup - Versão realista para Arch Linux

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

check_selinux_status() {
    echo -e "\n${GREEN}=== Status SELinux no Arch ===${NC}"
    
    if ! command -v sestatus >/dev/null 2>&1; then
        echo "✗ SELinux não está instalado"
        return 1
    fi
    
    if ! sestatus >/dev/null 2>&1; then
        echo "✗ SELinux não está ativo"
        echo "  Motivo comum no Arch: suporte incompleto do kernel"
        return 1
    fi
    
    echo "✓ SELinux está ativo"
    echo "Modo: $(getenforce 2>/dev/null || echo 'unknown')"
    return 0
}

check_for_problems() {
    log "Verificando problemas comuns no Arch..."
    
    # Verificar se serviços críticos estão funcionando
    local services=("dbus" "networkmanager" "gdm" "pipewire")
    
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            warn "Serviço $service pode estar afetado pelo SELinux"
        fi
    done
    
    # Verificar logs por problemas
    if journalctl -x --since="1 hour ago" | grep -i "selinux\|avc" | grep -i "denied"; then
        warn "Foram encontradas negações do SELinux nos logs"
    fi
}

show_arch_specific_advice() {
    echo -e "\n${YELLOW}=== Conselhos Específicos para Arch ===${NC}"
    echo ""
    echo "1. Mantenha o SELinux em 'permissive' no Arch"
    echo "2. Monitore os logs regularmente: journalctl -f"
    echo "3. Desative o SELinux se causar problemas críticos"
    echo "4. Faça backup frequente do sistema"
    echo "5. Considere usar AppArmor (alternativa mais suportada)"
    echo ""
}

disable_selinux_safely() {
    warn "DESATIVANDO SELINUX..."
    
    # Voltar para modo desativado
    setenforce 0 2>/dev/null || true
    
    # Editar configuração
    sed -i 's/SELINUX=.*/SELINUX=disabled/' /etc/selinux/config 2>/dev/null || true
    
    # Remover parâmetros do kernel
    if [[ -f "/etc/kernel/cmdline" ]]; then
        sed -i 's/selinux=[01]//g; s/security=selinux//g' /etc/kernel/cmdline
    fi
    
    log "SELinux desativado. Reinicie para efeito completo."
}

main_menu() {
    while true; do
        echo -e "\n${GREEN}=== Gerenciador SELinux - Arch Linux ===${NC}"
        check_selinux_status
        
        echo ""
        echo "1. Verificar problemas"
        echo "2. Mostrar logs do SELinux"
        echo "3. Ver conselhos para Arch"
        echo "4. Desativar SELinux (seguro)"
        echo "5. Sair"
        echo ""
        echo -n "Escolha [1-5]: "
        
        read choice
        case $choice in
            1) check_for_problems ;;
            2) journalctl -x | grep -i selinux | tail -20 || echo "Nenhum log encontrado" ;;
            3) show_arch_specific_advice ;;
            4) disable_selinux_safely ;;
            5) exit 0 ;;
            *) echo "Opção inválida" ;;
        esac
    done
}

main_menu
