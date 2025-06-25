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
rm -rf "$TEMP_DIR"  # Удаляем если существует
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
            else
                echo "❌ Файл $output пуст или не создался"
            fi
        else
            echo "❌ Ошибка скачивания $output (попытка $i)"
        fi
        sleep 5
    done
    
    echo "❌ Не удалось скачать $output после $attempts попыток"
    return 1
}

# Скачиваем архивы
echo "📦 Скачиваем waifu2x release 20220728..."

download_with_retry "https://github.com/nihui/waifu2x-ncnn-vulkan/releases/download/20220728/waifu2x-ncnn-vulkan-20220728-macos.zip" "waifu2x-macos.zip" || exit 1
download_with_retry "https://github.com/nihui/waifu2x-ncnn-vulkan/releases/download/20220728/waifu2x-ncnn-vulkan-20220728-windows.zip" "waifu2x-windows.zip" || exit 1
download_with_retry "https://github.com/nihui/waifu2x-ncnn-vulkan/releases/download/20220728/waifu2x-ncnn-vulkan-20220728-ubuntu.zip" "waifu2x-ubuntu.zip" || exit 1

# ДОПОЛНИТЕЛЬНО: Скачиваем FFmpeg отдельно для каждой платформы
echo "📦 Скачиваем FFmpeg отдельно..."

# FFmpeg для Linux
download_with_retry "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz" "ffmpeg-linux.tar.xz" || echo "⚠️ FFmpeg Linux не скачан, будем искать в waifu2x архиве"

# FFmpeg для Windows  
download_with_retry "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip" "ffmpeg-windows.zip" || echo "⚠️ FFmpeg Windows не скачан, будем искать в waifu2x архиве"

# FFmpeg для macOS (если найдем)
download_with_retry "https://evermeet.cx/ffmpeg/ffmpeg-6.1.zip" "ffmpeg-macos.zip" || echo "⚠️ FFmpeg macOS не скачан, будем искать в waifu2x архиве"

# Распаковываем waifu2x архивы
echo "📂 Распаковываем waifu2x архивы..."
unzip -q waifu2x-macos.zip || exit 1
unzip -q waifu2x-windows.zip || exit 1  
unzip -q waifu2x-ubuntu.zip || exit 1

# Распаковываем FFmpeg архивы
echo "📂 Распаковываем FFmpeg архивы..."
if [ -f "ffmpeg-linux.tar.xz" ]; then
    tar -xf ffmpeg-linux.tar.xz || echo "⚠️ Ошибка распаковки FFmpeg Linux"
fi

if [ -f "ffmpeg-windows.zip" ]; then
    unzip -q ffmpeg-windows.zip || echo "⚠️ Ошибка распаковки FFmpeg Windows"
fi

if [ -f "ffmpeg-macos.zip" ]; then
    unzip -q ffmpeg-macos.zip || echo "⚠️ Ошибка распаковки FFmpeg macOS"
fi

# Показываем что распаковалось
echo "📁 Содержимое после распаковки:"
ls -la

# Находим распакованные папки
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

echo "📁 Найденные FFmpeg папки:"
echo "  Linux: $FFMPEG_LINUX_DIR"
echo "  Windows: $FFMPEG_WINDOWS_DIR"

# Функция поиска FFmpeg в папке
find_ffmpeg() {
    local dir=$1
    local platform=$2
    
    echo "🔍 Ищем FFmpeg в $dir для $platform..."
    
    if [ -d "$dir" ]; then
        find "$dir" -name "ffmpeg*" -type f | while read ffmpeg_file; do
            local size=$(stat -c%s "$ffmpeg_file" 2>/dev/null || stat -f%z "$ffmpeg_file" 2>/dev/null || echo "0")
            local size_mb=$((size / 1024 / 1024))
            echo "  Найден: $ffmpeg_file (${size_mb}MB)"
        done
    fi
}

# Ищем FFmpeg в каждой папке
for dir in $MACOS_DIR $WINDOWS_DIR $UBUNTU_DIR $FFMPEG_LINUX_DIR $FFMPEG_WINDOWS_DIR; do
    if [ -n "$dir" ] && [ -d "$dir" ]; then
        find_ffmpeg "$dir" "$(basename "$dir")"
    fi
done

# Функция копирования моделей и исполняемых файлов
copy_models() {
    local source_dir=$1
    local target_platform=$2
    
    echo "📥 Копируем файлы для $target_platform из $source_dir..."
    
    if [ ! -d "$source_dir" ]; then
        echo "❌ Папка $source_dir не найдена"
        return 1
    fi
    
    # Показываем содержимое исходной папки
    echo "📋 Содержимое $source_dir:"
    ls -la "$source_dir/"
    
    # Копируем модели
    for model_dir in "models-cunet" "models-upconv_7_anime_style_art_rgb" "models-upconv_7_photo"; do
        if [ -d "$source_dir/$model_dir" ]; then
            cp -r "$source_dir/$model_dir"/* "../assets/executables/$target_platform/$model_dir/"
            echo "✅ $model_dir скопирована для $target_platform"
        else
            echo "⚠️ $model_dir не найдена в $source_dir"
        fi
    done
    
    # Копируем waifu2x
    if [ -f "$source_dir/waifu2x-ncnn-vulkan" ]; then
        cp "$source_dir/waifu2x-ncnn-vulkan" "../assets/executables/$target_platform/"
        echo "✅ waifu2x-ncnn-vulkan скопирован для $target_platform"
    elif [ -f "$source_dir/waifu2x-ncnn-vulkan.exe" ]; then
        cp "$source_dir/waifu2x-ncnn-vulkan.exe" "../assets/executables/$target_platform/"
        echo "✅ waifu2x-ncnn-vulkan.exe скопирован для $target_platform"
    else
        echo "⚠️ waifu2x исполняемый файл не найден в $source_dir"
    fi
}

# Функция копирования FFmpeg
copy_ffmpeg() {
    local source_dir=$1
    local target_platform=$2
    local ffmpeg_name=$3
    
    echo "📥 Ищем FFmpeg для $target_platform..."
    
    # Сначала ищем в waifu2x папке
    local ffmpeg_path=""
    if [ -f "$source_dir/$ffmpeg_name" ]; then
        ffmpeg_path="$source_dir/$ffmpeg_name"
    else
        # Ищем рекурсивно
        ffmpeg_path=$(find "$source_dir" -name "$ffmpeg_name" -type f | head -1)
    fi
    
    if [ -n "$ffmpeg_path" ] && [ -f "$ffmpeg_path" ]; then
        local size=$(stat -c%s "$ffmpeg_path" 2>/dev/null || stat -f%z "$ffmpeg_path" 2>/dev/null || echo "0")
        local size_mb=$((size / 1024 / 1024))
        
        if [ $size_mb -gt 10 ]; then
            cp "$ffmpeg_path" "../assets/executables/$target_platform/$ffmpeg_name"
            echo "✅ FFmpeg скопирован для $target_platform (${size_mb}MB)"
            return 0
        else
            echo "⚠️ FFmpeg найден но слишком мал (${size_mb}MB): $ffmpeg_path"
        fi
    fi
    
    return 1
}

# Копируем FFmpeg из отдельных архивов если есть
copy_standalone_ffmpeg() {
    local platform=$1
    local ffmpeg_name=$2
    
    case $platform in
        "linux")
            if [ -n "$FFMPEG_LINUX_DIR" ]; then
                local ffmpeg_path=$(find "$FFMPEG_LINUX_DIR" -name "ffmpeg" -type f | head -1)
                if [ -n "$ffmpeg_path" ] && [ -f "$ffmpeg_path" ]; then
                    cp "$ffmpeg_path" "../assets/executables/$platform/ffmpeg"
                    echo "✅ Standalone FFmpeg скопирован для Linux"
                    return 0
                fi
            fi
            ;;
        "windows")
            if [ -n "$FFMPEG_WINDOWS_DIR" ]; then
                local ffmpeg_path=$(find "$FFMPEG_WINDOWS_DIR" -name "ffmpeg.exe" -type f | head -1)
                if [ -n "$ffmpeg_path" ] && [ -f "$ffmpeg_path" ]; then
                    cp "$ffmpeg_path" "../assets/executables/$platform/ffmpeg.exe"
                    echo "✅ Standalone FFmpeg скопирован для Windows"
                    return 0
                fi
            fi
            ;;
        "macos")
            if [ -f "ffmpeg" ]; then  # Из evermeet архива
                cp "ffmpeg" "../assets/executables/$platform/ffmpeg"
                echo "✅ Standalone FFmpeg скопирован для macOS"
                return 0
            fi
            ;;
    esac
    
    return 1
}

# Копируем для каждой платформы
echo "📦 Копирование файлов..."

# macOS
if [ -n "$MACOS_DIR" ]; then
    copy_models "$MACOS_DIR" "macos"
    if ! copy_ffmpeg "$MACOS_DIR" "macos" "ffmpeg"; then
        copy_standalone_ffmpeg "macos" "ffmpeg"
    fi
fi

# Windows  
if [ -n "$WINDOWS_DIR" ]; then
    copy_models "$WINDOWS_DIR" "windows"
    if ! copy_ffmpeg "$WINDOWS_DIR" "windows" "ffmpeg.exe"; then
        copy_standalone_ffmpeg "windows" "ffmpeg.exe"
    fi
fi

# Linux
if [ -n "$UBUNTU_DIR" ]; then
    copy_models "$UBUNTU_DIR" "linux"
    if ! copy_ffmpeg "$UBUNTU_DIR" "linux" "ffmpeg"; then
        copy_standalone_ffmpeg "linux" "ffmpeg"
    fi
fi

# Возвращаемся в корень и удаляем временную папку
cd ..
rm -rf "$TEMP_DIR"

echo "✅ Скачивание завершено!"

# ФИНАЛЬНАЯ ПРОВЕРКА размеров файлов
echo "📊 ФИНАЛЬНАЯ ПРОВЕРКА РАЗМЕРОВ ФАЙЛОВ:"
all_good=true

for platform in macos windows linux; do
    echo "📁 $platform:"
    
    # Проверяем FFmpeg
    ffmpeg_name="ffmpeg"
    if [ "$platform" = "windows" ]; then
        ffmpeg_name="ffmpeg.exe"
    fi
    
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
        echo "  ❌ FFmpeg не найден"
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
