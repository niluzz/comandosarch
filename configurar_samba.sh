#!/bin/bash

# =========================
# Verificação root
# =========================
if [ "$EUID" -ne 0 ]; then
  echo "Execute com sudo."
  exit 1
fi

# =========================
# Funções
# =========================
erro() {
    echo "Erro: $1"
    exit 1
}

sanitizar_nome() {
    echo "$1" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/-/g'
}

obter_valor_conf() {
    grep -i "$1" /etc/samba/smb.conf 2>/dev/null | awk -F= '{print $2}' | xargs
}

# =========================
# Detectar usuário
# =========================
USUARIO=${SUDO_USER:-$(whoami)}
PASTA="/home/$USUARIO/Publico"

# =========================
# Função instalação
# =========================
instalar_samba() {

echo "Instalando e configurando Samba..."

read -p "WORKGROUP (padrão: WORKGROUP): " WORKGROUP
WORKGROUP=${WORKGROUP:-WORKGROUP}
WORKGROUP=$(sanitizar_nome "$WORKGROUP")

read -p "Nome do servidor (padrão: ARCH-SERVER): " NETBIOS
NETBIOS=${NETBIOS:-ARCH-SERVER}
NETBIOS=$(sanitizar_nome "$NETBIOS")

pacman -Syu --noconfirm || erro "Atualização"
pacman -S --noconfirm samba wsdd avahi inetutils || erro "Pacotes"

mkdir -p "$PASTA"
chmod 775 "$PASTA"
chown "$USUARIO:$USUARIO" "$PASTA"

cp /etc/samba/smb.conf /etc/samba/smb.conf.bak 2>/dev/null

cat > /etc/samba/smb.conf << EOF
[global]
   workgroup = $WORKGROUP
   netbios name = $NETBIOS
   server role = standalone server
   dns proxy = no
   unix charset = UTF-8

[ARCH-SHARE]
   path = $PASTA
   browseable = yes
   writable = yes
   guest ok = yes
   create mask = 0775
   directory mask = 0775
EOF

testparm -s || erro "Config inválida"

smbpasswd -a "$USUARIO"

echo "WSDD_PARAMS=\"--workgroup $WORKGROUP --hostname $NETBIOS\"" > /etc/conf.d/wsdd

systemctl enable smb wsdd avahi-daemon
systemctl restart smb wsdd avahi-daemon

echo "Samba instalado com sucesso!"
}

# =========================
# Função status/config atual
# =========================
mostrar_config() {

if [ ! -f /etc/samba/smb.conf ]; then
    echo "Samba não configurado."
    return
fi

WORKGROUP=$(obter_valor_conf "workgroup")
NETBIOS=$(obter_valor_conf "netbios name")

echo ""
echo "===== CONFIGURAÇÃO ATUAL ====="
echo "Workgroup: $WORKGROUP"
echo "Servidor: $NETBIOS"
echo "Pasta: $PASTA"
echo "=============================="
}

# =========================
# Função alterar nomes
# =========================
alterar_config() {

if [ ! -f /etc/samba/smb.conf ]; then
    echo "Samba não está instalado."
    return
fi

echo ""
echo "Alterar configurações:"

read -p "Novo WORKGROUP (enter mantém atual): " NOVO_WG
read -p "Novo nome do servidor (enter mantém atual): " NOVO_NB

# pegar atuais
WG_ATUAL=$(obter_valor_conf "workgroup")
NB_ATUAL=$(obter_valor_conf "netbios name")

NOVO_WG=${NOVO_WG:-$WG_ATUAL}
NOVO_NB=${NOVO_NB:-$NB_ATUAL}

NOVO_WG=$(sanitizar_nome "$NOVO_WG")
NOVO_NB=$(sanitizar_nome "$NOVO_NB")

# aplicar alterações
sed -i "s/^.*workgroup.*/   workgroup = $NOVO_WG/I" /etc/samba/smb.conf
sed -i "s/^.*netbios name.*/   netbios name = $NOVO_NB/I" /etc/samba/smb.conf

echo "WSDD_PARAMS=\"--workgroup $NOVO_WG --hostname $NOVO_NB\"" > /etc/conf.d/wsdd

systemctl restart smb wsdd

echo "Configuração atualizada com sucesso!"
}

# =========================
# MENU
# =========================
while true; do
    echo ""
    echo "========= MENU SAMBA ========="
    echo "1) Instalar / Reconfigurar Samba"
    echo "2) Ver configuração atual"
    echo "3) Alterar nome da rede/servidor"
    echo "4) Sair"
    echo "=============================="
    read -p "Escolha uma opção: " OP

    case $OP in
        1) instalar_samba ;;
        2) mostrar_config ;;
        3) alterar_config ;;
        4) exit 0 ;;
        *) echo "Opção inválida" ;;
    esac
done
