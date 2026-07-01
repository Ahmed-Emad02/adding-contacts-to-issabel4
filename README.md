# Adding Contacts to PBX

This repository contains a simple web dashboard and automatic installer script to configure **caller ID lookup** from PBX's Address Book database on incoming calls received via a USB dongle (`chan_dongle`).

It also hosts a web dashboard running on port **3000** on your PBX server to easily upload Google Contacts or standard CSV files directly into the SQLite database.

## Features
* Fallback from generic `dongle0` to show the caller's phone number if not in the address book.
* Suffix matching (compares the last 10 digits of the caller number) so contacts match regardless of country codes (like `+20` or `0`).
* Blazing-fast bulk imports using a SQLite transaction (imports 3,000+ contacts in under a second).
* Beautiful, glassmorphic dark-mode web interface.

## Installation Instructions

1. Clone or download this repository on your PBX server:
   ```bash
   cd /root
   git clone https://github.com/Ahmed-Emad02/adding-contacts-to-issabel4.git
   cd adding-contacts-to-pbx4
   ```
2. Make the installer script executable and run it as `root`:
   ```bash
   chmod +x install.sh
   ./install.sh
   ```
3. Open your browser and navigate to the dashboard at:
   `http://<your_pbx_server_ip>:3000`
4. Drag and drop your `.csv` contacts file to import.

## Supported CSV Format
You can upload Google Contacts exports or standard 3-column CSV files. Minimum required headers are:
`Name,Last Name,Phone Number` (or `Work's Phone Number` or `Phone 1 - Value`).
