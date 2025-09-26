#!/bin/bash

# 设置错误退出
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${PLAIN} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${PLAIN} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${PLAIN} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${PLAIN} $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "命令 $1 不存在，请先安装"
        exit 1
    fi
}

# 处理编译产物
process_artifacts() {
    # 参数检查
    if [ $# -lt 4 ]; then
        log_error "参数不足: 需要提供分支名称、芯片名称、设备名称和配置类型"
        log_info "用法: $0 process_artifacts <branch> <chip> <device_names> <config>"
        exit 1
    fi

    local branch=$1
    local chip=$2
    local device_names=$3
    local config=$4
    
    log_info "开始处理 ${branch}-${chip}-${config} 的编译产物"
    
    # 源目录和目标目录
    local src_dir="/workdir/openwrt/bin/targets"
    local target_dir=$(find ${src_dir} -type d -name "${chip}")
    
    if [ -z "$target_dir" ]; then
        log_error "找不到目标目录: ${chip}"
        exit 1
    fi
    
    log_info "找到目标目录: ${target_dir}"
    
    # 创建临时目录
    local firmware_dir="/tmp/artifact/firmware"
    local config_dir="/tmp/artifact/config"
    local logs_dir="/tmp/artifact/logs"
    local packages_dir="/tmp/artifact/packages"
    
    # 处理固件文件
    log_info "处理固件文件..."
    for device in ${device_names}; do
        log_info "处理设备: ${device}"
        
        # 查找固件文件
        local factory_files=$(find ${target_dir} -name "*${device}*factory*.bin")
        local sysupgrade_files=$(find ${target_dir} -name "*${device}*sysupgrade*.bin")
        
        # 处理factory固件
        for file in ${factory_files}; do
            local filename=$(basename ${file})
            local new_name="${branch}-${device}-factory-${config}.bin"
            log_info "重命名: ${filename} -> ${new_name}"
            cp -f ${file} ${firmware_dir}/${new_name}
        done
        
        # 处理sysupgrade固件
        for file in ${sysupgrade_files}; do
            local filename=$(basename ${file})
            local new_name="${branch}-${device}-sysupgrade-${config}.bin"
            log_info "重命名: ${filename} -> ${new_name}"
            cp -f ${file} ${firmware_dir}/${new_name}
        done
    done
    
    # 处理配置文件
    log_info "处理配置文件..."
    for device in ${device_names}; do
        # 复制并重命名.config文件
        if [ -f "/workdir/openwrt/.config" ]; then
            cp -f "/workdir/openwrt/.config" "${config_dir}/${branch}-${chip}-${device}-${config}.config"
        fi
        
        # 复制并重命名.config.buildinfo文件
        local buildinfo_file=$(find ${target_dir} -name "*.buildinfo")
        if [ -n "$buildinfo_file" ]; then
            cp -f ${buildinfo_file} "${config_dir}/${branch}-${chip}-${device}-${config}.config.buildinfo"
        fi
        
        # 复制并重命名.manifest文件
        local manifest_file=$(find ${target_dir} -name "*.manifest")
        if [ -n "$manifest_file" ]; then
            cp -f ${manifest_file} "${config_dir}/${branch}-${chip}-${device}-${config}.manifest"
        fi
    done
    
    # 处理日志文件
    log_info "处理日志文件..."
    # 复制编译日志
    if [ -f "/workdir/openwrt/logs/script.log" ]; then
        cp -f "/workdir/openwrt/logs/script.log" "${logs_dir}/${branch}-${chip}-${config}-script.log"
    fi
    
    if [ -f "/workdir/openwrt/logs/script_error.log" ]; then
        cp -f "/workdir/openwrt/logs/script_error.log" "${logs_dir}/${branch}-${chip}-${config}-script_error.log"
    fi
    
    # 提取错误和警告日志
    if [ -f "/workdir/openwrt/logs/script.log" ]; then
        grep -E "error:|warning:" "/workdir/openwrt/logs/script.log" > "${logs_dir}/${branch}-${chip}-${config}-errors.log" || true
    fi
    
    # 创建编译摘要
    create_build_summary "${branch}" "${chip}" "${config}" "${device_names}" "${logs_dir}/${branch}-${chip}-${config}-summary.log"
    
    # 处理软件包
    log_info "处理软件包..."
    local ipk_dir="/workdir/openwrt/bin/packages"
    local apk_dir="/workdir/openwrt/bin/packages"
    
    # 检查是否使用APK
    if grep -q "CONFIG_USE_APK=y" "/workdir/openwrt/.config"; then
        log_info "使用APK包格式"
        find ${apk_dir} -name "*.apk" -exec cp {} ${packages_dir}/ \;
    else
        log_info "使用IPK包格式"
        find ${ipk_dir} -name "*.ipk" -exec cp {} ${packages_dir}/ \;
    fi
    
    log_info "${branch}-${chip}-${config} 的编译产物处理完成"
}

# 创建编译摘要
create_build_summary() {
    local branch=$1
    local chip=$2
    local config=$3
    local device_names=$4
    local output_file=$5
    
    log_info "创建编译摘要: ${output_file}"
    
    {
        echo "============================================"
        echo "编译摘要: ${branch}-${chip}-${config}"
        echo "============================================"
        echo "编译时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        
        echo "内核版本:"
        if [ -f "target/linux/generic/kernel-6.12" ]; then
            grep -oP 'LINUX_KERNEL_HASH-\K[0-9]+\.[0-9]+\.[0-9]+' target/linux/generic/kernel-6.12 || echo "未知"
        else
            echo "6.12"
        fi
        echo ""
        
        echo "设备列表:"
        if [ -n "$device_names" ]; then
            for device in ${device_names}; do
                echo "- ${device}"
            done
        else
            echo "未检测到设备"
        fi
        echo ""
        
        echo "软件包列表:"
        find "/workdir/openwrt/bin/packages" -name "luci-app-*.ipk" -o -name "luci-app-*.apk" | sort | uniq | sed 's/.*\///g' | sed 's/_.*.ipk//g' | sed 's/_.*.apk//g' || echo "未找到软件包"
        echo ""
        
        echo "编译状态: 成功"
        echo "============================================"
    } > ${output_file}
}

# 主函数
main() {
    local command=$1
    shift
    
    case ${command} in
        process_artifacts)
            process_artifacts "$@"
            ;;
        *)
            log_error "未知命令: ${command}"
            log_info "可用命令: process_artifacts"
            exit 1
            ;;
    esac
}

# 执行主函数
if [ $# -gt 0 ]; then
    main "$@"
else
    log_error "请提供命令"
    log_info "可用命令: process_artifacts"
    exit 1
fi
