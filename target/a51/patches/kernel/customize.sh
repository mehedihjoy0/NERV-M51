echo "Replacing kernel"
rm -f "$WORK_DIR/kernel/boot.img"
rm -f "$WORK_DIR/kernel/dtbo.img"
cp -rf "$SRC_DIR/prebuilts/kernels/a51/"*.img "$WORK_DIR/kernel/"
