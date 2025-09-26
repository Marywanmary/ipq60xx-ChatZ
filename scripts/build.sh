#!/bin/bash

# ====== 脚本配置 ======
# 设置错误退出
set -e
set -o pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 创建日志目录
mkdir -p logs

# 日志文件
LOG_FILE="logs/build.log"
ERROR_LOG_FILE="logs/build_error.log"
SUMMARY_LOG_FILE="logs/build_summary.log"

# ====== 日志函数 ======
log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo -e "${GREEN}${msg}${PLAIN}" | tee -a ${LOG_FILE}
}

log_warn() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1"
    echo -e "${YELLOW}${msg}${PLAIN}" | tee -a ${LOG_FILE}
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}${msg}${PLAIN}" | tee -a ${LOG_FILE}
    echo -e "${msg}" >> ${ERROR_LOG_FILE}
}

log_debug() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1"
    echo -e "${BLUE}${msg}${PLAIN}" | tee -a ${LOG_FILE}
}

log_step() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [STEP] $1"
    echo -e "${CYAN}${msg}${PLAIN}" | tee -a ${LOG_FILE}
}

log_progress() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [PROGRESS] $1"
    echo -e "${GREEN}${msg}${PLAIN}" | tee -a ${LOG_FILE} ${SUMMARY_LOG_FILE}
}

# ====== 错误处理函数 ======
handle_error() {
    log_error "脚本在第 $1 行发生错误，错误代码: $2"
    # 记录错误前1000行日志
    echo -e "\n===== 错误前1000行日志 =====" >> ${ERROR_LOG_FILE}
    tail -n 1000 ${LOG_FILE} >> ${ERROR_LOG_FILE}
    exit $2
}

# 设置错误处理陷阱
trap 'handle_error ${LINENO} $?' ERR

# ====== 执行函数 ======
# 安全执行命令，出错时记录并退出
safe_exec() {
    log_debug "执行: $*"
    if ! "$@" >> ${LOG_FILE} 2>&1; then
        log_error "命令执行失败: $*"
        return 1
    fi
    return 0
}

# ====== 主要功能函数 ======
# 显示缓存状态
show_cache_status() {
    log_info "缓存状态:"
    
    if [ -d "dl" ]; then
        local dl_size=$(du -sh dl | cut -f1)
        log_info "dl 目录存在，大小: $dl_size"
    else
        log_info "dl 目录不存在"
    fi
    
    if [ -d "feeds" ]; then
        local feeds_size=$(du -sh feeds | cut -f1)
        log_info "feeds 目录存在，大小: $feeds_size"
    else
        log_info "feeds 目录不存在"
    fi
    
    if [ -d ".ccache" ]; then
        local ccache_size=$(du -sh .ccache | cut -f1)
        log_info "ccache 目录存在，大小: $ccache_size"
    else
        log_info "ccache 目录不存在"
    fi
    
    if [ -d "staging_dir" ]; then
        local staging_size=$(du -sh staging_dir | cut -f1)
        log_info "staging_dir 目录存在，大小: $staging_size"
    else
        log_info "staging_dir 目录不存在"
    fi
    
    if [ -d "build_dir" ]; then
        local build_size=$(du -sh build_dir | cut -f1)
        log_info "build_dir 目录存在，大小: $build_size"
    else
        log_info "build_dir 目录不存在"
    fi
    
    if [ -d "toolchain" ]; then
        local toolchain_size=$(du -sh toolchain | cut -f1)
        log_info "toolchain 目录存在，大小: $toolchain_size"
    else
        log_info "toolchain 目录不存在"
    fi
}

# 初始化编译环境
init_build_env() {
    log_step "初始化编译环境..."
    
    # 显示缓存状态
    show_cache_status
    
    # 更新并安装所有feeds
    log_progress "更新feeds..."
    safe_exec ./scripts/feeds update -a
    log_progress "安装feeds..."
    safe_exec ./scripts/feeds install -a
    
    # 配置构建环境
    log_progress "配置构建环境..."
    safe_exec make defconfig
    
    log_info "编译环境初始化完成"
}

# 编译固件
build_firmware() {
    local chip=$1
    local branch=$2
    local config=$3
    local devices=$4
    
    log_step "开始编译固件..."
    log_info "芯片: $chip, 分支: $branch, 配置: $config"
    log_info "设备列表: $devices"
    
    # 设置编译线程数
    local threads=$(nproc)
    log_info "使用 $threads 个线程进行编译"
    
    # 下载所需包
    log_progress "下载所需包..."
    safe_exec make download -j${threads}
    
    # 编译固件
    log_progress "编译固件..."
    safe_exec make -j${threads} V=s 2>&1 | grep -E "(error|Error|ERROR|warning|Warning|WARNING|make|Make|MAKE|time|Time|TIME|^\|.*\||Entering directory|Leaving directory)"
    
    log_info "固件编译完成"
}

# 处理产出物
process_artifacts() {
    local chip=$1
    local branch=$2
    local config=$3
    local devices=$4
    
    log_step "处理产出物..."
    
    # 创建输出目录
    local output_dir="output/${chip}-${branch}-${config}"
    mkdir -p $output_dir
    
    # 将设备字符串转换为数组
    local device_array=($devices)
    
    # 处理每个设备
    for device in "${device_array[@]}"; do
        log_info "处理设备: $device"
        
        # 查找固件文件
        local firmware_files=$(find bin/targets/ -name "*${device}*squashfs*.bin")
        
        # 处理每个固件文件
        for firmware in $firmware_files; do
            # 获取固件类型 (factory 或 sysupgrade)
            if [[ $firmware == *"factory"* ]]; then
                local firmware_type="factory"
            else
                local firmware_type="sysupgrade"
            fi
            
            # 重命名固件文件
            local new_firmware_name="${branch}-${chip}-${device}-${firmware_type}-${config}.bin"
            log_info "重命名固件: $firmware -> $output_dir/$new_firmware_name"
            cp $firmware "$output_dir/$new_firmware_name"
        done
        
        # 处理manifest文件
        local manifest_files=$(find bin/targets/ -name "*.manifest")
        for manifest in $manifest_files; do
            # 检查manifest文件是否包含当前设备
            if grep -q "$device" "$manifest"; then
                local manifest_name="${branch}-${chip}-${device}-${config}.manifest"
                log_info "复制manifest文件: $manifest -> $output_dir/$manifest_name"
                cp $manifest "$output_dir/$manifest_name"
            fi
        done
    done
    
    # 处理配置文件
    if [ -f ".config" ]; then
        local config_name="${branch}-${chip}-${config}.config"
        log_info "复制配置文件: .config -> $output_dir/$config_name"
        cp .config "$output_dir/$config_name"
    fi
    
    # 处理config.buildinfo文件
    if [ -d "bin/targets" ]; then
        local buildinfo_files=$(find bin/targets/ -name "config.buildinfo")
        for buildinfo in $buildinfo_files; do
            local buildinfo_name="${branch}-${chip}-${config}.config.buildinfo"
            log_info "复制buildinfo文件: $buildinfo -> $output_dir/$buildinfo_name"
            cp $buildinfo "$output_dir/$buildinfo_name"
        done
    fi
    
    # 复制日志文件
    log_info "复制日志文件..."
    cp logs/*.log $output_dir/
    
    # 复制软件包
    local packages_dirs=$(find bin/packages -type d -name "base" 2>/dev/null)
    for packages_dir in $packages_dirs; do
        if [ -d "$packages_dir" ]; then
            local app_output_dir="$output_dir/packages"
            mkdir -p $app_output_dir
            log_info "复制软件包: $packages_dir -> $app_output_dir"
            cp -r $packages_dir/* $app_output_dir/
        fi
    done
    
    # 创建压缩包
    log_info "创建压缩包..."
    cd $output_dir/..
    
    # 配置文件压缩包
    tar -czf "${chip}-config.tar.gz" "${chip}-${branch}-${config}/"*.config "${chip}-${branch}-${config}/"*.config.buildinfo "${chip}-${branch}-${config}/"*.manifest
    
    # 日志文件压缩包
    tar -czf "${chip}-log.tar.gz" "${chip}-${branch}-${config}/"*.log
    
    # 软件包压缩包
    if [ -d "${chip}-${branch}-${config}/packages" ]; then
        tar -czf "${chip}-app.tar.gz" -C "${chip}-${branch}-${config}" packages/
    fi
    
    cd ..
    
    log_info "产出物处理完成"
}

# ====== 主函数 ======
main() {
    # 检查参数
    if [ $# -ne 4 ]; then
        log_error "参数错误: $0 <chip> <branch> <config> <devices>"
        exit 1
    fi
    
    local chip=$1
    local branch=$2
    local config=$3
    local devices=$4
    
    log_info "====== 开始执行编译脚本 ======"
    log_info "芯片: $chip, 分支: $branch, 配置: $config, 设备: $devices"
    
    # 初始化编译环境
    init_build_env
    
    # 编译固件
    build_firmware $chip $branch $config "$devices"
    
    # 处理产出物
    process_artifacts $chip $branch $config "$devices"
    
    log_info "====== 编译脚本执行完成 ======"
}

# 执行主函数
main "$@"
