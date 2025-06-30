# Dexpreopt
find "$WORK_DIR/product" -type d -name "oat" -print0 | xargs -0 -I "{}" -P "$(nproc)" \
    bash -c 'source "$SRC_DIR/scripts/utils/module_utils.sh"; DELETE_FROM_WORK_DIR "product" "${1//$WORK_DIR\/product\//}"' "bash" "{}"
find "$WORK_DIR/system" -type d -name "oat" -print0 | xargs -0 -I "{}" -P "$(nproc)" \
    bash -c 'source "$SRC_DIR/scripts/utils/module_utils.sh"; DELETE_FROM_WORK_DIR "system" "${1//$WORK_DIR\/system\//}"' "bash" "{}"
DELETE_FROM_WORK_DIR "system" "system/etc/boot-image.bprof"
DELETE_FROM_WORK_DIR "system" "system/etc/boot-image.prof"
DELETE_FROM_WORK_DIR "system" "system/framework/arm"
DELETE_FROM_WORK_DIR "system" "system/framework/arm64"
find "$WORK_DIR/system/system/framework" -type f -name "*.vdex" -print0 | xargs -0 -I "{}" -P "$(nproc)" \
    bash -c 'source "$SRC_DIR/scripts/utils/module_utils.sh"; DELETE_FROM_WORK_DIR "system" "${1//$WORK_DIR\/system\//}"' "bash" "{}"
if $TARGET_HAS_SYSTEM_EXT; then
    find "$WORK_DIR/system_ext" -type d -name "oat" -print0 | xargs -0 -I "{}" -P "$(nproc)" \
        bash -c 'source "$SRC_DIR/scripts/utils/module_utils.sh"; DELETE_FROM_WORK_DIR "system_ext" "${1//$WORK_DIR\/system_ext\//}"' "bash" "{}"
fi

# ROM & device-specific debloat list
[ -f "$SRC_DIR/unica/debloat.sh" ] && source "$SRC_DIR/unica/debloat.sh"
[ -f "$SRC_DIR/target/$TARGET_CODENAME/debloat.sh" ] && source "$SRC_DIR/target/$TARGET_CODENAME/debloat.sh"

ODM_DEBLOAT="$(sed "/^$/d" <<< "$ODM_DEBLOAT" | sort)"
PRODUCT_DEBLOAT="$(sed "/^$/d" <<< "$PRODUCT_DEBLOAT" | sort)"
SYSTEM_DEBLOAT="$(sed "/^$/d" <<< "$SYSTEM_DEBLOAT" | sort)"
SYSTEM_EXT_DEBLOAT="$(sed "/^$/d" <<< "$SYSTEM_EXT_DEBLOAT" | sort)"
VENDOR_DEBLOAT="$(sed "/^$/d" <<< "$VENDOR_DEBLOAT" | sort)"

[ "$ODM_DEBLOAT" ] && echo "$ODM_DEBLOAT" | xargs -I "{}" -P "$(nproc)" \
    bash -c 'if [ -f "$WORK_DIR/odm/{}" ]; then
        source "$SRC_DIR/scripts/utils/module_utils.sh"
        DELETE_FROM_WORK_DIR "odm" "{}"
    fi'

[ "$PRODUCT_DEBLOAT" ] && echo "$PRODUCT_DEBLOAT" | xargs -I "{}" -P "$(nproc)" \
    bash -c 'if [ -f "$WORK_DIR/product/{}" ]; then
        source "$SRC_DIR/scripts/utils/module_utils.sh"
        DELETE_FROM_WORK_DIR "product" "{}"
    fi'

[ "$SYSTEM_DEBLOAT" ] && echo "$SYSTEM_DEBLOAT" | xargs -I "{}" -P "$(nproc)" \
    bash -c 'if [ -f "$WORK_DIR/system/system/{}" ]; then
        source "$SRC_DIR/scripts/utils/module_utils.sh"
        DELETE_FROM_WORK_DIR "system" "{}"
    fi'

[ "$SYSTEM_EXT_DEBLOAT" ] && echo "$SYSTEM_EXT_DEBLOAT" | xargs -I "{}" -P "$(nproc)" \
    bash -c 'if [ -f "$WORK_DIR/system_ext/{}" ]; then
        source "$SRC_DIR/scripts/utils/module_utils.sh"
        DELETE_FROM_WORK_DIR "system_ext" "{}"
    fi'

[ "$VENDOR_DEBLOAT" ] && echo "$VENDOR_DEBLOAT" | xargs -I "{}" -P "$(nproc)" \
    bash -c 'if [ -f "$WORK_DIR/vendor/{}" ]; then
        source "$SRC_DIR/scripts/utils/module_utils.sh"
        DELETE_FROM_WORK_DIR "vendor" "{}"
    fi'

