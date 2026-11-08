#!/usr/bin/env bash
# ------------------------------------------------------------------
# instalar-claude-arch.sh
# Instala o Claude no Arch Linux:
#   1) Claude Code (CLI oficial)
#   2) Claude Desktop (empacotando o .deb oficial com PKGBUILD, NAO oficial)
#   3) Dependencias do Cowork (QEMU, OVMF, virtiofsd, KVM, vhost_vsock)
#   4) Tudo
#   5) Atualizar o Claude Desktop
#
# Uso:  chmod +x instalar-claude-arch.sh && ./instalar-claude-arch.sh
# Rode como usuario normal (o script pede sudo quando precisar).
# ------------------------------------------------------------------
set -euo pipefail

REPO="https://downloads.claude.ai/claude-desktop/apt/stable"
VERDE="\e[32m"; AMARELO="\e[33m"; VERMELHO="\e[31m"; AZUL="\e[34m"; FIM="\e[0m"

info()  { echo -e "${AZUL}==>${FIM} $*"; }
ok()    { echo -e "${VERDE}[ok]${FIM} $*"; }
aviso() { echo -e "${AMARELO}[aviso]${FIM} $*"; }
erro()  { echo -e "${VERMELHO}[erro]${FIM} $*" >&2; exit 1; }

# ---------------- checagens iniciais ----------------
checar_sistema() {
  [[ $EUID -eq 0 ]] && erro "Nao rode como root. Use seu usuario normal."
  command -v pacman >/dev/null || erro "Este script e para Arch Linux (pacman nao encontrado)."
  case "$(uname -m)" in
    x86_64)  DEB_ARCH="amd64" ;;
    aarch64) DEB_ARCH="arm64" ;;
    *) erro "Arquitetura $(uname -m) nao suportada." ;;
  esac
  sudo -v || erro "Precisa de sudo."
  sudo pacman -S --needed --noconfirm curl git base-devel >/dev/null
}

# ---------------- 1) Claude Code CLI ----------------
instalar_cli() {
  info "Instalando o Claude Code (CLI oficial)..."
  curl -fsSL https://claude.ai/install.sh | bash

  # garante ~/.local/bin no PATH (bash e zsh)
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [[ -f "$rc" ]] || continue
    if ! grep -q 'HOME/.local/bin' "$rc"; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc"
      ok "PATH ajustado em $rc"
    fi
  done
  ok "CLI instalado. Abra um terminal novo e rode: claude"
}

# ---------------- 2) Claude Desktop (PKGBUILD a partir do .deb) ----------------
instalar_desktop() {
  aviso "O app desktop NAO tem suporte oficial no Arch. Isso empacota o .deb oficial."

  info "Instalando dependencias do app..."
  sudo pacman -S --needed --noconfirm gtk3 nss alsa-lib libsecret gnome-keyring xdg-utils libnotify

  info "Buscando a versao mais recente do .deb..."
  local caminho
  caminho="$(curl -fsSL "$REPO/dists/stable/main/binary-$DEB_ARCH/Packages" \
    | grep '^Filename: pool/main/c/claude-desktop/claude-desktop_' \
    | sort -V | tail -n 1 | cut -d' ' -f2)"
  [[ -n "$caminho" ]] || erro "Nao achei o pacote no repositorio. Verifique sua conexao."

  local versao_deb; versao_deb="$(basename "$caminho" | cut -d_ -f2)"
  local versao_nova; versao_nova="$(echo "$versao_deb" | tr -- '-~:' '___')"
  local versao_atual; versao_atual="$(pacman -Q claude-desktop 2>/dev/null | awk '{print $2}' || true)"
  if [[ -n "$versao_atual" && "${versao_atual%-*}" == "$versao_nova" ]]; then
    ok "Voce ja esta na versao mais recente ($versao_nova)."
    return 0
  fi

  local tmp; tmp="$(mktemp -d)"

  info "Baixando claude-desktop $versao_deb..."
  (cd "$tmp" && curl -fLo claude-desktop.deb "$REPO/$caminho")

  info "Montando o pacote do Arch..."
  cat > "$tmp/PKGBUILD" <<EOF
pkgname=claude-desktop
pkgver=$versao_nova
pkgrel=1
pkgdesc="Claude Desktop (empacotado do .deb oficial da Anthropic)"
arch=('$(uname -m)')
url="https://claude.ai"
license=('custom')
depends=('gtk3' 'nss' 'alsa-lib' 'libsecret' 'xdg-utils' 'libnotify')
optdepends=('qemu-system-x86: Cowork' 'edk2-ovmf: Cowork' 'virtiofsd: Cowork')
options=('!strip' '!debug')
source=("claude-desktop.deb")
sha256sums=('SKIP')

package() {
  bsdtar -xpf data.tar.* -C "\$pkgdir"
  # nao precisamos de repositorio apt no Arch
  rm -rf "\$pkgdir/etc/apt"
  # sandbox do Electron precisa de setuid
  find "\$pkgdir" -name chrome-sandbox -exec chmod 4755 {} +
}
EOF

  if ! (cd "$tmp" && makepkg -si --noconfirm); then
    rm -rf "$tmp"
    erro "Falha ao montar ou instalar o pacote."
  fi
  rm -rf "$tmp"
  ok "Claude Desktop $versao_deb instalado. Abra pelo menu do GNOME ou rode: claude-desktop"
}

# ---------------- 3) Cowork ----------------
instalar_cowork() {
  info "Verificando virtualizacao no processador..."
  if grep -Eq 'svm|vmx' /proc/cpuinfo; then
    ok "Virtualizacao disponivel."
  else
    aviso "Virtualizacao nao detectada. Ligue AMD-V/SVM (ou VT-x) na BIOS do notebook."
  fi

  info "Instalando QEMU, OVMF e virtiofsd..."
  if [[ "$DEB_ARCH" == "amd64" ]]; then
    sudo pacman -S --needed --noconfirm qemu-system-x86 qemu-img edk2-ovmf virtiofsd
  else
    sudo pacman -S --needed --noconfirm qemu-system-aarch64 qemu-img edk2-aarch64 virtiofsd
  fi

  # Links de compatibilidade com os caminhos que o Debian usa
  if [[ "$DEB_ARCH" == "amd64" && ! -e /usr/share/OVMF ]]; then
    sudo mkdir -p /usr/share/OVMF
    for f in /usr/share/edk2/x64/OVMF_CODE.4m.fd:OVMF_CODE_4M.fd \
             /usr/share/edk2/x64/OVMF_VARS.4m.fd:OVMF_VARS_4M.fd \
             /usr/share/edk2/x64/OVMF_CODE.4m.fd:OVMF_CODE.fd \
             /usr/share/edk2/x64/OVMF_VARS.4m.fd:OVMF_VARS.fd; do
      src="${f%%:*}"; dst="/usr/share/OVMF/${f##*:}"
      [[ -e "$src" ]] && sudo ln -sf "$src" "$dst"
    done
    ok "Links de OVMF criados em /usr/share/OVMF"
  fi
  if [[ ! -e /usr/libexec/virtiofsd && -e /usr/lib/virtiofsd ]]; then
    sudo mkdir -p /usr/libexec
    sudo ln -sf /usr/lib/virtiofsd /usr/libexec/virtiofsd
    ok "Link do virtiofsd criado em /usr/libexec"
  fi

  info "Adicionando $USER ao grupo kvm..."
  sudo usermod -aG kvm "$USER"

  info "Carregando o modulo vhost_vsock (agora e em todo boot)..."
  sudo modprobe vhost_vsock || aviso "Nao consegui carregar vhost_vsock agora. Reinicie e tente de novo."
  echo vhost_vsock | sudo tee /etc/modules-load.d/vhost_vsock.conf >/dev/null

  ok "Cowork preparado. IMPORTANTE: saia da sessao e entre de novo (ou reinicie) para o grupo kvm valer."
}

# ---------------- menu ----------------
menu() {
  echo
  echo -e "${AZUL}Instalador do Claude para Arch Linux${FIM}"
  echo "  1) Claude Code (CLI oficial)"
  echo "  2) Claude Desktop (nao oficial)"
  echo "  3) Dependencias do Cowork"
  echo "  4) Tudo (1 + 2 + 3)"
  echo "  5) Atualizar o Claude Desktop"
  echo "  0) Sair"
  read -rp "Escolha: " op
  case "$op" in
    1) instalar_cli ;;
    2) instalar_desktop ;;
    3) instalar_cowork ;;
    4) instalar_cli; instalar_desktop; instalar_cowork ;;
    5) instalar_desktop ;;
    0) exit 0 ;;
    *) aviso "Opcao invalida."; menu ;;
  esac
}

checar_sistema
menu
echo
ok "Pronto!"
