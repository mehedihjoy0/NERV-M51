#!/usr/bin/env bash
#
# Copyright (C) 2023 Salvo Giangreco
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# [
source "$SRC_DIR/scripts/utils/build_utils.sh" || exit 1

SOURCE_FINGERPRINT="$(GET_PROP "$WORK_DIR/system/system/build.prop" "ro.system.build.fingerprint")"
SOURCE_FINGERPRINT="${SOURCE_FINGERPRINT//$(GET_PROP "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/build.prop" "ro.build.product")/$(GET_PROP "$FW_DIR/$SOURCE_FIRMWARE_PATH/vendor/build.prop" "ro.product.vendor.device")}"
TARGET_FINGERPRINT="$(GET_PROP "$WORK_DIR/vendor/build.prop" "ro.vendor.build.fingerprint")"
TARGET_FINGERPRINT="${TARGET_FINGERPRINT//$(GET_PROP "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/build.prop" "ro.build.product")/$(GET_PROP "$FW_DIR/$TARGET_FIRMWARE_PATH/vendor/build.prop" "ro.product.vendor.device")}"

TMP_DIR="$OUT_DIR/zip"

ZIP_FILE_SUFFIX="-sign.zip"
! $ROM_IS_OFFICIAL && ZIP_FILE_SUFFIX=".zip"

TARGET_DEVICE="$TARGET_CODENAME"
[ -n "$TARGET_MODEL" ] && TARGET_DEVICE="$TARGET_MODEL"

ZIP_FILE_NAME="ProjectNERV_${ROM_VERSION}_$(date +%Y%m%d)_${TARGET_DEVICE}${ZIP_FILE_SUFFIX}"
while [ -f "$OUT_DIR/$ZIP_FILE_NAME" ]; do
    INCREMENTAL=$((INCREMENTAL + 1))
    ZIP_FILE_NAME="ProjectNERV_${ROM_VERSION}_$(date +%Y%m%d)-${INCREMENTAL}_${TARGET_DEVICE}${ZIP_FILE_SUFFIX}"
done

PRIVATE_KEY_PATH="$SRC_DIR/security/"
PUBLIC_KEY_PATH="$SRC_DIR/security/"
if $ROM_IS_OFFICIAL; then
    PRIVATE_KEY_PATH+="platform"
    PUBLIC_KEY_PATH+="platform"
else
    PRIVATE_KEY_PATH+="aosp_platform"
    PUBLIC_KEY_PATH+="aosp_platform"
fi
PRIVATE_KEY_PATH+=".pk8"
PUBLIC_KEY_PATH+=".x509.pem"

trap 'rm -rf "$TMP_DIR"' EXIT INT

# https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/build_super_image.py#72
BUILD_SUPER_EMPTY()
{
    local CMD

    CMD="lpmake"
    # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/build_super_image.py#75
    CMD+=" --metadata-size \"65536\""
    # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/core/config.mk#1033
    CMD+=" --super-name \"super\""
    # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/build_super_image.py#85
    CMD+=" --metadata-slots \"2\""
    CMD+=" --device \"super:$TARGET_SUPER_PARTITION_SIZE\""
    CMD+=" --group \"$TARGET_SUPER_GROUP_NAME:$TARGET_SUPER_GROUP_SIZE\""
    if [ -f "$TMP_DIR/system.img" ]; then
        CMD+=" --partition \"system:readonly:0:$TARGET_SUPER_GROUP_NAME\""
    fi
    if [ -f "$TMP_DIR/vendor.img" ]; then
        CMD+=" --partition \"vendor:readonly:0:$TARGET_SUPER_GROUP_NAME\""
    fi
    if [ -f "$TMP_DIR/product.img" ]; then
        CMD+=" --partition \"product:readonly:0:$TARGET_SUPER_GROUP_NAME\""
    fi
    if [ -f "$TMP_DIR/system_ext.img" ]; then
        CMD+=" --partition \"system_ext:readonly:0:$TARGET_SUPER_GROUP_NAME\""
    fi
    if [ -f "$TMP_DIR/odm.img" ]; then
        CMD+=" --partition \"odm:readonly:0:$TARGET_SUPER_GROUP_NAME\""
    fi
    if [ -f "$TMP_DIR/vendor_dlkm.img" ]; then
        CMD+=" --partition \"vendor_dlkm:readonly:0:$TARGET_SUPER_GROUP_NAME\""
    fi
    if [ -f "$TMP_DIR/odm_dlkm.img" ]; then
        CMD+=" --partition \"odm_dlkm:readonly:0:$TARGET_SUPER_GROUP_NAME\""
    fi
    if [ -f "$TMP_DIR/system_dlkm.img" ]; then
        CMD+=" --partition \"system_dlkm:readonly:0:$TARGET_SUPER_GROUP_NAME\""
    fi
    CMD+=" --output \"$TMP_DIR/unsparse_super_empty.img\""

    EVAL "$CMD" || exit 1
}

CREATE_ROM_ZIP()
{
    local STORED_LIST="$OUT_DIR/stored.txt"
    local COMPRESSED_LIST="$OUT_DIR/compressed.txt"

    [ -f "$STORED_LIST" ] || [ -f "$COMPRESSED_LIST" ] && rm -f "$STORED_LIST" "$COMPRESSED_LIST"
    touch "$STORED_LIST" "$COMPRESSED_LIST"

    EVAL "rm -f \"$OUT_DIR/rom.zip\"" || exit 1

    find "$TMP_DIR" -type f \( -name "*.new.dat.br" -o -name "*.patch.dat" \) >> "$STORED_LIST"
    find "$TMP_DIR/META-INF" -type f >> "$STORED_LIST"
    find "$TMP_DIR" -type f \
        ! -name "*.zip" \
        ! -name "*.new.dat.br" \
        ! -name "*.patch.dat" \
        ! -path "$TMP_DIR/META-INF/*" >> "$COMPRESSED_LIST"

    sed -i "s|^$TMP_DIR/||g" "$STORED_LIST" \
        && sed -i "s|^$TMP_DIR/||g" "$COMPRESSED_LIST"

    (
    cd "$TMP_DIR" || exit 1
    EVAL "7z a -tzip -mx=0 -mmt=$(nproc) \"$TMP_DIR/rom.zip\" @\"$STORED_LIST\"" || exit 1
    EVAL "7z a -tzip -mx=9 -mmt=$(nproc) \"$TMP_DIR/rom.zip\" @\"$COMPRESSED_LIST\"" || exit 1
    )

    rm -f "$STORED_LIST" "$COMPRESSED_LIST"
}

GENERATE_BUILD_INFO()
{
    local BUILD_INFO_FILE="$TMP_DIR/build_info.txt"

    {
        echo "device=$TARGET_CODENAME"
        echo "version=$ROM_VERSION"
        echo "timestamp=$ROM_BUILD_TIMESTAMP"
        echo "security_patch_version=$(GET_PROP "system" "ro.build.version.security_patch")"
    } > "$BUILD_INFO_FILE"
}

# https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/common.py#4042
GENERATE_OP_LIST()
{
    local OP_LIST_FILE="$TMP_DIR/dynamic_partitions_op_list"

    local HAS_SYSTEM=false
    local HAS_VENDOR=false
    local HAS_PRODUCT=false
    local HAS_SYSTEM_EXT=false
    local HAS_ODM=false
    local HAS_VENDOR_DLKM=false
    local HAS_ODM_DLKM=false
    local HAS_SYSTEM_DLKM=false

    [ -f "$TMP_DIR/system.img" ] && HAS_SYSTEM=true
    [ -f "$TMP_DIR/vendor.img" ] && HAS_VENDOR=true
    [ -f "$TMP_DIR/product.img" ] && HAS_PRODUCT=true
    [ -f "$TMP_DIR/system_ext.img" ] && HAS_SYSTEM_EXT=true
    [ -f "$TMP_DIR/odm.img" ] && HAS_ODM=true
    [ -f "$TMP_DIR/vendor_dlkm.img" ] && HAS_VENDOR_DLKM=true
    [ -f "$TMP_DIR/odm_dlkm.img" ] && HAS_ODM_DLKM=true
    [ -f "$TMP_DIR/system_dlkm.img" ] && HAS_SYSTEM_DLKM=true

    local PARTITION_SIZE=0
    local OCCUPIED_SPACE=0

    {
        echo "# Remove all existing dynamic partitions and groups before applying full OTA"
        echo "remove_all_groups"
        echo "# Add group $TARGET_SUPER_GROUP_NAME with maximum size $TARGET_SUPER_GROUP_SIZE"
        echo "add_group $TARGET_SUPER_GROUP_NAME $TARGET_SUPER_GROUP_SIZE"
        $HAS_SYSTEM && echo "# Add partition system to group $TARGET_SUPER_GROUP_NAME"
        $HAS_SYSTEM && echo "add system $TARGET_SUPER_GROUP_NAME"
        $HAS_VENDOR && echo "# Add partition vendor to group $TARGET_SUPER_GROUP_NAME"
        $HAS_VENDOR && echo "add vendor $TARGET_SUPER_GROUP_NAME"
        $HAS_PRODUCT && echo "# Add partition product to group $TARGET_SUPER_GROUP_NAME"
        $HAS_PRODUCT && echo "add product $TARGET_SUPER_GROUP_NAME"
        $HAS_SYSTEM_EXT && echo "# Add partition system_ext to group $TARGET_SUPER_GROUP_NAME"
        $HAS_SYSTEM_EXT && echo "add system_ext $TARGET_SUPER_GROUP_NAME"
        $HAS_ODM && echo "# Add partition odm to group $TARGET_SUPER_GROUP_NAME"
        $HAS_ODM && echo "add odm $TARGET_SUPER_GROUP_NAME"
        $HAS_VENDOR_DLKM && echo "# Add partition vendor_dlkm to group $TARGET_SUPER_GROUP_NAME"
        $HAS_VENDOR_DLKM && echo "add vendor_dlkm $TARGET_SUPER_GROUP_NAME"
        $HAS_ODM_DLKM && echo "# Add partition odm_dlkm to group $TARGET_SUPER_GROUP_NAME"
        $HAS_ODM_DLKM && echo "add odm_dlkm $TARGET_SUPER_GROUP_NAME"
        $HAS_SYSTEM_DLKM && echo "# Add partition system_dlkm to group $TARGET_SUPER_GROUP_NAME"
        $HAS_SYSTEM_DLKM && echo "add system_dlkm $TARGET_SUPER_GROUP_NAME"
        if $HAS_SYSTEM; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/system.img")"
            echo "# Grow partition system from 0 to $PARTITION_SIZE"
            echo "resize system $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
        if $HAS_VENDOR; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/vendor.img")"
            echo "# Grow partition vendor from 0 to $PARTITION_SIZE"
            echo "resize vendor $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
        if $HAS_PRODUCT; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/product.img")"
            echo "# Grow partition product from 0 to $PARTITION_SIZE"
            echo "resize product $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
        if $HAS_SYSTEM_EXT; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/system_ext.img")"
            echo "# Grow partition system_ext from 0 to $PARTITION_SIZE"
            echo "resize system_ext $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
        if $HAS_ODM; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/odm.img")"
            echo "# Grow partition odm from 0 to $PARTITION_SIZE"
            echo "resize odm $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
        if $HAS_VENDOR_DLKM; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/vendor_dlkm.img")"
            echo "# Grow partition vendor_dlkm from 0 to $PARTITION_SIZE"
            echo "resize vendor_dlkm $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
        if $HAS_ODM_DLKM; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/odm_dlkm.img")"
            echo "# Grow partition odm_dlkm from 0 to $PARTITION_SIZE"
            echo "resize odm_dlkm $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
        if $HAS_SYSTEM_DLKM; then
            PARTITION_SIZE="$(GET_IMAGE_SIZE "$TMP_DIR/system_dlkm.img")"
            echo "# Grow partition system_dlkm from 0 to $PARTITION_SIZE"
            echo "resize system_dlkm $PARTITION_SIZE"
            OCCUPIED_SPACE=$((OCCUPIED_SPACE + PARTITION_SIZE))
        fi
    } > "$OP_LIST_FILE"

    if [[ "$OCCUPIED_SPACE" -gt "$TARGET_SUPER_GROUP_SIZE" ]]; then
        LOGE "OS size ($OCCUPIED_SPACE) is bigger than the target group size ($TARGET_SUPER_GROUP_SIZE)"
        exit 1
    fi
}

GENERATE_OTA_METADATA()
{
    local PROTO_FILE="$SRC_DIR/external/android-tools/vendor/build/tools/releasetools/ota_metadata.proto"

    local INCREMENTAL
    local RELEASE
    local SECURITY_PATCH_LEVEL
    local TIMESTAMP

    INCREMENTAL="$(GET_PROP "system" "ro.build.version.incremental")"
    RELEASE="$(GET_PROP "system" "ro.build.version.release")"
    SECURITY_PATCH_LEVEL="$(GET_PROP "system" "ro.build.version.security_patch")"
    TIMESTAMP="$(GET_PROP "system" "ro.build.date.utc")"

    mkdir -p "$TMP_DIR/META-INF/com/android"

    # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/ota_utils.py#259
    if [ -f "$PROTO_FILE" ]; then
        local MESSAGE

        MESSAGE+="type: BLOCK"
        MESSAGE+=", precondition: {device: \\\"$TARGET_CODENAME\\\"}"
        MESSAGE+=", postcondition: {device: \\\"$TARGET_CODENAME\\\""
        MESSAGE+=", build: \\\"$SOURCE_FINGERPRINT\\\""
        MESSAGE+=", build_incremental: \\\"$INCREMENTAL\\\""
        MESSAGE+=", timestamp: $TIMESTAMP"
        MESSAGE+=", sdk_level: \\\"$RELEASE\\\""
        MESSAGE+=", security_patch_level: \\\"$SECURITY_PATCH_LEVEL\\\"}"

        EVAL "protoc --encode=build.tools.releasetools.OtaMetadata --proto_path=\"$(dirname "$PROTO_FILE")\" \"$PROTO_FILE\" <<< \"$MESSAGE\" > \"$TMP_DIR/META-INF/com/android/metadata.pb\"" || exit 1
    fi

    # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/ota_utils.py#317
    {
        echo "ota-required-cache=0"
        echo "ota-type=BLOCK"
        echo "post-build=$SOURCE_FINGERPRINT"
        echo "post-build-incremental=$INCREMENTAL"
        echo "post-sdk-level=$RELEASE"
        echo "post-security-patch-level=$SECURITY_PATCH_LEVEL"
        echo "post-timestamp=$TIMESTAMP"
        echo "pre-device=$TARGET_CODENAME"
    } > "$TMP_DIR/META-INF/com/android/metadata"
}

GENERATE_UPDATER_SCRIPT()
{
    local SCRIPT_FILE="$TMP_DIR/META-INF/com/google/android/updater-script"
    local BROTLI_EXTENSION
    $DEBUG || BROTLI_EXTENSION=".br"

    local PARTITION_COUNT=0
    local HAS_BOOT=false
    local HAS_DTBO=false
    local HAS_INIT_BOOT=false
    local HAS_VENDOR_BOOT=false
    local HAS_SUPER_EMPTY=false
    local HAS_SYSTEM=false
    local HAS_VENDOR=false
    local HAS_PRODUCT=false
    local HAS_SYSTEM_EXT=false
    local HAS_ODM=false
    local HAS_VENDOR_DLKM=false
    local HAS_ODM_DLKM=false
    local HAS_SYSTEM_DLKM=false
    local HAS_POST_INSTALL=false

    [ -f "$TMP_DIR/boot.img" ] && HAS_BOOT=true
    [ -f "$TMP_DIR/dtbo.img" ] && HAS_DTBO=true
    [ -f "$TMP_DIR/init_boot.img" ] && HAS_INIT_BOOT=true
    [ -f "$TMP_DIR/vendor_boot.img" ] && HAS_VENDOR_BOOT=true
    [ -f "$TMP_DIR/unsparse_super_empty.img" ] && HAS_SUPER_EMPTY=true
    [ -f "$TMP_DIR/system.new.dat${BROTLI_EXTENSION}" ] && HAS_SYSTEM=true
    [ -f "$TMP_DIR/vendor.new.dat${BROTLI_EXTENSION}" ] && HAS_VENDOR=true && PARTITION_COUNT=$((PARTITION_COUNT + 1))
    [ -f "$TMP_DIR/product.new.dat${BROTLI_EXTENSION}" ] && HAS_PRODUCT=true && PARTITION_COUNT=$((PARTITION_COUNT + 1))
    [ -f "$TMP_DIR/system_ext.new.dat${BROTLI_EXTENSION}" ] && HAS_SYSTEM_EXT=true && PARTITION_COUNT=$((PARTITION_COUNT + 1))
    [ -f "$TMP_DIR/odm.new.dat${BROTLI_EXTENSION}" ] && HAS_ODM=true && PARTITION_COUNT=$((PARTITION_COUNT + 1))
    [ -f "$TMP_DIR/vendor_dlkm.new.dat${BROTLI_EXTENSION}" ] && HAS_VENDOR_DLKM=true && PARTITION_COUNT=$((PARTITION_COUNT + 1))
    [ -f "$TMP_DIR/odm_dlkm.new.dat${BROTLI_EXTENSION}" ] && HAS_ODM_DLKM=true && PARTITION_COUNT=$((PARTITION_COUNT + 1))
    [ -f "$TMP_DIR/system_dlkm.new.dat${BROTLI_EXTENSION}" ] && HAS_SYSTEM_DLKM=true && PARTITION_COUNT=$((PARTITION_COUNT + 1))
    [ -f "$SRC_DIR/target/$TARGET_CODENAME/postinstall.edify" ] && HAS_POST_INSTALL=true

    {
        if [ -n "$TARGET_ASSERT_MODEL" ]; then
            IFS=':' read -r -a TARGET_ASSERT_MODEL <<< "$TARGET_ASSERT_MODEL"
            for i in "${TARGET_ASSERT_MODEL[@]}"; do
                echo -n 'getprop("ro.boot.em.model") == "'
                echo -n "$i"
                echo -n '" || '
            done
            echo -n 'abort("E3004: This package is for \"'
            echo -n "$TARGET_CODENAME"
            echo    '\" devices; this is a \"" + getprop("ro.product.device") + "\".");'
        else
            echo -n 'getprop("ro.product.device") == "'
            echo -n "$TARGET_CODENAME"
            echo -n '" || abort("E3004: This package is for \"'
            echo -n "$TARGET_CODENAME"
            echo    '\" devices; this is a \"" + getprop("ro.product.device") + "\".");'
        fi

        PRINT_HEADER

        # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/common.py#4007
        echo -e "\n# --- Start patching dynamic partitions ---\n\n"
        echo -e "# Update dynamic partition metadata\n"
        echo -n 'assert(update_dynamic_partitions(package_extract_file("dynamic_partitions_op_list")'
        if $HAS_SUPER_EMPTY; then
            # https://github.com/LineageOS/android_build/commit/98549f6893c3a93057e2d4cdd1015a93e9473b16
            # https://github.com/LineageOS/android_bootable_deprecated-ota/commit/e97be4333bd3824b8561c9637e9e6de28bc29da0
            echo -n ', package_extract_file("unsparse_super_empty.img")'
        fi
        echo    '));'
        if $HAS_SYSTEM; then
            echo -e "\n# Patch partition system\n"
            echo    'ui_print("Patching system image unconditionally...");'
            echo -n 'show_progress(0.'
            echo -n "$(bc -l <<< "9 - $PARTITION_COUNT")"
            echo    '00000, 0);'
            echo -n 'block_image_update(map_partition("system"), package_extract_file("system.transfer.list"), "'
            echo -n "system.new.dat${BROTLI_EXTENSION}"
            echo    '", "system.patch.dat") ||'
            echo    '  abort("E1001: Failed to update system image.");'
        fi
        if $HAS_VENDOR; then
            echo -e "\n# Patch partition vendor\n"
            echo    'ui_print("Patching vendor image unconditionally...");'
            echo    'show_progress(0.100000, 0);'
            echo -n 'block_image_update(map_partition("vendor"), package_extract_file("vendor.transfer.list"), "'
            echo -n "vendor.new.dat${BROTLI_EXTENSION}"
            echo    '", "vendor.patch.dat") ||'
            echo    '  abort("E2001: Failed to update vendor image.");'
        fi
        if $HAS_PRODUCT; then
            echo -e "\n# Patch partition product\n"
            echo    'ui_print("Patching product image unconditionally...");'
            echo    'show_progress(0.100000, 0);'
            echo -n 'block_image_update(map_partition("product"), package_extract_file("product.transfer.list"), "'
            echo -n "product.new.dat${BROTLI_EXTENSION}"
            echo    '", "product.patch.dat") ||'
            echo    '  abort("E2001: Failed to update product image.");'
        fi
        if $HAS_SYSTEM_EXT; then
            echo -e "\n# Patch partition system_ext\n"
            echo    'ui_print("Patching system_ext image unconditionally...");'
            echo    'show_progress(0.100000, 0);'
            echo -n 'block_image_update(map_partition("system_ext"), package_extract_file("system_ext.transfer.list"), "'
            echo -n "system_ext.new.dat${BROTLI_EXTENSION}"
            echo    '", "system_ext.patch.dat") ||'
            echo    '  abort("E2001: Failed to update system_ext image.");'
        fi
        if $HAS_ODM; then
            echo -e "\n# Patch partition odm\n"
            echo    'ui_print("Patching odm image unconditionally...");'
            echo    'show_progress(0.100000, 0);'
            echo -n 'block_image_update(map_partition("odm"), package_extract_file("odm.transfer.list"), "'
            echo -n "odm.new.dat${BROTLI_EXTENSION}"
            echo    '", "odm.patch.dat") ||'
            echo    '  abort("E2001: Failed to update odm image.");'
        fi
        if $HAS_VENDOR_DLKM; then
            echo -e "\n# Patch partition vendor_dlkm\n"
            echo    'ui_print("Patching vendor_dlkm image unconditionally...");'
            echo    'show_progress(0.100000, 0);'
            echo -n 'block_image_update(map_partition("vendor_dlkm"), package_extract_file("vendor_dlkm.transfer.list"), "'
            echo -n "vendor_dlkm.new.dat${BROTLI_EXTENSION}"
            echo    '", "vendor_dlkm.patch.dat") ||'
            echo    '  abort("E2001: Failed to update vendor_dlkm image.");'
        fi
        if $HAS_ODM_DLKM; then
            echo -e "\n# Patch partition odm_dlkm\n"
            echo    'ui_print("Patching odm_dlkm image unconditionally...");'
            echo    'show_progress(0.100000, 0);'
            echo -n 'block_image_update(map_partition("odm_dlkm"), package_extract_file("odm_dlkm.transfer.list"), "'
            echo -n "odm_dlkm.new.dat${BROTLI_EXTENSION}"
            echo    '", "odm_dlkm.patch.dat") ||'
            echo    '  abort("E2001: Failed to update odm_dlkm image.");'
        fi
        if $HAS_SYSTEM_DLKM; then
            echo -e "\n# Patch partition system_dlkm\n"
            echo    'ui_print("Patching system_dlkm image unconditionally...");'
            echo    'show_progress(0.100000, 0);'
            echo -n 'block_image_update(map_partition("system_dlkm"), package_extract_file("system_dlkm.transfer.list"), "'
            echo -n "system_dlkm.new.dat${BROTLI_EXTENSION}"
            echo    '", "system_dlkm.patch.dat") ||'
            echo    '  abort("E2001: Failed to update system_dlkm image.");'
        fi
        echo -e "\n# --- End patching dynamic partitions ---\n"
        if $HAS_DTBO; then
            echo    'ui_print("Full Patching dtbo.img img...");'
            echo -n 'package_extract_file("dtbo.img", "'
            echo -n "$TARGET_BOOT_DEVICE_PATH"
            echo    '/dtbo");'
        fi
        if $HAS_INIT_BOOT; then
            echo    'ui_print("Full Patching init_boot.img img...");'
            echo -n 'package_extract_file("init_boot.img", "'
            echo -n "$TARGET_BOOT_DEVICE_PATH"
            echo    '/init_boot");'
        fi
        if $HAS_VENDOR_BOOT; then
            echo    'ui_print("Full Patching vendor_boot.img img...");'
            echo -n 'package_extract_file("vendor_boot.img", "'
            echo -n "$TARGET_BOOT_DEVICE_PATH"
            echo    '/vendor_boot");'
        fi
        if $HAS_BOOT; then
            echo    'ui_print("Installing boot image...");'
            echo -n 'package_extract_file("boot.img", "'
            echo -n "$TARGET_BOOT_DEVICE_PATH"
            echo    '/boot");'
        fi

        if $HAS_POST_INSTALL; then
            cat "$SRC_DIR/target/$TARGET_CODENAME/postinstall.edify"
        fi

        echo    'set_progress(1.000000);'
        echo    'ui_print("************************************************");'
        echo    'ui_print(" ");'
    } > "$SCRIPT_FILE"
}

PRINT_HEADER()
{
    local VERSION_INFO
    local SIDE_PADDING
    local ONEUI_VERSION
    local MAJOR
    local MINOR
    local PATCH

    VERSION_INFO="$ROM_VERSION for $TARGET_NAME"
    SIDE_PADDING="$(bc -l <<< "scale=0; (49 - ${#VERSION_INFO}) / 2")"
    [ "$SIDE_PADDING" -lt 1 ] && SIDE_PADDING=1

    ONEUI_VERSION="$(GET_PROP "system" "ro.build.version.oneui")"
    MAJOR=$(bc -l <<< "scale=0; $ONEUI_VERSION / 10000")
    MINOR=$(bc -l <<< "scale=0; $ONEUI_VERSION % 10000 / 100")
    PATCH=$(bc -l <<< "scale=0; $ONEUI_VERSION % 100")
    if [[ "$PATCH" != "0" ]]; then
        ONEUI_VERSION="$MAJOR.$MINOR.$PATCH"
    else
        ONEUI_VERSION="$MAJOR.$MINOR"
    fi

    echo    'ui_print(" ");'
    echo    'ui_print("************************************************");'
    echo    'ui_print(" ");'
    echo    'ui_print("              _  __ ____ ___  _   __");'
    echo    'ui_print("             / |/ // __// _ \| | / /");'
    echo    'ui_print("            /    // _/ / , _/| |/ / ");'
    echo    'ui_print("           /_/|_//___//_/|_| |___/  ");'
    echo    'ui_print(" ");'
    echo -n 'ui_print("'
    for i in $(seq 1 "$SIDE_PADDING"); do
        echo -n ' '
    done
    echo -n "$VERSION_INFO"
    echo    '");'
    echo    'ui_print(" ");'
    echo    'ui_print("************************************************");'
    echo -n 'ui_print("'
    echo -n "One UI version: $ONEUI_VERSION"
    echo    '");'
    echo -n 'ui_print("'
    echo -n "Source: $SOURCE_FINGERPRINT"
    echo    '");'
    echo -n 'ui_print("'
    echo -n "Target: $TARGET_FINGERPRINT"
    echo    '");'
    echo    'ui_print("************************************************");'
}

SIGN_IMAGE_WITH_AVB()
{
    local FILE="$1"

    if ! avbtool info_image --image "$FILE" &> /dev/null; then
        local PARTITION_NAME
        PARTITION_NAME="$(basename "$FILE")"
        PARTITION_NAME="${PARTITION_NAME//.img/}"

        local PARTITION_SIZE
        PARTITION_SIZE="TARGET_$(tr "[:lower:]" "[:upper:]" <<< "$PARTITION_NAME")_PARTITION_SIZE"
        _CHECK_NON_EMPTY_PARAM "$PARTITION_SIZE" "${!PARTITION_SIZE//none/}" || exit 1

        local CMD
        CMD+="avbtool add_hash_footer "
        CMD+="--image \"$FILE\" "
        CMD+="--partition_size \"${!PARTITION_SIZE}\" "
        CMD+="--partition_name \"$PARTITION_NAME\" "
        CMD+="--hash_algorithm \"sha256\" "
        CMD+="--algorithm \"SHA256_RSA4096\" "
        CMD+="--key \"$SRC_DIR/security/avb/testkey_rsa4096.pem\""

        LOG "- Signing image with AVB"
        EVAL "$CMD" || exit 1
    fi
}
# ]

[ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/META-INF/com/google/android"
cp -a "$SRC_DIR/prebuilts/bootable/deprecated-ota/updater" "$TMP_DIR/META-INF/com/google/android/update-binary"

LOG_STEP_IN "- Building OS partitions"
while IFS= read -r f; do
    PARTITION=$(basename "$f")
    IS_VALID_PARTITION_NAME "$PARTITION" || continue

    "$SRC_DIR/scripts/build_fs_image.sh" "$TARGET_OS_FILE_SYSTEM" \
        -o "$TMP_DIR/$PARTITION.img" -S \
        "$WORK_DIR/$PARTITION" "$WORK_DIR/configs/file_context-$PARTITION" "$WORK_DIR/configs/fs_config-$PARTITION" || exit 1
done < <(find "$WORK_DIR" -maxdepth 1 -type d)
LOG_STEP_OUT

LOG "- Building unsparse_super_empty.img"
BUILD_SUPER_EMPTY

LOG "- Generating dynamic_partitions_op_list"
GENERATE_OP_LIST

while IFS= read -r f; do
    PARTITION="$(basename "$f" | sed "s/.img//g")"
    IS_VALID_PARTITION_NAME "$PARTITION" || continue

    LOG "- Converting $PARTITION.img to $PARTITION.new.dat"
    EVAL "img2sdat -o \"$TMP_DIR\" \"$f\"" || exit 1
    rm -f "$f"

    if ! $DEBUG; then
        LOG "- Compressing $PARTITION.new.dat"
        # https://android.googlesource.com/platform/build/+/refs/tags/android-15.0.0_r1/tools/releasetools/common.py#3585
        EVAL "brotli --quality=6 --output=\"$TMP_DIR/$PARTITION.new.dat.br\" \"$TMP_DIR/$PARTITION.new.dat\"" || exit 1
        rm -f "$TMP_DIR/$PARTITION.new.dat"
    fi
done < <(find "$TMP_DIR" -maxdepth 1 -type f -name "*.img")

if [ -d "$WORK_DIR/kernel" ]; then
    while IFS= read -r f; do
        IMG="$(basename "$f")"

        LOG_STEP_IN "- Copying $IMG"

        cp -a "$WORK_DIR/kernel/$IMG" "$TMP_DIR/$IMG"

        if ! $TARGET_DISABLE_AVB_SIGNING; then
            SIGN_IMAGE_WITH_AVB "$TMP_DIR/$IMG"
        fi

        LOG_STEP_OUT
    done < <(find "$WORK_DIR/kernel" -maxdepth 1 -type f -name "*.img")
fi

LOG "- Generating updater-script"
GENERATE_UPDATER_SCRIPT

LOG "- Generating build_info.txt"
GENERATE_BUILD_INFO

LOG "- Generating OTA metadata"
GENERATE_OTA_METADATA

LOG "- Creating zip"
CREATE_ROM_ZIP

if $ROM_IS_OFFICIAL; then
    LOG "- Signing zip"
    EVAL "signapk -w \"$PUBLIC_KEY_PATH\" \"$PRIVATE_KEY_PATH\" \"$TMP_DIR/rom.zip\" \"$OUT_DIR/$ZIP_FILE_NAME\"" || exit 1
    rm -f "$TMP_DIR/rom.zip"
else
    mv -f "$TMP_DIR/rom.zip" "$OUT_DIR/$ZIP_FILE_NAME"
fi

exit 0
