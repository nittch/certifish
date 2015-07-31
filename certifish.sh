#!/bin/bash
#
# Copyright (C) 2015 Nicolas TANDE
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

function usage() { cat << EOUSAGE
Usage : $0 CN [altname] [altname]...
      : example : $0 coin.example.net coin2.example.net coin3.example.net
EOUSAGE
}

#################
# Configuration #
#################

# Path to openssl binary
openssl=/usr/bin/openssl

# Crypto ciphers rsa 4096 + sha 512
openssl_crypto="rsa:4096 -sha512"

# Certificate Authority that will sign our certificates
ca=

# Details to be added to every certificates
country=""
province=""
locality=""
organization=""
organizationunitname=""
# TODO emailadress

#################
# Sanity checks #
#################
if [ "$country" = "" -o "$province" = "" -o "$locality" = "" -o "$organization" = "" -o "$organizationunitname" = "" ] ; then
  echo -- Please set configuration at the begin of the script --
  exit 42
fi

if [ \! -r "$ca" ]; then
  echo -- CA is not readable, please check configuration at the begin of the script --
  exit 42
fi

if [ \! -x "$openssl" ]; then
  echo -- Could not find openssl binary, please check configuration at the begin of the script --
  exit 42
fi

##############################
# Do no edit below this line #
##############################
set -e

function confirmation()
{
  echo "Is it correct ? [y/N]"
  read confirmation
  
  if [ "$confirmation" != "y" ]; then return 2; fi
}

# Reading parameters

n=$#
if [ $n -lt 1 ]; then 
  usage
  exit 1
fi

cn=$1
shift
altname=$@

# Only display parameters

echo -- You called this script with the following parameters --
echo CommonName: $cn
havealtname=0
if [ ${#altname[@]} -ne 0 ]; then
  for i in ${altname[@]} ; do
    havealtname=1
    echo "AltName: $i";
  done
fi

confirmation

mkdir "$cn"
cp "$ca" "$cn"
cd "$cn"

# Display OpenSSL parameters

(
  echo "[req]"
  echo "distinguished_name = req_distinguished_name"
  echo "req_extensions = req_ext"
  echo "prompt = no"
  echo ""
  echo "[req_distinguished_name]"
  echo "C = $country"
  echo "ST = $province"
  echo "L = $locality"
  echo "CN = $cn"
  echo "OU = $organizationunitname"
  echo ""
  echo "[req_ext]"
dns=1
if [ $havealtname -ne 0 ]; then
  echo "subjectAltName = @alt_names"
  echo ""
  echo "[alt_names]"
  for i in ${altname[@]} ; do
    echo "DNS.$dns  = $i";
    dns=$((dns + 1))
  done
fi
) > "$cn.cnf"

echo -- We are going to generate keys with following parameters --
echo -- The Crypto will be $openssl_crypto and the config will be --
cat "$cn.cnf"
confirmation

# Generate key + csr

$openssl req -new -newkey $openssl_crypto -nodes -keyout "$cn.key" -out "$cn.csr" -config "$cn.cnf"
chmod 600 "$cn.key"

echo -- This is the CSR, copy paste it in your CA website --
cat "$cn.csr"

# read user certificate

ok=0
until [ "$ok" = 1 ] ; do
  echo -- Copy paste here the certificate from your CA website, Control-D to finish --
  while read line; do
    cert+=( "$line" )
  done
  
  echo -- You entered --
  for line in "${cert[@]}"; do
    echo "$line"
  done
  
  confirmation && ok=1

done
for line in "${cert[@]}"; do
  echo "$line" >> "${cn}".crt
done

# generate chained certificate

cat "${cn}.crt" $(basename "${ca}") > "${cn}.chained.crt"

# generate DNSSEC/TLSA record

echo -- TLSA --
echo "If you with to use DNSSEC/TLSA, add this in DNS zone (replace host with real hostname):"

fpr=$( $openssl x509 -noout -fingerprint -sha512 < "${cn}.crt" |sed -e "s/.*=//g" | sed -e "s/\://g" )

echo "_port._tcp.host IN TLSA ( 3 0 2 $fpr )" > "${cn}.tlsa.txt"
echo "_port._tcp.host IN TLSA ( 3 0 2 $fpr )"

