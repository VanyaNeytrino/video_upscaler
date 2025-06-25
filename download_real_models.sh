#!/bin/bash

echo "📥 Скачиваем НАСТОЯЩИЕ файлы модели из GitHub Releases..."

# Переходим в корень проекта  
cd "$(dirname "$0")"

# Создаем директории для моделей
echo "📁 Создание директорий для моделей..."
for platform in macos windows linux; do
    mkdir -p "assets/executables/$platform/models-cunet"
    mkdir -p "assets/executables/$platform/models-upconv_7_anime_style_art_rgb"
    mkdir -p "assets/executables/$platform/models-upconv_7_photo"
done

# Создаем временную папку
TEMP_DIR="temp_models_download"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Скачиваем последний release с НАСТОЯЩИМИ файлами
echo "📦 Скачиваем waifu2x release 20220728..."
curl -L -o "waifu2x-macos.zip" \
  "https://github.com/nihui/waifu2x-ncnn-vulkan/releases/download/20220728/waifu2x-ncnn-vulkan-20220728-macos.zip"

curl -L -o "waifu2x-windows.zip" \
  "https://github.com/nihui/waifu2x-ncnn-vulkan/releases/download/20220728/waifu2x-ncnn-vulkan-20220728-windows.zip"

curl -L -o "waifu2x-ubuntu.zip" \
  "https://github.com/nihui/waifu2x-ncnn-vulkan/releases/download/20220728/waifu2x-ncnn-vulkan-20220728-ubuntu.zip"

# Распаковываем архивы
echo "📂 Распаковываем архивы..."
unzip -q waifu2x-macos.zip
unzip -q waifu2x-windows.zip  
unzip -q waifu2x-ubuntu.zip

# Находим распакованные папки
MACOS_DIR=$(find . -name "*macos*" -type d | head -1)
WINDOWS_DIR=$(find . -name "*windows*" -type d | head -1)
UBUNTU_DIR=$(find . -name "*ubuntu*" -type d | head -1)

echo "📁 Найденные папки:"
echo "  macOS: $MACOS_DIR"
echo "  Windows: $WINDOWS_DIR"
echo "  Ubuntu: $UBUNTU_DIR"

# Функция копирования моделей
copy_models() {
    local source_dir=$1
    local target_platform=$2
    
    if [ -d "$source_dir" ]; then
        echo "📥 Копируем модели для $target_platform..."
        
        # Копируем все папки с моделями
        for model_dir in "models-cunet" "models-upconv_7_anime_style_art_rgb" "models-upconv_7_photo"; do
            if [ -d "$source_dir/$model_dir" ]; then
                cp -r "$source_dir/$model_dir"/* "../assets/executables/$target_platform/$model_dir/"
                echo "✅ $model_dir скопирована для $target_platform"
            else
                echo "⚠️ $model_dir не найдена в $source_dir"
            fi
        done
        
        # Копируем исполняемые файлы
        if [[ "$target_platform" == "windows" ]]; then
            cp "$source_dir"/*.exe "../assets/executables/$target_platform/" 2>/dev/null || echo "Исполняемые файлы не найдены"
        else
            cp "$source_dir/waifu2x-ncnn-vulkan" "../assets/executables/$target_platform/" 2>/dev/null || echo "Исполняемый файл не найден"
            cp "$source_dir/ffmpeg" "../assets/executables/$target_platform/" 2>/dev/null || echo "FFmpeg не найден"
        fi
    else
        echo "❌ Папка $source_dir не найдена"
    fi
}

# Копируем модели для каждой платформы
copy_models "$MACOS_DIR" "macos"
copy_models "$WINDOWS_DIR" "windows"  
copy_models "$UBUNTU_DIR" "linux"

# Возвращаемся в корень и удаляем временную папку
cd ..
rm -rf "$TEMP_DIR"

echo "✅ Скачивание завершено!"

# ФИНАЛЬНАЯ ПРОВЕРКА размеров файлов
echo "📊 ПРОВЕРЯЕМ РАЗМЕРЫ ФАЙЛОВ:"
for platform in macos windows linux; do
    echo "📁 $platform:"
    if [ -d "assets/executables/$platform/models-cunet" ]; then
        find "assets/executables/$platform/models-cunet" -name "*.param" 2>/dev/null | head -3 | while read file; do
            if [ -f "$file" ]; then
                if command -v stat >/dev/null 2>&1; then
                    # macOS/BSD stat
                    size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
                    size_kb=$((size / 1024))
                    if [ $size_kb -gt 100 ]; then
                        echo "  ✅ $(basename "$file"): ${size_kb}KB - НАСТОЯЩИЙ ФАЙЛ!"
                    else
                        echo "  💀 $(basename "$file"): ${size}B - ВСЕ ЕЩЕ УКАЗАТЕЛЬ!"
                    fi
                else
                    echo "  📄 $(basename "$file"): найден"
                fi
            fi
        done
    else
        echo "  ❌ Модели не найдены"
    fi
done

echo ""
echo "🎯 Если видите 'НАСТОЯЩИЙ ФАЙЛ!' - значит проблема решена!"
echo "🎯 Если видите 'ВСЕ ЕЩЕ УКАЗАТЕЛЬ!' - нужно другое решение"
