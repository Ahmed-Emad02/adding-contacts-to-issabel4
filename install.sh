#!/bin/bash
# Issabel 4 Contacts Uploader Installer
# Run this script as root!

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root!"
  exit 1
fi

echo "=========================================================="
echo " Starting Issabel 4 Caller ID & Dashboard Setup"
echo "=========================================================="

# 1. Install dependencies
echo "1. Installing Python 3 and Pip..."
yum install -y python3 python3-pip sqlite3
pip3 install flask

# 2. Setup Dashboard directory
echo "2. Copying Dashboard files to /opt/issabel-contacts-uploader..."
mkdir -p /opt/issabel-contacts-uploader/templates
cp app.py /opt/issabel-contacts-uploader/
cp templates/index.html /opt/issabel-contacts-uploader/templates/

# Ensure SQLite database directory is readable and writable
chown -R asterisk:asterisk /opt/issabel-contacts-uploader
chown asterisk:asterisk /var/www/db/address_book.db
chmod 664 /var/www/db/address_book.db
chmod 775 /var/www/db

# 3. Setup Systemd Service
echo "3. Creating and starting systemd service..."
cp issabel-contacts-uploader.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable issabel-contacts-uploader
systemctl start issabel-contacts-uploader

# 4. Open Firewalld port 3000
echo "4. Opening port 3000 in Firewall..."
if systemctl is-active --quiet firewalld; then
  firewall-cmd --zone=public --add-port=3000/tcp --permanent
  firewall-cmd --reload
  echo "Port 3000 opened in firewalld."
else
  echo "Firewalld is not running. If you are using iptables, please open TCP port 3000."
fi

# 5. Setup Asterisk Config (dongle.conf)
echo "5. Updating chan_dongle context configuration..."
DONGLE_CONF="/etc/asterisk/dongle.conf"
if [ -f "$DONGLE_CONF" ]; then
  cp "$DONGLE_CONF" "${DONGLE_CONF}.bak"
  # Change context to from-dongle-custom in [defaults]
  sed -i 's/^context=from-trunk/context=from-dongle-custom/g' "$DONGLE_CONF"
  asterisk -rx "dongle reload now"
  echo "Updated dongle.conf and reloaded chan_dongle."
else
  echo "WARNING: /etc/asterisk/dongle.conf not found. Ensure chan_dongle is installed."
fi

# 6. Setup Asterisk Dialplan (extensions_custom.conf)
echo "6. Injecting Caller ID lookup logic into extensions_custom.conf..."
EXT_CONF="/etc/asterisk/extensions_custom.conf"
if [ -f "$EXT_CONF" ]; then
  cp "$EXT_CONF" "${EXT_CONF}.bak"
  
  # Remove previous definition if installer runs multiple times
  sed -i '/\[from-dongle-custom\]/,/^\s*$/d' "$EXT_CONF"
  sed -i '/\[from-dongle-lookup\]/,/^\s*$/d' "$EXT_CONF"

  # Append new dialplan code
  cat << 'EOF' >> "$EXT_CONF"

[from-dongle-custom]
exten => sms,1,NoOp(--- Incoming SMS on ${DONGLENAME} ---)
same => n,Verbose(1, [SMS-RECEIVE] Dongle: ${DONGLENAME}, Sender: ${CALLERID(num)}, Content: ${SMS})
same => n,Hangup()

exten => ussd,1,NoOp(--- Incoming USSD on ${DONGLENAME} ---)
same => n,NoOp(USSD Session Type: ${USSD_TYPE})
same => n,NoOp(USSD Content: ${USSD})
same => n,Hangup()

exten => s,1,Goto(from-dongle-lookup,${EXTEN},1)
exten => _[+0-9].,1,Goto(from-dongle-lookup,${EXTEN},1)

[from-dongle-lookup]
exten => _.,1,NoOp(--- Incoming call from Dongle on ${EXTEN} ---)
same => n,Set(CALLERID(name)=${CALLERID(num)})
same => n,Set(CLEAN_NUM=${FILTER(0-9,${CALLERID(num)})})
same => n,Set(SEARCH_NUM=${IF($[${LEN(${CLEAN_NUM})} >= 10]?${CLEAN_NUM:-10}:${CLEAN_NUM})})
same => n,Set(CONTACT_NAME=${SHELL(sqlite3 /var/www/db/address_book.db "SELECT trim(coalesce(name, '')) || ' ' || trim(coalesce(last_name, '')) FROM contact WHERE (telefono IS NOT NULL AND (replace(replace(replace(telefono, ' ', ''), '-', ''), '+', '') LIKE '%${SEARCH_NUM}' OR '${CLEAN_NUM}' LIKE '%' || replace(replace(replace(telefono, ' ', ''), '-', ''), '+', ''))) OR (cell_phone IS NOT NULL AND (replace(replace(replace(cell_phone, ' ', ''), '-', ''), '+', '') LIKE '%${SEARCH_NUM}' OR '${CLEAN_NUM}' LIKE '%' || replace(replace(replace(cell_phone, ' ', ''), '-', ''), '+', ''))) LIMIT 1" | tr -d '
' | tr -d '')})
same => n,GotoIf($[ "${CONTACT_NAME}" != "" ]?setname:skipname)
same => n(setname),Set(CALLERID(name)=${CONTACT_NAME})
same => n(skipname),NoOp(CallerID Name is set to: ${CALLERID(name)})
same => n,Goto(from-trunk,${EXTEN},1)
EOF

  asterisk -rx "dialplan reload"
  echo "Updated extensions_custom.conf and reloaded Asterisk dialplan."
else
  echo "ERROR: /etc/asterisk/extensions_custom.conf not found!"
  exit 1
fi

echo "=========================================================="
echo " Setup complete!"
echo " Access the dashboard on http://<your_issabel_ip>:3000"
echo "=========================================================="
