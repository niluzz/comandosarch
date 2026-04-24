#!/bin/bash

# Script Samba Arch Linux - Versão Blindada

# =========================
# Verificação de root
# =========================
if [ "$EUID" -ne 0 ]; then
  echo "Execute com sudo."
  exit 1
fi

# =========================
# Função de erro
# =========================
verificar_erro() {
    if [ $? -ne 0 ]; then
        echo "Erro: $1 falhou!"
        exit 1
    fi
}

# =========================
# Detectar usuário
# =========================
USUARIO=${SUDO_USER:-$(whoami)}
echo "Usuário detectado: $USUARIO"

# =========================
# Função sanitizar nome
# =========================
sanitizar_nome() {
    echo "$1" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/-/g'
}

# =========================
# Entrada interativa
# =========================
echo ""
echo "===== CONFIGURAÇÃO DE REDE ====="

read -p "Nome do WORKGROUP (padrão: WORKGROUP): " WORKGROUP
WORKGROUP=${WORKGROUP:-WORKGROUP}
WORKGROUP=$(sanitizar_nome "$WORKGROUP")

read -p "Nome do servidor (sem espaços) (padrão: ARCH-SERVER): " NETBIOS
NETBIOS=${NETBIOS:-ARCH-SERVER}
NETBIOS=$(sanitizar_nome "$NETBIOS")

echo ""
echo "Configuração final:"
echo "Workgroup: $WORKGROUP"
echo "Servidor: $NETBIOS"
echo ""

# =========================
# Atualização
# =========================
echo "Atualizando sistema..."
pacman -Syu --noconfirm
verificar_erro "Atualização"

# =========================
# Instalar pacotes
# =========================
echo "Instalando pacotes..."
pacman -S --noconfirm samba wsdd avahi inetutils
verificar_erro "Pacotes"

# =========================
# Criar pasta
# =========================
PASTA="/home/$USUARIO/Publico"
mkdir -p "$PASTA"
chmod 775 "$PASTA"
chown "$USUARIO:$USUARIO" "$PASTA"

# =========================
# Backup config
# =========================
cp /etc/samba/smb.conf /etc/samba/smb.conf.bak 2>/dev/null

# =========================
# Criar smb.conf
# =========================
cat > /etc/samba/smb.conf << EOF
[global]
   workgroup = $WORKGROUP
   netbios name = $NETBIOS
   server string = Samba Server
   server role = standalone server

   log file = /var/log/samba/log.%m
   max log size = 50

   dns proxy = no
   unix charset = UTF-8

[homes]
   browseable = no
   writable = yes

[ARCH-SHARE]
   comment = Pasta Compartilhada
   path = $PASTA
   browseable = yes
   writable = yes
   guest ok = yes
   create mask = 0775
   directory mask = 0775
EOF

verificar_erro "smb.conf"

# =========================
# Validar config
# =========================
testparm -s
verificar_erro "Validação"

# =========================
# Criar senha Samba
# =========================
smbpasswd -a "$USUARIO"
verificar_erro "Senha Samba"

# =========================
# Configurar WSDD
# =========================
echo "WSDD_PARAMS=\"--workgroup $WORKGROUP --hostname $NETBIOS\"" > /etc/conf.d/wsdd

# =========================
# Serviços
# =========================
systemctl enable smb wsdd avahi-daemon
systemctl restart smb wsdd avahi-daemon
verificar_erro "Serviços"

# =========================
# Firewall UFW
# =========================
if command -v ufw >/dev/null 2>&1; then
    echo "Configurando UFW..."
    ufw allow 137/udp
    ufw allow 138/udp
    ufw allow 139/tcp
    ufw allow 445/tcp
fi

# =========================
# Firewall firewalld
# =========================
if command -v firewall-cmd >/dev/null 2>&1; then
    echo "Configurando firewalld..."
    firewall-cmd --permanent --add-service=samba
    firewall-cmd --reload
fi

# =========================
# Obter IP (robusto)
# =========================
IP=$(ip route get 1 | awk '{print $7; exit}')

# =========================
# Status
# =========================
systemctl status smb wsdd avahi-daemon --no-pager -l

# =========================
# Final
# =========================
echo ""
echo "======================================"
echo " SAMBA CONFIGURADO COM SUCESSO"
echo "======================================"
echo "Usuário: $USUARIO"
echo "Workgroup: $WORKGROUP"
echo "Servidor: $NETBIOS"
echo "Pasta: $PASTA"
echo ""
echo "Acesse no Windows:"
echo "\\\\$NETBIOS"
echo "\\\\$IP"
echo "======================================"
