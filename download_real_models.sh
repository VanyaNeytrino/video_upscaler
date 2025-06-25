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
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Функция безопасного скачивания
download_with_retry() {
    local url=$1
    local output=$2
    local attempts=3
    
    for i in $(seq 1 $attempts); do
        echo "Попытка $i/$attempts: скачивание $output..."
        if curl -L --fail --connect-timeout 30 --max-time 600 -o "$output" "$url"; then
            if [ -f "$output" ] && [ -s "$output" ]; then
                local size=$(stat -c%s "$output" 2>/dev/null || stat -f%z "$output" 2>/dev/null || echo "0")
                local size_mb=$((size / 1024 / 1024))
                echo "✅ $output скачан: ${size_mb}MB"
                return 0
            fi
        fi
        echo "❌ Ошибка скачивания $output (попытка $i)"
        sleep 5
    done
    
    echo "❌ Не удалось скачать $output после $attempts попыток"
    return 1
}

# Скачиваем waifu2x архивы
echo "📦 Скачиваем waifu2x release 20220728..."
download_with_retry "https://github.com/nihui/waifu2x-ncnn-vulkan/releases/download/20220728/waifu2x-ncnn-vulkan-20220728-macos.zip" "waifu2x-macos.zip" || exit 1
download_with_retry "https://github.com/nihui/waifu2x-ncnn-vulkan/releases/download/20220728/waifu2x-ncnn-vulkan-20220728-windows.zip" "waifu2x-windows.zip" || exit 1
download_with_retry "https://github.com/nihui/waifu2x-ncnn-vulkan/releases/download/20220728/waifu2x-ncnn-vulkan-20220728-ubuntu.zip" "waifu2x-ubuntu.zip" || exit 1

# ИСПРАВЛЕНО: Скачиваем FFmpeg из правильных источников (только ZIP, без 7z)
echo "📦 Скачиваем FFmpeg из проверенных источников..."

# Windows FFmpeg (используем BtbN, который дает ZIP архивы)
echo "🪟 Скачиваем FFmpeg для Windows из BtbN..."
download_with_retry "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip" "ffmpeg-windows.zip" || {
    echo "⚠️ Основной источник Windows не работает, пробуем альтернативный..."
    download_with_retry "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-lgpl.zip" "ffmpeg-windows.zip" || {
        echo "⚠️ Альтернативный тоже не работает, будем искать в waifu2x"
    }
}

# Linux FFmpeg
echo "🐧 Скачиваем FFmpeg для Linux..."
download_with_retry "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz" "ffmpeg-linux.tar.xz" || echo "⚠️ FFmpeg Linux не скачан"

# macOS FFmpeg (используем BtbN, который более стабилен)
echo "🍎 Скачиваем FFmpeg для macOS..."
download_with_retry "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-macos64-gpl.tar.xz" "ffmpeg-macos.tar.xz" || {
    echo "⚠️ BtbN macOS не работает, пробуем evermeet..."
    download_with_retry "https://evermeet.cx/ffmpeg/ffmpeg-6.1.zip" "ffmpeg-macos-evermeet.zip" || echo "⚠️ FFmpeg macOS не скачан"
}

# Распаковываем waifu2x архивы
echo "📂 Распаковываем waifu2x архивы..."
unzip -q waifu2x-macos.zip || exit 1
unzip -q waifu2x-windows.zip || exit 1  
unzip -q waifu2x-ubuntu.zip || exit 1

# Распаковываем FFmpeg архивы
echo "📂 Распаковываем FFmpeg архивы..."

# Linux FFmpeg
if [ -f "ffmpeg-linux.tar.xz" ]; then
    echo "Распаковка Linux FFmpeg..."
    tar -xf ffmpeg-linux.tar.xz && echo "✅ Linux FFmpeg распакован" || echo "❌ Ошибка распаковки Linux FFmpeg"
fi

# Windows FFmpeg (ZIP формат)
if [ -f "ffmpeg-windows.zip" ]; then
    echo "Распаковка Windows FFmpeg..."
    unzip -q ffmpeg-windows.zip && echo "✅ Windows FFmpeg распакован" || echo "❌ Ошибка распаковки Windows FFmpeg"
fi

# macOS FFmpeg
if [ -f "ffmpeg-macos.tar.xz" ]; then
    echo "Распаковка macOS FFmpeg (BtbN)..."
    tar -xf ffmpeg-macos.tar.xz && echo "✅ macOS FFmpeg распакован" || echo "❌ Ошибка распаковки"
elif [ -f "ffmpeg-macos-evermeet.zip" ]; then
    echo "Распаковка macOS FFmpeg (evermeet)..."
    unzip -q ffmpeg-macos-evermeet.zip && echo "✅ macOS FFmpeg распакован" || echo "❌ Ошибка распаковки"
fi

# Показываем что распаковалось
echo "📁 Содержимое после распаковки:"
ls -la
echo ""
echo "📂 Ищем все распакованные папки:"
find . -type d -name "*ffmpeg*" | head -10

# Находим waifu2x папки
MACOS_DIR=$(find . -name "*macos*" -type d | head -1)
WINDOWS_DIR=$(find . -name "*windows*" -type d | head -1)
UBUNTU_DIR=$(find . -name "*ubuntu*" -type d | head -1)

echo "📁 Найденные waifu2x папки:"
echo "  macOS: $MACOS_DIR"
echo "  Windows: $WINDOWS_DIR"
echo "  Ubuntu: $UBUNTU_DIR"

# Находим FFmpeg папки
FFMPEG_LINUX_DIR=$(find . -name "*ffmpeg*linux*" -type d | head -1)
FFMPEG_WINDOWS_DIR=$(find . -name "*ffmpeg*win*" -type d | head -1)
FFMPEG_MACOS_DIR=$(find . -name "*ffmpeg*macos*" -type d | head -1)

echo "📁 Найденные FFmpeg папки:"
echo "  Linux: $FFMPEG_LINUX_DIR"
echo "  Windows: $FFMPEG_WINDOWS_DIR" 
echo "  macOS: $FFMPEG_MACOS_DIR"

# ИСПРАВЛЕНА функция поиска FFmpeg с детальной диагностикой
find_and_copy_ffmpeg() {
    local target_platform=$1
    local executable_name=$2
    
    echo ""
    echo "🔍 ДЕТАЛЬНЫЙ поиск FFmpeg для $target_platform (ищем $executable_name)..."
    
    # Определяем папку для поиска
    local search_dirs=""
    case $target_platform in
        "windows")
            search_dirs="$FFMPEG_WINDOWS_DIR $WINDOWS_DIR ."
            ;;
        "linux")
            search_dirs="$FFMPEG_LINUX_DIR $UBUNTU_DIR ."
            ;;
        "macos")
            search_dirs="$FFMPEG_MACOS_DIR $MACOS_DIR ."
            ;;
    esac
    
    echo "Папки для поиска: $search_dirs"
    
    # Ищем во всех возможных местах
    local found_ffmpeg=""
    
    for search_dir in $search_dirs; do
        if [ -n "$search_dir" ] && [ -d "$search_dir" ]; then
            echo "🔍 Поиск в: $search_dir"
            
            # Показываем содержимое папки
            echo "  Содержимое папки $search_dir:"
            ls -la "$search_dir/" | head -10
            
            # Поиск FFmpeg в разных подпапках
            for subdir in "$search_dir" "$search_dir/bin" "$search_dir/ffmpeg" "$search_dir"/*; do
                if [ -d "$subdir" ]; then
                    local candidate="$subdir/$executable_name"
                    echo "    Проверка: $candidate"
                    
                    if [ -f "$candidate" ]; then
                        local size=$(stat -c%s "$candidate" 2>/dev/null || stat -f%z "$candidate" 2>/dev/null || echo "0")
                        local size_mb=$((size / 1024 / 1024))
                        
                        echo "    🎯 НАЙДЕН: $candidate (${size_mb}MB)"
                        
                        if [ $size_mb -gt 10 ]; then
                            found_ffmpeg="$candidate"
                            echo "    ✅ Подходящий размер!"
                            break 2
                        else
                            echo "    ⚠️ Слишком мал: ${size_mb}MB"
                        fi
                    else
                        echo "    ❌ Не найден: $candidate"
                    fi
                fi
            done
            
            # Дополнительный рекурсивный поиск
            if [ -z "$found_ffmpeg" ]; then
                echo "  🔄 Рекурсивный поиск в $search_dir..."
                local recursive_find=$(find "$search_dir" -name "$executable_name" -type f 2>/dev/null | head -3)
                if [ -n "$recursive_find" ]; then
                    echo "  Найдено рекурсивно:"
                    echo "$recursive_find" | while read found_file; do
                        local size=$(stat -c%s "$found_file" 2>/dev/null || stat -f%z "$found_file" 2>/dev/null || echo "0")
                        local size_mb=$((size / 1024 / 1024))
                        echo "    $found_file (${size_mb}MB)"
                        
                        if [ $size_mb -gt 10 ] && [ -z "$found_ffmpeg" ]; then
                            found_ffmpeg="$found_file"
                        fi
                    done
                    
                    # Берем первый подходящий
                    local first_good=$(find "$search_dir" -name "$executable_name" -type f -exec stat -c%s {} \; -print 2>/dev/null | awk 'NR%2==1{size=$1} NR%2==0{if(size>10485760) print $0}' | head -1)
                    if [ -n "$first_good" ]; then
                        found_ffmpeg="$first_good"
                        echo "  ✅ Выбран лучший кандидат: $found_ffmpeg"
                        break
                    fi
                fi
            fi
        else
            echo "❌ Папка не найдена или недоступна: $search_dir"
        fi
    done
    
    # Копируем если найден
    if [ -n "$found_ffmpeg" ] && [ -f "$found_ffmpeg" ]; then
        echo "📋 Копирование $found_ffmpeg в ../assets/executables/$target_platform/$executable_name"
        cp "$found_ffmpeg" "../assets/executables/$target_platform/$executable_name"
        
        local final_size=$(stat -c%s "../assets/executables/$target_platform/$executable_name" 2>/dev/null || stat -f%z "../assets/executables/$target_platform/$executable_name" 2>/dev/null || echo "0")
        local final_size_mb=$((final_size / 1024 / 1024))
        echo "✅ FFmpeg скопирован для $target_platform: ${final_size_mb}MB"
        return 0
    else
        echo "❌ FFmpeg для $target_platform НЕ НАЙДЕН"
        return 1
    fi
}

# Функция копирования waifu2x и моделей (без изменений)
copy_waifu2x_models() {
    local source_dir=$1
    local target_platform=$2
    
    echo ""
    echo "📥 Копируем waifu2x и модели для $target_platform..."
    
    if [ ! -d "$source_dir" ]; then
        echo "❌ Папка $source_dir не найдена"
        return 1
    fi
    
    # Копируем модели
    for model_dir in "models-cunet" "models-upconv_7_anime_style_art_rgb" "models-upconv_7_photo"; do
        if [ -d "$source_dir/$model_dir" ]; then
            cp -r "$source_dir/$model_dir"/* "../assets/executables/$target_platform/$model_dir/"
            echo "✅ $model_dir скопирована"
        else
            echo "⚠️ $model_dir не найдена"
        fi
    done
    
    # Копируем waifu2x
    local waifu2x_name="waifu2x-ncnn-vulkan"
    if [ "$target_platform" = "windows" ]; then
        waifu2x_name="waifu2x-ncnn-vulkan.exe"
    fi
    
    if [ -f "$source_dir/$waifu2x_name" ]; then
        cp "$source_dir/$waifu2x_name" "../assets/executables/$target_platform/"
        echo "✅ $waifu2x_name скопирован"
    else
        echo "⚠️ $waifu2x_name не найден"
    fi
}

# Копируем waifu2x и модели для каждой платформы
echo ""
echo "=========================================="
echo "📦 КОПИРОВАНИЕ WAIFU2X И МОДЕЛЕЙ"
echo "=========================================="

if [ -n "$MACOS_DIR" ]; then
    copy_waifu2x_models "$MACOS_DIR" "macos"
fi

if [ -n "$WINDOWS_DIR" ]; then
    copy_waifu2x_models "$WINDOWS_DIR" "windows"
fi

if [ -n "$UBUNTU_DIR" ]; then
    copy_waifu2x_models "$UBUNTU_DIR" "linux"
fi

# Ищем и копируем FFmpeg для каждой платформы
echo ""
echo "=========================================="
echo "📦 ПОИСК И КОПИРОВАНИЕ FFMPEG"
echo "=========================================="

find_and_copy_ffmpeg "linux" "ffmpeg"
find_and_copy_ffmpeg "windows" "ffmpeg.exe"
find_and_copy_ffmpeg "macos" "ffmpeg"

# Возвращаемся в корень
cd ..
rm -rf "$TEMP_DIR"

echo ""
echo "✅ Скачивание завершено!"

# ФИНАЛЬНАЯ ПРОВЕРКА
echo ""
echo "=========================================="
echo "📊 ФИНАЛЬНАЯ ПРОВЕРКА РАЗМЕРОВ ФАЙЛОВ"
echo "=========================================="
all_good=true

for platform in linux windows macos; do
    echo "📁 $platform:"
    
    # Определяем имя FFmpeg
    ffmpeg_name="ffmpeg"
    if [ "$platform" = "windows" ]; then
        ffmpeg_name="ffmpeg.exe"
    fi
    
    # Проверяем FFmpeg
    if [ -f "assets/executables/$platform/$ffmpeg_name" ]; then
        size=$(stat -c%s "assets/executables/$platform/$ffmpeg_name" 2>/dev/null || stat -f%z "assets/executables/$platform/$ffmpeg_name" 2>/dev/null || echo "0")
        size_mb=$((size / 1024 / 1024))
        
        if [ $size_mb -gt 50 ]; then
            echo "  ✅ FFmpeg: ${size_mb}MB - НАСТОЯЩИЙ ФАЙЛ!"
        else
            echo "  💀 FFmpeg: ${size_mb}MB - СЛИШКОМ МАЛ!"
            all_good=false
        fi
    else
        echo "  ❌ FFmpeg ($ffmpeg_name) не найден"
        all_good=false
    fi
    
    # Проверяем waifu2x
    waifu2x_name="waifu2x-ncnn-vulkan"
    if [ "$platform" = "windows" ]; then
        waifu2x_name="waifu2x-ncnn-vulkan.exe"
    fi
    
    if [ -f "assets/executables/$platform/$waifu2x_name" ]; then
        size=$(stat -c%s "assets/executables/$platform/$waifu2x_name" 2>/dev/null || stat -f%z "assets/executables/$platform/$waifu2x_name" 2>/dev/null || echo "0")
        size_mb=$((size / 1024 / 1024))
        echo "  ✅ waifu2x: ${size_mb}MB"
    else
        echo "  ❌ waifu2x не найден"
        all_good=false
    fi
    
    # Проверяем модели
    if [ -d "assets/executables/$platform/models-cunet" ]; then
        model_count=$(find "assets/executables/$platform/models-cunet" -name "*.param" 2>/dev/null | wc -l)
        if [ $model_count -gt 0 ]; then
            echo "  ✅ Модели: $model_count файлов .param"
        else
            echo "  ❌ Модели не найдены"
            all_good=false
        fi
    else
        echo "  ❌ Папка моделей не найдена"
        all_good=false
    fi
    echo "---"
done

if [ "$all_good" = true ]; then
    echo ""
    echo "🎯 Все файлы успешно загружены и проверены!"
    exit 0
else
    echo ""
    echo "❌ Обнаружены проблемы с загрузкой файлов!"
    exit 1
fi
