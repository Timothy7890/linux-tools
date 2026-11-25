#!/bin/bash
# g y -> 目录工具集（独立于任何项目）。
# 触发：yazi 中只选中一个【大文件夹】后按 g 再按 y（见 keymap.toml）。
#
# 功能菜单：
#   1) 挑选子文件夹复制or剪切
#      以某个子目录为“参考”，勾选要处理的项（如 images / transforms.json），
#      对大文件夹的所有【直接子目录】复制/剪切到同级 <名>-Copy / <名>-Move，
#      保持子目录结构。
#
#   2) 目录重整（前两层级互换：日期 <-> 品种）
#      把 <大>/L1/L2/... 结构中的前两层互换成 <大>/L2/L1/...，
#      用于在“日期/品种”与“品种/日期”两种组织方式间转换（移动方式）。
#
#   3) 拼接（合并两个一致结构，移动孙目录）
#      选中两个同结构文件夹，把源每个一级目录下的孙目录移动到目标对应一级目录下。
#
#   4) transforms 广播（源品种各日期 -> 其他品种同日期）
#      选中源品种（品种/日期结构），把它每个日期的 transforms.json 广播到同级其他
#      品种的相同日期下；调用 transforms_tools use_existed_trans，按目标 images/
#      过滤帧并备份目标原有 transforms。
#      单层模式：若源目录自身含 transforms.json（如 img/Rice_001/transforms.json），
#      则直接广播到同级其他目录；也可只选中该 transforms.json 文件触发。
#
# 依赖：bash、tmux；功能 4 额外需要 python3（use_existed_trans.py 只用标准库，随本脚本分发）。

set -o pipefail

SEL_FILE="/tmp/yazi_copy_files"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

abort() { echo "$1"; sleep "${2:-1}"; exit 0; }

# 生成同级目标目录名（重名自动追加数字）
make_dest() {
    local base_dir="$1" name="$2" suf="$3" d n=1
    d="$base_dir/$name$suf"
    while [ -e "$d" ]; do
        d="$base_dir/$name$suf$n"
        n=$((n+1))
    done
    printf '%s' "$d"
}

# 求多个绝对路径的“共同母目录”（最深公共祖先）
common_ancestor() {
    local common="$1"; shift
    local p
    for p in "$@"; do
        while [ "$p" != "$common" ] && [ "${p#"$common"/}" = "$p" ]; do
            common="$(dirname "$common")"
            [ "$common" = "/" ] && break
        done
    done
    printf '%s' "$common"
}

mapfile -t raw < "$SEL_FILE"

# 清洗：去空行、去尾部斜杠
sel=()
for p in "${raw[@]}"; do
    [ -z "$p" ] && continue
    p="${p%/}"
    sel+=("$p")
done
[ ${#sel[@]} -eq 0 ] && abort "没有选中任何文件，已取消"

# ---------- 识别大文件夹（选中项中唯一的目录）----------
dirs=()
for p in "${sel[@]}"; do
    [ -d "$p" ] && dirs+=("$p")
done
# 只选中一个 transforms.json 文件时，以其所在目录作为源（功能 4 单层模式）
if [ ${#dirs[@]} -eq 0 ] && [ ${#sel[@]} -eq 1 ] && [ "$(basename "${sel[0]}")" = "transforms.json" ]; then
    dirs=("$(dirname "${sel[0]}")")
fi
[ ${#dirs[@]} -eq 0 ] && abort "请选中文件夹后再按 g y。" 3
big="${dirs[0]}"   # 功能 1/2 用（单个大文件夹）；功能 3 用 dirs[0]/dirs[1]

# =====================================================================
# 功能 1：挑选子文件夹复制or剪切
# =====================================================================
feature_copy() {
    echo ""
    echo "  1) 复制"
    echo "  2) 剪切"
    echo "  q) 取消"
    echo ""
    local mode action verb suffix_single suffix_multi
    read -p "请选择 [1-2/q]: " mode
    case "$mode" in
        1) action="copy"; verb="复制"; suffix_single="-Copy"; suffix_multi="_Copy" ;;
        2) action="cut";  verb="剪切"; suffix_single="-Move"; suffix_multi="_Move" ;;
        *) abort "已取消" ;;
    esac

    local multi=0
    [ ${#dirs[@]} -gt 1 ] && multi=1

    # 选择“参考大目录”（多选时）
    local refbig i
    if [ $multi -eq 1 ]; then
        echo ""
        echo "==============================="
        echo "  选择参考大目录（用它的某个子目录来决定要处理哪些项）"
        echo "==============================="
        for i in "${!dirs[@]}"; do
            printf "  %2d) %s\n" "$((i+1))" "$(basename "${dirs[$i]}")"
        done
        echo ""
        local rb
        read -p "请选择参考大目录 [默认 1]: " rb
        [ -z "$rb" ] && rb=1
        if ! [[ "$rb" =~ ^[0-9]+$ ]] || [ "$rb" -lt 1 ] || [ "$rb" -gt ${#dirs[@]} ]; then
            abort "无效选择: $rb" 2
        fi
        refbig="${dirs[$((rb-1))]}"
    else
        refbig="${dirs[0]}"
    fi

    # 收集参考大目录的直接子目录
    shopt -s nullglob
    local subdirs=() d
    for d in "$refbig"/*/; do subdirs+=("${d%/}"); done
    shopt -u nullglob
    [ ${#subdirs[@]} -eq 0 ] && abort "参考大目录下没有子目录：$refbig" 3

    # 选择参考子目录
    echo ""
    echo "==============================="
    echo "  选择参考子目录（用于列出可勾选的内容，来自: $(basename "$refbig")）"
    echo "==============================="
    for i in "${!subdirs[@]}"; do
        printf "  %2d) %s\n" "$((i+1))" "$(basename "${subdirs[$i]}")"
    done
    echo ""
    local rc
    read -p "请选择参考子目录 [默认 1]: " rc
    [ -z "$rc" ] && rc=1
    if ! [[ "$rc" =~ ^[0-9]+$ ]] || [ "$rc" -lt 1 ] || [ "$rc" -gt ${#subdirs[@]} ]; then
        abort "无效选择: $rc" 2
    fi
    local ref="${subdirs[$((rc-1))]}"
    local refname; refname="$(basename "$ref")"   # 参考子目录名（如日期 20250915 或品种 K02）

    # 列出参考子目录内容，勾选
    shopt -s nullglob
    local entries=() e
    for e in "$ref"/*; do entries+=("$(basename "$e")"); done
    shopt -u nullglob
    [ ${#entries[@]} -eq 0 ] && abort "参考子目录为空：$ref" 3

    echo ""
    echo "==============================="
    echo "  勾选要$verb的项（参考自: $(basename "$ref")）"
    echo "==============================="
    for i in "${!entries[@]}"; do
        local mark="[文件]"
        [ -d "$ref/${entries[$i]}" ] && mark="[目录]"
        local hint=""
        [[ "${entries[$i]}" == *"$refname"* ]] && hint="   （含子目录名「$refname」，将按各子目录自动替换）"
        printf "  %2d) %-6s %s%s\n" "$((i+1))" "$mark" "${entries[$i]}" "$hint"
    done
    echo ""
    echo "  输入编号（空格或逗号分隔，如: 1 2），或输入 a 选择全部"
    local picks
    read -p "请勾选: " picks
    [ -z "$picks" ] && abort "未勾选任何项，已取消"

    local patterns=()
    if [[ "$picks" =~ ^([aA]|all|ALL)$ ]]; then
        patterns=("${entries[@]}")
    else
        picks="${picks//,/ }"
        declare -A seen
        local n idx ent
        for n in $picks; do
            if ! [[ "$n" =~ ^[0-9]+$ ]]; then echo "  忽略无效输入: $n"; continue; fi
            idx=$((n-1))
            if [ "$idx" -lt 0 ] || [ "$idx" -ge ${#entries[@]} ]; then echo "  编号越界: $n"; continue; fi
            ent="${entries[$idx]}"
            if [ -z "${seen[$ent]+x}" ]; then seen[$ent]=1; patterns+=("$ent"); fi
        done
    fi
    [ ${#patterns[@]} -eq 0 ] && abort "未勾选任何有效项，已取消"

    # 计算目标文件夹
    #   单选：<大目录>-Copy / -Move
    #   多选：<共同母目录>_Copy / _Move ，各大目录按相对结构放入
    local dest common=""
    if [ $multi -eq 1 ]; then
        common="$(common_ancestor "${dirs[@]}")"
        dest="$(make_dest "$(dirname "$common")" "$(basename "$common")" "$suffix_multi")"
    else
        dest="$(make_dest "$(dirname "$refbig")" "$(basename "$refbig")" "$suffix_single")"
    fi

    # 生成计划 & 检查缺失（遍历每个被选中的大目录）
    local plan_src=() plan_rel=() missing=() emptybig=()
    local big bsub bn s sn pat relprefix
    for big in "${dirs[@]}"; do
        if [ $multi -eq 1 ]; then
            relprefix="${big#"$common"/}/"      # 例如 pepper/ 或 a/pepper/
        else
            relprefix=""                         # 单选：dest 已对应该大目录
        fi
        shopt -s nullglob
        bsub=()
        for d in "$big"/*/; do bsub+=("${d%/}"); done
        shopt -u nullglob
        if [ ${#bsub[@]} -eq 0 ]; then emptybig+=("$(basename "$big")"); continue; fi
        for s in "${bsub[@]}"; do
            sn="$(basename "$s")"
            local realpat
            for pat in "${patterns[@]}"; do
                # 若勾选项名字里含参考子目录名（如 <日期>_psnppcuda.txt），
                # 则对每个子目录把该名替换成当前子目录名，取“同类”的那份文件
                if [[ "$pat" == *"$refname"* ]]; then
                    realpat="${pat//"$refname"/"$sn"}"
                else
                    realpat="$pat"
                fi
                if [ -e "$s/$realpat" ]; then
                    plan_src+=("$s/$realpat"); plan_rel+=("${relprefix}${sn}/${realpat}")
                else
                    missing+=("${relprefix}${sn}/${realpat}")
                fi
            done
        done
    done
    [ ${#plan_src[@]} -eq 0 ] && abort "所有子目录都找不到勾选的项，无事可做。" 3

    # 预览
    echo ""
    echo "==============================="
    echo "  操作预览（$verb）"
    echo "==============================="
    if [ $multi -eq 1 ]; then
        echo "  选中大目录: ${#dirs[@]} 个"
        echo "  共同母目录: $common"
    else
        echo "  大文件夹  : $refbig"
    fi
    echo "  目标文件夹: $dest"
    echo "  勾选项    : ${patterns[*]}"
    echo "  待$verb项 : ${#plan_src[@]}"
    echo ""
    local show=${#plan_rel[@]}; [ "$show" -gt 20 ] && show=20
    local k
    for ((k=0; k<show; k++)); do echo "    + $dest/${plan_rel[$k]}"; done
    [ ${#plan_rel[@]} -gt 20 ] && echo "    ... 其余 $(( ${#plan_rel[@]} - 20 )) 项"

    if [ ${#emptybig[@]} -gt 0 ]; then
        echo ""
        echo "  ℹ 以下 ${#emptybig[@]} 个大目录没有子目录，已跳过： ${emptybig[*]}"
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo ""
        echo "  ⚠ 警告：以下 ${#missing[@]} 个项在对应子目录中缺失，将被跳过："
        local mshow=${#missing[@]}; [ "$mshow" -gt 20 ] && mshow=20
        for ((k=0; k<mshow; k++)); do echo "      - ${missing[$k]}"; done
        [ ${#missing[@]} -gt 20 ] && echo "      ... 其余 $(( ${#missing[@]} - 20 )) 项"
    fi

    echo ""
    local ans
    read -p "是否继续执行 $verb ? [Y/n] (回车=是): " ans
    case "$ans" in ""|y|Y|yes|YES|Yes) ;; *) abort "已取消" ;; esac

    echo ""
    echo "开始$verb ..."
    local ok=0 fail=0 src rel tgt
    for ((k=0; k<${#plan_src[@]}; k++)); do
        src="${plan_src[$k]}"; rel="${plan_rel[$k]}"; tgt="$dest/$rel"
        mkdir -p "$(dirname "$tgt")"
        if [ "$action" = "copy" ]; then
            if cp -a "$src" "$tgt"; then ok=$((ok+1)); else fail=$((fail+1)); echo "  [失败] $rel"; fi
        else
            if mv "$src" "$tgt"; then ok=$((ok+1)); else fail=$((fail+1)); echo "  [失败] $rel"; fi
        fi
    done
    echo ""
    echo "完成：成功 $ok，失败 $fail"
    echo "目标：$dest"
}

# =====================================================================
# 功能 2：目录重整（前两层级互换，移动方式）
# =====================================================================
feature_reorg() {
    # 收集一级子目录 L1
    shopt -s nullglob
    local l1s=()
    local d
    for d in "$big"/*/; do l1s+=("${d%/}"); done
    shopt -u nullglob
    [ ${#l1s[@]} -eq 0 ] && abort "大文件夹下没有一级子目录。" 3

    # 生成计划：big/L1/L2 -> dest/L2/L1；散文件记录到 loose
    local plan_src=() plan_rel=() loose=()
    local l1 n1 e b
    for l1 in "${l1s[@]}"; do
        n1="$(basename "$l1")"
        shopt -s nullglob
        for e in "$l1"/*; do
            b="$(basename "$e")"
            if [ -d "$e" ]; then
                plan_src+=("$e"); plan_rel+=("$b/$n1")     # L2/L1
            else
                loose+=("$n1/$b")
            fi
        done
        shopt -u nullglob
    done
    [ ${#plan_src[@]} -eq 0 ] && abort "没有可重整的二级目录。" 3

    # 判断当前布局（仅用于提示）
    local date_re='^[0-9]{8}$' all_date=1
    for l1 in "${l1s[@]}"; do
        [[ "$(basename "$l1")" =~ $date_re ]] || { all_date=0; break; }
    done
    local layout
    if [ $all_date -eq 1 ]; then
        layout="日期/品种  →  品种/日期"
    else
        layout="品种/日期  →  日期/品种"
    fi

    local dest
    dest="$(make_dest "$(dirname "$big")" "$(basename "$big")" "-Reorg")"

    # 预览
    echo ""
    echo "==============================="
    echo "  目录重整预览（移动 / 前两层互换）"
    echo "==============================="
    echo "  大文件夹  : $big"
    echo "  目标文件夹: $dest"
    echo "  转换方向  : $layout"
    echo "  一级目录数: ${#l1s[@]}"
    echo "  待移动项  : ${#plan_src[@]}"
    echo ""
    local show=${#plan_rel[@]}; [ "$show" -gt 20 ] && show=20
    local k
    for ((k=0; k<show; k++)); do echo "    $(basename "$big")/${plan_src[$k]#$big/}  ->  ${plan_rel[$k]}"; done
    [ ${#plan_rel[@]} -gt 20 ] && echo "    ... 其余 $(( ${#plan_rel[@]} - 20 )) 项"

    if [ ${#loose[@]} -gt 0 ]; then
        echo ""
        echo "  ⚠ 警告：以下 ${#loose[@]} 个散文件直接位于一级目录下（不是二级目录），将被跳过不搬："
        local lshow=${#loose[@]}; [ "$lshow" -gt 20 ] && lshow=20
        for ((k=0; k<lshow; k++)); do echo "      - ${loose[$k]}"; done
        [ ${#loose[@]} -gt 20 ] && echo "      ... 其余 $(( ${#loose[@]} - 20 )) 项"
    fi

    echo ""
    echo "  说明：采用【移动】方式，完成后原大文件夹里的一级目录会变空（结构保留）。"
    echo "        确认新目录无误后可自行删除原文件夹。"
    echo ""
    local ans
    read -p "是否继续执行 目录重整 ? [Y/n] (回车=是): " ans
    case "$ans" in ""|y|Y|yes|YES|Yes) ;; *) abort "已取消" ;; esac

    echo ""
    echo "开始重整（移动）..."
    local ok=0 fail=0 src rel tgt
    for ((k=0; k<${#plan_src[@]}; k++)); do
        src="${plan_src[$k]}"; rel="${plan_rel[$k]}"; tgt="$dest/$rel"
        mkdir -p "$(dirname "$tgt")"
        if mv "$src" "$tgt"; then ok=$((ok+1)); else fail=$((fail+1)); echo "  [失败] $rel"; fi
    done
    echo ""
    echo "完成：成功 $ok，失败 $fail"
    echo "目标：$dest"
}

# =====================================================================
# 功能 3：拼接（合并两个结构一致的文件夹，移动孙目录，就地合并）
# =====================================================================
feature_merge() {
    local A="${dirs[0]}" B="${dirs[1]}"

    echo ""
    echo "==============================="
    echo "  选择拼接方向（把[源]的孙目录移动到[目标]对应一级目录下）"
    echo "==============================="
    echo "  1) 源: $(basename "$A")  ->  目标: $(basename "$B")   （$(basename "$A") 将被搬空）"
    echo "  2) 源: $(basename "$B")  ->  目标: $(basename "$A")   （$(basename "$B") 将被搬空）"
    echo "  q) 取消"
    echo ""
    local dc src tgt
    read -p "请选择 [1-2/q]: " dc
    case "$dc" in
        1) src="$A"; tgt="$B" ;;
        2) src="$B"; tgt="$A" ;;
        *) abort "已取消" ;;
    esac

    # 源的一级目录
    shopt -s nullglob
    local sl1=() d
    for d in "$src"/*/; do sl1+=("$(basename "${d%/}")"); done
    shopt -u nullglob
    [ ${#sl1[@]} -eq 0 ] && abort "源没有一级目录。" 3

    # 目标的一级目录集合（用于一致性检查）
    declare -A tgt_has
    shopt -s nullglob
    for d in "$tgt"/*/; do tgt_has["$(basename "${d%/}")"]=1; done
    shopt -u nullglob

    # 生成计划 & 检查冲突 / 缺失 / 散文件
    local plan_src=() plan_tgt=()
    local collisions=() loose=() new_l1=()
    local n1 e b
    for n1 in "${sl1[@]}"; do
        [ -z "${tgt_has[$n1]+x}" ] && new_l1+=("$n1")
        shopt -s nullglob
        for e in "$src/$n1"/*; do
            b="$(basename "$e")"
            if [ -d "$e" ]; then
                if [ -e "$tgt/$n1/$b" ]; then
                    collisions+=("$n1/$b")
                else
                    plan_src+=("$e"); plan_tgt+=("$tgt/$n1/$b")
                fi
            else
                loose+=("$n1/$b")
            fi
        done
        shopt -u nullglob
    done

    # 冲突 -> 中止（按设置，不覆盖、不改动）
    local k
    if [ ${#collisions[@]} -gt 0 ]; then
        echo ""
        echo "  ✗ 检测到 ${#collisions[@]} 个孙目录在目标中已存在（冲突），已中止，未做任何改动："
        local cshow=${#collisions[@]}; [ "$cshow" -gt 30 ] && cshow=30
        for ((k=0; k<cshow; k++)); do echo "      - ${collisions[$k]}"; done
        [ ${#collisions[@]} -gt 30 ] && echo "      ... 其余 $(( ${#collisions[@]} - 30 )) 项"
        abort "" 4
    fi
    [ ${#plan_src[@]} -eq 0 ] && abort "没有可移动的孙目录。" 3

    # 预览
    echo ""
    echo "==============================="
    echo "  拼接预览（移动 / 就地合并）"
    echo "==============================="
    echo "  源      : $src"
    echo "  目标    : $tgt"
    echo "  一级目录: 源 ${#sl1[@]} 个"
    echo "  待移动项: ${#plan_src[@]}"
    echo ""
    local show=${#plan_src[@]}; [ "$show" -gt 20 ] && show=20
    for ((k=0; k<show; k++)); do
        echo "    ${plan_src[$k]#$src/}  ->  $(basename "$tgt")/${plan_tgt[$k]#$tgt/}"
    done
    [ ${#plan_src[@]} -gt 20 ] && echo "    ... 其余 $(( ${#plan_src[@]} - 20 )) 项"

    if [ ${#new_l1[@]} -gt 0 ]; then
        echo ""
        echo "  ℹ 以下 ${#new_l1[@]} 个一级目录目标中没有，将自动新建并搬入： ${new_l1[*]}"
    fi
    if [ ${#loose[@]} -gt 0 ]; then
        echo ""
        echo "  ⚠ 警告：以下 ${#loose[@]} 个散文件直接位于源的一级目录下（不是孙目录），将被跳过不搬："
        local lshow=${#loose[@]}; [ "$lshow" -gt 20 ] && lshow=20
        for ((k=0; k<lshow; k++)); do echo "      - ${loose[$k]}"; done
        [ ${#loose[@]} -gt 20 ] && echo "      ... 其余 $(( ${#loose[@]} - 20 )) 项"
    fi

    echo ""
    echo "  说明：采用【移动】方式就地合并，完成后源文件夹的一级目录会变空（结构保留）。"
    echo ""
    local ans
    read -p "是否继续执行 拼接 ? [Y/n] (回车=是): " ans
    case "$ans" in ""|y|Y|yes|YES|Yes) ;; *) abort "已取消" ;; esac

    echo ""
    echo "开始拼接（移动）..."
    local ok=0 fail=0 s t
    for ((k=0; k<${#plan_src[@]}; k++)); do
        s="${plan_src[$k]}"; t="${plan_tgt[$k]}"
        mkdir -p "$(dirname "$t")"
        if mv "$s" "$t"; then ok=$((ok+1)); else fail=$((fail+1)); echo "  [失败] ${s#$src/}"; fi
    done
    echo ""
    echo "完成：成功 $ok，失败 $fail"
    echo "目标：$tgt"
}

# =====================================================================
# 功能 4：transforms 广播（把源品种各日期的 transforms.json 复制到其他品种同日期，
#         使用 transforms_tools use_existed_trans：按目标 images/ 过滤帧、备份原文件）
# =====================================================================
feature_broadcast() {
    local src="$big"                        # 源品种目录（单选）
    local vroot sname
    vroot="$(dirname "$src")"               # 品种根（源的父目录）
    sname="$(basename "$src")"

    # use_existed_trans.py 随本脚本分发，只依赖 Python 标准库（可用 YAZI_TT_PYTHON 指定解释器）
    local TT_SCRIPT="$SCRIPT_DIR/use_existed_trans.py"
    local TT_PY="${YAZI_TT_PYTHON:-python3}"
    [ -f "$TT_SCRIPT" ] || abort "找不到 $TT_SCRIPT，请重跑 ./install.sh yazi。" 4
    command -v "$TT_PY" >/dev/null 2>&1 || abort "找不到 $TT_PY，功能 4 需要 Python 3。" 4

    # 源日期：源品种下含 transforms.json 的直接子目录
    # 单层模式：源目录自身含 transforms.json 时，日期为空串，直接广播到同级目录
    local sdates=() d layout="品种/日期"
    if [ -f "$src/transforms.json" ]; then
        sdates=("")
        layout="单层（源目录自身含 transforms.json）"
    else
        shopt -s nullglob
        for d in "$src"/*/; do
            d="${d%/}"
            [ -f "$d/transforms.json" ] && sdates+=("$(basename "$d")")
        done
        shopt -u nullglob
    fi
    [ ${#sdates[@]} -eq 0 ] && abort "源目录自身及其子目录下都没有 transforms.json：$src" 4

    # 目标品种：同级目录，排除源自身与名字以 skip 开头的目录
    shopt -s nullglob
    local tvars=() skipped=() bn
    for d in "$vroot"/*/; do
        d="${d%/}"
        bn="$(basename "$d")"
        [ "$d" = "$src" ] && continue
        case "$bn" in skip*) skipped+=("$bn"); continue ;; esac
        tvars+=("$bn")
    done
    shopt -u nullglob
    [ ${#tvars[@]} -eq 0 ] && abort "没有可用的目标品种（同级目录）。" 4

    # 生成计划：每个 (源日期, 目标品种)，目标存在该日期目录才处理
    local plan_tgt=() plan_src=() missing=()
    local dt v sub
    for dt in "${sdates[@]}"; do
        sub="${dt:+/$dt}"
        for v in "${tvars[@]}"; do
            if [ -d "$vroot/$v$sub" ]; then
                plan_tgt+=("$vroot/$v$sub"); plan_src+=("$src$sub/transforms.json")
            else
                missing+=("$v$sub")
            fi
        done
    done
    [ ${#plan_tgt[@]} -eq 0 ] && abort "目标品种都没有与源匹配的日期目录，无事可做。" 4

    # 预览
    echo ""
    echo "==============================="
    echo "  transforms 广播预览（use_existed_trans / 按目标 images 过滤帧）"
    echo "==============================="
    echo "  源品种  : $src"
    echo "  品种根  : $vroot"
    echo "  结构    : $layout"
    [ -n "${sdates[0]}" ] && echo "  源日期数: ${#sdates[@]}（均含 transforms.json）"
    echo "  目标品种: ${#tvars[@]} 个 -> ${tvars[*]}"
    echo "  待写入项: ${#plan_tgt[@]}"
    [ ${#skipped[@]} -gt 0 ] && echo "  已排除  : ${skipped[*]}"
    echo ""
    local show=${#plan_tgt[@]}; [ "$show" -gt 15 ] && show=15
    local k
    for ((k=0; k<show; k++)); do
        echo "    ${plan_src[$k]#$vroot/}  ->  ${plan_tgt[$k]#$vroot/}/transforms.json"
    done
    [ ${#plan_tgt[@]} -gt 15 ] && echo "    ... 其余 $(( ${#plan_tgt[@]} - 15 )) 项"

    if [ ${#missing[@]} -gt 0 ]; then
        echo ""
        echo "  ⚠ 警告：以下 ${#missing[@]} 个 目标品种/日期 不存在，将被跳过："
        local mshow=${#missing[@]}; [ "$mshow" -gt 15 ] && mshow=15
        for ((k=0; k<mshow; k++)); do echo "      - ${missing[$k]}"; done
        [ ${#missing[@]} -gt 15 ] && echo "      ... 其余 $(( ${#missing[@]} - 15 )) 项"
    fi

    echo ""
    echo "  说明：目标若已有 transforms.json 会被自动改名备份为 transforms_<时间戳>.json（不会丢）。"
    echo "        帧会按目标 images/ 过滤，指向不存在图片的帧会被删除。"
    echo ""
    local ans
    read -p "是否继续执行 广播 ? [Y/n] (回车=是): " ans
    case "$ans" in ""|y|Y|yes|YES|Yes) ;; *) abort "已取消" ;; esac

    echo ""
    echo "开始广播（$TT_PY use_existed_trans.py）..."
    local ok=0 fail=0
    for ((k=0; k<${#plan_tgt[@]}; k++)); do
        echo "---- [$((k+1))/${#plan_tgt[@]}] ${plan_tgt[$k]#$vroot/} ----"
        if "$TT_PY" "$TT_SCRIPT" -i "${plan_tgt[$k]}" -t "${plan_src[$k]}" -L 1; then
            ok=$((ok+1))
        else
            fail=$((fail+1)); echo "  [失败] ${plan_tgt[$k]#$vroot/}"
        fi
    done
    echo ""
    echo "完成：成功 $ok，失败 $fail"
    echo "目标根：$vroot"
}

# =====================================================================
# g y 主菜单
# =====================================================================
echo "==============================="
echo "  g y  目录工具"
echo "==============================="
echo "  已选目录 (${#dirs[@]} 个):"
for d in "${dirs[@]}"; do echo "    - $d"; done
echo ""
echo "  1) 挑选子文件夹复制or剪切          （可选中 1 个或多个文件夹）"
echo "  2) 目录重整（前两层级互换：日期 <-> 品种） （需选中 1 个文件夹）"
echo "  3) 拼接（合并两个一致结构，移动孙目录）    （需选中 2 个文件夹）"
echo "  4) transforms 广播（源品种各日期 -> 其他品种同日期；或单层：源 -> 同级目录）（选中 1 个源目录或其 transforms.json）"
echo "  q) 取消"
echo ""
read -p "请选择 [1-4/q]: " feat
case "$feat" in
    1) feature_copy ;;
    2) [ ${#dirs[@]} -eq 1 ] || abort "功能2 需要且只需选中 1 个文件夹（当前 ${#dirs[@]} 个）。" 3; feature_reorg ;;
    3) [ ${#dirs[@]} -eq 2 ] || abort "功能3 需要选中 2 个文件夹（当前 ${#dirs[@]} 个）。" 3; feature_merge ;;
    4) [ ${#dirs[@]} -eq 1 ] || abort "功能4 需要且只需选中 1 个源品种目录（当前 ${#dirs[@]} 个）。" 3; feature_broadcast ;;
    *) abort "已取消" ;;
esac

echo ""
echo "按回车关闭窗口..."
read
