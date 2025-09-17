LOG_STEP_IN "- Adding ExtremeROM logo PNG"
DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk"
cp -a --preserve=all "$SRC_DIR/unica/mods/settings/SecSettings.apk/"* "$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk"
LOG_STEP_OUT
