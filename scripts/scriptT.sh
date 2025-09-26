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
    if ! "$@" >> ${LOG_FILE} 2>&1; then
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
    safe_exec sed -i 's/192.168.1.1/192.168.111.1/g' package/base-files/files/bin/config_generate
    
    # 修改主机名
    safe_exec sed -i "s/hostname='.*'/hostname='WRT'/g" package/base-files/files/bin/config_generate
    
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
            log_debug "移除: $pkg"
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
    
    log_debug "稀疏克隆: $repourl 分支: $branch 目录: $*"
    
    if ! git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl; then
        log_error "克隆仓库失败: $repourl"
        return 1
    fi
    
    local repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
    
    cd $repodir || {
        log_error "无法进入目录: $repodir"
        return 1
    }
    
    if ! git sparse-checkout set "$@"; then
        log_error "设置稀疏检出失败: $*"
        cd ..
        rm -rf $repodir
        return 1
    fi
    
    mv -f "$@" ../package || {
        log_error "移动文件失败: $* -> ../package"
        cd ..
        rm -rf $repodir
        return 1
    }
    
    cd .. && rm -rf $repodir
    return 0
}

# 克隆第三方软件包
clone_packages() {
    log_info "开始克隆第三方软件包..."
    
    # 基础软件包
    log_debug "克隆基础软件包..."
    safe_exec git clone --depth=1 https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang
    safe_exec git clone --depth=1 https://github.com/sbwml/luci-app-openlist2 package/openlist
    
    # 稀疏克隆包
    log_debug "稀疏克隆软件包..."
    git_sparse_clone ariang https://github.com/laipeng668/packages net/ariang
    git_sparse_clone frp https://github.com/laipeng668/packages net/frp
    safe_exec mv -f package/frp feeds/packages/net/frp
    git_sparse_clone frp https://github.com/laipeng668/luci applications/luci-app-frpc applications/luci-app-frps
    safe_exec mv -f package/luci-app-frpc feeds/luci/applications/luci-app-frpc
    safe_exec mv -f package/luci-app-frps feeds/luci/applications/luci-app-frps
    git_sparse_clone main https://github.com/VIKINGYFY/packages luci-app-wolplus
    
    # 完整克隆包
    log_debug "克隆完整软件包..."
    safe_exec git clone --depth=1 https://github.com/lwb1978/openwrt-gecoosac package/openwrt-gecoosac
    safe_exec git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led package/luci-app-athena-led
    safe_exec chmod +x package/luci-app-athena-led/root/etc/init.d/athena_led package/luci-app-athena-led/root/usr/sbin/athena-led
    
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
        log_debug "克隆: $pkg"
        safe_exec git clone --depth=1 $pkg
    done
    
    log_info "Mary定制包克隆完成"
}

# 添加kenzok8软件源
add_kenzok8_repo() {
    log_info "添加kenzok8软件源..."
    safe_exec git clone --depth=1 https://github.com/kenzok8/small-package small8
    log_info "kenzok8软件源添加完成"
}

# 更新feeds
update_feeds() {
    log_info "开始更新feeds..."
    safe_exec ./scripts/feeds update -a
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
