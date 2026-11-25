#!/bin/bash
mapfile -t files < /tmp/yazi_transfer_files
if [ ${#files[@]} -eq 0 ]; then
    echo "没有选中文件，已取消"; sleep 1; exit 0
fi

echo "==============================="
echo "  选择目标服务器"
echo "==============================="
echo ""
echo "  1) macos-yx    ~/Downloads/"
echo "  2) macmini     /Users/timo_clawd/Transfer/"
echo "  q) 取消"
echo ""
read -p "请选择 [1-2/q]: " choice

case $choice in
    1) dest="macos-yx:~/Downloads/";               use_scp=false ;;
    2) dest="macmini:/Users/timo_clawd/Transfer/"; use_scp=false ;;
    *) echo "已取消"; sleep 1; exit 0 ;;
esac

echo ""
echo "→ 目标: $dest"
echo "→ 文件: ${files[*]}"
echo ""
if $use_scp; then
    scp -r -p "${files[@]}" "$dest"
else
    rsync -avzP "${files[@]}" "$dest"
fi
echo ""
echo "传输完成，2秒后关闭..."
sleep 2
