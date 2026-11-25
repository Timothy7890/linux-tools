#!/bin/bash
mapfile -t files < /tmp/yazi_transfer_files
if [ ${#files[@]} -eq 0 ]; then
        echo "没有选中文件，已取消"; sleep 1; exit 0
fi

echo "==============================="
echo "  选择目标服务器"
echo "==============================="
echo ""
echo "  1) macos-yx       ~/Downloads/"
echo "  q) 取消"
echo ""
read -p "请选择 [1/q]: " choice

case $choice in
    1) dest="macos-yx:~/Downloads/" ;;
    *) echo "已取消"; sleep 1; exit 0 ;;
esac

echo ""
echo "→ 目标: $dest"
echo "→ 文件: ${files[*]}"
echo ""
rsync -avzP "${files[@]}" "$dest"
echo ""
echo "传输完成，2秒后关闭..."
sleep 2
