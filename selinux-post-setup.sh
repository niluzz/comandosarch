#!/bin/bash

# Script de pós-instalação para PipeWire + Wayland

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

AUR_HELPER="paru"

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_aur_helper() {
    if command -v paru >/dev/null 2>&1; then
        AUR_HELPER="paru"
        return 0
    elif command -v yay >/dev/null 2>&1; then
        AUR_HELPER="yay"
        return 0
    else
        warn "Nenhum AUR helper encontrado"
        return 1
    fi
}

check_wayland_pipewire() {
    log "Verificando integração Wayland + PipeWire..."
    
    # Verificar sessão Wayland
    if [[ "$XDG_SESSION_TYPE" == "wayland" ]]; then
        log "✓ Sessão Wayland ativa"
    else
        warn "Sessão X11 detectada"
    fi
    
    # Verificar PipeWire
    if command -v pipewire >/dev/null 2>&1; then
        log "✓ PipeWire instalado"
    else
        warn "PipeWire não encontrado"
    fi
    
    if systemctl --user is-active --quiet pipewire.service 2>/dev/null; then
        log "✓ PipeWire ativo para usuário"
    else
        warn "PipeWire não está ativo para o usuário"
    fi
}

diagnose_wayland_issues() {
    log "Diagnosticando problemas Wayland..."
    
    # Verificar compositor Wayland
    if pgrep -x "gnome-shell" >/dev/null 2>&1 || pgrep -x "mutter" >/dev/null 2>&1; then
        log "✓ Compositor Wayland em execução"
    else
        warn "Compositor Wayland não detectado"
    fi
    
    echo -e "\nVariáveis Wayland:"
    env | grep -E "WAYLAND|XDG" | grep -v "DISPLAY" || echo "Nenhuma variável Wayland encontrada"
}

diagnose_pipewire_issues() {
    log "Diagnosticando problemas PipeWire..."
    
    echo -e "\nProcessos PipeWire:"
    ps -e | grep -E "pipewire|wireplumber" | head -5 || echo "Nenhum processo PipeWire encontrado"
}

fix_common_issues() {
    log "Aplicando correções comuns..."
    
    # Corrigir contextos de dispositivos de áudio
    if [[ -d "/dev/snd" ]]; then
        log "Corrigindo contextos de dispositivos de áudio..."
        restorecon -R /dev/snd/ 2>/dev/null && log "✓ Contextos de áudio corrigidos" || warn "Falha ao corrigir contextos de áudio"
    fi
    
    # Corrigir contextos de configuração do PipeWire
    if [[ -d "/etc/pipewire" ]]; then
        log "Corrigindo contextos do PipeWire..."
        restorecon -R /etc/pipewire/ 2>/dev/null && log "✓ Contextos PipeWire corrigidos" || warn "Falha ao corrigir contextos PipeWire"
    fi
    
    log "✓ Correções aplicadas"
}

show_post_menu() {
    echo -e "\n${GREEN}=== PÓS-INSTALAÇÃO SELINUX ===${NC}"
    check_aur_helper
    echo "AUR Helper: ${GREEN}$AUR_HELPER${NC}"
    echo ""
    echo "1. Verificar integração Wayland + PipeWire"
    echo "2. Analisar Violações SELinux"
    echo "3. Diagnosticar problemas Wayland"
    echo "4. Diagnosticar problemas PipeWire"
    echo "5. Auto-corrigir Políticas"
    echo "6. Aplicar correções comuns"
    echo "7. Alterar Modo SELinux"
    echo "8. Ver Status Completo"
    echo "9. Sair"
    echo -n "Escolha [1-9]: "
}

main() {
    # Verificar se SELinux está ativo antes de executar
    if ! command -v sestatus >/dev/null 2>&1; then
        error "SELinux não está instalado. Execute o script de instalação primeiro."
        exit 1
    fi
    
    if ! sestatus &>/dev/null; then
        error "SELinux não está ativo. Reinicie o sistema após a instalação."
        exit 1
    fi
    
    while true; do
        show_post_menu
        read -r choice
        
        case $choice in
            1) check_wayland_pipewire ;;
            2) 
                if command -v ausearch >/dev/null 2>&1 && command -v sealert >/dev/null 2>&1; then
                    log "Analisando violações SELinux..."
                    ausearch -m avc -ts today 2>/dev/null | sealert -a - 2>/dev/null || warn "Nenhuma violação encontrada"
                else
                    warn "Ferramentas de análise não disponíveis"
                fi
                ;;
            3) diagnose_wayland_issues ;;
            4) diagnose_pipewire_issues ;;
            5) 
                if command -v audit2allow >/dev/null 2>&1; then
                    log "Gerando políticas automáticas..."
                    audit2allow -a -M local-policy 2>/dev/null && semodule -i local-policy.pp 2>/dev/null && log "✓ Políticas aplicadas" || warn "Falha ao gerar políticas"
                else
                    warn "audit2allow não disponível"
                fi
                ;;
            6) fix_common_issues ;;
            7) 
                if command -v getenforce >/dev/null 2>&1 && command -v setenforce >/dev/null 2>&1; then
                    echo "Modo atual: $(getenforce)"
                    echo "1. Permissive | 2. Enforcing"
                    read -r -p "Escolha: " mode
                    case $mode in
                        1) setenforce 0 && log "Modo Permissivo ativado" ;;
                        2) setenforce 1 && log "Modo Enforcing ativado" ;;
                        *) warn "Opção inválida" ;;
                    esac
                else
                    warn "Comandos SELinux não disponíveis"
                fi
                ;;
            8) 
                if command -v sestatus >/dev/null 2>&1; then
                    sestatus
                else
                    error "sestatus não disponível"
                fi
                ;;
            9) exit 0 ;;
            *) echo "Opção inválida" ;;
        esac
        
        echo -e "\nPressione Enter para continuar..."
        read -r
    done
}

# Executar apenas se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
