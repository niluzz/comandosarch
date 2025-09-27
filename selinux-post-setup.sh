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

# Função para verificar se SELinux está realmente instalado
check_selinux_installed() {
    log "Verificando instalação do SELinux..."
    
    # Verificar se pacotes SELinux estão instalados
    if pacman -Q selinux >/dev/null 2>&1 || pacman -Q libselinux >/dev/null 2>&1; then
        log "✓ Pacotes SELinux encontrados"
        return 0
    fi
    
    # Verificar se comandos SELinux existem
    if command -v sestatus >/dev/null 2>&1 || command -v getenforce >/dev/null 2>&1; then
        log "✓ Comandos SELinux disponíveis"
        return 0
    fi
    
    # Verificar se arquivos de configuração existem
    if [[ -f "/etc/selinux/config" ]] || [[ -d "/etc/selinux/targeted" ]]; then
        log "✓ Configurações SELinux encontradas"
        return 0
    fi
    
    return 1
}

# Função para verificar se SELinux está ativo
check_selinux_active() {
    log "Verificando status do SELinux..."
    
    # Tentar usar sestatus primeiro
    if command -v sestatus >/dev/null 2>&1; then
        if sestatus >/dev/null 2>&1; then
            log "✓ SELinux está ativo (sestatus)"
            return 0
        fi
    fi
    
    # Tentar usar getenforce
    if command -v getenforce >/dev/null 2>&1; then
        local mode=$(getenforce 2>/dev/null)
        if [[ $mode == "Enforcing" ]] || [[ $mode == "Permissive" ]]; then
            log "✓ SELinux está ativo (getenforce: $mode)"
            return 0
        fi
    fi
    
    # Verificar se o módulo do kernel está carregado
    if lsmod | grep -q selinux; then
        log "✓ Módulo SELinux carregado no kernel"
        return 0
    fi
    
    # Verificar parâmetros de kernel
    if grep -q "selinux=1" /proc/cmdline 2>/dev/null || 
       grep -q "security=selinux" /proc/cmdline 2>/dev/null; then
        log "✓ Parâmetros SELinux no kernel"
        return 0
    fi
    
    return 1
}

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
    elif [[ -n "$WAYLAND_DISPLAY" ]]; then
        log "✓ Wayland detectado (WAYLAND_DISPLAY)"
    else
        warn "Sessão X11 detectada ou variáveis Wayland não encontradas"
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
    
    if systemctl is-active --quiet pipewire.service 2>/dev/null; then
        log "✓ PipeWire ativo no sistema"
    fi
}

diagnose_wayland_issues() {
    log "Diagnosticando problemas Wayland..."
    
    # Verificar compositor Wayland
    if pgrep -x "gnome-shell" >/dev/null 2>&1; then
        log "✓ GNOME Shell em execução"
        # Verificar se está usando Wayland
        if grep -q "WAYLAND_DISPLAY" /proc/$(pgrep -x "gnome-shell")/environ 2>/dev/null; then
            log "✓ GNOME Shell usando Wayland"
        else
            warn "GNOME Shell pode não estar usando Wayland"
        fi
    else
        warn "GNOME Shell não detectado"
    fi
    
    echo -e "\nVariáveis de ambiente relevantes:"
    env | grep -E "XDG_SESSION_TYPE|WAYLAND_DISPLAY|XDG_CURRENT_DESKTOP" | head -10
    
    echo -e "\nProcessos gráficos:"
    ps aux | grep -E "gnome-shell|mutter|wayland" | grep -v grep | head -5
}

diagnose_pipewire_issues() {
    log "Diagnosticando problemas PipeWire..."
    
    echo -e "\nProcessos PipeWire:"
    ps aux | grep -E "pipewire|wireplumber" | grep -v grep | head -5
    
    echo -e "\nStatus dos serviços:"
    systemctl --user status pipewire pipewire-pulse wireplumber --no-pager -l | head -10 2>/dev/null
    
    echo -e "\nDispositivos de áudio:"
    if command -v pw-cli >/dev/null 2>&1; then
        pw-cli info 2>/dev/null | head -5
    else
        warn "pw-cli não disponível"
    fi
}

fix_common_issues() {
    log "Aplicando correções comuns..."
    
    # Corrigir contextos de arquivos
    log "Corrigindo contextos de arquivos..."
    
    # Arquivos de sistema importantes
    restorecon -R /etc/selinux/ 2>/dev/null && log "✓ Contextos do SELinux corrigidos" || warn "Falha ao corrigir contextos do SELinux"
    restorecon -R /etc/pipewire/ 2>/dev/null && log "✓ Contextos do PipeWire corrigidos" || warn "Falha ao corrigir contextos do PipeWire"
    
    # Binários importantes
    for binary in sestatus getenforce setenforce semodule seinfo; do
        if command -v $binary >/dev/null 2>&1; then
            binary_path=$(command -v $binary)
            restorecon "$binary_path" 2>/dev/null && log "✓ Contexto de $binary corrigido" || warn "Falha ao corrigir contexto de $binary"
        fi
    done
    
    # Diretórios de usuário
    if [[ -d "$HOME/.config/pipewire" ]]; then
        restorecon -R "$HOME/.config/pipewire" 2>/dev/null && log "✓ Contextos do PipeWire do usuário corrigidos" || warn "Falha ao corrigir contextos do usuário"
    fi
    
    # Recarregar políticas se possível
    if command -v semodule >/dev/null 2>&1; then
        semodule -R 2>/dev/null && log "✓ Políticas recarregadas" || warn "Falha ao recarregar políticas"
    fi
    
    log "✓ Correções aplicadas"
}

analyze_selinux_violations() {
    log "Analisando violações SELinux..."
    
    # Verificar logs de auditoria
    if [[ -f "/var/log/audit/audit.log" ]]; then
        log "Analisando /var/log/audit/audit.log"
        if command -v ausearch >/dev/null 2>&1; then
            ausearch -m avc -ts today 2>/dev/null | head -20
        else
            grep "avc:" /var/log/audit/audit.log | head -10
        fi
    else
        # Verificar journalctl
        log "Analisando journalctl para violações SELinux"
        journalctl -x | grep -i "selinux\|avc" | head -10 2>/dev/null || warn "Nenhuma violação encontrada"
    fi
    
    # Tentar usar sealert se disponível
    if command -v sealert >/dev/null 2>&1; then
        log "Analisando com sealert..."
        sealert -a /var/log/audit/audit.log 2>/dev/null | head -5
    fi
}

auto_fix_policies() {
    log "Tentando correção automática de políticas..."
    
    if command -v audit2allow >/dev/null 2>&1; then
        # Criar política baseada em violações recentes
        if [[ -f "/var/log/audit/audit.log" ]]; then
            audit2allow -i /var/log/audit/audit.log -o /tmp/local_policy.te 2>/dev/null
            if [[ -s "/tmp/local_policy.te" ]]; then
                log "Política gerada:"
                cat /tmp/local_policy.te | head -10
                
                read -r -p "Deseja compilar e instalar esta política? (s/N): " install_policy
                if [[ $install_policy == "s" || $install_policy == "S" ]]; then
                    if command -v checkmodule >/dev/null 2>&1 && command -v semodule_package >/dev/null 2>&1; then
                        checkmodule -M -m -o /tmp/local_policy.mod /tmp/local_policy.te && \
                        semodule_package -o /tmp/local_policy.pp -m /tmp/local_policy.mod && \
                        semodule -i /tmp/local_policy.pp && \
                        log "✓ Política instalada com sucesso" || \
                        warn "Falha ao instalar política"
                    else
                        warn "Ferramentas de compilação não disponíveis"
                    fi
                fi
            else
                warn "Nenhuma violação recente para gerar políticas"
            fi
        else
            warn "Arquivo de auditoria não encontrado"
        fi
    else
        warn "audit2allow não disponível"
    fi
}

show_selinux_status() {
    echo -e "\n${GREEN}=== STATUS DO SELINUX ===${NC}"
    
    # Verificar se está instalado
    if check_selinux_installed; then
        echo "✓ SELinux está instalado"
    else
        echo "✗ SELinux não está instalado"
        return 1
    fi
    
    # Verificar se está ativo
    if check_selinux_active; then
        echo "✓ SELinux está ativo"
    else
        echo "✗ SELinux não está ativo"
        warn "Reinicie o sistema para ativar o SELinux"
    fi
    
    # Mostrar modo atual
    if command -v getenforce >/dev/null 2>&1; then
        echo "Modo atual: $(getenforce 2>/dev/null || echo 'Desconhecido')"
    fi
    
    # Mostrar políticas carregadas
    if command -v seinfo >/dev/null 2>&1; then
        echo -e "\nPolíticas carregadas:"
        seinfo 2>/dev/null | head -5
    fi
    
    # Mostrar configuração
    if [[ -f "/etc/selinux/config" ]]; then
        echo -e "\nConfiguração atual:"
        cat /etc/selinux/config | grep -v "^#" | grep -v "^$"
    fi
}

show_post_menu() {
    echo -e "\n${GREEN}=== PÓS-INSTALAÇÃO SELINUX ===${NC}"
    check_aur_helper
    echo "AUR Helper: ${GREEN}$AUR_HELPER${NC}"
    show_selinux_status | head -10
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
    # Verificações iniciais mais tolerantes
    if ! check_selinux_installed; then
        error "SELinux não parece estar instalado corretamente."
        error "Execute o script de instalação primeiro: sudo ./selinux-arch-installer.sh"
        exit 1
    fi
    
    if ! check_selinux_active; then
        warn "SELinux não está ativo. Algumas funcionalidades podem ser limitadas."
        warn "Reinicie o sistema após a instalação para ativar o SELinux completamente."
        read -r -p "Continuar mesmo assim? (s/N): " continue_anyway
        if [[ $continue_anyway != "s" && $continue_anyway != "S" ]]; then
            exit 1
        fi
    fi
    
    while true; do
        show_post_menu
        read -r choice
        
        case $choice in
            1) check_wayland_pipewire ;;
            2) analyze_selinux_violations ;;
            3) diagnose_wayland_issues ;;
            4) diagnose_pipewire_issues ;;
            5) auto_fix_policies ;;
            6) fix_common_issues ;;
            7) 
                if command -v getenforce >/dev/null 2>&1 && command -v setenforce >/dev/null 2>&1; then
                    echo "Modo atual: $(getenforce 2>/dev/null || echo 'Desconhecido')"
                    echo "1. Permissive (Recomendado para testes)"
                    echo "2. Enforcing (Produção)"
                    read -r -p "Escolha: " mode
                    case $mode in
                        1) setenforce 0 2>/dev/null && log "Modo Permissivo ativado" || error "Falha ao alterar modo" ;;
                        2) setenforce 1 2>/dev/null && log "Modo Enforcing ativado" || error "Falha ao alterar modo" ;;
                        *) warn "Opção inválida" ;;
                    esac
                else
                    warn "Comandos SELinux não disponíveis"
                fi
                ;;
            8) show_selinux_status ;;
            9) 
                log "Saindo..."
                exit 0 
                ;;
            *) 
                error "Opção inválida"
                ;;
        esac
        
        echo -e "\nPressione Enter para continuar..."
        read -r
    done
}

# Executar apenas se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
