#!/bin/bash

# enable_cac_piv.sh: Configure Firefox to use DoD CAC/PIV
# Copyright (C) 2020  Michael A. Mead
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Ensure root
if (( $EUID != 0 )); then
	echo "ERROR: This must be run with root privileges"
	exit 1
fi

# Install required packages
apt -y install libccid opensc libnss3-tools

# Download DoD certificates
pushd /tmp
	wget https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_v5-6_dod.zip
	unzip unclass-certificates_pkcs7_v5-6_dod.zip
	rm /tmp/unclass-certificates_pkcs7_v5-6_dod.zip
popd

pushd /tmp/Certificates_PKCS7_v5.6_DoD
	# Split .p7b into separate .crt files
	openssl pkcs7 -inform DER -outform PEM -in Certificates_PKCS7_v5.6_DoD.der.p7b -print_certs | awk '/subject=/ { i++; } /subject=/, /END/ { print > "cert-" i ".crt"  }'

	# Rename .crt files to match CN (common name)
	# Strip files down to just certificate data
	for filename in cert-*.crt; do
		newname="$(head -1 ${filename} | sed 's/.*, CN = //g').crt"
		sed -n '/BEGIN/,/END/p' "${filename}" > "${newname}"
	done

	# Delete original .crt files
	rm cert-*.crt

	# Import certificates into NSS databases
	for certDB in $(find /home/*/.mozilla -name "cert9.db"); do
		certDir=$(dirname "${certDB}")
		for filename in *.crt; do
			certTitle="${filename/.crt/}"
			echo ${certTitle}
			certutil -A -n "${certTitle}" -t "TCu,Cuw,Tuw" -i "${filename}" -d "${certDir}"
		done
	done
popd

# Cleanup temporary files
rm -r -f /tmp/Certificates_PKCS7_v5.6_DoD

# Load OpenSC into Firefox
for modDB in $(find /home/*/.mozilla -name "pkcs11.txt"); do
	# Load module
	modDir=$(dirname "${modDB}")
	moduleFile=$(find /usr/lib/*/pkcs11 -name opensc-pkcs11.so)
	modutil -dbdir "${modDir}" -add "OpenSC Smart Card Module" -libfile "${moduleFile}"

	# Fix permissions (modutil changes owner to root)
	fileUser=`stat -c "%U" "${modDir}"`
	fileGroup=`stat -c "%G" "${modDir}"`
	chown -R ${fileUser}:${fileGroup} "${modDB}"
done
