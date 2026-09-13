import os
import shutil
import re

ROOT_DIR = r"d:\medicineApp\medicine_app"

def replace_in_file(filepath, replacements):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return

    new_content = content
    for old, new in replacements:
        new_content = new_content.replace(old, new)
        
    if new_content != content:
        try:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print(f"Updated {filepath}")
        except Exception as e:
            print(f"Error writing {filepath}: {e}")

def main():
    replacements = [
        ("german_learning_app", "medicine_app"),
        ("german_app_real", "medicine_app"),
        ("germanAppReal", "medicineApp"),
        ("GermanAppReal", "MedicineApp"),
    ]

    skip_dirs = {'.git', '.dart_tool', 'build', '.idea', 'windows/flutter/ephemeral'}
    
    for root, dirs, files in os.walk(ROOT_DIR):
        # Modify dirs in-place to skip unwanted directories
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        
        for file in files:
            # Skip the script itself and lock files if needed, but pubspec.lock can be safely overwritten by pub get
            if file == "rename_script.py" or file.endswith(".png") or file.endswith(".ttf") or file.endswith(".svg"):
                continue
            
            filepath = os.path.join(root, file)
            replace_in_file(filepath, replacements)
            
            # Rename .iml file
            if file == "german_app_real.iml":
                new_filepath = os.path.join(root, "medicine_app.iml")
                os.rename(filepath, new_filepath)
                print(f"Renamed {filepath} to {new_filepath}")

    # Rename Android package directory
    old_kotlin_dir = os.path.join(ROOT_DIR, "android", "app", "src", "main", "kotlin", "com", "example", "german_app_real")
    new_kotlin_dir = os.path.join(ROOT_DIR, "android", "app", "src", "main", "kotlin", "com", "example", "medicine_app")
    
    if os.path.exists(old_kotlin_dir):
        os.rename(old_kotlin_dir, new_kotlin_dir)
        print(f"Renamed {old_kotlin_dir} to {new_kotlin_dir}")
    
    old_java_dir = os.path.join(ROOT_DIR, "android", "app", "src", "main", "java", "com", "example", "german_app_real")
    new_java_dir = os.path.join(ROOT_DIR, "android", "app", "src", "main", "java", "com", "example", "medicine_app")
    if os.path.exists(old_java_dir):
        os.rename(old_java_dir, new_java_dir)
        print(f"Renamed {old_java_dir} to {new_java_dir}")

if __name__ == '__main__':
    main()
