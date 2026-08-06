#!/usr/bin/env bash

###############################################################################
#
# Walker Install 3.0
#
# Complete installer for Walker Launcher + Elephant
#
# Author : Nilo Fernandez
# License: MIT
#
###############################################################################

set -Eeuo pipefail

#######################################
# Version
#######################################

VERSION="3.0.0"

#######################################
# Colors
#######################################

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"
RESET="\033[0m"

#######################################
# Variables
#######################################

AUR_HELPER=""
DISTRO=""
DESKTOP=""
SESSION=""
HOME_CONFIG="$HOME/.config/walker"
THEME_DIR="$HOME/.config/walker/themes"
BACKUP_DIR="$HOME/.local/share/walker-install/backups"

#######################################
# Banner
#######################################

banner() {

clear

echo -e "${CYAN}"

cat << "EOF"

██╗    ██╗ █████╗ ██╗     ██╗  ██╗███████╗██████╗
██║    ██║██╔══██╗██║     ██║ ██╔╝██╔════╝██╔══██╗
██║ █╗ ██║███████║██║     █████╔╝ █████╗  ██████╔╝
██║███╗██║██╔══██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗
╚███╔███╔╝██║  ██║███████╗██║  ██╗███████╗██║  ██║
 ╚══╝╚══╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝

EOF

echo -e "${WHITE}"
echo "Walker Install v${VERSION}"
echo

}

#######################################
# Logger
#######################################

info(){

echo -e "${BLUE}▶${RESET} $1"

}

success(){

echo -e "${GREEN}✔${RESET} $1"

}

warning(){

echo -e "${YELLOW}⚠${RESET} $1"

}

error(){

echo -e "${RED}✖${RESET} $1"

}

#######################################
# Exit on Error
#######################################

trap 'error "Erro na linha ${LINENO}"; exit 1' ERR

#######################################
# Spinner
#######################################

spinner(){

local pid=$!
local delay=0.1
local spin='|/-\'

while ps -p $pid &>/dev/null
do

for i in $(seq 0 3)
do
printf "\r${CYAN}[%c]${RESET}" "${spin:$i:1}"
sleep $delay
done

done

printf "\r"

}

#######################################
# Internet
#######################################

check_internet(){

info "Verificando internet..."

if ping -c1 archlinux.org &>/dev/null
then
success "Internet OK"
else
error "Sem conexão com a internet."
exit 1
fi

}

#######################################
# Detect Distro
#######################################

detect_distro(){

DISTRO=$(grep "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"')

if [[ "$DISTRO" != "arch" ]]

then

error "Este script suporta apenas Arch Linux."

exit 1

fi

success "Arch Linux detectado"

}

#######################################
# Detect Desktop
#######################################

detect_desktop(){

DESKTOP="${XDG_CURRENT_DESKTOP:-Unknown}"

success "Desktop: ${DESKTOP}"

}

#######################################
# Detect Session
#######################################

detect_session(){

SESSION="${XDG_SESSION_TYPE:-unknown}"

if [[ "$SESSION" != "wayland" ]]
then

warning "Você não está utilizando Wayland."

else

success "Wayland detectado."

fi

}

#######################################
# Detect AUR Helper
#######################################

detect_aur(){

if command -v paru &>/dev/null
then

AUR_HELPER="paru"

elif command -v yay &>/dev/null
then

AUR_HELPER="yay"

else

error "Paru ou Yay não encontrados."

exit 1

fi

success "Helper encontrado: ${AUR_HELPER}"

}

#######################################
# Backup
#######################################

backup(){

mkdir -p "$BACKUP_DIR"

if [[ -d "$HOME_CONFIG" ]]
then

info "Criando backup..."

cp -r "$HOME_CONFIG" \
"$BACKUP_DIR/walker-$(date +%F-%H%M%S)"

success "Backup criado."

fi

}

#######################################
# Create folders
#######################################

create_directories(){

mkdir -p "$HOME_CONFIG"

mkdir -p "$THEME_DIR"

}

#######################################
# Check Package
#######################################

package_installed() {

    pacman -Qi "$1" &>/dev/null

}

#######################################
# Install Packages
#######################################

install_packages() {

    info "Sincronizando repositórios..."
    sudo pacman -Sy --noconfirm

    # Pacotes principais
    local core_packages=("walker" "elephant")
    local missing_core=()

    info "Instalando pacotes principais (Walker e Elephant)..."
    for pkg in "${core_packages[@]}"; do
        if package_installed "$pkg"; then
            success "$pkg já instalado."
        else
            missing_core+=("$pkg")
        fi
    done

    if [[ ${#missing_core[@]} -gt 0 ]]; then
        "$AUR_HELPER" -S --needed --noconfirm "${missing_core[@]}" &
        spinner
        echo
    fi

    # Provedores (instalação individual para evitar falhas em massa)
    info "Instalando provedores Elephant..."
    local providers=(
        "elephant-providerlist"
        "elephant-desktopapplications"
        "elephant-files"
        "elephant-runner"
        "elephant-calc"
        "elephant-websearch"
        "elephant-clipboard"
        "elephant-menus"
        "elephant-symbols"
    )

    for pkg in "${providers[@]}"; do
        if package_installed "$pkg"; then
            success "$pkg já instalado."
        else
            info "Tentando instalar $pkg..."
            if "$AUR_HELPER" -S --needed --noconfirm "$pkg" &>/dev/null; then
                success "$pkg instalado."
            else
                warning "Falha ao instalar $pkg. Pulando..."
            fi
        fi
    done

    echo
    success "Processo de instalação concluído."

}

#######################################
# Elephant Service
#######################################

enable_elephant() {
    info "Iniciando Elephant como daemon..."
    # Mata qualquer instância antiga primeiro
    pkill elephant 2>/dev/null || true
    sleep 1
    # Inicia o serviço em segundo plano
    elephant --daemon &
    sleep 2
    success "Elephant iniciado."
}

#######################################
# Update Index
#######################################

update_index() {
    info "Atualizando índice..."
    elephant update
    success "Índice atualizado."
}

#######################################
# Verify Elephant
#######################################

verify_elephant() {
    info "Verificando Elephant..."
    if pgrep -x "elephant" &>/dev/null; then
        success "Elephant está em execução."
    else
        warning "Elephant não está em execução. Tente iniciar manualmente com 'elephant --daemon'."
    fi
}

#######################################
# Verify Walker
#######################################

verify_walker() {

    info "Verificando Walker..."

    if command -v walker &>/dev/null
    then

        success "Walker instalado."

    else

        error "Walker não encontrado."

        exit 1

    fi

}

#######################################
# Install Theme
#######################################

install_theme() {

    info "Criando diretórios do tema..."

    mkdir -p "$THEME_DIR"

    mkdir -p "$THEME_DIR/glass-premium"

    success "Diretórios criados."

}

#######################################
# Install Config
#######################################

install_config() {

    info "Criando configuração..."

    mkdir -p "$HOME_CONFIG"

    touch "$HOME_CONFIG/config.toml"

    success "Configuração criada."

}

#######################################
# Autostart
#######################################

create_autostart() {

    info "Configurando Autostart..."

    mkdir -p "$HOME/.config/autostart"

cat > "$HOME/.config/autostart/walker.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Walker
Comment=Application launcher
Exec=env GDK_BACKEND=wayland walker --service
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

    success "Autostart criado."

}

#######################################
# Repair
#######################################

repair_installation() {

    info "Reparando instalação..."

    install_packages

    enable_elephant

    update_index

    generate_config

    generate_theme

    create_autostart

    verify_installation

}

#######################################
# Update
#######################################

update_installation() {

    info "Atualizando Walker..."

    "$AUR_HELPER" -Syu --noconfirm

    update_index

    success "Atualização concluída."

}

#######################################
# Remove
#######################################

remove_installation() {

    warning "Removendo Walker..."

    "$AUR_HELPER" -Rns --noconfirm \
        walker \
        elephant \
        elephant-providerlist \
        elephant-desktopapplications \
        elephant-files \
        elephant-runner \
        elephant-calc \
        elephant-websearch \
        elephant-clipboard \
        elephant-symbols \
        elephant-menus || true

    rm -rf "$HOME_CONFIG"

    rm -f "$HOME/.config/autostart/walker.desktop"

    success "Walker removido."

}

#######################################
# Verify Installation
#######################################

verify_installation() {

    verify_walker

    verify_elephant

}

#######################################
# Doctor
#######################################

doctor() {

    echo
    echo "──────────────────────────────────────────────"
    echo " Walker Doctor"
    echo "──────────────────────────────────────────────"
    echo

    command -v walker >/dev/null \
        && success "Walker instalado." \
        || error "Walker não encontrado."

    command -v elephant >/dev/null \
        && success "Elephant instalado." \
        || error "Elephant não encontrado."

    pgrep -x "elephant" &>/dev/null \
        && success "Elephant Service ativo." \
        || warning "Elephant Service parado."

    [[ -f "$HOME_CONFIG/config.toml" ]] \
        && success "Configuração encontrada." \
        || warning "Configuração ausente."

    [[ -d "$THEME_DIR/glass-premium" ]] \
        && success "Tema instalado." \
        || warning "Tema não encontrado."

    [[ -f "$HOME/.config/autostart/walker.desktop" ]] \
        && success "Autostart configurado." \
        || warning "Autostart ausente."

    echo

}

#######################################
# Benchmark
#######################################

benchmark() {

    info "Executando Benchmark..."

    local start
    local end

    start=$(date +%s%N)

    walker --gapplication-service >/dev/null 2>&1 &
    sleep 2
    pkill walker || true

    end=$(date +%s%N)

    local elapsed=$(( (end-start)/1000000 ))

    success "Tempo de inicialização: ${elapsed} ms"

}

#######################################
# Create Config
#######################################

generate_config() {

info "Gerando config.toml otimizado..."

cat > "$HOME_CONFIG/config.toml" << 'EOF'
# Configuração gerada pelo Walker Install Script

[walker]
# Tema a ser usado
theme = "glass-premium"

# Comportamento da janela
[walker.window]
width = 700
height = 550

[gtk]
# Nome do tema GTK (se quiser herdar do sistema, deixe vazio)
theme_name = ""

# Configuração dos provedores
[providers]
# Provedores ativos por padrão
default = [
    "desktopapplications",
    "files",
    "runner",
    "calc",
    "websearch",
    "clipboard",
    "symbols",
]
# Provedor usado quando a pesquisa está vazia
empty = ["desktopapplications"]

# Prefixos para ativação rápida
[providers.prefixes]
files = "/"
runner = ">"
calc = "="
websearch = "?"
clipboard = ":"
symbols = ";"

# Atalhos de teclado (opcional)
[keybindings]
toggle = ["<Super>space"]
quit = ["<Ctrl>q"]
EOF

success "Configuração criada."

}

#######################################
# Generate Theme
#######################################

generate_theme() {

info "Criando tema Glass Premium..."

mkdir -p "$THEME_DIR/glass-premium"

cat > "$THEME_DIR/glass-premium/style.css" << 'EOF'
/*
Glass Premium
Walker Install 3.0
Tema atualizado para GTK4
*/

window {
    background: transparent;
}

.box-wrapper {
    background: rgba(30, 30, 40, 0.85);
    border-radius: 18px;
    padding: 18px;
    border: 1px solid rgba(255, 255, 255, 0.1);
    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);
}

.input {
    padding: 12px;
    border-radius: 10px;
    background: rgba(255, 255, 255, 0.05);
    color: #f2ecbc;
}

.item-box {
    padding: 10px;
    border-radius: 10px;
    transition: all 150ms ease;
}

child:selected .item-box,
child:hover .item-box {
    background: rgba(255, 255, 255, 0.1);
}

.item-image {
    margin-right: 10px;
}

.list {
    background: transparent;
}

.preview {
    padding: 12px;
    border-radius: 10px;
    border: 1px solid rgba(255, 255, 255, 0.1);
}

scrollbar {
    opacity: 0;
}
EOF

success "Tema criado."

}

#######################################
# INSTALL
#######################################

install() {

banner

backup

create_directories

install_packages

enable_elephant

update_index

generate_config

generate_theme

create_autostart

verify_installation

echo

success "Walker instalado com sucesso."

echo

echo "Abra utilizando Super + Espaço."

}

#######################################
# Help
#######################################

usage() {

cat << EOF

Walker Install ${VERSION}

Uso:

    $0 install
    $0 update
    $0 repair
    $0 doctor
    $0 benchmark
    $0 remove

Opções:

    --help

EOF

}

#######################################
# Main
#######################################

main() {

    detect_distro

    detect_desktop

    detect_session

    detect_aur

    check_internet

    case "${1:-install}" in

        install)

            install
            ;;

        update)

            update_installation
            ;;

        repair)

            repair_installation
            ;;

        doctor)

            doctor
            ;;

        benchmark)

            benchmark
            ;;

        remove)

            remove_installation
            ;;

        --help|-h)

            usage
            ;;

        *)

            usage
            exit 1
            ;;

    esac

}

#######################################
# Run
#######################################

main "$@"