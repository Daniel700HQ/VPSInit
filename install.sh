#!/bin/bash

# --- CONFIGURACIÓN ---
ARCHIVO_CLAVE="1.txt"
NUEVO_USUARIO="a0"

# Mismos paquetes que se pre-descargaron en firewall.sh
# NOTA: No incluimos 'sudo' aquí porque se asume instalado, pero se añade por seguridad.
PKG_TODO="sudo xfce4 xfce4-goodies dbus-x11 dbus-user-session xrdp wireshark virtualbox* gvfs*"

# --- VERIFICACIONES INICIALES ---

# 1. Root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Ejecutar como root."
  exit 1
fi

# 2. Archivo de contraseña
if [ ! -f "$ARCHIVO_CLAVE" ]; then
    echo "Error: Falta $ARCHIVO_CLAVE."
    exit 1
fi

# Leer contraseña
NUEVA_CONTRASENA=$(cat "$ARCHIVO_CLAVE" | tr -d '[:space:]')
if [ -z "$NUEVA_CONTRASENA" ]; then
    echo "Error: $ARCHIVO_CLAVE está vacío."
    exit 1
fi

echo "--- INICIANDO INSTALACIÓN (Modo Rápido) ---"
echo "Usando paquetes en caché descargados por el script anterior..."

# Evitar interacciones
export DEBIAN_FRONTEND=noninteractive

# --- PASO 1: PREPARACIÓN DEL SISTEMA ---

# Eliminar actualizaciones automáticas para evitar bloqueos de dpkg
echo " > Desactivando actualizaciones automáticas..."
systemctl stop unattended-upgrades.service 2>/dev/null || true
systemctl disable unattended-upgrades.service 2>/dev/null || true
apt-get purge -y unattended-upgrades > /dev/null 2>&1

# --- PASO 2: INSTALACIÓN DE PAQUETES ---

echo " > Instalando Entorno Gráfico, RDP y Wireshark..."

# Pre-configurar Wireshark para que no pregunte nada
echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections

# Instalación masiva (Usará la caché automáticamente)
apt-get install -y $PKG_TODO

# --- PASO 3: CONFIGURACIÓN DE XRDP ---

echo " > Configurando Escritorio Remoto..."
# Añadir usuario xrdp al grupo ssl-cert
adduser xrdp ssl-cert > /dev/null

# Forzar inicio de XFCE4
if [ -f /etc/xrdp/startwm.sh ]; then
    cp /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.bak
    sed -i '/^test -x/d' /etc/xrdp/startwm.sh
    sed -i '/^exec \/bin\/sh/d' /etc/xrdp/startwm.sh
    echo -e "\nstartxfce4" >> /etc/xrdp/startwm.sh
fi
systemctl enable xrdp > /dev/null 2>&1

# --- PASO 4: CREACIÓN DE USUARIO ---

echo " > Configurando usuario '$NUEVO_USUARIO'..."

# Crear usuario si no existe
if ! id "$NUEVO_USUARIO" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$NUEVO_USUARIO" > /dev/null
fi

# Asignar contraseña
echo "$NUEVO_USUARIO:$NUEVA_CONTRASENA" | chpasswd

# Asignar grupos (sudo, wireshark)
usermod -aG sudo,ssl-cert,wireshark "$NUEVO_USUARIO"

# --- FINALIZACIÓN ---

echo "------------------------------------------------------------------"
echo "INSTALACIÓN COMPLETADA."
echo "Usuario: $NUEVO_USUARIO"
echo "Reiniciando sistema en 5 segundos..."
echo "------------------------------------------------------------------"
sleep 5
reboot
