import os
import csv
import sqlite3
from flask import Flask, request, jsonify, render_template

app = Flask(__name__)
DB_PATH = '/var/www/db/address_book.db'
UPLOAD_FOLDER = '/tmp'

@app.route('/')
def index():
    # Fetch contact count
    count = 0
    try:
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT count(*) FROM contact;")
        count = cur.fetchone()[0]
        conn.close()
    except Exception as e:
        count = f"Error ({e})"
    return render_template('index.html', contact_count=count)

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return jsonify({"success": False, "error": "No file uploaded"}), 400
        
    file = request.files['file']
    if file.filename == '':
        return jsonify({"success": False, "error": "Empty filename"}), 400
        
    if not file.filename.lower().endswith('.csv'):
        return jsonify({"success": False, "error": "File must be a CSV (.csv)"}), 400

    filepath = os.path.join(UPLOAD_FOLDER, file.filename)
    file.save(filepath)
    
    contacts = []
    try:
        with open(filepath, mode='r', encoding='utf-8', errors='replace') as f:
            sample = f.read(2048)
            f.seek(0)
            delimiter = ';' if ';' in sample and sample.count(';') > sample.count(',') else ','
            
            reader = csv.DictReader(f, delimiter=delimiter)
            for row in reader:
                first_name = row.get('First Name', row.get('Name', '')).strip()
                middle_name = row.get('Middle Name', '').strip()
                last_name = row.get('Last Name', '').strip()
                
                full_first = first_name
                full_last = (middle_name + " " + last_name).strip() if middle_name else last_name
                
                phones = []
                phone_keys = [
                    'Phone 1 - Value', 'Phone 2 - Value', 'Phone 3 - Value',
                    'Phone Number', "Work's Phone Number", 'Cell Phone Number (SMS)', 'Home Phone Number'
                ]
                
                for key in phone_keys:
                    val = row.get(key, '')
                    if val:
                        for p in val.split(':::'):
                            p_clean = p.strip()
                            if p_clean and p_clean not in phones:
                                phones.append(p_clean)
                
                if not full_first and not phones:
                    continue
                    
                telefono = phones[0] if len(phones) > 0 else ''
                cell_phone = phones[1] if len(phones) > 1 else ''
                home_phone = phones[2] if len(phones) > 2 else ''
                
                contacts.append((full_first, full_last, telefono, cell_phone, home_phone))
                
        if not contacts:
            os.remove(filepath)
            return jsonify({"success": False, "error": "No contacts found in CSV"}), 400
            
        # Bulk Insert into Database
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.execute("BEGIN TRANSACTION;")
        
        inserted = 0
        for c in contacts:
            # Check if contact with same name & phone number already exists
            cur.execute("SELECT id FROM contact WHERE name=? AND last_name=? AND telefono=?;", (c[0], c[1], c[2]))
            if cur.fetchone():
                continue
            cur.execute(
                "INSERT INTO contact (name, last_name, telefono, cell_phone, home_phone, status, directory) VALUES (?, ?, ?, ?, ?, 'isPublic', 'external');",
                c
            )
            inserted += 1
            
        conn.commit()
        conn.close()
        
        os.remove(filepath)
        return jsonify({
            "success": True, 
            "message": f"Successfully parsed {len(contacts)} contacts. Imported {inserted} new contacts."
        })
        
    except Exception as e:
        if os.path.exists(filepath):
            os.remove(filepath)
        return jsonify({"success": False, "error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000)
