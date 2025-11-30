#!/bin/bash

# Verificar si el usuario es root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Por favor, ejecuta este script como root (sudo)."
  exit 1
fi

# --- CONFIGURACIÓN DE VARIABLES ---

ARCHIVO_IPS="2.txt"

# Paquetes del OTRO script (Entorno Gráfico, RDP, Herramientas)
PKG_INSTALL="sudo xfce4 xfce4-goodies dbus-x11 dbus-user-session xrdp wireshark virtualbox* gvfs"

# Paquetes de ESTE script (Seguridad)
PKG_FIREWALL="iptables iptables-persistent netfilter-persistent"

# Combinación de ambos para la descarga masiva
ALL_PACKAGES="$PKG_INSTALL $PKG_FIREWALL"


# --- FASE 1: GESTIÓN DE PAQUETES (PRE-DESCARGA MASIVA) ---

echo "--- FASE 1: Preparando paquetes ---"

# Evitar interacciones (ventanas azules)
export DEBIAN_FRONTEND=noninteractive

# 1. Actualizar lista de repositorios
echo "Actualizando repositorios..."
apt-get update -q

# 2. PRE-DESCARGA TOTAL (Cache Warmer)
# Esto baja XFCE, Wireshark, IPTables, etc., pero NO los instala todavía.
echo "Pre-descargando TODOS los paquetes (Install + Firewall)..."
apt-get install --download-only -y $ALL_PACKAGES
echo ">> Descarga completada. Los paquetes están en caché."

# 3. Remover UFW (Conflictivo)
echo "Removiendo UFW y sus dependencias..."
apt-get remove --purge -y 'ufw*'

# 4. Instalar SOLO los paquetes de Firewall
# Como ya están descargados en el paso 2, esto es instantáneo.
echo "Instalando paquetes de seguridad (IPTables)..."
apt-get install -y $PKG_FIREWALL


# --- FASE 2: CONFIGURACIÓN DE REGLAS IPTABLES ---

echo "--- FASE 2: Configurando reglas del Firewall ---"

# 1. Verificación del archivo de IPs
if [ ! -f "$ARCHIVO_IPS" ]; then
    echo "Error CRÍTICO: El archivo $ARCHIVO_IPS no existe."
    echo "Debes crear el archivo antes de ejecutar este script."
    exit 1
fi

# 2. Políticas por defecto en ACCEPT (Para evitar bloqueos durante el flush)
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# 3. Limpieza total (Flush)
iptables -F
iptables -X
iptables -t nat -F
iptables -t mangle -F

# 4. Permitir Loopback (Localhost) - Vital
iptables -A INPUT -i lo -j ACCEPT

# 5. Procesar lista blanca desde el archivo txt
# Convertimos comas a espacios para procesar
LISTA_IPS=$(cat "$ARCHIVO_IPS" | tr ',' ' ')

for ip in $LISTA_IPS; do
    # Limpiar espacios en blanco
    ip_limpia=$(echo "$ip" | xargs)
    
    if [ -n "$ip_limpia" ]; then
        echo " > Aceptando tráfico de: $ip_limpia"
        iptables -A INPUT -s "$ip_limpia" -j ACCEPT
    fi
done

# 6. Permitir conexiones ya establecidas (Salida a internet del servidor)
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 7. BLOQUEO FINAL (DROP)
echo "Aplicando bloqueo (DROP) a todo lo demás..."
iptables -A INPUT -j DROP
iptables -A FORWARD -j DROP

# --- FASE 3: PERSISTENCIA ---

echo "--- FASE 3: Guardando configuración ---"
# Guardar reglas
netfilter-persistent save

echo "¡Firewall configurado! Los paquetes del entorno gráfico ya están pre-descargados para el siguiente script."
