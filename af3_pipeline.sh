#!/bin/bash
# /public/home/jxtang/bin/af3_pipeline.sh
# AlphaFold3 Pipeline - 主入口脚本

set -e

# 加载工具函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/af3_utils.sh"

VERSION="1.0.2"

# ==================== 帮助信息 ====================
show_help() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║              AlphaFold3 Pipeline v1.0.2                          ║
║              蛋白质结构预测完整工作流程                             ║
╚══════════════════════════════════════════════════════════════════╝

使用方法:
    af3_pipeline.sh [模式] [选项] <输入> [输出目录]

模式:
    full        完整流程: FASTA -> ColabFold MSA -> AF3 (默认，推荐)
    msa         仅 MSA:   FASTA -> ColabFold MSA
    af3         原生预测: FASTA -> AF3 (使用 AF3 内置 MSA 计算)
    resume      恢复执行: 从任务目录继续（自动检测状态）
    json        仅 JSON:  FASTA -> JSON (不含 MSA)
    transfer    仅传输:   传输结果文件

全局选项:
    -g, --gpu ID            GPU ID (默认: 0，支持 CUDA_VISIBLE_DEVICES 环境变量)
    -n, --task-name NAME    任务名称，用于创建输出子目录 (默认: 从输入文件名提取)
    -m, --msa-method M      MSA 方式: api, local (默认: api)
    -t, --threads N         线程数 (默认: 64)
    --use-template          使用模板搜索 (默认)
    --no-template           不使用模板
    -h, --help              显示帮助
    -v, --version           显示版本

传输选项:
    --transfer-to PATH      完成后传输结果到指定路径 (自动检测远程输出路径)
    --keep-temp             保留临时目录不删除 (用于调试)

示例:
    # 完整流程（输出到 /tmp/output/seq/ 子目录）
    af3_pipeline.sh full -m api /path/to/seq.fa /tmp/output

    # 指定任务名称
    af3_pipeline.sh full -n my_task /path/to/seq.fa /tmp/output

    # 使用环境变量指定 GPU
    CUDA_VISIBLE_DEVICES=1 af3_pipeline.sh full /path/to/seq.fa /tmp/output

    # 远程输入和输出（自动创建临时目录并传输）
    af3_pipeline.sh json user@host:/path/input.fa user@host:/path/output

    # 仅 MSA
    af3_pipeline.sh msa -m api /path/to/seq.fa /tmp/output

    # 原生预测（使用 AF3 内置 MSA，无需预计算 ColabFold MSA）
    af3_pipeline.sh af3 /path/to/seq.fa /tmp/output

    # 恢复执行 - MSA 完成后 AF3 中断，从断点继续
    af3_pipeline.sh resume /tmp/output/task_name

    # 恢复执行 - 完成后传输结果
    af3_pipeline.sh resume /tmp/output/task_name --transfer-to user@host:/path

EOF
}

show_version() {
    echo "AlphaFold3 Pipeline v${VERSION}"
}

# ==================== 打印配置信息 ====================
print_config() {
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│                      当前配置                               │"
    echo "├─────────────────────────────────────────────────────────────┤"
    printf "│  %-12s : %-44s │\n" "运行模式" "$MODE"
    printf "│  %-12s : %-44s │\n" "任务名称" "$TASK_NAME"
    printf "│  %-12s : %-44s │\n" "输入路径" "$INPUT_PATH"
    printf "│  %-12s : %-44s │\n" "输出目录" "$OUTPUT_DIR"
    printf "│  %-12s : %-44s │\n" "MSA 方式" "$MSA_METHOD"
    printf "│  %-12s : %-44s │\n" "GPU ID" "$GPU_ID"
    printf "│  %-12s : %-44s │\n" "线程数" "$THREADS"
    printf "│  %-12s : %-44s │\n" "使用模板" "$USE_TEMPLATE"
    if [[ -n "$TEMP_DIR" ]]; then
        printf "│  %-12s : %-44s │\n" "临时目录" "$TEMP_DIR"
    fi
    if [[ -n "$TRANSFER_TO" ]]; then
        printf "│  %-12s : %-44s │\n" "传输目标" "$TRANSFER_TO"
    fi
    if [[ "$KEEP_TEMP" == true ]]; then
        printf "│  %-12s : %-44s │\n" "保留临时" "是"
    fi
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
}

# ==================== 完整流程 ====================
run_full_pipeline() {
    local input="$1"
    local output="$2"
    
    log_step "阶段 1/2: MSA 计算"
    
    # 直接调用 af3_msa.sh，传递所有必要参数
    local template_flag="--use-template"
    if [[ "$USE_TEMPLATE" != true ]]; then
        template_flag="--no-template"
    fi
    
    log_info "执行: af3_msa.sh -m $MSA_METHOD -g $GPU_ID -t $THREADS $template_flag $input $output"
    
    bash "${SCRIPT_DIR}/af3_msa.sh" \
        -m "$MSA_METHOD" \
        -g "$GPU_ID" \
        -t "$THREADS" \
        $template_flag \
        "$input" \
        "$output"
    
    log_step "阶段 2/2: AlphaFold3 预测"
    
    log_info "执行: af3_run.sh -g $GPU_ID ${output}/msa $output"
    
    bash "${SCRIPT_DIR}/af3_run.sh" -g "$GPU_ID" "${output}/msa" "$output"
    
    # 传输结果
    if [[ -n "$TRANSFER_TO" ]]; then
        log_step "阶段 3/3: 传输结果"
        bash "${SCRIPT_DIR}/af3_transfer.sh" "${output}/af3" "$TRANSFER_TO"
    fi
    
    log_step "Pipeline 完成!"
    echo ""
    echo "结果目录:"
    echo "  MSA:  ${output}/msa/"
    echo "  AF3:  ${output}/af3/"
    if [[ -n "$TRANSFER_TO" ]]; then
        echo "  远程: ${TRANSFER_TO}"
    fi
}

# ==================== 仅 MSA ====================
run_msa_only() {
    local input="$1"
    local output="$2"
    
    local template_flag="--use-template"
    if [[ "$USE_TEMPLATE" != true ]]; then
        template_flag="--no-template"
    fi
    
    log_info "执行: af3_msa.sh -m $MSA_METHOD -g $GPU_ID -t $THREADS $template_flag $input $output"
    
    bash "${SCRIPT_DIR}/af3_msa.sh" \
        -m "$MSA_METHOD" \
        -g "$GPU_ID" \
        -t "$THREADS" \
        $template_flag \
        "$input" \
        "$output"
    
    if [[ -n "$TRANSFER_TO" ]]; then
        log_step "传输 MSA 结果"
        bash "${SCRIPT_DIR}/af3_transfer.sh" "${output}/msa" "$TRANSFER_TO"
    fi
    
    log_step "MSA 计算完成!"
    echo ""
    echo "结果目录: ${output}/msa/"
    echo ""
    echo "下一步运行 AF3:"
    echo "  af3_pipeline.sh af3 ${output}/msa ${output}"
}

# ==================== 仅 AF3 ====================
run_af3_only() {
    local input="$1"
    local output="$2"
    
    log_info "执行: af3_run.sh -g $GPU_ID $input $output"
    
    bash "${SCRIPT_DIR}/af3_run.sh" -g "$GPU_ID" "$input" "$output"
    
    if [[ -n "$TRANSFER_TO" ]]; then
        log_step "传输 AF3 结果"
        bash "${SCRIPT_DIR}/af3_transfer.sh" "${output}/af3" "$TRANSFER_TO"
    fi
    
    log_step "AF3 预测完成!"
    echo ""
    echo "结果目录: ${output}/af3/"
}

# ==================== 仅 JSON生成 ====================
run_json_mode() {
    local input="$1"
    local output="$2"
    
    if [[ -f "$input" ]]; then
        # 本地文件
        :
    elif is_remote_path "$input"; then
        # 远程文件 - 自动下载
        local local_fasta="${output}/input/$(basename "${input##*:}")"
        ensure_dir "$(dirname "$local_fasta")"
        
        log_info "下载远程 FASTA: ${input} -> ${local_fasta}"
        rsync -avz --progress "$input" "$local_fasta"
        input="$local_fasta"
    fi

    log_step "生成 AF3 JSON 文件"
    log_info "输入文件: $input"
    log_info "输出目录: $output"
    
    python3 "${SCRIPT_DIR}/fasta_to_af3_json.py" "$input" "$output" --name "$TASK_NAME"
    
    log_success "JSON 生成完成"
    echo "输出目录: $output"

    if [[ -n "$TRANSFER_TO" ]]; then
        log_step "传输 JSON 结果"
        # 直接传输 output 目录下的 json 文件
        # 或者更准确地，传输整个输出目录中的内容
        # 但考虑到 consistency, 也许我们想把所有的json都传过去
        # 这里虽然没有专门的 json 子目录， fasta_to_af3_json.py 是直接输出到 output 的
        # 为了传输方便，我们直接传输 output 目录
        bash "${SCRIPT_DIR}/af3_transfer.sh" "$output" "$TRANSFER_TO"
    fi
}

# ==================== 仅传输 ====================
run_transfer_only() {
    local src="$1"
    local dst="$2"

    bash "${SCRIPT_DIR}/af3_transfer.sh" "$src" "$dst"
}

# ==================== 恢复执行 ====================
# 检测任务目录状态并从断点继续
run_resume() {
    local task_dir="$1"

    log_step "检测任务状态"
    log_info "任务目录: $task_dir"

    local msa_dir="${task_dir}/msa"
    local af3_dir="${task_dir}/af3"

    # 检查 MSA 状态
    local msa_json_count=0
    if [[ -d "$msa_dir" ]]; then
        msa_json_count=$(find "$msa_dir" -maxdepth 1 -name "*.json" -type f 2>/dev/null | wc -l)
    fi

    # 检查 AF3 状态
    local af3_result_count=0
    if [[ -d "$af3_dir" ]]; then
        af3_result_count=$(find "$af3_dir" -name "*.cif" -o -name "*.pdb" 2>/dev/null | wc -l)
    fi

    echo ""
    echo "┌─────────────────────────────────────────┐"
    echo "│          任务状态检测                   │"
    echo "├─────────────────────────────────────────┤"
    printf "│  %-12s : %-24s │\n" "MSA 目录" "$([ -d "$msa_dir" ] && echo "存在" || echo "不存在")"
    printf "│  %-12s : %-24s │\n" "MSA JSON" "${msa_json_count} 个文件"
    printf "│  %-12s : %-24s │\n" "AF3 目录" "$([ -d "$af3_dir" ] && echo "存在" || echo "不存在")"
    printf "│  %-12s : %-24s │\n" "AF3 结果" "${af3_result_count} 个结构文件"
    echo "└─────────────────────────────────────────┘"
    echo ""

    # 决定从哪里继续
    if [[ $msa_json_count -eq 0 ]]; then
        log_error "MSA 未完成或不存在，无法恢复"
        log_info "请使用 'full' 或 'msa' 模式从头开始"
        exit 1
    fi

    if [[ $af3_result_count -gt 0 ]] && [[ $af3_result_count -ge $msa_json_count ]]; then
        log_success "任务已完成！"
        log_info "MSA 结果: ${msa_dir}"
        log_info "AF3 结果: ${af3_dir}"

        # 如果指定了传输，执行传输
        if [[ -n "$TRANSFER_TO" ]]; then
            log_step "传输结果"
            bash "${SCRIPT_DIR}/af3_transfer.sh" "${af3_dir}" "$TRANSFER_TO"
        fi
        return 0
    fi

    # MSA 完成，AF3 需要运行或继续
    log_info "MSA 已完成，继续运行 AF3..."

    log_step "运行 AlphaFold3 预测"
    log_info "执行: af3_run.sh -g $GPU_ID $msa_dir $task_dir"

    bash "${SCRIPT_DIR}/af3_run.sh" -g "$GPU_ID" "$msa_dir" "$task_dir"

    # 传输结果
    if [[ -n "$TRANSFER_TO" ]]; then
        log_step "传输结果"
        bash "${SCRIPT_DIR}/af3_transfer.sh" "${af3_dir}" "$TRANSFER_TO"
    fi

    log_step "恢复执行完成!"
    echo ""
    echo "结果目录:"
    echo "  MSA:  ${msa_dir}/"
    echo "  AF3:  ${af3_dir}/"
    if [[ -n "$TRANSFER_TO" ]]; then
        echo "  远程: ${TRANSFER_TO}"
    fi
}

# ==================== 主函数 ====================
main() {
    # 默认值
    MODE="full"
    MSA_METHOD="${DEFAULT_MSA_METHOD:-api}"
    GPU_ID="${DEFAULT_GPU_ID:-0}"
    THREADS="${DEFAULT_THREADS:-64}"
    USE_TEMPLATE="${DEFAULT_USE_TEMPLATE:-true}"
    TRANSFER_TO=""
    TASK_NAME=""
    KEEP_TEMP=false
    TEMP_DIR=""
    POSITIONAL_ARGS=()

    # 检查是否是模式参数
    case "${1:-}" in
        full|msa|af3|json|transfer|resume)
            MODE="$1"
            shift
            ;;
    esac

    # 解析选项
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--gpu)
                GPU_ID="$2"
                shift 2
                ;;
            -n|--task-name)
                TASK_NAME="$2"
                shift 2
                ;;
            -m|--msa-method)
                MSA_METHOD="$2"
                shift 2
                ;;
            -t|--threads)
                THREADS="$2"
                shift 2
                ;;
            --use-template)
                USE_TEMPLATE=true
                shift
                ;;
            --no-template)
                USE_TEMPLATE=false
                shift
                ;;
            --transfer-to)
                TRANSFER_TO="$2"
                shift 2
                ;;
            --keep-temp)
                KEEP_TEMP=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -*)
                # 遇到未知选项，如果不是help/version，仍然报错，但是...
                # 这里有一个问题。如果用户把选项写在位置参数后面，while 循环在遇到第一个位置参数时就break了
                # 所以选项必须写在位置参数前面
                # 为了支持放在后面，我们需要修改解析逻辑
                log_error "未知选项: $1"
                echo "使用 -h 查看帮助"
                exit 1
                ;;
            *)
                # 遇到非选项参数（即位置参数），我们先把它保存起来，然后继续解析后续参数
                # 但 bash 的位置参数处理比较麻烦。
                # 简单的做法是：我们允许位置参数穿插在选项中，或者我们要重构解析逻辑。
                # 这里采用：收集位置参数到数组，继续解析
                POSITIONAL_ARGS+=("$1")
                shift
                ;;
        esac
    done

    # 恢复位置参数
    set -- "${POSITIONAL_ARGS[@]}"

    # ==================== resume 模式特殊处理 ====================
    if [[ "$MODE" == "resume" ]]; then
        if [[ $# -lt 1 ]]; then
            log_error "resume 模式需要指定任务目录"
            echo "使用: af3_pipeline.sh resume <任务目录> [选项]"
            exit 1
        fi

        local TASK_DIR="$1"

        # 将相对路径转换为绝对路径
        if [[ ! "$TASK_DIR" =~ ^/ ]]; then
            if command -v realpath &>/dev/null; then
                TASK_DIR="$(realpath -m "$TASK_DIR")"
            else
                TASK_DIR="$(pwd)/${TASK_DIR#./}"
            fi
        fi

        # 检查任务目录是否存在
        if [[ ! -d "$TASK_DIR" ]]; then
            log_error "任务目录不存在: $TASK_DIR"
            exit 1
        fi

        # 从目录名提取任务名称
        TASK_NAME=$(basename "$TASK_DIR")
        INPUT_PATH="$TASK_DIR"
        OUTPUT_DIR="$TASK_DIR"

        # 显示 Banner
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║              AlphaFold3 Pipeline v${VERSION}                          ║"
        echo "║              $(date '+%Y-%m-%d %H:%M:%S')                               ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"

        # 打印配置
        print_config

        # 记录开始时间
        START_TIME=$(date +%s)

        # 运行恢复
        run_resume "$TASK_DIR"

        # 计算运行时间
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        HOURS=$((DURATION / 3600))
        MINUTES=$(((DURATION % 3600) / 60))
        SECONDS=$((DURATION % 60))

        echo ""
        echo "════════════════════════════════════════════════════════════════════"
        printf "总运行时间: %02d:%02d:%02d\n" $HOURS $MINUTES $SECONDS
        echo "════════════════════════════════════════════════════════════════════"
        exit 0
    fi

    # ==================== af3 模式：使用 AF3 内置 MSA 预测 ====================
    if [[ "$MODE" == "af3" ]]; then
        if [[ $# -lt 2 ]]; then
            log_error "af3 模式需要指定输入 FASTA 和输出目录"
            echo "使用: af3_pipeline.sh af3 <FASTA文件> <输出目录>"
            echo ""
            echo "此模式使用 AlphaFold3 内置的 MSA 计算方法，无需预计算 ColabFold MSA"
            exit 1
        fi

        INPUT_PATH="$1"
        local OUTPUT_BASE="$2"

        # 将相对路径转换为绝对路径
        if [[ ! "$INPUT_PATH" =~ ^/ ]] && [[ -e "$INPUT_PATH" ]]; then
            if command -v realpath &>/dev/null; then
                INPUT_PATH="$(realpath "$INPUT_PATH")"
            else
                INPUT_PATH="$(cd "$(dirname "$INPUT_PATH")" && pwd)/$(basename "$INPUT_PATH")"
            fi
        fi

        if [[ ! "$OUTPUT_BASE" =~ ^/ ]] && ! is_remote_path "$OUTPUT_BASE"; then
            if command -v realpath &>/dev/null; then
                OUTPUT_BASE="$(realpath -m "$OUTPUT_BASE")"
            else
                OUTPUT_BASE="$(pwd)/${OUTPUT_BASE#./}"
            fi
        fi

        # 检查输入文件
        if [[ ! -f "$INPUT_PATH" ]]; then
            log_error "FASTA 文件不存在: $INPUT_PATH"
            exit 1
        fi

        # 从文件名提取任务名称
        if [[ -z "$TASK_NAME" ]]; then
            local input_basename=$(basename "$INPUT_PATH")
            TASK_NAME="${input_basename%.*}"
        fi

        OUTPUT_DIR="${OUTPUT_BASE}/${TASK_NAME}"

        # 显示 Banner
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║              AlphaFold3 Pipeline v${VERSION}                          ║"
        echo "║              $(date '+%Y-%m-%d %H:%M:%S')                               ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"

        echo ""
        echo "┌─────────────────────────────────────────────────────────────┐"
        echo "│           AF3 原生预测模式（使用 AF3 内置 MSA）             │"
        echo "├─────────────────────────────────────────────────────────────┤"
        printf "│  %-12s : %-44s │\n" "输入文件" "$(basename "$INPUT_PATH")"
        printf "│  %-12s : %-44s │\n" "输出目录" "$OUTPUT_DIR"
        printf "│  %-12s : %-44s │\n" "任务名称" "$TASK_NAME"
        printf "│  %-12s : %-44s │\n" "GPU ID" "$GPU_ID"
        echo "└─────────────────────────────────────────────────────────────┘"
        echo ""

        # 创建输出目录
        ensure_dir "$OUTPUT_DIR"

        # 记录开始时间
        START_TIME=$(date +%s)

        # 步骤1: 生成 AF3 JSON（不含预计算 MSA，让 AF3 自行计算）
        log_step "步骤 1/2: 生成 AF3 JSON"

        local json_dir="${OUTPUT_DIR}/json"
        ensure_dir "$json_dir"

        log_info "执行: fasta_to_af3_json.py $INPUT_PATH $json_dir --name $TASK_NAME"
        python3 "${SCRIPT_DIR}/fasta_to_af3_json.py" "$INPUT_PATH" "$json_dir" --name "$TASK_NAME"

        # 步骤2: 运行 AF3 预测
        log_step "步骤 2/2: 运行 AlphaFold3 预测"

        log_info "执行: af3_run.sh -g $GPU_ID $json_dir $OUTPUT_DIR"
        bash "${SCRIPT_DIR}/af3_run.sh" -g "$GPU_ID" "$json_dir" "$OUTPUT_DIR"

        # 传输结果
        if [[ -n "$TRANSFER_TO" ]]; then
            log_step "传输 AF3 结果"
            bash "${SCRIPT_DIR}/af3_transfer.sh" "${OUTPUT_DIR}/af3" "$TRANSFER_TO"
        fi

        log_step "AF3 原生预测完成!"
        echo ""
        echo "结果目录:"
        echo "  JSON: ${json_dir}/"
        echo "  AF3:  ${OUTPUT_DIR}/af3/"
        if [[ -n "$TRANSFER_TO" ]]; then
            echo "  远程: ${TRANSFER_TO}"
        fi

        # 计算运行时间
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        HOURS=$((DURATION / 3600))
        MINUTES=$(((DURATION % 3600) / 60))
        SECONDS=$((DURATION % 60))

        echo ""
        echo "════════════════════════════════════════════════════════════════════"
        printf "总运行时间: %02d:%02d:%02d\n" $HOURS $MINUTES $SECONDS
        echo "════════════════════════════════════════════════════════════════════"
        exit 0
    fi

    # ==================== 其他模式需要两个参数 ====================
    # 检查参数
    if [[ $# -lt 2 ]]; then
        log_error "缺少必要参数: <输入路径> <输出目录>"
        echo ""
        echo "使用 -h 查看帮助"
        exit 1
    fi

    INPUT_PATH="$1"
    local OUTPUT_BASE="$2"

    # 将相对路径转换为绝对路径（避免后续 cd 导致路径解析错误）
    if [[ ! "$OUTPUT_BASE" =~ ^/ ]] && ! is_remote_path "$OUTPUT_BASE"; then
        # 使用 realpath 或手动构建绝对路径
        if command -v realpath &>/dev/null; then
            OUTPUT_BASE="$(realpath -m "$OUTPUT_BASE")"
        else
            # 手动构建：当前工作目录 + 相对路径
            OUTPUT_BASE="$(pwd)/${OUTPUT_BASE#./}"
        fi
        log_info "输出路径转换为绝对路径: $OUTPUT_BASE"
    fi

    # 检测输出路径是否为远程路径
    if is_remote_path "$OUTPUT_BASE"; then
        log_info "检测到远程输出路径: $OUTPUT_BASE"

        # 如果没有显式指定 --transfer-to，则自动设置
        if [[ -z "$TRANSFER_TO" ]]; then
            TRANSFER_TO="$OUTPUT_BASE"
            log_info "自动设置传输目标: $TRANSFER_TO"
        fi

        # 创建本地临时目录
        TEMP_DIR=$(mktemp -d -t af3_pipeline_XXXXXX)
        log_info "创建临时工作目录: $TEMP_DIR"

        # 使用临时目录作为本地输出目录
        OUTPUT_BASE="$TEMP_DIR"

        # 设置清理陷阱（如果不保留临时目录）
        if [[ "$KEEP_TEMP" != true ]]; then
            setup_cleanup_trap "$TEMP_DIR"
        else
            log_info "临时目录将被保留: $TEMP_DIR"
        fi
    fi

    # 如果没有指定任务名称，从输入文件名提取
    if [[ -z "$TASK_NAME" ]]; then
        # 获取文件名（不含路径和扩展名）
        local input_basename=$(basename "$INPUT_PATH")
        TASK_NAME="${input_basename%.*}"
    fi

    # 构建最终输出目录：基础目录/任务名称
    OUTPUT_DIR="${OUTPUT_BASE}/${TASK_NAME}"

    # 显示 Banner
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║              AlphaFold3 Pipeline v${VERSION}                          ║"
    echo "║              $(date '+%Y-%m-%d %H:%M:%S')                               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"

    # 打印配置
    print_config

    # 创建输出目录
    ensure_dir "$OUTPUT_DIR"

    # 记录开始时间
    START_TIME=$(date +%s)
    
    # 根据模式执行 (af3 和 resume 已在前面处理)
    case "$MODE" in
        full)
            run_full_pipeline "$INPUT_PATH" "$OUTPUT_DIR"
            ;;
        msa)
            run_msa_only "$INPUT_PATH" "$OUTPUT_DIR"
            ;;
        json)
            run_json_mode "$INPUT_PATH" "$OUTPUT_DIR"
            ;;
        transfer)
            run_transfer_only "$INPUT_PATH" "$OUTPUT_DIR"
            ;;
        *)
            log_error "未知模式: $MODE"
            exit 1
            ;;
    esac
    
    # 计算运行时间
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    HOURS=$((DURATION / 3600))
    MINUTES=$(((DURATION % 3600) / 60))
    SECONDS=$((DURATION % 60))
    
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    printf "总运行时间: %02d:%02d:%02d\n" $HOURS $MINUTES $SECONDS
    echo "════════════════════════════════════════════════════════════════════"
}

# 执行主函数
main "$@"
