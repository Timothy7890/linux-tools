#!/bin/bash
# Web 可视化 yazi 选中的 transforms.json 或 semantic/instance 标签图。
# 触发：yazi 中按 g 再按 v（见 keymap.toml）。
#
# 选中处理：
#   - 只选一个 semantic/instance/instance_g 目录（或其 pngs/）-> 彩色 Mask 图库
#   - 选中 transforms.json 文件 -> 直接使用
#   - 选中文件夹                 -> 使用该文件夹下的 transforms.json
#   - transforms 文件和文件夹可混选
#
# 依赖：tmux，以及装有 numpy/pillow/plotly/fastapi/uvicorn 的 Python。
# Python 查找顺序：$YAZI_VIZ_PYTHON → ~/.local/share/yazi-viz/bin/python（install.sh 创建）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIZ_SCRIPT="$SCRIPT_DIR/visualize_transforms_web.py"
MASK_VIZ_SCRIPT="$SCRIPT_DIR/visualize_masks_web.py"
LIST_FILE="/tmp/yazi_viz_files"

PYTHON_BIN="${YAZI_VIZ_PYTHON:-$HOME/.local/share/yazi-viz/bin/python}"
if [ ! -x "$PYTHON_BIN" ]; then
    echo "找不到可视化 Python: $PYTHON_BIN"
    echo ""
    echo "请先安装依赖:  ./install.sh yazi   （选择安装 gv 可视化依赖）"
    echo "或指定已有环境: export YAZI_VIZ_PYTHON=/path/to/python"
    echo ""
    read -p "按回车关闭窗口..."
    exit 0
fi

mapfile -t raw < "$LIST_FILE"
if [ ${#raw[@]} -eq 0 ]; then
    echo "没有选中文件，已取消"; sleep 1; exit 0
fi

choose_port() {
    echo ""
    echo "==============================="
    echo "  选择端口"
    echo "==============================="
    echo "  1) 7007"
    echo "  2) 7008"
    echo "  3) 自定义输入"
    echo "  q) 取消"
    echo ""
    read -p "请选择 [1-3/q]: " pchoice
    case "$pchoice" in
        1) port=7007 ;;
        2) port=7008 ;;
        3) read -p "请输入端口: " port ;;
        *) echo "已取消"; sleep 1; exit 0 ;;
    esac

    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "无效端口: $port，已取消"; sleep 2; exit 0
    fi
}

print_start() {
    echo ""
    echo "→ 端口: $port"
    echo "→ Python: $PYTHON_BIN"
    echo "→ 本地查看: ssh -L ${port}:localhost:${port} <user>@<remote>  然后打开 http://localhost:${port}"
    echo "→ 启动中... (Ctrl-C 停止)"
    echo ""
}

finish() {
    echo ""
    echo "已退出，按回车关闭窗口..."
    read
    exit 0
}

# ---- 单选 semantic/instance/instance_g（或其 pngs 子目录）→ 彩色 Mask 图库 ----
selected_paths=()
for p in "${raw[@]}"; do
    [ -n "$p" ] && selected_paths+=("${p%/}")
done

if [ ${#selected_paths[@]} -eq 1 ] && [ -d "${selected_paths[0]}" ]; then
    selected_dir="${selected_paths[0]}"
    selected_name="$(basename "$selected_dir")"
    mask_type=""
    png_dir=""

    case "$selected_name" in
        semantic|instance|instance_g)
            mask_type="$selected_name"
            png_dir="$selected_dir/pngs"
            ;;
        pngs)
            parent_name="$(basename "$(dirname "$selected_dir")")"
            case "$parent_name" in
                semantic|instance|instance_g)
                    mask_type="$parent_name"
                    png_dir="$selected_dir"
                    ;;
            esac
            ;;
    esac

    if [ -n "$mask_type" ]; then
        if [ ! -d "$png_dir" ]; then
            echo "找不到 PNG 目录: $png_dir"; sleep 3; exit 0
        fi

        shopt -s nullglob nocaseglob
        mask_pngs=("$png_dir"/*.png)
        shopt -u nullglob nocaseglob
        if [ ${#mask_pngs[@]} -eq 0 ]; then
            echo "目录中没有 PNG: $png_dir"; sleep 3; exit 0
        fi

        echo "==============================="
        echo "  ${mask_type} 彩色 Mask 图库"
        echo "==============================="
        echo "  目录: $png_dir"
        echo "  图像: ${#mask_pngs[@]} 张"

        choose_port
        print_start
        "$PYTHON_BIN" "$MASK_VIZ_SCRIPT" \
            --host 0.0.0.0 --port "$port" \
            --png-dir "$png_dir" --mask-type "$mask_type"
        finish
    fi
fi

# ---- transforms.json 相机位姿可视化 ----
viz_paths=()
labels=()
for p in "${raw[@]}"; do
    [ -z "$p" ] && continue
    if [ -d "$p" ]; then
        t="$p/transforms.json"
    else
        t="$p"
    fi
    if [ ! -f "$t" ]; then
        echo "[跳过] 未找到: $t"
        continue
    fi
    viz_paths+=("$t")
    labels+=("$(basename "$(dirname "$t")")")
done

if [ ${#viz_paths[@]} -eq 0 ]; then
    echo "没有可用的 transforms.json，已取消"; sleep 2; exit 0
fi

echo "==============================="
echo "  即将可视化以下 transforms.json (共 ${#viz_paths[@]} 个)"
echo "==============================="
for i in "${!viz_paths[@]}"; do
    printf "  %2d) %-24s %s\n" "$((i+1))" "${labels[$i]}" "${viz_paths[$i]}"
done
echo ""
read -p "是否继续? [Y/n] (回车=是): " ans
case "$ans" in
    ""|y|Y|yes|YES|Yes) ;;
    *) echo "已取消"; sleep 1; exit 0 ;;
esac

choose_port
print_start
"$PYTHON_BIN" "$VIZ_SCRIPT" --host 0.0.0.0 --port "$port" "${viz_paths[@]}"
finish
