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
PLAIN='\033[0m'

# 创建日志目录
mkdir -p logs

# 日志文件
LOG_FILE="logs/script.log"
ERROR_LOG_FILE="logs/script_error.log"

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE_ABS="$SCRIPT_DIR/$LOG_FILE"
ERROR_LOG_FILE_ABS="$SCRIPT_DIR/$ERROR_LOG_FILE"

# ====== 日志函数 ======
log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo -e "${GREEN}${msg}${PLAIN}" | tee -a ${LOG_FILE_ABS}
}

log_warn() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1"
    echo -e "${YELLOW}${msg}${PLAIN}" | tee -a ${LOG_FILE_ABS}
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}${msg}${PLAIN}" | tee -a ${LOG_FILE_ABS}
    echo -e "${msg}" >> ${ERROR_LOG_FILE_ABS}
}

log_debug() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1"
    echo -e "${BLUE}${msg}${PLAIN}" | tee -a ${LOG_FILE_ABS}
}

log_progress() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [PROGRESS] $1"
    echo -e "${GREEN}${msg}${PLAIN}" | tee -a ${LOG_FILE_ABS}
}

# ====== 错误处理函数 ======
handle_error() {
    log_error "脚本在第 $1 行发生错误，错误代码: $2"
    exit $2
}

# 设置错误处理陷阱
trap 'handle_error ${LINENO} $?' ERR

# ====== 执行函数 ======
# 安全执行命令，出错时记录并退出
safe_exec() {
    log_debug "执行: $*"
    if ! "$@" >> ${LOG_FILE_ABS} 2>&1; then
        log_error "命令执行失败: $*"
        return 1
    fi
    return 0
}

# ====== 主要功能函数 ======
# 修改系统默认配置
modify_system_defaults() {
    log_info "开始修改系统默认配置..."
    
    # 修改默认IP
    if [ -f "package/base-files/files/bin/config_generate" ]; then
        log_progress "修改默认IP为 192.168.111.1"
        safe_exec sed -i 's/192.168.1.1/192.168.111.1/g' package/base-files/files/bin/config_generate
    else
        log_warn "package/base-files/files/bin/config_generate 不存在，跳过修改默认IP"
    fi
    
    # 修改主机名
    if [ -f "package/base-files/files/bin/config_generate" ]; then
        log_progress "修改主机名为 WRT"
        safe_exec sed -i "s/hostname='.*'/hostname='WRT'/g" package/base-files/files/bin/config_generate
    else
        log_warn "package/base-files/files/bin/config_generate 不存在，跳过修改主机名"
    fi
    
    log_info "系统默认配置修改完成"
}

# 移除要替换的包
remove_packages() {
    log_info "开始移除要替换的包..."
    
    local packages=(
        "feeds/luci/applications/luci-app-appfilter"
        "feeds/luci/applications/luci-app-frpc"
        "feeds/luci/applications/luci-app-frps"
        "feeds/packages/net/open-app-filter"
        "feeds/packages/net/adguardhome"
        "feeds/packages/net/ariang"
        "feeds/packages/net/frp"
        "feeds/packages/lang/golang"
    )
    
    for pkg in "${packages[@]}"; do
        if [ -d "$pkg" ]; then
            log_progress "移除: $pkg"
            safe_exec rm -rf "$pkg"
        else
            log_debug "包不存在，跳过: $pkg"
        fi
    done
    
    log_info "包移除完成"
}

# Git稀疏克隆，只克隆指定目录到本地
git_sparse_clone() {
    local branch="$1" 
    local repourl="$2"
    shift 2
    
    log_progress "稀疏克隆: $repourl 分支: $branch 目录: $*"
    
    # 创建临时目录
    local temp_dir=$(mktemp -d)
    log_debug "创建临时目录: $temp_dir"
    
    # 进入临时目录
    cd "$temp_dir"
    
    # 克隆仓库
    log_debug "克隆仓库: $repourl 分支: $branch"
    if ! git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl; then
        log_error "克隆仓库失败: $repourl 分支: $branch"
        cd "$SCRIPT_DIR"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 获取仓库名称
    local repodir=$(echo $repourl | awk -F '/' '{print $(NF)}' | sed 's/.git$//')
    log_debug "仓库名称: $repodir"
    
    # 进入仓库目录
    cd $repodir || {
        log_error "无法进入目录: $repodir"
        cd "$SCRIPT_DIR"
        rm -rf "$temp_dir"
        return 1
    }
    
    # 设置稀疏检出
    log_debug "设置稀疏检出: $*"
    if ! git sparse-checkout set "$@"; then
        log_error "设置稀疏检出失败: $*"
        cd "$SCRIPT_DIR"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 返回上一级目录
    cd ..
    
    # 移动文件
    log_debug "移动文件: $repodir/$@ -> $SCRIPT_DIR/package/"
    if [ ! -d "$SCRIPT_DIR/package" ]; then
        mkdir -p "$SCRIPT_DIR/package"
    fi
    
    if ! mv -f "$repodir/$@" "$SCRIPT_DIR/package/"; then
        log_error "移动文件失败: $repodir/$@ -> $SCRIPT_DIR/package/"
        cd "$SCRIPT_DIR"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 返回脚本目录
    cd "$SCRIPT_DIR"
    
    # 清理临时目录
    log_debug "清理临时目录: $temp_dir"
    rm -rf "$temp_dir"
    
    log_progress "稀疏克隆完成: $repourl"
    return 0
}

# 克隆第三方软件包
clone_packages() {
    log_info "开始克隆第三方软件包..."
    
    # 基础软件包
    log_progress "克隆基础软件包..."
    
    # 克隆golang包
    if [ ! -d "feeds/packages/lang/golang" ]; then
        log_debug "克隆golang包"
        safe_exec git clone --depth=1 https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang
    else
        log_debug "golang包已存在，跳过"
    fi
    
    # 克隆openlist包
    if [ ! -d "package/openlist" ]; then
        log_debug "克隆openlist包"
        safe_exec git clone --depth=1 https://github.com/sbwml/luci-app-openlist2 package/openlist
    else
        log_debug "openlist包已存在，跳过"
    fi
    
    # 稀疏克隆包
    log_progress "稀疏克隆软件包..."
    
    # 克隆ariang包
    if [ ! -d "package/net/ariang" ]; then
        log_debug "克隆ariang包"
        if ! git_sparse_clone ariang https://github.com/laipeng668/packages net/ariang; then
            log_error "克隆ariang包失败，尝试完整克隆"
            safe_exec git clone --depth=1 https://github.com/laipeng668/packages -b ariang package/ariang-temp
            if [ -d "package/ariang-temp/net/ariang" ]; then
                mkdir -p package/net
                mv package/ariang-temp/net/ariang package/net/
                rm -rf package/ariang-temp
            else
                log_error "无法找到ariang包目录"
            fi
        fi
    else
        log_debug "ariang包已存在，跳过"
    fi
    
    # 克隆frp包
    if [ ! -d "package/net/frp" ]; then
        log_debug "克隆frp包"
        if ! git_sparse_clone frp https://github.com/laipeng668/packages net/frp; then
            log_error "克隆frp包失败，尝试完整克隆"
            safe_exec git clone --depth=1 https://github.com/laipeng668/packages -b frp package/frp-temp
            if [ -d "package/frp-temp/net/frp" ]; then
                mkdir -p package/net
                mv package/frp-temp/net/frp package/net/
                rm -rf package/frp-temp
            else
                log_error "无法找到frp包目录"
            fi
        fi
        if [ -d "package/net/frp" ]; then
            log_debug "移动frp包到feeds目录"
            safe_exec mv -f package/net/frp feeds/packages/net/frp
        fi
    else
        log_debug "frp包已存在，跳过"
    fi
    
    # 克隆luci-app-frpc和luci-app-frps包
    if [ ! -d "package/applications/luci-app-frpc" ]; then
        log_debug "克隆luci-app-frpc和luci-app-frps包"
        if ! git_sparse_clone frp https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps; then
            log_error "克隆luci-app-frpc和luci-app-frps包失败，尝试完整克隆"
            safe_exec git clone --depth=1 https://github.com/laipeng668/luci -b frp package/luci-temp
            if [ -d "package/luci-temp/applications/luci-app-frpc" ]; then
                mkdir -p package/applications
                mv package/luci-temp/applications/luci-app-frpc package/applications/
            fi
            if [ -d "package/luci-temp/applications/luci-app-frps" ]; then
                mkdir -p package/applications
                mv package/luci-temp/applications/luci-app-frps package/applications/
            fi
            rm -rf package/luci-temp
        fi
        
        if [ -d "package/applications/luci-app-frpc" ]; then
            log_debug "移动luci-app-frpc包到feeds目录"
            safe_exec mv -f package/applications/luci-app-frpc feeds/luci/applications/luci-app-frpc
        fi
        
        if [ -d "package/applications/luci-app-frps" ]; then
            log_debug "移动luci-app-frps包到feeds目录"
            safe_exec mv -f package/applications/luci-app-frps feeds/luci/applications/luci-app-frps
        fi
    else
        log_debug "luci-app-frpc和luci-app-frps包已存在，跳过"
    fi
    
    # 克隆luci-app-wolplus包
    if [ ! -d "package/luci-app-wolplus" ]; then
        log_debug "克隆luci-app-wolplus包"
        if ! git_sparse_clone main https://github.com/VIKINGYFY/packages luci-app-wolplus; then
            log_error "克隆luci-app-wolplus包失败，尝试完整克隆"
            safe_exec git clone --depth=1 https://github.com/VIKINGYFY/packages -b main package/wolplus-temp
            if [ -d "package/wolplus-temp/luci-app-wolplus" ]; then
                mv package/wolplus-temp/luci-app-wolplus package/
                rm -rf package/wolplus-temp
            else
                log_error "无法找到luci-app-wolplus包目录"
            fi
        fi
    else
        log_debug "luci-app-wolplus包已存在，跳过"
    fi
    
    # 完整克隆包
    log_progress "克隆完整软件包..."
    
    # 克隆openwrt-gecoosac包
    if [ ! -d "package/openwrt-gecoosac" ]; then
        log_debug "克隆openwrt-gecoosac包"
        safe_exec git clone --depth=1 https://github.com/lwb1978/openwrt-gecoosac package/openwrt-gecoosac
    else
        log_debug "openwrt-gecoosac包已存在，跳过"
    fi
    
    # 克隆luci-app-athena-led包
    if [ ! -d "package/luci-app-athena-led" ]; then
        log_debug "克隆luci-app-athena-led包"
        safe_exec git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
        if [ -f "package/luci-app-athena-led/root/etc/init.d/athena_led" ]; then
            safe_exec chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led
        fi
        if [ -f "package/luci-app-athena-led/root/usr/sbin/athena-led" ]; then
            safe_exec chmod +x package/luci-app-athena-led/root/usr/sbin/athena-led
        fi
    else
        log_debug "luci-app-athena-led包已存在，跳过"
    fi
    
    log_info "第三方软件包克隆完成"
}

# 克隆Mary定制包
clone_mary_packages() {
    log_info "开始克隆Mary定制包..."
    
    local packages=(
        "https://github.com/sirpdboy/luci-app-netspeedtest package/netspeedtest"
        "https://github.com/sirpdboy/luci-app-partexp package/luci-app-partexp"
        "https://github.com/sirpdboy/luci-app-taskplan package/luci-app-taskplan"
        "https://github.com/tailscale/tailscale package/tailscale"
        "https://github.com/gdy666/luci-app-lucky package/luci-app-lucky"
        "https://github.com/destan19/OpenAppFilter.git package/OpenAppFilter"
        "https://github.com/nikkinikki-org/OpenWrt-momo package/luci-app-momo"
        "https://github.com/nikkinikki-org/OpenWrt-nikki package/nikki"
        "https://github.com/vernesong/OpenClash package/OpenClash"
    )
    
    for pkg in "${packages[@]}"; do
        local url=$(echo $pkg | cut -d' ' -f1)
        local dir=$(echo $pkg | cut -d' ' -f2)
        
        if [ ! -d "$dir" ]; then
            log_progress "克隆: $url -> $dir"
            safe_exec git clone --depth=1 $url $dir
        else
            log_debug "包已存在，跳过: $dir"
        fi
    done
    
    log_info "Mary定制包克隆完成"
}

# 添加kenzok8软件源
add_kenzok8_repo() {
    log_info "添加kenzok8软件源..."
    
    if [ ! -d "small8" ]; then
        safe_exec git clone --depth=1 https://github.com/kenzok8/small-package small8
    else
        log_debug "kenzok8软件源已存在，跳过"
    fi
    
    log_info "kenzok8软件源添加完成"
}

# 更新feeds
update_feeds() {
    log_info "开始更新feeds..."
    
    log_progress "更新feeds..."
    safe_exec ./scripts/feeds update -a
    
    log_progress "安装feeds..."
    safe_exec ./scripts/feeds install -a
    
    log_info "feeds更新完成"
}

# ====== 主函数 ======
main() {
    log_info "====== 开始执行自定义脚本 ======"
    
    # 修改系统默认配置
    modify_system_defaults
    
    # 移除要替换的包
    remove_packages
    
    # 克隆第三方软件包
    clone_packages
    
    # 克隆Mary定制包
    clone_mary_packages
    
    # 添加kenzok8软件源
    add_kenzok8_repo
    
    # 更新feeds
    update_feeds
    
    log_info "====== 自定义脚本执行完成 ======"
}

# 执行主函数
main
