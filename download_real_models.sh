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

# НОВОЕ: Скачиваем FFmpeg из надежных источников
echo "📦 Скачиваем FFmpeg из проверенных источников..."

# Получаем последнюю версию FFmpeg для Windows (gyan.dev - самый надежный)
echo "🪟 Скачиваем FFmpeg для Windows..."
download_with_retry "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" "ffmpeg-windows-gyan.zip" || {
    echo "⚠️ Основной источник не работает, пробуем альтернативный..."
    download_with_retry "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip" "ffmpeg-windows-btbn.zip" || {
        echo "⚠️ Оба источника Windows FFmpeg недоступны, будем искать в waifu2x"
    }
}

# FFmpeg для Linux  
echo "🐧 Скачиваем FFmpeg для Linux..."
download_with_retry "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz" "ffmpeg-linux.tar.xz" || echo "⚠️ FFmpeg Linux не скачан"

# FFmpeg для macOS
echo "🍎 Скачиваем FFmpeg для macOS..."
download_with_retry "https://evermeet.cx/ffmpeg/ffmpeg-6.1.zip" "ffmpeg-macos.zip" || {
    echo "⚠️ Пробуем альтернативный источник macOS FFmpeg..."
    download_with_retry "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-macos64-gpl.tar.xz" "ffmpeg-macos.tar.xz" || echo "⚠️ FFmpeg macOS не скачан"
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

# Windows FFmpeg (несколько вариантов)
if [ -f "ffmpeg-windows-gyan.zip" ]; then
    echo "Распаковка Windows FFmpeg (Gyan)..."
    unzip -q ffmpeg-windows-gyan.zip && echo "✅ Windows FFmpeg (Gyan) распакован" || echo "❌ Ошибка распаковки"
elif [ -f "ffmpeg-windows-btbn.zip" ]; then
    echo "Распаковка Windows FFmpeg (BtbN)..."
    unzip -q ffmpeg-windows-btbn.zip && echo "✅ Windows FFmpeg (BtbN) распакован" || echo "❌ Ошибка распаковки"
fi

# macOS FFmpeg
if [ -f "ffmpeg-macos.zip" ]; then
    echo "Распаковка macOS FFmpeg (evermeet)..."
    unzip -q ffmpeg-macos.zip && echo "✅ macOS FFmpeg распакован" || echo "❌ Ошибка распаковки"
elif [ -f "ffmpeg-macos.tar.xz" ]; then
    echo "Распаковка macOS FFmpeg (BtbN)..."
    tar -xf ffmpeg-macos.tar.xz && echo "✅ macOS FFmpeg распакован" || echo "❌ Ошибка распаковки"
fi

# Показываем что распаковалось
echo "📁 Содержимое после распаковки:"
ls -la

# Находим waifu2x папки
MACOS_DIR=$(find . -name "*macos*" -type d | head -1)
WINDOWS_DIR=$(find . -name "*windows*" -type d | head -1)
UBUNTU_DIR=$(find . -name "*ubuntu*" -type d | head -1)

echo "📁 Найденные waifu2x папки:"
echo "  macOS: $MACOS_DIR"
echo "  Windows: $WINDOWS_DIR"
echo "  Ubuntu: $UBUNTU_DIR"

# Функция поиска FFmpeg в любой папке
find_and_copy_ffmpeg() {
    local target_platform=$1
    local executable_name=$2
    
    echo "🔍 Поиск FFmpeg для $target_platform (ищем $executable_name)..."
    
    # Ищем во всех распакованных папках
    local found_ffmpeg=""
    
    # Поиск по всем возможным местам
    for search_path in . */bin */ffmpeg* ffmpeg* *ffmpeg*; do
        if [ -d "$search_path" ]; then
            local candidate=$(find "$search_path" -name "$executable_name" -type f 2>/dev/null | head -1)
            if [ -n "$candidate" ] && [ -f "$candidate" ]; then
                local size=$(stat -c%s "$candidate" 2>/dev/null || stat -f%z "$candidate" 2>/dev/null || echo "0")
                local size_mb=$((size / 1024 / 1024))
                
                echo "  Найден кандидат: $candidate (${size_mb}MB)"
                
                if [ $size_mb -gt 10 ]; then
                    found_ffmpeg="$candidate"
                    echo "  ✅ Подходящий FFmpeg найден: $candidate"
                    break
                else
                    echo "  ⚠️ Слишком мал: $candidate"
                fi
            fi
        fi
    done
    
    # Копируем если найден
    if [ -n "$found_ffmpeg" ] && [ -f "$found_ffmpeg" ]; then
        cp "$found_ffmpeg" "../assets/executables/$target_platform/$executable_name"
        local final_size=$(stat -c%s "../assets/executables/$target_platform/$executable_name" 2>/dev/null || stat -f%z "../assets/executables/$target_platform/$executable_name" 2>/dev/null || echo "0")
        local final_size_mb=$((final_size / 1024 / 1024))
        echo "✅ FFmpeg скопирован для $target_platform: ${final_size_mb}MB"
        return 0
    else
        echo "❌ FFmpeg для $target_platform не найден"
        return 1
    fi
}

# Функция копирования waifu2x и моделей
copy_waifu2x_models() {
    local source_dir=$1
    local target_platform=$2
    
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
echo "📦 Копирование waifu2x и моделей..."

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
echo "📦 Поиск и копирование FFmpeg..."

find_and_copy_ffmpeg "linux" "ffmpeg"
find_and_copy_ffmpeg "windows" "ffmpeg.exe"
find_and_copy_ffmpeg "macos" "ffmpeg"

# Дополнительно: если FFmpeg в Windows или Linux не найден, копируем из waifu2x папок
echo "🔄 Дополнительная проверка FFmpeg в waifu2x архивах..."

# Для Windows
if [ ! -f "../assets/executables/windows/ffmpeg.exe" ] && [ -n "$WINDOWS_DIR" ]; then
    if [ -f "$WINDOWS_DIR/ffmpeg.exe" ]; then
        cp "$WINDOWS_DIR/ffmpeg.exe" "../assets/executables/windows/"
        echo "✅ FFmpeg скопирован из Windows waifu2x архива"
    fi
fi

# Для Linux  
if [ ! -f "../assets/executables/linux/ffmpeg" ] && [ -n "$UBUNTU_DIR" ]; then
    if [ -f "$UBUNTU_DIR/ffmpeg" ]; then
        cp "$UBUNTU_DIR/ffmpeg" "../assets/executables/linux/"
        echo "✅ FFmpeg скопирован из Linux waifu2x архива"
    fi
fi

# Для macOS
if [ ! -f "../assets/executables/macos/ffmpeg" ] && [ -n "$MACOS_DIR" ]; then
    if [ -f "$MACOS_DIR/ffmpeg" ]; then
        cp "$MACOS_DIR/ffmpeg" "../assets/executables/macos/"
        echo "✅ FFmpeg скопирован из macOS waifu2x архива"
    fi
fi

# Возвращаемся в корень
cd ..
rm -rf "$TEMP_DIR"

echo "✅ Скачивание завершено!"

# ФИНАЛЬНАЯ ПРОВЕРКА
echo "📊 ФИНАЛЬНАЯ ПРОВЕРКА РАЗМЕРОВ ФАЙЛОВ:"
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
