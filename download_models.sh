#!/bin/bash

echo "📥 Скачиваем все файлы модели waifu2x-ncnn-vulkan..."

# ПРАВИЛЬНЫЙ базовый URL (с models/ в начале)
BASE_URL="https://github.com/nihui/waifu2x-ncnn-vulkan/raw/master/models"

# Создаем структуру папок для всех платформ
for platform in macos windows linux; do
    mkdir -p "assets/executables/$platform/models-cunet"
    mkdir -p "assets/executables/$platform/models-upconv_7_anime_style_art_rgb"
    mkdir -p "assets/executables/$platform/models-upconv_7_photo"
done

# Функция для скачивания файла для всех платформ
download_for_all_platforms() {
    local model_dir=$1
    local filename=$2
    local url="$BASE_URL/$model_dir/$filename"
    
    echo "📥 Скачиваем: $filename"
    
    for platform in macos windows linux; do
        local target_path="assets/executables/$platform/$model_dir/$filename"
        curl -L -f -o "$target_path" "$url"
        
        if [ $? -eq 0 ]; then
            local size=$(ls -lh "$target_path" | awk '{print $5}')
            echo "✅ $platform: $filename ($size)"
        else
            echo "❌ $platform: Ошибка скачивания $filename"
        fi
    done
}

# CUNET модель - основная
echo "📁 Скачиваем CUNET модель..."
download_for_all_platforms "models-cunet" "noise0_model.bin"
download_for_all_platforms "models-cunet" "noise0_model.param"
download_for_all_platforms "models-cunet" "noise0_scale2.0x_model.bin"
download_for_all_platforms "models-cunet" "noise0_scale2.0x_model.param"
download_for_all_platforms "models-cunet" "noise1_model.bin"
download_for_all_platforms "models-cunet" "noise1_model.param"
download_for_all_platforms "models-cunet" "noise1_scale2.0x_model.bin"
download_for_all_platforms "models-cunet" "noise1_scale2.0x_model.param"
download_for_all_platforms "models-cunet" "noise2_model.bin"
download_for_all_platforms "models-cunet" "noise2_model.param"
download_for_all_platforms "models-cunet" "noise2_scale2.0x_model.bin"
download_for_all_platforms "models-cunet" "noise2_scale2.0x_model.param"
download_for_all_platforms "models-cunet" "noise3_model.bin"
download_for_all_platforms "models-cunet" "noise3_model.param"
download_for_all_platforms "models-cunet" "noise3_scale2.0x_model.bin"
download_for_all_platforms "models-cunet" "noise3_scale2.0x_model.param"

# ANIME модель
echo "📁 Скачиваем ANIME модель..."
download_for_all_platforms "models-upconv_7_anime_style_art_rgb" "noise0_scale2.0x_model.bin"
download_for_all_platforms "models-upconv_7_anime_style_art_rgb" "noise0_scale2.0x_model.param"
download_for_all_platforms "models-upconv_7_anime_style_art_rgb" "noise1_scale2.0x_model.bin"
download_for_all_platforms "models-upconv_7_anime_style_art_rgb" "noise1_scale2.0x_model.param"
download_for_all_platforms "models-upconv_7_anime_style_art_rgb" "noise2_scale2.0x_model.bin"
download_for_all_platforms "models-upconv_7_anime_style_art_rgb" "noise2_scale2.0x_model.param"
download_for_all_platforms "models-upconv_7_anime_style_art_rgb" "noise3_scale2.0x_model.bin"
download_for_all_platforms "models-upconv_7_anime_style_art_rgb" "noise3_scale2.0x_model.param"

# PHOTO модель
echo "📁 Скачиваем PHOTO модель..."
download_for_all_platforms "models-upconv_7_photo" "noise0_scale2.0x_model.bin"
download_for_all_platforms "models-upconv_7_photo" "noise0_scale2.0x_model.param"
download_for_all_platforms "models-upconv_7_photo" "noise1_scale2.0x_model.bin"
download_for_all_platforms "models-upconv_7_photo" "noise1_scale2.0x_model.param"
download_for_all_platforms "models-upconv_7_photo" "noise2_scale2.0x_model.bin"
download_for_all_platforms "models-upconv_7_photo" "noise2_scale2.0x_model.param"
download_for_all_platforms "models-upconv_7_photo" "noise3_scale2.0x_model.bin"
download_for_all_platforms "models-upconv_7_photo" "noise3_scale2.0x_model.param"

echo "✅ Скачивание завершено!"
echo "📊 Проверяем размеры файлов..."

# Проверяем результат
for platform in macos windows linux; do
    echo "📁 $platform:"
    find "assets/executables/$platform" -name "*.bin" -o -name "*.param" | head -5 | xargs ls -lh
done
