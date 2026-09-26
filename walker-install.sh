#!/usr/bin/env bash
# =====================================================================
#  Walker + Elephant no Arch Linux (GNOME) com visual estilo Spotlight
#
#  Uso:   bash walker-spotlight.sh
#  Opções (variáveis de ambiente, todas opcionais):
#    TEMA_COR=claro            tema claro (padrão: escuro)
#    KEYBIND='<Super>space'    atalho para abrir o Walker
#    CENTRALIZAR_JANELAS=0     não ativar "centralizar novas janelas" no GNOME
#
#  Exemplo: TEMA_COR=claro KEYBIND='<Control>space' bash walker-spotlight.sh
#  Não rode como root: o script pede sudo só quando precisa.
# =====================================================================

set -Eeuo pipefail

# ---------------------------------------------------------------------
# Opções
# ---------------------------------------------------------------------
TEMA_COR="${TEMA_COR:-escuro}"
KEYBIND="${KEYBIND:-<Super>space}"
CENTRALIZAR_JANELAS="${CENTRALIZAR_JANELAS:-1}"

# Repositórios oficiais: fd (busca de arquivos), qalc (calculadora), fonte Inter
PACOTES_REPO=(fd libqalculate inter-font)

# AUR: Walker + backend Elephant e os provedores que o config realmente usa
PACOTES_AUR=(
  walker
  elephant
  elephant-desktopapplications
  elephant-files
  elephant-calc
  elephant-runner
  elephant-websearch
  elephant-providerlist
)

CFG="$HOME/.config/walker"
TEMA="spotlight"
SYSTEMD_USER="$HOME/.config/systemd/user"
BACKUP="$HOME/.config/walker-backup-$(date +%Y%m%d-%H%M%S)"

# ---------------------------------------------------------------------
# Saída formatada e tratamento de erro
# ---------------------------------------------------------------------
azul=$'\e[1;34m'; verde=$'\e[32m'; amarelo=$'\e[33m'; vermelho=$'\e[31m'; reset=$'\e[0m'
passo() { printf '\n%s[%s]%s %s\n' "$azul" "$1" "$reset" "$2"; }
ok()    { printf '%s  ✔ %s%s\n' "$verde" "$1" "$reset"; }
aviso() { printf '%s  ! %s%s\n' "$amarelo" "$1" "$reset"; }
erro()  { printf '%s  ✖ %s%s\n' "$vermelho" "$1" "$reset" >&2; exit 1; }
trap 'erro "Falhou na linha $LINENO: $BASH_COMMAND"' ERR

printf '%s=======================================================%s\n' "$azul" "$reset"
printf '%s  Walker + Elephant | tema Spotlight (%s)%s\n' "$azul" "$TEMA_COR" "$reset"
printf '%s=======================================================%s\n' "$azul" "$reset"

# ---------------------------------------------------------------------
# 1. Verificações
# ---------------------------------------------------------------------
passo 1/7 "Verificando o sistema"

(( EUID != 0 ))           || erro "Não rode como root."
[[ -f /etc/arch-release ]] || erro "Este script é para Arch Linux."
[[ $TEMA_COR == escuro || $TEMA_COR == claro ]] || erro "TEMA_COR deve ser 'escuro' ou 'claro'."

if   command -v paru >/dev/null; then AUR=paru
elif command -v yay  >/dev/null; then AUR=yay
else erro "Nenhum helper AUR encontrado. Instale o paru ou o yay."
fi
ok "Helper AUR: $AUR"

GNOME=0
[[ ${XDG_CURRENT_DESKTOP:-} == *GNOME* ]] && GNOME=1
(( GNOME )) && ok "GNOME detectado" || aviso "GNOME não detectado: atalho de teclado não será criado"
[[ ${XDG_SESSION_TYPE:-} == wayland ]] && ok "Sessão Wayland" || aviso "Sessão não é Wayland (${XDG_SESSION_TYPE:-desconhecida})"

# ---------------------------------------------------------------------
# 2. Pacotes
# ---------------------------------------------------------------------
passo 2/7 "Instalando pacotes"

sudo pacman -S --needed --noconfirm "${PACOTES_REPO[@]}"
# Sem --noconfirm no AUR de propósito: você revisa o PKGBUILD antes de compilar
"$AUR" -S --needed "${PACOTES_AUR[@]}"

command -v walker   >/dev/null || erro "walker não ficou instalado."
command -v elephant >/dev/null || erro "elephant não ficou instalado."
WALKER_BIN="$(command -v walker)"
ok "Pacotes prontos"

# ---------------------------------------------------------------------
# 3. Backup + config do Walker
# ---------------------------------------------------------------------
passo 3/7 "Criando configuração"

if [[ -d $CFG ]]; then
  cp -a "$CFG" "$BACKUP"
  ok "Config anterior salva em $BACKUP"
fi
mkdir -p "$CFG/themes/$TEMA"

cat > "$CFG/config.toml" <<EOF
# Walker | configuração estilo Spotlight
theme = "$TEMA"

force_keyboard_focus = true    # já abre pronto para digitar
close_when_open      = true    # atalho abre e fecha (toggle), igual ao Spotlight
click_to_close       = true    # clicar fora fecha
selection_wrap       = true    # seta para baixo no último item volta ao topo
hide_quick_activation = true   # visual limpo, sem números ao lado dos itens
hide_action_hints     = true   # sem barra de atalhos no rodapé

[placeholders]
"default" = { input = "Buscar", list = "Nenhum resultado" }

[providers]
# O que aparece ao digitar sem prefixo: apps, conta rápida e busca na web
default     = ["desktopapplications", "calc", "websearch"]
empty       = ["desktopapplications"]
max_results = 12
# Sem painel de pré-visualização: ele alarga a janela e tira do centro no GNOME
ignore_preview = ["files", "clipboard"]

# Prefixos (digite o símbolo antes do texto)
[[providers.prefixes]]
prefix   = "/"
provider = "files"

[[providers.prefixes]]
prefix   = ">"
provider = "runner"

[[providers.prefixes]]
prefix   = "="
provider = "calc"

[[providers.prefixes]]
prefix   = "?"
provider = "websearch"

[[providers.prefixes]]
prefix   = ";"
provider = "providerlist"
EOF
ok "config.toml criado"

# ---------------------------------------------------------------------
# 4. Tema Spotlight
# ---------------------------------------------------------------------
passo 4/7 "Criando tema Spotlight ($TEMA_COR)"

if [[ $TEMA_COR == escuro ]]; then
  BG='rgba(30, 30, 32, 0.82)';    FG='#f5f5f7'; MUTED='rgba(245, 245, 247, 0.50)'
  LINE='rgba(255, 255, 255, 0.08)'; BORDER='rgba(255, 255, 255, 0.12)'
else
  BG='rgba(246, 246, 248, 0.86)'; FG='#1d1d1f'; MUTED='rgba(29, 29, 31, 0.50)'
  LINE='rgba(0, 0, 0, 0.08)';     BORDER='rgba(255, 255, 255, 0.70)'
fi

cat > "$CFG/themes/$TEMA/style.css" <<EOF
/* Walker | tema Spotlight ($TEMA_COR) */

@define-color sp_bg     $BG;
@define-color sp_fg     $FG;
@define-color sp_muted  $MUTED;
@define-color sp_line   $LINE;
@define-color sp_border $BORDER;
@define-color sp_accent #0a84ff;

* {
  all: unset;
  font-family: "Inter", "SF Pro Display", "Cantarell", sans-serif;
}

/* Janela invisível: só o cartão aparece */
window {
  background: transparent;
}

/* Cartão principal */
.box-wrapper {
  min-width: 680px;
  margin: 28px;                 /* espaço para a sombra não ser cortada */
  padding: 10px;
  border-radius: 18px;
  background: @sp_bg;
  border: 1px solid @sp_border;
  box-shadow:
    0 22px 60px rgba(0, 0, 0, 0.35),
    0 0 0 0.5px rgba(0, 0, 0, 0.30);
}

/* Campo de busca grande, como no macOS */
.input {
  min-height: 44px;
  padding: 4px 12px;
  font-size: 22px;
  font-weight: 300;
  color: @sp_fg;
  caret-color: @sp_accent;
}

.input placeholder {
  color: @sp_muted;
}

/* Resultados separados por uma linha fina */
.list {
  margin-top: 6px;
  padding-top: 6px;
  border-top: 1px solid @sp_line;
  color: @sp_fg;
}

.item-box {
  padding: 7px 10px;
  border-radius: 9px;
}

child:hover .item-box {
  background: alpha(@sp_accent, 0.15);
}

/* Item selecionado em azul, texto branco */
child:selected .item-box {
  background: @sp_accent;
}

child:selected .item-text {
  color: #ffffff;
}

child:selected .item-subtext {
  color: rgba(255, 255, 255, 0.75);
}

.item-text {
  font-size: 15px;
}

.item-subtext {
  font-size: 12px;
  color: @sp_muted;
}

.item-image,
.item-image-text {
  margin-right: 12px;
}

.large-icons  { -gtk-icon-size: 32px; }
.normal-icons { -gtk-icon-size: 20px; }

.placeholder,
.elephant-hint {
  padding: 10px;
  font-size: 14px;
  color: @sp_muted;
}

.preview {
  margin-left: 10px;
  padding: 10px;
  border-radius: 10px;
  border: 1px solid @sp_line;
  color: @sp_fg;
}

.error {
  padding: 10px;
  border-radius: 8px;
  background: #c34043;
  color: #ffffff;
}

scrollbar {
  opacity: 0;
}
EOF
ok "Tema criado em $CFG/themes/$TEMA"

# ---------------------------------------------------------------------
# 5. Serviços (Elephant + Walker via systemd do usuário)
# ---------------------------------------------------------------------
passo 5/7 "Configurando serviços"

# Elephant: o próprio binário gera e habilita a unit
elephant service enable
systemctl --user daemon-reload
systemctl --user restart elephant.service
ok "Elephant ativo"

# Walker residente em memória: abre instantâneo e reinicia sozinho se cair
mkdir -p "$SYSTEMD_USER"
cat > "$SYSTEMD_USER/walker.service" <<EOF
[Unit]
Description=Walker launcher (modo serviço)
PartOf=graphical-session.target
After=graphical-session.target elephant.service
Wants=elephant.service

[Service]
Type=simple
ExecStart=$WALKER_BIN --gapplication-service
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
EOF

# Remove o autostart antigo (do script anterior) para não rodar duplicado
rm -f "$HOME/.config/autostart/walker.desktop"

systemctl --user daemon-reload
systemctl --user enable walker.service >/dev/null
systemctl --user restart walker.service
ok "Walker ativo como serviço"

# ---------------------------------------------------------------------
# 6. Atalho de teclado e ajustes do GNOME
# ---------------------------------------------------------------------
passo 6/7 "Atalho de teclado"

if (( GNOME )); then
  SCHEMA=org.gnome.settings-daemon.plugins.media-keys
  KPATH=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/walker/

  # Acrescenta o atalho preservando os que você já tem
  atuais="$(gsettings get "$SCHEMA" custom-keybindings)"
  if [[ $atuais != *"$KPATH"* ]]; then
    if [[ $atuais == "@as []" || $atuais == "[]" ]]; then
      novo="['$KPATH']"
    else
      novo="${atuais%]}, '$KPATH']"
    fi
    gsettings set "$SCHEMA" custom-keybindings "$novo"
  fi

  gsettings set "$SCHEMA.custom-keybinding:$KPATH" name    'Walker'
  gsettings set "$SCHEMA.custom-keybinding:$KPATH" command 'walker'
  gsettings set "$SCHEMA.custom-keybinding:$KPATH" binding "$KEYBIND"

  # No GNOME, Super+Espaço troca o layout do teclado por padrão. Liberamos.
  if [[ $KEYBIND == "<Super>space" ]]; then
    gsettings set org.gnome.desktop.wm.keybindings switch-input-source          "['XF86Keyboard']"
    gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "['<Shift>XF86Keyboard']"
    aviso "Super+Espaço deixou de trocar o layout do teclado"
  fi
  ok "Atalho $KEYBIND configurado"

  # O GNOME não centraliza janelas novas por padrão; o Spotlight aparece no centro
  if [[ $CENTRALIZAR_JANELAS == 1 ]]; then
    gsettings set org.gnome.mutter center-new-windows true
    ok "Novas janelas abrem centralizadas (vale para todos os apps)"
  fi
else
  aviso "Crie o atalho manualmente no seu ambiente com o comando: walker"
fi

# ---------------------------------------------------------------------
# 7. Conferência final
# ---------------------------------------------------------------------
passo 7/7 "Conferindo"

falhou=0
for s in elephant walker; do
  if systemctl --user is-active --quiet "$s.service"; then
    ok "$s rodando"
  else
    aviso "$s não está ativo. Veja: journalctl --user -u $s -e"
    falhou=1
  fi
done

echo
if (( falhou )); then
  printf '%sInstalação terminou com avisos. Confira os logs acima.%s\n' "$amarelo" "$reset"
else
  printf '%s=======================================================%s\n' "$verde" "$reset"
  printf '%s  Pronto! Aperte %s para abrir.%s\n' "$verde" "$KEYBIND" "$reset"
  printf '%s=======================================================%s\n' "$verde" "$reset"
fi
cat <<'EOF'

  Dicas de uso:
    digite normal   apps, conta e busca na web
    /texto          arquivos
    =2+2            calculadora
    >comando        rodar comando
    ?texto          buscar na web
    ;               listar todos os provedores
EOF
