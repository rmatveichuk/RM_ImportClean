# -*- coding: utf-8 -*-
"""
Helper script to package RM_ImportClean into a single .mzp file
"""
import os
import zipfile

def build_mzp():
    current_dir = os.path.dirname(os.path.abspath(__file__))
    
    files_to_pack = [
        "mzp.run",
        "Install.ms",
        "RM_ImportClean.mcr",
        "RM_ImportClean.ms",
        "Icon_RM_ImportClean.svg",
    ]
    
    output_filename = "RM_ImportClean.mzp"
    output_path = os.path.join(current_dir, output_filename)
    
    print("Начало сборки установщика RM ImportClean...")
    
    try:
        with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zip_file:
            for file_name in files_to_pack:
                file_path = os.path.join(current_dir, file_name)
                if os.path.exists(file_path):
                    zip_file.write(file_path, file_name)
                    print(f" -> Добавлен: {file_name}")
                else:
                    print(f" -> Ошибка: Файл {file_name} не найден!")
                    return
        print(f"\nСборка успешно завершена!\nСоздан файл: {output_path}")
    except Exception as e:
        print(f"Ошибка при сборке архива: {e}")

if __name__ == "__main__":
    build_mzp()
