#!/bin/bash
# =====================================================================
#  Pós-instalação Arch Linux
#  Uso:  ./pos-instalacao-arch.sh          (abre o menu)
#        ./pos-instalacao-arch.sh 1 3      (roda direto as opções 1 e 3)
#  Opções: 1 GNOME AMD Notebook | 2 Zsh | 3 Fontes GNOME | 4 Samba
#  Rodar como usuário normal (NÃO como root). O script pede sudo quando precisa.
# =====================================================================

# ---------------------------------------------------------------------
# Cores e visual
# ---------------------------------------------------------------------
if [[ -t 1 ]]; then
  R=$'\e[0m'; B=$'\e[1m'; D=$'\e[2m'
  AZUL=$'\e[38;5;39m'; CIANO=$'\e[38;5;51m'; VERDE=$'\e[38;5;42m'
  AMARELO=$'\e[38;5;220m'; VERMELHO=$'\e[38;5;196m'; CINZA=$'\e[38;5;245m'
else
  R='' B='' D='' AZUL='' CIANO='' VERDE='' AMARELO='' VERMELHO='' CINZA=''
fi

titulo() { echo; echo "${B}${AZUL}━━━ $* ${R}"; }
passo()  { echo "${CIANO}  ›${R} $*"; }
ok()     { echo "${VERDE}  ✔${R} $*"; }
aviso()  { echo "${AMARELO}  !${R} $*"; }
erro()   { echo "${VERMELHO}  ✖${R} $*" >&2; }

# ---------------------------------------------------------------------
# Verificações iniciais
# ---------------------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
  erro "Não rode este script como root. Use seu usuário normal."
  erro "O makepkg (Paru) e a configuração do Zsh precisam do seu usuário."
  exit 1
fi

if ! command -v pacman &>/dev/null; then
  erro "Este script é só para Arch Linux."
  exit 1
fi

# Pede a senha uma vez e mantém o sudo ativo enquanto o script estiver aberto
iniciar_sudo() {
  echo "${CINZA}Digite sua senha para liberar o sudo durante a instalação:${R}"
  sudo -v || { erro "Não foi possível obter sudo."; exit 1; }
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
  SUDO_PID=$!
  trap 'kill "$SUDO_PID" 2>/dev/null' EXIT
}

# Guarda cópia de segurança antes de editar qualquer arquivo
backup() {
  local arquivo="$1"
  if [[ -f "$arquivo" ]]; then
    sudo cp -a "$arquivo" "${arquivo}.bak-$(date +%Y%m%d-%H%M%S)"
  fi
}

backup_usuario() {
  local arquivo="$1"
  if [[ -f "$arquivo" ]]; then
    cp -a "$arquivo" "${arquivo}.bak-$(date +%Y%m%d-%H%M%S)"
  fi
}

# Verifica internet antes de cada opção (todas baixam pacotes)
checar_internet() {
  if ! curl -fsS --max-time 8 -o /dev/null https://archlinux.org; then
    erro "Sem conexão com a internet. Conecte e tente de novo."
    return 1
  fi
}

# =====================================================================
#  OPÇÃO 1 - GNOME AMD NOTEBOOK (pós-instalação completa)
# =====================================================================
opcao_gnome_amd_notebook() {

  titulo "1. Atualizando o sistema"
  sudo pacman -Syu --noconfirm

  titulo "2. Pacotes oficiais"
  passo "Ferramentas básicas..."
  sudo pacman -S --needed --noconfirm \
    git zsh curl systemd-ukify pacman-contrib \
    file-roller p7zip unrar unzip \
    fwupd mesa-utils ibus base-devel

  passo "Mídia e multimídia..."
  sudo pacman -S --needed --noconfirm \
    ffmpeg \
    gstreamer gst-plugins-base gst-plugins-good \
    gst-plugins-bad gst-plugins-ugly gst-libav \
    libdvdread libdvdnav libdvdcss \
    ffmpegthumbnailer

  passo "Fontes..."
  sudo pacman -S --needed --noconfirm \
    ttf-firacode-nerd ttf-dejavu-nerd ttf-hack-nerd \
    inter-font noto-fonts noto-fonts-emoji \
    ttf-opensans ttf-roboto noto-fonts-cjk

  passo "Outros..."
  sudo pacman -S --needed --noconfirm \
    gufw thunderbird-i18n-pt-br playerctl \
    expac fastfetch power-profiles-daemon \
    plymouth speedtest-cli \
    bluez bluez-utils zram-generator

  passo "Ferramentas de backup..."
  sudo pacman -S --needed --noconfirm \
    btrfs-assistant btrfsmaintenance snapper

  passo "Jellyfin..."
  sudo pacman -S --needed --noconfirm \
    jellyfin-ffmpeg jellyfin-server jellyfin-web

  titulo "3. Paru e pacotes do AUR"
  if ! command -v paru &>/dev/null; then
    passo "Instalando Paru..."
    rm -rf /tmp/paru
    git clone --depth 1 https://aur.archlinux.org/paru.git /tmp/paru
    (cd /tmp/paru && makepkg -si --noconfirm)
    rm -rf /tmp/paru
  else
    ok "Paru já está instalado."
  fi

  passo "Pacotes do AUR..."
  paru -S --needed --noconfirm \
    google-chrome phinger-cursors ttf-ms-fonts

  titulo "4. Serviços"
  sudo systemctl enable --now fwupd-refresh.timer
  sudo systemctl enable --now bluetooth.service
  sudo systemctl enable --now power-profiles-daemon
  sudo systemctl enable --now systemd-oomd
  sudo systemctl enable --now jellyfin.service
  ok "Serviços ativos. Jellyfin disponível em http://localhost:8096"

  titulo "5. ZRAM"
  backup /etc/systemd/zram-generator.conf
  sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
[zram0]
zram-size = ram
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF
  sudo systemctl daemon-reload
  if sudo systemctl restart systemd-zram-setup@zram0.service; then
    ok "ZRAM aplicado."
  else
    aviso "ZRAM em uso agora. A nova configuração vale após reiniciar."
  fi

  titulo "6. Parâmetros de memória (sysctl)"
  sudo tee /etc/sysctl.d/99-vm-zram-parameters.conf >/dev/null <<'EOF'
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF
  sudo sysctl --system >/dev/null
  ok "Parâmetros aplicados."

  titulo "7. Tampa do notebook (bloquear ao fechar)"
  local LOGIND=/etc/systemd/logind.conf
  backup "$LOGIND"
  if sudo grep -qE '^#?HandleLidSwitch=' "$LOGIND"; then
    sudo sed -i -E 's/^#?HandleLidSwitch=.*/HandleLidSwitch=lock/' "$LOGIND"
  else
    sudo grep -q '^\[Login\]' "$LOGIND" || echo "[Login]" | sudo tee -a "$LOGIND" >/dev/null
    echo "HandleLidSwitch=lock" | sudo tee -a "$LOGIND" >/dev/null
  fi
  ok "HandleLidSwitch=lock (vale no próximo boot)."

  titulo "8. Plymouth"
  local MKINIT=/etc/mkinitcpio.conf
  backup "$MKINIT"
  if sudo grep -qE '^HOOKS=.*\bplymouth\b' "$MKINIT"; then
    ok "Hook plymouth já está presente."
  elif sudo grep -qE '^HOOKS=.*\budev\b' "$MKINIT"; then
    sudo sed -i -E '/^HOOKS=/ s/\budev\b/udev plymouth/' "$MKINIT"
    ok "plymouth adicionado após o udev."
  elif sudo grep -qE '^HOOKS=.*\bsystemd\b' "$MKINIT"; then
    sudo sed -i -E '/^HOOKS=/ s/\bsystemd\b/systemd plymouth/' "$MKINIT"
    ok "plymouth adicionado após o systemd."
  else
    aviso "Não encontrei udev nem systemd em HOOKS. Adicione plymouth manualmente."
  fi
  echo "${CINZA}    $(sudo grep -E '^HOOKS=' "$MKINIT")${R}"

  local CMDLINE=/etc/kernel/cmdline
  if [[ -f "$CMDLINE" ]]; then
    backup "$CMDLINE"
    for param in quiet splash; do
      sudo grep -qw "$param" "$CMDLINE" || sudo sed -i "1 s/\$/ $param/" "$CMDLINE"
    done
    ok "quiet splash na linha do kernel."
    echo "${CINZA}    $(sudo cat "$CMDLINE")${R}"
  else
    aviso "$CMDLINE não existe. Adicione quiet splash manualmente no bootloader."
  fi

  local PRESET=/etc/mkinitcpio.d/linux.preset
  if [[ -f "$PRESET" ]]; then
    backup "$PRESET"
    sudo sed -i -E 's|^(default_options=.*--splash /usr/share/systemd/bootctl/splash-arch\.bmp.*)|#\1|' "$PRESET"
    ok "Splash do Arch comentado no preset."
  else
    aviso "$PRESET não encontrado."
  fi

  passo "Aplicando tema bgrt e gerando a imagem de boot..."
  sudo plymouth-set-default-theme -R bgrt
  ok "Plymouth configurado."
}

# =====================================================================
#  OPÇÃO 2 - ZSH + OH MY ZSH + POWERLEVEL10K
# =====================================================================
opcao_zsh() {

  titulo "1. Pacotes"
  sudo pacman -S --needed --noconfirm zsh curl git fzf

  titulo "2. Oh My Zsh"
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    # RUNZSH=no não abre o zsh no meio do script; CHSH=no porque trocamos o shell no fim
    RUNZSH=no CHSH=no sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    ok "Oh My Zsh já está instalado."
  fi

  local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

  # Clona só se ainda não existir
  clonar() {
    local url="$1" destino="$2"
    if [[ -d "$destino" ]]; then
      ok "$(basename "$destino") já está instalado."
    else
      git clone --depth 1 "$url" "$destino"
    fi
  }

  titulo "3. Tema e plugins"
  clonar https://github.com/romkatv/powerlevel10k.git              "$ZSH_CUSTOM/themes/powerlevel10k"
  clonar https://github.com/zsh-users/zsh-autosuggestions           "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  clonar https://github.com/zsh-users/zsh-syntax-highlighting.git   "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  clonar https://github.com/zsh-users/zsh-history-substring-search  "$ZSH_CUSTOM/plugins/zsh-history-substring-search"

  titulo "4. Configurando ~/.zshrc"
  local ZSHRC="$HOME/.zshrc"
  if [[ ! -f "$ZSHRC" ]]; then
    cp "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$ZSHRC"
  fi
  backup_usuario "$ZSHRC"

  if grep -q '^ZSH_THEME=' "$ZSHRC"; then
    sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
  else
    echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSHRC"
  fi

  # Ordem importa: syntax-highlighting antes de history-substring-search
  local PLUGINS_LINE='plugins=(git fzf zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search)'
  if grep -q '^plugins=' "$ZSHRC"; then
    sed -i "s|^plugins=.*|$PLUGINS_LINE|" "$ZSHRC"
  else
    echo "$PLUGINS_LINE" >> "$ZSHRC"
  fi

  # Setas para cima/baixo buscam no histórico pelo que já foi digitado
  if ! grep -q 'history-substring-search-up' "$ZSHRC"; then
    cat >> "$ZSHRC" <<'EOF'

# Busca no histórico com as setas
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
EOF
  fi
  ok "Arquivo .zshrc configurado."

  titulo "5. Shell padrão"
  local ZSH_BIN
  ZSH_BIN="$(command -v zsh)"
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" == "$ZSH_BIN" ]]; then
    ok "Zsh já é o shell padrão."
  else
    sudo chsh -s "$ZSH_BIN" "$USER"
    ok "Zsh definido como shell padrão (vale no próximo login)."
  fi

  echo
  echo "${CINZA}    Abra um novo terminal. Na primeira vez o Powerlevel10k abre o assistente"
  echo "    de configuração. Para refazer depois: p10k configure${R}"
}

# =====================================================================
#  OPÇÃO 3 - MELHORAR FONTES NO GNOME
# =====================================================================
opcao_fontes() {

  local FONTCONFIG_DIR="$HOME/.config/fontconfig"
  local FONTCONFIG_FILE="$FONTCONFIG_DIR/fonts.conf"
  local ENV_FILE="/etc/environment"
  local FREETYPE_LINE='FREETYPE_PROPERTIES="cff:no-stem-darkening=0 autofitter:no-stem-darkening=0"'

  titulo "1. Fontconfig (subpixel e hinting)"
  mkdir -p "$FONTCONFIG_DIR"
  backup_usuario "$FONTCONFIG_FILE"
  cat > "$FONTCONFIG_FILE" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="font">
    <edit name="rgba" mode="assign">
      <const>rgb</const>
    </edit>
    <edit name="hinting" mode="assign">
      <bool>true</bool>
    </edit>
    <edit name="hintstyle" mode="assign">
      <const>hintslight</const>
    </edit>
    <edit name="antialias" mode="assign">
      <bool>true</bool>
    </edit>
    <edit name="lcdfilter" mode="assign">
      <const>lcddefault</const>
    </edit>
  </match>
</fontconfig>
EOF
  ok "Fontconfig configurado."

  titulo "2. FreeType (stem darkening)"
  if grep -q '^FREETYPE_PROPERTIES=' "$ENV_FILE" 2>/dev/null; then
    ok "FREETYPE_PROPERTIES já existe em $ENV_FILE. Nada alterado."
  else
    backup "$ENV_FILE"
    echo "$FREETYPE_LINE" | sudo tee -a "$ENV_FILE" >/dev/null
    ok "FREETYPE_PROPERTIES adicionado."
  fi

  titulo "3. Ajustes do GNOME"
  if command -v gsettings &>/dev/null && gsettings list-keys org.gnome.desktop.interface &>/dev/null; then
    gsettings set org.gnome.desktop.interface font-antialiasing 'rgba' 2>/dev/null \
      && ok "Antialiasing: rgba" || aviso "Não foi possível definir antialiasing."
    gsettings set org.gnome.desktop.interface font-hinting 'slight' 2>/dev/null \
      && ok "Hinting: slight" || aviso "Não foi possível definir hinting."
  else
    aviso "GNOME não detectado nesta sessão. Pulando gsettings."
  fi

  titulo "4. Cache de fontes"
  fc-cache -f >/dev/null
  ok "Cache atualizado."

  echo
  echo "${CINZA}    Faça logout e login (ou reinicie) para aplicar tudo.${R}"
}

# =====================================================================
#  OPÇÃO 4 - SAMBA (compartilhamento de pasta na rede)
#  Rodar de novo serve para ver e alterar a configuração atual.
# =====================================================================
opcao_samba() {

  local USUARIO="$USER"
  local GRUPO; GRUPO="$(id -gn)"
  local CONF=/etc/samba/smb.conf
  local COMPARTILHAMENTO="ARCH-SHARE"

  # Nome no padrão NetBIOS: maiúsculas, sem acento, só letras/números/hífen, até 15 caracteres
  sanitizar_nome() {
    local s
    s=$(printf '%s' "$1" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || printf '%s' "$1")
    printf '%s' "$s" | tr '[:lower:]' '[:upper:]' \
      | sed -E 's/[^A-Z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-15 | sed -E 's/-+$//'
  }

  # Lê um valor do smb.conf ignorando comentários
  valor_atual() {
    [[ -f "$CONF" ]] || return 0
    sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*(.*)$/\1/Ip" "$CONF" | head -n1 | xargs
  }

  titulo "1. Pacotes"
  sudo pacman -Syu --needed --noconfirm samba wsdd avahi

  titulo "2. Nomes na rede"
  local WG_ATUAL NB_ATUAL
  WG_ATUAL="$(valor_atual workgroup)";      WG_ATUAL="${WG_ATUAL:-WORKGROUP}"
  NB_ATUAL="$(valor_atual 'netbios name')"; NB_ATUAL="${NB_ATUAL:-ARCH-SERVER}"
  if [[ -f "$CONF" ]]; then
    echo "${CINZA}    Configuração atual: workgroup ${B}$WG_ATUAL${R}${CINZA}, servidor ${B}$NB_ATUAL${R}"
    echo "${CINZA}    Enter mantém o valor atual.${R}"
  fi

  local WORKGROUP NETBIOS GUEST
  read -rp "    WORKGROUP [$WG_ATUAL]: " WORKGROUP
  WORKGROUP="$(sanitizar_nome "${WORKGROUP:-$WG_ATUAL}")"; WORKGROUP="${WORKGROUP:-WORKGROUP}"

  read -rp "    Nome do servidor [$NB_ATUAL]: " NETBIOS
  NETBIOS="$(sanitizar_nome "${NETBIOS:-$NB_ATUAL}")"; NETBIOS="${NETBIOS:-ARCH-SERVER}"

  read -rp "    Permitir acesso sem senha (convidado)? [S/n]: " GUEST
  [[ "$GUEST" =~ ^[nN]$ ]] && GUEST=no || GUEST=yes

  ok "Workgroup: $WORKGROUP  |  Servidor: $NETBIOS  |  Convidado: $GUEST"

  titulo "3. Pasta compartilhada"
  # Usa a pasta Público do GNOME (nome certo no idioma do sistema)
  local PASTA
  PASTA="$(xdg-user-dir PUBLICSHARE 2>/dev/null || true)"
  if [[ -z "$PASTA" || "$PASTA" == "$HOME" ]]; then
    PASTA="$HOME/Publico"
  fi
  mkdir -p "$PASTA"
  chmod 775 "$PASTA"
  ok "Pasta: $PASTA"

  titulo "4. Gerando smb.conf"
  local TMP; TMP="$(mktemp)"
  local LINHA_GUEST LINHA_USERS=""
  if [[ $GUEST == yes ]]; then
    LINHA_GUEST="   map to guest = Bad User"
  else
    LINHA_GUEST="   map to guest = Never"
    LINHA_USERS="   valid users = $USUARIO"
  fi

  cat > "$TMP" <<EOF
[global]
   workgroup = $WORKGROUP
   netbios name = $NETBIOS
   server string = Samba %h
   server role = standalone server
$LINHA_GUEST
   dns proxy = no
   unix charset = UTF-8
   logging = systemd
   log level = 1

   # Sem impressoras (evita erros no log)
   load printers = no
   printcap name = /dev/null
   disable spoolss = yes

   # Anúncio no macOS é feito pelo Avahi (evita nome duplicado)
   multicast dns register = no

   # Compatibilidade com macOS (Finder)
   vfs objects = catia fruit streams_xattr
   fruit:metadata = stream
   fruit:model = MacSamba
   fruit:veto_appledouble = no
   fruit:nfs_aces = no
   fruit:wipe_intentionally_left_blank_rfork = yes
   fruit:delete_empty_adfiles = yes

[$COMPARTILHAMENTO]
   comment = Pasta pública de $USUARIO
   path = $PASTA
   browseable = yes
   read only = no
   guest ok = $GUEST
$LINHA_USERS
   # Arquivos gravados pela rede ficam no seu nome (e a pasta pessoal pode continuar 700)
   force user = $USUARIO
   force group = $GRUPO
   create mask = 0664
   directory mask = 0775
EOF

  # Valida ANTES de substituir o arquivo atual
  if ! testparm -s "$TMP" >/dev/null 2>&1; then
    erro "Configuração gerada é inválida:"
    testparm -s "$TMP" || true
    rm -f "$TMP"
    return 1
  fi
  backup "$CONF"
  sudo install -Dm644 "$TMP" "$CONF"
  rm -f "$TMP"
  ok "smb.conf validado e aplicado."

  titulo "5. Senha do Samba"
  if sudo pdbedit -L -u "$USUARIO" &>/dev/null; then
    local REDEF
    read -rp "    Usuário $USUARIO já tem senha no Samba. Redefinir? [s/N]: " REDEF
    if [[ "$REDEF" =~ ^[sS]$ ]]; then
      until sudo smbpasswd "$USUARIO"; do aviso "Senhas não conferem. Tente de novo."; done
    fi
  else
    echo "${CINZA}    Crie a senha que será usada para acessar a pasta pela rede.${R}"
    until sudo smbpasswd -a "$USUARIO"; do aviso "Senhas não conferem. Tente de novo."; done
  fi
  sudo smbpasswd -e "$USUARIO" >/dev/null
  ok "Usuário $USUARIO ativo no Samba."

  titulo "6. Descoberta na rede (Windows e macOS)"
  backup /etc/conf.d/wsdd
  echo "WSDD_PARAMS=\"--workgroup $WORKGROUP --hostname $NETBIOS\"" | sudo tee /etc/conf.d/wsdd >/dev/null
  ok "wsdd configurado (aparece na Rede do Windows)."

  sudo tee /etc/avahi/services/smb.service >/dev/null <<EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>$NETBIOS</name>
  <service>
    <type>_smb._tcp</type>
    <port>445</port>
  </service>
  <service>
    <type>_device-info._tcp</type>
    <port>0</port>
    <txt-record>model=MacSamba</txt-record>
  </service>
</service-group>
EOF
  ok "Avahi configurado (aparece no Finder do macOS)."

  titulo "7. Firewall"
  if command -v ufw &>/dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    sudo ufw allow 137,138/udp comment 'Samba NetBIOS' >/dev/null
    sudo ufw allow 139,445/tcp comment 'Samba'         >/dev/null
    sudo ufw allow 3702/udp    comment 'wsdd'          >/dev/null
    sudo ufw allow 5357/tcp    comment 'wsdd'          >/dev/null
    sudo ufw allow 5353/udp    comment 'mDNS Avahi'    >/dev/null
    ok "Portas liberadas no UFW."
  else
    ok "UFW não está ativo. Nada a liberar."
  fi

  titulo "8. Serviços"
  sudo systemctl enable smb nmb wsdd avahi-daemon >/dev/null 2>&1
  sudo systemctl restart smb nmb wsdd avahi-daemon
  local s
  for s in smb nmb wsdd avahi-daemon; do
    if systemctl is-active --quiet "$s"; then ok "$s ativo"; else erro "$s não iniciou (veja: journalctl -u $s)"; return 1; fi
  done

  local IP
  IP="$( (ip -4 -o route get 1.1.1.1 2>/dev/null || true) | sed -nE 's/.* src ([0-9.]+).*/\1/p')"
  echo
  echo "${B}    Como acessar:${R}"
  echo "${CINZA}    macOS:   Finder › Rede › $NETBIOS   ou   smb://${IP:-IP-DO-PC}/$COMPARTILHAMENTO"
  echo "    Windows: Rede › $NETBIOS          ou   \\\\${IP:-IP-DO-PC}\\$COMPARTILHAMENTO"
  echo "    Login:   usuário $USUARIO e a senha do Samba${R}"
}

# =====================================================================
#  Execução de cada opção
#  Cada opção roda isolada: se uma falhar, o menu continua funcionando
#  e mostra a linha exata do erro.
# =====================================================================
declare -A NOMES=(
  [1]="GNOME AMD Notebook"
  [2]="Zsh + Oh My Zsh"
  [3]="Melhorar fontes GNOME"
  [4]="Samba (pasta na rede)"
)
declare -A FUNCOES=(
  [1]=opcao_gnome_amd_notebook
  [2]=opcao_zsh
  [3]=opcao_fontes
  [4]=opcao_samba
)
declare -A STATUS=()
PRECISA_REINICIAR=0

executar() {
  local n="$1"
  echo
  echo "${B}${AZUL}  ┌────────────────────────────────────────────────${R}"
  echo "${B}${AZUL}  │${R}  ${B}Executando:${R} ${CIANO}${NOMES[$n]}${R}"
  echo "${B}${AZUL}  └────────────────────────────────────────────────${R}"
  echo

  checar_internet || { STATUS[$n]="${VERMELHO}✖ sem internet${R}"; return; }

  (
    set -Eeo pipefail
    trap 'erro "Falhou na linha $LINENO: $BASH_COMMAND"' ERR
    "${FUNCOES[$n]}"
  )
  local rc=$?

  if [[ $rc -eq 0 ]]; then
    STATUS[$n]="${VERDE}✔ concluído${R}"
    [[ $n != 4 ]] && PRECISA_REINICIAR=1
    echo; ok "${B}${NOMES[$n]} concluído com sucesso! 🚀${R}"
  else
    STATUS[$n]="${VERMELHO}✖ falhou${R}"
    echo; erro "${B}${NOMES[$n]} parou por causa de um erro (veja acima).${R}"
    erro "Os arquivos editados têm cópia .bak-DATA ao lado. Pode rodar a opção de novo."
  fi
}

# =====================================================================
#  Menu
# =====================================================================
menu() {
  clear
  local LINHA="────────────────────────────────────────────────"
  echo
  echo "   ${AZUL}╭${LINHA}╮${R}"
  echo "   ${AZUL}│${R}  ${B}${CIANO}PÓS-INSTALAÇÃO ARCH LINUX${R}"
  echo "   ${AZUL}│${R}  ${CINZA}$USER · kernel $(uname -r | cut -d- -f1)${R}"
  echo "   ${AZUL}╰${LINHA}╯${R}"
  echo
  local n
  for n in 1 2 3 4; do
    printf "     ${B}${CIANO}%s${R}  %-24s %s\n" "$n" "${NOMES[$n]}" "${STATUS[$n]:-${D}pendente${R}}"
  done
  echo
  echo "     ${B}${VERMELHO}0${R}  Sair"
  echo
  echo "   ${CINZA}${LINHA}${R}"
  echo "   ${CINZA}Várias opções de uma vez: separe por espaço (ex: 1 2 3)${R}"
  echo
}

# ---------------------------------------------------------------------
# Início
# ---------------------------------------------------------------------
iniciar_sudo

# Modo direto: ./pos-instalacao-arch.sh 1 2 3
if [[ $# -gt 0 ]]; then
  for op in "$@"; do
    if [[ -n "${FUNCOES[$op]}" ]]; then executar "$op"; else aviso "Opção inválida: $op"; fi
  done
  [[ $PRECISA_REINICIAR -eq 1 ]] && echo && aviso "Reinicie o computador para aplicar tudo."
  exit 0
fi

# Modo menu
while true; do
  menu
  read -rp "   ${B}Escolha:${R} " -a escolhas
  [[ ${#escolhas[@]} -eq 0 ]] && continue

  for op in "${escolhas[@]}"; do
    case "$op" in
      0)
        echo
        if [[ $PRECISA_REINICIAR -eq 1 ]]; then
          aviso "Reinicie o computador para ativar Plymouth, ZRAM, logind, Zsh e fontes."
          read -rp "   Reiniciar agora? [s/N] " r
          [[ "$r" =~ ^[sS]$ ]] && sudo systemctl reboot
        fi
        echo "   Até mais! 👋"
        exit 0
        ;;
      1|2|3|4) executar "$op" ;;
      *) aviso "Opção inválida: $op" ;;
    esac
  done

  echo
  read -rp "   ${CINZA}Pressione Enter para voltar ao menu...${R}" _
done
