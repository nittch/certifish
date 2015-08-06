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
Usage : $0 CN [altnames]
      : example : $0 mail.example.net
      : example : $0 www.example.net alt.example.net secure.example.net
      :
      : for *.example.net you can either put '*.example.net' or 'wildcard.example.net'
EOUSAGE
}

#################
# Configuration #
#################

# Path to openssl binary
openssl=$(which openssl)

# Crypto ciphers rsa 4096 + sha 512
openssl_crypto="rsa:4096 -sha512"

# Certificate Authority that will sign our certificates
ca=

# Details to be added to every certificates
organization=""
organizationunitname=""
locality=""
province=""
country=""

# you may also define those variables in your home directory
userconfig="$HOME/.certifishrc"
[ -r "$userconfig" ] && source "$userconfig"

#################
# Sanity checks #
#################
function error()
{
  echo "-- $1 --" >&2
  exit 1
}

[ "$country" = "" -o "$province" = "" -o "$locality" = "" -o "$organization" = "" -o "$organizationunitname" = "" ] &&
  error "Please set configuration at the begin of the script"
[ ! -r "$ca" ] && error "CA is not readable (path=$ca), please check configuration at the begin of the script"
[ ! -x "$openssl" ] && error "Could not find openssl binary (path=$openssl), please check configuration at the begin of the script"

##############################
# Do no edit below this line #
##############################
set -e
function notice()
{
  echo "-- $1 --"
}

function confirmation()
{
  notice "Is it correct ? [y/N]"
  read confirmation
  
  if [ "$confirmation" != "y" ]; then return 1; fi
}

# Reading parameters

n=$#
if [ $n -lt 1 ]; then 
  usage
  error "Invalid parameters"
fi

# you can either input '*' or 'wildcard'
real_cn=$(echo "$1" | sed 's/wildcard/\*/g')
cn=$(echo "$1"|sed 's/\*/wildcard/g')
shift
altname=$@

# Only display parameters

notice "You called this script with the following parameters"
echo CommonName: $real_cn
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
  echo "CN = $real_cn"
  echo "O = $organization"
  echo "OU = $organizationunitname"
  echo "L = $locality"
  echo "ST = $province"
  echo "C = $country"
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

notice "We are going to generate keys with following parameters"
notice "The Crypto will be $openssl_crypto and the config will be"

cat "$cn.cnf"
confirmation

# Generate key + csr

$openssl req -new -newkey $openssl_crypto -nodes -keyout "$cn.key" -out "$cn.csr" -config "$cn.cnf"
chmod 600 "$cn.key"

notice "This is the CSR, copy paste it in your CA website"
cat "$cn.csr"

# read user certificate

ok=0
until [ "$ok" = 1 ] ; do
  notice "Copy paste here the certificate from your CA website, Control-D to finish"
  while read line; do
    cert+=( "$line" )
  done
  
  notice "You entered"
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

notice "TLSA"
notice "If you wish to use DNSSEC/TLSA, add this in DNS zone (replace host with real hostname):"

fpr=$( $openssl x509 -noout -fingerprint -sha512 < "${cn}.crt" |sed -e "s/.*=//g" | sed -e "s/\://g" )

echo "_port._tcp.host IN TLSA ( 3 0 2 $fpr )" > "${cn}.tlsa.txt"
echo "_port._tcp.host IN TLSA ( 3 0 2 $fpr )"

