#!/bin/bash

# Script de pós-instalação para PipeWire + Wayland com suporte a paru

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

AUR_HELPER="paru"

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Função para verificar AUR helper
check_aur_helper() {
    if command -v paru &> /dev/null; then
        AUR_HELPER="paru"
        return 0
    elif command -v yay &> /dev/null; then
        AUR_HELPER="yay"
        return 0
    else
        warn "Nenhum AUR helper encontrado. Algumas funcionalidades podem ser limitadas."
        return 1
    fi
}

# Função para instalar pacotes AUR se necessário
install_aur_tools() {
    check_aur_helper || return 1
    
    log "Instalando ferramentas SELinux do AUR usando $AUR_HELPER..."
    
    if [[ $AUR_HELPER == "paru" ]]; then
        paru -S --noconfirm selinux-troubleshoot selinux-gui
    else
        yay -S --noconfirm selinux-troubleshoot selinux-gui
    fi
    
    if [[ $? -eq 0 ]]; then
        log "✓ Ferramentas AUR instaladas com sucesso"
    else
        warn "Falha ao instalar ferramentas AUR"
    fi
}

# Função para verificar pacotes AUR instalados
check_aur_packages() {
    log "Verificando pacotes AUR instalados..."
    
    local packages=("linux-selinux" "selinux-refpolicy-arch" "selinux-python")
    
    for pkg in "${packages[@]}"; do
        if pacman -Q "$pkg" &> /dev/null; then
            echo "✓ $pkg: $(pacman -Q "$pkg")"
        else
            echo "✗ $pkg: Não instalado"
        fi
    done
}

# Menu de pós-instalação atualizado
show_post_menu() {
    echo -e "\n${GREEN}=== PÓS-INSTALAÇÃO SELINUX ===${NC}"
    echo "AUR Helper: ${GREEN}$AUR_HELPER${NC}"
    echo ""
    echo "1. Verificar integração Wayland + PipeWire"
    echo "2. Verificar pacotes AUR"
    echo "3. Instalar ferramentas adicionais do AUR"
    echo "4. Analisar Violações SELinux"
    echo "5. Diagnosticar problemas Wayland"
    echo "6. Diagnosticar problemas PipeWire"
    echo "7. Auto-corrigir Políticas"
    echo "8. Aplicar correções comuns"
    echo "9. Alterar Modo SELinux"
    echo "10. Ver Status Completo"
    echo "11. Sair"
    echo -n "Escolha [1-11]: "
}

# Função principal atualizada
main() {
    check_aur_helper
    
    while true; do
        show_post_menu
        read choice
        
        case $choice in
            1) 
                log "Verificando integração Wayland + PipeWire..."
                # ... (resto da função igual)
                ;;
            2) check_aur_packages ;;
            3) install_aur_tools ;;
            4) 
                log "Analisando violações SELinux..."
                if command -v sealert &> /dev/null; then
                    sudo ausearch -m avc -ts today 2>/dev/null | sudo sealert -a - 2>/dev/null || 
                    warn "Nenhuma violação encontrada"
                else
                    warn "sealert não disponível. Instale com: sudo $AUR_HELPER -S setroubleshoot"
                fi
                ;;
            5) 
                log "Diagnosticando problemas Wayland..."
                # ... (resto da função igual)
                ;;
            6) 
                log "Diagnosticando problemas PipeWire..."
                # ... (resto da função igual)
                ;;
            7) 
                log "Gerando políticas automáticas..."
                if command -v audit2allow &> /dev/null; then
                    sudo audit2allow -a -M local-policy
                    sudo semodule -i local-policy.pp
                else
                    warn "audit2allow não disponível"
                fi
                ;;
            8) 
                log "Aplicando correções comuns..."
                # ... (resto da função igual)
                ;;
            9) 
                echo "Modo atual: $(getenforce)"
                echo "1. Permissive | 2. Enforcing"
                read -p "Escolha: " mode
                case $mode in
                    1) sudo setenforce 0; log "Modo Permissivo ativado" ;;
                    2) sudo setenforce 1; log "Modo Enforcing ativado" ;;
                    *) warn "Opção inválida" ;;
                esac
                ;;
            10) 
                sestatus
                echo -e "\n---"
                check_aur_packages
                ;;
            11) exit 0 ;;
            *) echo "Opção inválida" ;;
        esac
        
        echo -e "\nPressione Enter para continuar..."
        read
    done
}

# Verificar se SELinux está ativo antes de executar
if ! sestatus &>/dev/null; then
    echo -e "${RED}ERRO: SELinux não está ativo. Execute o script de instalação primeiro.${NC}"
    exit 1
fi

main "$@"