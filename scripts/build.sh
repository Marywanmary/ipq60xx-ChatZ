#!/bin/bash
# OpenWrt编译及产出物管理脚本
# 功能：执行编译、收集产出物、重命名文件、打包分类
# 参数：$1=分支缩写 $2=配置类型 $3=芯片架构

set -euo pipefail  # 严格错误处理

# 参数校验
if [ $# -ne 3 ]; then
    echo "错误：参数不足！用法: $0 <分支缩写> <配置类型> <芯片架构>"
    exit 1
fi

REPO_SHORT=$1
CONFIG_TYPE=$2
CHIP_ARCH=$3
WORKSPACE=$(pwd)
BUILD_DIR="$WORKSPACE/openwrt"
ARTIFACTS_DIR="$WORKSPACE/artifacts"

# 创建目录结构
mkdir -p "$ARTIFACTS_DIR"/{config,log,app}

echo "=== 开始编译：$REPO_SHORT-$CONFIG_TYPE-$CHIP_ARCH ==="

# 1. 合并配置文件
echo "步骤1：合并配置文件..."
cat "$WORKSPACE/configs/${CHIP_ARCH}_base.config" \
    "$WORKSPACE/configs/${REPO_SHORT}_base.config" \
    "$WORKSPACE/configs/${CONFIG_TYPE}.config" > "$BUILD_DIR/.config"

# 2. 提取设备名称
echo "步骤2：提取设备名称..."
DEVICE_NAME=$(grep -oP 'CONFIG_TARGET_DEVICE_.*_DEVICE_\K.*(?==y)' "$BUILD_DIR/.config" | head -1)
if [ -z "$DEVICE_NAME" ]; then
    echo "错误：无法从配置中提取设备名称！"
    exit 1
fi
echo "检测到设备名称: $DEVICE_NAME"

# 3. 准备编译环境
echo "步骤3：准备编译环境..."
cd "$BUILD_DIR"
bash "$WORKSPACE/scripts/scripts.sh"  # 执行预置脚本
./scripts/feeds update -a
./scripts/feeds install -a
make defconfig

# 4. 编译固件
echo "步骤4：开始编译..."
export CCACHE_DIR="$WORKSPACE/.ccache"
export CCACHE_COMPRESS=1
export CCACHE_MAXSIZE=5G

start_time=$(date +%s)
make -j$(nproc) 2>&1 | tee "$ARTIFACTS_DIR/log/build.log"
end_time=$(date +%s)

# 检查编译状态
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "::error::编译失败！保存错误日志..."
    tail -n 1000 "$ARTIFACTS_DIR/log/build.log" > "$ARTIFACTS_DIR/log/error.log"
    exit 1
fi

echo "编译耗时: $((end_time - start_time)) 秒"

# 5. 收集产出物
echo "步骤5：收集产出物..."

# 5.1 固件文件处理
for bin in bin/targets/*/*/*.bin; do
    if [[ $bin =~ .*$CHIP_ARCH.*-(factory|sysupgrade)\.bin$ ]]; then
        type=$(basename "$bin" | sed -n 's/.*-\(factory\|sysupgrade\)\.bin/\1/p')
        new_name="${REPO_SHORT}-${CHIP_ARCH}-${DEVICE_NAME}-${type}-${CONFIG_TYPE}.bin"
        cp "$bin" "$ARTIFACTS_DIR/$new_name"
        echo "固件重命名: $(basename $bin) -> $new_name"
    fi
done

# 5.2 配置文件处理
cp "$BUILD_DIR/.config" "$ARTIFACTS_DIR/config/${REPO_SHORT}-${CHIP_ARCH}-${DEVICE_NAME}-${CONFIG_TYPE}.config"
[ -f "$BUILD_DIR/.config.buildinfo" ] && cp "$BUILD_DIR/.config.buildinfo" "$ARTIFACTS_DIR/config/${REPO_SHORT}-${CHIP_ARCH}-${DEVICE_NAME}-${CONFIG_TYPE}.config.buildinfo"
[ -f "$BUILD_DIR/.manifest" ] && cp "$BUILD_DIR/.manifest" "$ARTIFACTS_DIR/config/${REPO_SHORT}-${CHIP_ARCH}-${DEVICE_NAME}-${CONFIG_TYPE}.manifest"

# 5.3 软件包收集
mkdir -p "$ARTIFACTS_DIR/app"
find "$BUILD_DIR/bin/packages" -name "*.ipk" -exec cp {} "$ARTIFACTS_DIR/app/" \;

# 6. 生成摘要
echo "步骤6：生成编译摘要..."
cat > "$ARTIFACTS_DIR/summary.txt" << EOF
编译摘要
========================================
分支: $REPO_SHORT
配置: $CONFIG_TYPE
芯片: $CHIP_ARCH
设备: $DEVICE_NAME
编译时间: $(date +'%Y-%m-%d %H:%M:%S')
耗时: $((end_time - start_time)) 秒
内核版本: $(grep -oP 'CONFIG_LINUX_KERNEL=\K.*' "$BUILD_DIR/.config" | tr -d '"')
========================================
EOF

echo "=== 编译完成：$REPO_SHORT-$CONFIG_TYPE-$CHIP_ARCH ==="
exit 0
