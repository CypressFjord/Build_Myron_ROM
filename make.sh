#!/bin/bash

###构建前准备
URL="$1"              #系统包下载地址
GITHUB_ENV="$2"       #输出环境变量
GITHUB_WORKSPACE="$3" #工作目录

Red='\033[1;31m'      #粗体红色
Yellow='\033[1;33m'   #粗体黄色
Blue='\033[1;34m'     #粗体蓝色
Green='\033[1;32m'    #粗体绿色
NC='\033[0m'          #重置颜色

device=myron          # 设备代号

#系统包系统OS版本号
vendor_os_version=$(echo "$URL" | awk -F'/' '{print $(NF-1)}')
#系统包系统zip名称
vendor_zip_name=$(echo "$URL" | awk -F'/' '{print $NF}' | awk -F'?' '{print $1}')
#Android版本号
android_version=$(echo "$URL" | grep -oE '-user-[0-9]+' | grep -oE '[0-9]+')
#构建时间
build_time=$(date) && build_utc=$(date -d "$build_time" +%s)
#工具位置
a7z="$GITHUB_WORKSPACE"/tools/7zzs
e2fsdroid="$GITHUB_WORKSPACE"/tools/e2fsdroid
erofs_extract="$GITHUB_WORKSPACE"/tools/extract.erofs
lpmake="$GITHUB_WORKSPACE"/tools/lpmake
magiskboot="$GITHUB_WORKSPACE"/tools/magiskboot
mke2fs="$GITHUB_WORKSPACE"/tools/mke2fs
erofs_mkfs="$GITHUB_WORKSPACE"/tools/mkfs.erofs
payload_extract="$GITHUB_WORKSPACE"/tools/payload_extract
ksud="$GITHUB_WORKSPACE"/tools/ksu_lkm_patch/ksud
ksuinit="$GITHUB_WORKSPACE/tools/ksu_lkm_patch/ksuinit"
ksu_ko="$GITHUB_WORKSPACE/tools/ksu_lkm_patch/android16-6.12_kernelsu.ko"
#创建文件夹
mkdir -p "$GITHUB_WORKSPACE"/tools
mkdir -p "$GITHUB_WORKSPACE"/firmware
mkdir -p "$GITHUB_WORKSPACE"/files
#为文件夹赋予755权限
chmod -R 755 "$GITHUB_WORKSPACE"/tools
chmod -R 755 "$GITHUB_WORKSPACE"/firmware
chmod -R 755 "$GITHUB_WORKSPACE"/files
#声明时间栈数组,支持多层嵌套计时
TIMER_STACK_S=()
TIMER_STACK_NS=()
#开始时间设置)
Start_Time() {
  TIMER_STACK_S+=("$(date +%s)")
  TIMER_STACK_NS+=("$(date +%N)")
}
#结束时间设置
End_Time() {
  local stack_len=${#TIMER_STACK_S[@]}
  if (( stack_len == 0 )); then
    echo -e "${Red}- 警告: 找不到匹配的 Start_Time${NC}"
    return
  fi
#获取栈顶时间
  local last_idx=$((stack_len - 1))
  local Start_s=${TIMER_STACK_S[$last_idx]}
  local Start_ns=${TIMER_STACK_NS[$last_idx]}
#移除栈顶元素，并且重置数组索引
  unset 'TIMER_STACK_S[$last_idx]'
  unset 'TIMER_STACK_NS[$last_idx]'
  TIMER_STACK_S=("${TIMER_STACK_S[@]}")
  TIMER_STACK_NS=("${TIMER_STACK_NS[@]}")
  local End_s End_ns time_s time_ns
  End_s=$(date +%s)
  End_ns=$(date +%N)
  time_s=$((10#$End_s - 10#$Start_s))
  time_ns=$((10#$End_ns - 10#$Start_ns))
  if ((time_ns < 0)); then
    ((time_s--))
    ((time_ns += 1000000000))
  fi 
  local ns ms sec min hour
  ns=$((time_ns % 1000000))
  ms=$((time_ns / 1000000))
  sec=$((time_s % 60))
  min=$((time_s / 60 % 60))
  hour=$((time_s / 3600))
  if ((hour > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$hour小时$min分$sec秒$ms毫秒${NC}"
  elif ((min > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$min分$sec秒$ms毫秒${NC}"
  elif ((sec > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$sec秒$ms毫秒${NC}"
  elif ((ms > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$ms毫秒${NC}"
  else
    echo -e "${Green}- 本次$1用时: ${Blue}$ns纳秒${NC}"
  fi
}
###构建前准备结束

######构建$device官改ROM
echo -e "${Red}- 开始构建$device官改ROM${NC}"
Start_Time

###系统包下载
echo -e "${Red}- 开始系统包下载${NC}"
Start_Time
if [ -f "$GITHUB_WORKSPACE/${vendor_zip_name}" ]; then
  echo -e "${Green}- 检测到本地已存在系统包: ${vendor_zip_name}，跳过网络下载步骤${NC}"
else
  echo -e "${Yellow}- 本地不存在系统包，开始网络下载系统包${NC}"
  aria2c -x16 -s16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" "${URL}" &
  wait
fi
End_Time 系统包下载
###系统包下载结束

###解压并分解系统包的文件
echo -e "${Red}- 开始解压并分解系统包的文件${NC}"
Start_Time
mkdir -p "$GITHUB_WORKSPACE"/vendor_zip
mkdir -p "$GITHUB_WORKSPACE"/images/config
mkdir -p "$GITHUB_WORKSPACE"/super
mkdir -p "$GITHUB_WORKSPACE"/Extra_dir
mkdir -p "$GITHUB_WORKSPACE"/zip
#解压系统包ZIP
echo -e "${Red}- 开始解压系统包ZIP${NC}"
Start_Time
$a7z x "$GITHUB_WORKSPACE"/${vendor_zip_name} -o"$GITHUB_WORKSPACE"/vendor_zip payload.bin >/dev/null
rm -rf "$GITHUB_WORKSPACE"/${vendor_zip_name}
End_Time 解压系统包ZIP
#分解系统包Payload
echo -e "${Red}- 开始分解系统包Payload${NC}"
Start_Time
$payload_extract -s -o "$GITHUB_WORKSPACE"/firmware/images -i "$GITHUB_WORKSPACE"/vendor_zip/payload.bin -X abl,aop,aop_config,bluetooth,boot,countrycode,cpucp,cpucp_dtb,dcp,devcfg,dsp,dtbo,featenabler,hyp,hyp_ac_config,idmanager,imagefv,init_boot,keymaster,modem,modemfirmware,multiimgqti,pdp,pdp_cdb,pvmfw,qtvm_dtbo,qupfw,secretkeeper,shrm,soccp,soccp_dcd,soccp_debug,spuservice,tme_config,tme_fw,tme_seq_patch,tz,tz_ac_config,tz_qti_config,uefi,uefisecapp,vbmeta,vbmeta_system,vendor_boot,vm-bootsys,xbl,xbl_ac_config,xbl_config,xbl_ramdump -T0
$payload_extract -s -o "$GITHUB_WORKSPACE"/Extra_dir -i "$GITHUB_WORKSPACE"/vendor_zip/payload.bin -X mi_ext,odm,product,system,system_dlkm,system_ext,vendor,vendor_dlkm -T0
sudo rm -rf "$GITHUB_WORKSPACE"/vendor_zip/payload.bin
End_Time 分解系统包Payload
#分解系统包的Images
echo -e "${Red}- 开始分解系统包的Images${NC}"
Start_Time
for i in mi_ext odm product system system_dlkm system_ext vendor vendor_dlkm; do
echo -e "${Red}- 正在分解$i.img${NC}"
Start_Time
  cd "$GITHUB_WORKSPACE"/images
  sudo $erofs_extract -i "$GITHUB_WORKSPACE"/Extra_dir/$i.img -x -s
  rm -rf "$GITHUB_WORKSPACE"/Extra_dir/$i.img
End_Time 分解$i.img
done
End_Time 分解系统包的Images
End_Time 解压并分解系统包的文件
###解压并分解系统包的文件结束

###写入系统包的变量
echo -e "${Red}- 开始写入系统包的变量${NC}"
Start_Time
#ROM构建日期
echo -e "${Red}- ROM构建日期: $build_time${NC}"
echo "build_time=$build_time" >>$GITHUB_ENV
#系统包SOTA版本
mi_ext_build_prop=$GITHUB_WORKSPACE/images/mi_ext/etc/build.prop
incremental_version=$(grep "ro.mi.xms.version.incremental=" "$mi_ext_build_prop" | awk -F "=" '{print $2}')
echo -e "${Red}- 系统包SOTA版本: $incremental_version${NC}"
echo "incremental_version=$incremental_version" >>$GITHUB_ENV
#系统包系统版本
echo -e "${Red}- 系统包系统版本: $vendor_os_version${NC}"
echo "vendor_os_version=$vendor_os_version" >>$GITHUB_ENV
#系统包System安全补丁日期
system_build_prop=$(find "$GITHUB_WORKSPACE"/images/system/system/ -maxdepth 1 -type f -name "build.prop" | head -n 1)
port_security_patch=$(grep "ro.build.version.security_patch=" "$system_build_prop" | awk -F "=" '{print $2}')
echo -e "${Red}- 系统包System安全补丁日期: $port_security_patch${NC}"
echo "port_security_patch=$port_security_patch" >>$GITHUB_ENV
#系统包Vendor安全补丁日期
vendor_build_prop=$GITHUB_WORKSPACE/images/vendor/build.prop
vendor_security_patch=$(grep "ro.vendor.build.security_patch=" "$vendor_build_prop" | awk -F "=" '{print $2}')
echo -e "${Red}- 系统包Vendor安全补丁日期: $vendor_security_patch${NC}"
echo "vendor_security_patch=$vendor_security_patch" >>$GITHUB_ENV
#系统包System基线版本
system_build_prop=$(find "$GITHUB_WORKSPACE"/images/system/system/ -maxdepth 1 -type f -name "build.prop" | head -n 1)
system_base_line=$(grep "ro.system.build.id=" "$system_build_prop" | awk -F "=" '{print $2}')
echo -e "${Red}- 系统包System基线版本: $system_base_line${NC}"
echo "system_base_line=$system_base_line" >>$GITHUB_ENV
#系统包Vendor基线版本
vendor_build_prop=$GITHUB_WORKSPACE/images/vendor/build.prop
vendor_base_line=$(grep "ro.vendor.build.id=" "$vendor_build_prop" | awk -F "=" '{print $2}')
echo -e "${Red}- 系统包Vendor基线版本: $vendor_base_line${NC}"
echo "vendor_base_line=$vendor_base_line" >>$GITHUB_ENV
End_Time 写入系统包的变量
###写入系统包的变量结束

###功能修复
echo -e "${Red}- 开始功能修复${NC}"
Start_Time
#复制通用文件
echo -e "${Red}- 开始复制通用文件${NC}"
Start_Time
mkdir -p "$GITHUB_WORKSPACE"/images
\cp -rf "$GITHUB_WORKSPACE"/files/common/* "$GITHUB_WORKSPACE"/images/
cat "$GITHUB_WORKSPACE"/files/mi_ext_build.prop >> "$GITHUB_WORKSPACE"/images/mi_ext/etc/build.prop
cat "$GITHUB_WORKSPACE"/files/system_ext_build.prop >> "$GITHUB_WORKSPACE"/images/system_ext/etc/build.prop
echo -e "${Green}- 已复制通用文件${NC}"
End_Time 复制通用文件
#删除低功耗音频白名单
echo -e "${Red}- 开始删除低功耗音频白名单${NC}"
Start_Time
audio_lowpower_xml="$GITHUB_WORKSPACE"/images/odm/etc/audio/audio_lowpower_app_list.xml
if [ -f "$audio_lowpower_xml" ]; then
    sed -i '/<package name="[^"]*"\/>/d' "$audio_lowpower_xml"
    echo -e "${Green}- 已删除低功耗音频白名单${NC}"
else
    echo -e "${Yellow}- 警告: 未找到audio_lowpower_app_list.xml，跳过此步骤${NC}"
fi
End_Time 删除低功耗音频白名单
#解锁谷歌国区限制和谷歌快速分享
echo -e "${Red}- 开始解锁谷歌国区限制和谷歌快速分享${NC}"
Start_Time
cn_google_xml="$GITHUB_WORKSPACE"/images/product/etc/permissions/cn.google.services.xml
if [ -f "$cn_google_xml" ]; then
    sed -i '/<feature name="cn.google.services" \/>/d; /<feature name="com.google.android.feature.services_updater" \/>/d' "$cn_google_xml"
    echo -e "${Green}- 已解锁谷歌国区限制和谷歌快速分享${NC}"
else
    echo -e "${Yellow}- 警告: 未找到cn.google.services.xml，跳过此步骤${NC}"
fi
End_Time 解锁谷歌国区限制和谷歌快速分享
##修改myron.xml
echo -e "${Red}- 开始修改myron.xml${NC}"
Start_Time
#添加全天候息屏AOD功能
echo -e "${Red}- 开始添加全天候息屏AOD功能${NC}"
Start_Time
myron_xml="$GITHUB_WORKSPACE"/images/product/etc/device_features/myron.xml
if [ -f "$myron_xml" ]; then
    if grep -qF '<bool name="support_aod_fullscreen">false</bool>' "$myron_xml"; then
        sed -i 's|<bool name="support_aod_fullscreen">false</bool>|<bool name="support_aod_fullscreen">true</bool>|' "$myron_xml"
        echo -e "${Green}- 已添加全天候息屏AOD功能${NC}"
    elif grep -qF '<bool name="support_aod_fullscreen">true</bool>' "$myron_xml"; then
        echo -e "${Yellow}- 跳过: 全天候息屏AOD功能存在${NC}"
    else
        echo -e "${Yellow}- 警告: 未找到support_aod_fullscreen${NC}"
    fi
else
    echo -e "${Yellow}- 警告: 未找到myron.xml，跳过此步骤${NC}"
fi
End_Time 添加全天候息屏AOD功能
#补全刷新率档位和添加全局高刷
echo -e "${Red}- 开始补全刷新率档位和添加全局高刷${NC}"
Start_Time
myron_xml="$GITHUB_WORKSPACE"/images/product/etc/device_features/myron.xml
if [ -f "$myron_xml" ]; then
    if grep -qF '<integer name="support_max_fps">120</integer>' "$myron_xml"; then
        sed -i '/<integer name="support_max_fps">120<\/integer>/d' "$myron_xml"
        echo -e "${Green}- 已删除support_max_fps${NC}"
    else
        echo -e "${Yellow}- 跳过: support_max_fps不存在或已删除${NC}"
    fi
    if sed -n '/<integer-array name="fpsList">/,/<\/integer-array>/p' "$myron_xml" | grep -qF '<item>90</item>'; then
        echo -e "${Yellow}- 跳过: 存在刷新档位和全局高刷${NC}"
    else
        sed -i '/<integer-array name="fpsList">/,/<\/integer-array>/{
            /<item>120<\/item>/a\        <item>90</item>
            /<item>60<\/item>/a\        <item>6</item>
        }' "$myron_xml"
        echo -e "${Green}- 已补全刷新档位和添加全局高刷${NC}"
    fi
else
    echo -e "${Yellow}- 警告: 未找到myron.xml，跳过此步骤${NC}"
fi
End_Time 补全刷新率档位和添加全局高刷
#添加REDMI K90 Pro Max Patch
echo -e "${Red}- 开始添加REDMI K90 Pro Max Patch${NC}"
Start_Time
myron_xml="$GITHUB_WORKSPACE"/images/product/etc/device_features/myron.xml
if [ -f "$myron_xml" ]; then
    if grep -qF 'support_video_idle_dim' "$myron_xml"; then
        echo -e "${Yellow}- 跳过: REDMI K90 Pro Max Patch已存在${NC}"
    else
        sed -i "/<\/features>/{
            i\\    <!-- REDMI K90 Pro Max Patch -->\\
    <!-- Don't let the volume go down when playing videos -->\\
    <bool name=\"support_video_idle_dim\">true</bool>\\
    <!-- REDMI K90 Pro Max Patch END -->
            a\\<!-- END Patch-->
        }" "$myron_xml"
        echo -e "${Green}- 已添加REDMI K90 Pro Max Patch${NC}"
    fi
else
    echo -e "${Yellow}- 警告: 未找到myron.xml，跳过此步骤${NC}"
fi
End_Time 添加REDMIK90ProMaxPatch
End_Time 修改myron.xml
#检测并添加WRITE_MEDIA_STORAGE权限
echo -e "${Red}- 开始检测并添加WRITE_MEDIA_STORAGE权限${NC}"
Start_Time
privapp_xml="$GITHUB_WORKSPACE"/images/product/etc/permissions/privapp-permissions-product.xml
if [ -f "$privapp_xml" ]; then
    if awk '
        /<privapp-permissions package="com.miui.securitycenter">/ { inblock=1 }
        inblock && /<permission name="android.permission.WRITE_MEDIA_STORAGE" \/>/ { found=1; exit }
        inblock && /<\/privapp-permissions>/ { exit }
        END { exit !found }
    ' "$privapp_xml"; then
        echo -e "${Yellow}- 跳过: WRITE_MEDIA_STORAGE权限存在${NC}"
    else
        awk '
        /<privapp-permissions package="com.miui.securitycenter">/ { inblock=1; found=0 }
        inblock && /<permission name="android.permission.WRITE_MEDIA_STORAGE" \/>/ { found=1 }
        inblock && /<\/privapp-permissions>/ {
            if (!found) {
                print "      <permission name=\"android.permission.WRITE_MEDIA_STORAGE\" />"
            }
            inblock=0
        }
        { print }
        ' "$privapp_xml" > "${privapp_xml}.tmp" && mv "${privapp_xml}.tmp" "$privapp_xml"
        echo -e "${Green}- 已添加WRITE_MEDIA_STORAGE权限${NC}"
    fi
else
    echo -e "${Yellow}- 警告: 未找到privapp-permissions-product.xml，跳过此步骤${NC}"
fi
End_Time 检测并添加WRITE_MEDIA_STORAGE权限
#合并校验替换MiuiCamera相关文件
echo -e "${Red}- 开始合并校验替换MiuiCamera相关文件${NC}"
Start_Time
camera_src_dir="$GITHUB_WORKSPACE"/files/MiuiCamera_parts
camera_dst_dir="$GITHUB_WORKSPACE"/images/product/priv-app/MiuiCamera
camera_dst_apk="$camera_dst_dir/MiuiCamera.apk"
temp_apk="${camera_dst_apk}.tmp"
if [ -d "$camera_src_dir" ] && ls "$camera_src_dir"/MiuiCamera.apk.part* >/dev/null 2>&1; then
    mkdir -p "$camera_dst_dir"
    cat "$camera_src_dir"/MiuiCamera.apk.part* > "$temp_apk"
    if [ -f "${camera_src_dir}/MiuiCamera.apk.sha256" ]; then
        expected=$(awk '{print $1}' "${camera_src_dir}/MiuiCamera.apk.sha256")
        actual=$(sha256sum "$temp_apk" | awk '{print $1}')        
        if [ "$expected" = "$actual" ]; then      
            mv -f "$temp_apk" "$camera_dst_apk"
            echo -e "${Green}- MiuiCamera.apk合并且完整性校验通过，已成功替换${NC}"
            if [ -d "$camera_src_dir/oat" ]; then
                cp -rf "$camera_src_dir/oat" "$camera_dst_dir/"
                echo -e "${Green}- MiuiCamera相关oat文件替换成功${NC}"
            fi
        else
            rm -f "$temp_apk"
            echo -e "${Yellow}- 严重警告: MiuiCamera.apk完整性校验失败(预期:$expected 实际:$actual)${NC}"
            echo -e "${Yellow}- 已拦截错误：保留了原文件${NC}"
        fi
    else
        echo -e "${Yellow}- 提示: 未找到MiuiCamera.apk.sha256校验文件，跳过校验直接替换${NC}"
        mv -f "$temp_apk" "$camera_dst_apk"
        if [ -d "$camera_src_dir/oat" ]; then
            cp -rf "$camera_src_dir/oat" "$camera_dst_dir/"
            echo -e "${Green}- MiuiCamera相关oat文件替换成功${NC}"
        fi
    fi
else
    echo -e "${Yellow}- 提示: 未找到MiuiCamera.apk分卷文件，保留原文件${NC}"
fi
End_Time 合并校验替换MiuiCamera相关文件
##内置水龙优化
echo -e "${Red}- 开始内置水龙优化${NC}"
Start_Time
#处理cpq调速器
echo -e "${Red}- 开始处理cpq调速器${NC}"
Start_Time
RC_FILE="$GITHUB_WORKSPACE/images/vendor/etc/init/hw/init.qti.kernel.rc"
ANCHOR='write /sys/block/sda/queue/scheduler cpq'
if [ -f "$RC_FILE" ] && grep -qF 'iosched/read_expire 4' "$RC_FILE"; then
    echo -e "${Yellow}- 跳过: cpq调速器参数已处理过${NC}"
elif [ -f "$RC_FILE" ] && grep -qF "$ANCHOR" "$RC_FILE"; then
    sed -i "/${ANCHOR//\//\\/}/a\\
    write /sys/block/sda/queue/iosched/prio_aging_expire 200" "$RC_FILE"
    echo -e "${Green}- 成功处理cpq调速器${NC}"
else
    echo -e "${Yellow}- 警告: 未找到cpq锚点或文件不存在${NC}"
fi
End_Time 处理cpq调速器
#关闭F2FS iostat减少读写时锁争用
Start_Time
echo -e "${Red}- 开始关闭F2FS iostat减少读写时锁争用${NC}"
INIT_RC="$GITHUB_WORKSPACE"/images/system/system/etc/init/hw/init.rc
grep -qF "iostat" "$INIT_RC" || echo -e "${Yellow}- 警告: 未找到iostat相关行${NC}"
sed -i '/write \/dev\/sys\/fs\/by-name\/userdata\/iostat_period_ms 1000/d' "$INIT_RC"
sed -i '/write \/dev\/sys\/fs\/by-name\/userdata\/iostat_enable 1/d' "$INIT_RC"
echo -e "${Green}- 已关闭F2FS iostat减少读写时锁争用${NC}"
End_Time 关闭F2FS iostat减少读写时锁争用
#Amktiao的ZRAM压缩算法优化
Start_Time
echo -e "${Red}- 开始Amktiao的ZRAM压缩算法优化${NC}"
zram_rc="$GITHUB_WORKSPACE"/images/system/system/etc/init/hw/init.rc
perfinit="$GITHUB_WORKSPACE"/images/system_ext/etc/perfinit.conf
if [ -f "$zram_rc" ] && ! grep -qF 'Amktiao ZRAM opt Add' "$zram_rc"; then
    sed -i '/# System server manages zram writeback/a\
    # Amktiao ZRAM opt Add\
    write /proc/sys/vm/page-cluster 0\
    # Amktiao ZRAM opt End' "$zram_rc" && echo -e "${Green}- init.rc已成功修改${NC}"
fi
if [ -f "$perfinit" ] && ! grep -q '"comp_algo"' "$perfinit"; then
    sed -i '/"swap_on": 1,/{p; s/.*/        "comp_algo": "lz4",/}' "$perfinit"
    python3 -c "import json; json.load(open('$perfinit'))" 2>/dev/null \
        && echo -e "${Green}- perfinit.conf已成功修改${NC}" \
        || echo -e "${Yellow}- 严重警告: JSON校验失败${NC}"
fi
End_Time Amktiao的ZRAM压缩算法优化
End_Time 内置水龙优化
##处理IMG文件
echo -e "${Red}- 开始处理IMG文件${NC}"
Start_Time
#去除vbmeta.img验证
echo -e "${Red}- 开始去除vbmeta验证${NC}"
Start_Time
vbmeta_img="$GITHUB_WORKSPACE"/firmware/images/vbmeta.img
hex_orig="0000000000000000617662746F6F6C20"
hex_patched="0000000100000000617662746F6F6C20"
if [ -f "$vbmeta_img" ]; then
    echo -e "${Red}- 正在处理: vbmeta.img${NC}"
    if xxd -p "$vbmeta_img" | tr -d '\n' | grep -iq "$hex_patched"; then
        echo -e "${Green}- vbmeta.img验证已被去除，跳过修补${NC}"
    else
        if "$magiskboot" hexpatch "$vbmeta_img" "$hex_orig" "$hex_patched"; then
            if xxd -p "$vbmeta_img" | tr -d '\n' | grep -iq "$hex_patched"; then
                echo -e "${Green}- vbmeta.img验证去除成功，并且已经确认写入${NC}"
            else
                echo -e "${Yellow}- hexpatch返回成功，但二次验证失败，请检查${NC}"
            fi
        else
            echo -e "${Yellow}- vbmeta.img修补失败${NC}"
        fi
    fi
else
    echo -e "${Yellow}- vbmeta.img不存在，跳过${NC}"
fi
End_Time 去除vbmeta验证
#init_boot.img修补KernelSU
echo -e "${Red}- 开始为init_boot.img修补KernelSU${NC}"
Start_Time
ksu_ok=1
export PATH="$GITHUB_WORKSPACE"/tools:$PATH
init_boot_img="$GITHUB_WORKSPACE"/firmware/images/init_boot.img
for f in "$init_boot_img" "$ksud" "$ksuinit" "$ksu_ko" "$magiskboot"; do
  [ -f "$f" ] || { echo -e "${Yellow}- 警告: 未找到修补所需相关文件: $f${NC}"; ksu_ok=0; }
done
if [ "$ksu_ok" -eq 1 ]; then
  chmod +x "$ksud" "$magiskboot"
  cp -f "$init_boot_img" "$init_boot_img.orig"  
  cd "$GITHUB_WORKSPACE" 
  if "$ksud" boot-patch --boot "$init_boot_img" --module "$ksu_ko" --init "$ksuinit"; then
      patched_img=$(find "$GITHUB_WORKSPACE" -maxdepth 1 -type f -name "*kernelsu*.img" | head -n 1)
      if [ -n "$patched_img" ]; then
          mv -f "$patched_img" "$init_boot_img"
      else
          echo -e "${Yellow}- 警告: 未找到修补后的init_boot.img${NC}"
          ksu_ok=0
      fi
  else
      ksu_ok=0
  fi 
  if [ "$ksu_ok" -eq 0 ] && [ -f "$init_boot_img.orig" ]; then
      cp -f "$init_boot_img.orig" "$init_boot_img"
  fi
  rm -f "$init_boot_img.orig"
fi
if [ "$ksu_ok" -eq 1 ]; then
  echo -e "${Green}- init_boot.img修补KernelSU完成${NC}"
else
  echo -e "${Yellow}- init_boot.img修补KernelSU失败，本次构建将使用官方init_boot.img${NC}"
fi
End_Time 为init_boot.img修补KernelSU
End_Time 处理IMG文件
#精简apk
echo -e "${Red}- 开始精简apk${NC}"
Start_Time
rm -rf "$GITHUB_WORKSPACE"/images/product/app/AnalyticsCore
rm -rf "$GITHUB_WORKSPACE"/images/product/app/BSGameCenter
rm -rf "$GITHUB_WORKSPACE"/images/product/app/HybridPlatform
rm -rf "$GITHUB_WORKSPACE"/images/product/app/MiTrustService
rm -rf "$GITHUB_WORKSPACE"/images/product/app/MIUIAccessibility
rm -rf "$GITHUB_WORKSPACE"/images/product/app/MIUIgreenguard
rm -rf "$GITHUB_WORKSPACE"/images/product/app/MIUISecurityInputMethod
rm -rf "$GITHUB_WORKSPACE"/images/product/app/SogouIME
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/BaiduIME
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/Health
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/iFlytekIME
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIGalleryLockscreen
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIpay
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIService
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MiShop
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUIDuokanReader
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUIEmail
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUIGameCenter
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUIHuanji
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUIMusicT
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUINewHome_Removable
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUIVideo
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUIVirtualSim
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUIYoupin
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/OS2VipAccount
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/MIUIXiaoAiSpeechEngine
rm -rf "$GITHUB_WORKSPACE"/images/product/data-app/SmartHome
rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/MiniGameService
rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/MIUIBrowser
rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/MiuiHome
End_Time 精简apk
End_Time 功能修复
###功能修复结束

###生成super.img
#生成$partition.img
echo -e "${Red}- 开始生成分区镜像${NC}"
Start_Time
partitions=("mi_ext" "odm" "product" "system" "system_dlkm" "system_ext" "vendor" "vendor_dlkm")
for partition in "${partitions[@]}"; do
echo -e "${Red}- 正在生成$partition${NC}"
Start_Time
    sudo python3 "$GITHUB_WORKSPACE"/tools/fspatch.py "$GITHUB_WORKSPACE"/images/$partition "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config
    sudo python3 "$GITHUB_WORKSPACE"/tools/contextpatch.py "$GITHUB_WORKSPACE"/images/$partition "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts None
    sudo $erofs_mkfs --quiet -zlz4hc,9 -T 1230768000 --mount-point /$partition --fs-config-file "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config --file-contexts "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts "$GITHUB_WORKSPACE"/super/$partition.img "$GITHUB_WORKSPACE"/images/$partition
    eval "$partition"_size=$(du -sb "$GITHUB_WORKSPACE"/super/$partition.img | awk {'print $1'})
    sudo rm -rf "$GITHUB_WORKSPACE"/images/$partition
End_Time 生成${partition}.img
done
sudo rm -rf "$GITHUB_WORKSPACE"/images/config
End_Time 生成分区镜像
echo -e "${Red}- 开始打包super.img${NC}"
Start_Time
  $lpmake --metadata-size 65536 --super-name super --block-size 4096 \
  --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a \
  --image mi_ext_a="$GITHUB_WORKSPACE"/super/mi_ext.img \
  --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b \
  --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a \
  --image odm_a="$GITHUB_WORKSPACE"/super/odm.img \
  --partition odm_b:readonly:0:qti_dynamic_partitions_b \
  --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a \
  --image product_a="$GITHUB_WORKSPACE"/super/product.img \
  --partition product_b:readonly:0:qti_dynamic_partitions_b \
  --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a \
  --image system_a="$GITHUB_WORKSPACE"/super/system.img \
  --partition system_b:readonly:0:qti_dynamic_partitions_b \
  --partition system_dlkm_a:readonly:"$system_dlkm_size":qti_dynamic_partitions_a \
  --image system_dlkm_a="$GITHUB_WORKSPACE"/super/system_dlkm.img \
  --partition system_dlkm_b:readonly:0:qti_dynamic_partitions_b \
  --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a \
  --image system_ext_a="$GITHUB_WORKSPACE"/super/system_ext.img \
  --partition system_ext_b:readonly:0:qti_dynamic_partitions_b \
  --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a \
  --image vendor_a="$GITHUB_WORKSPACE"/super/vendor.img \
  --partition vendor_b:readonly:0:qti_dynamic_partitions_b \
  --partition vendor_dlkm_a:readonly:"$vendor_dlkm_size":qti_dynamic_partitions_a \
  --image vendor_dlkm_a="$GITHUB_WORKSPACE"/super/vendor_dlkm.img \
  --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b \
  --device super:14495514624 \
  --metadata-slots 3 \
  --group qti_dynamic_partitions_a:14495514624 \
  --group qti_dynamic_partitions_b:14495514624 \
  --virtual-ab -F \
  --output "$GITHUB_WORKSPACE"/super/super.img  
  for partition in "${partitions[@]}"; do
    rm -rf "$GITHUB_WORKSPACE"/super/$partition.img
  done
End_Time 打包super.img
###生成super.img结束

###生成完整刷机包
echo -e "${Red}- 开始生成完整刷机包${NC}"
Start_Time
#压缩super.img.zst
echo -e "${Red}- 开始压缩super.img.zst${NC}"
Start_Time
sudo find "$GITHUB_WORKSPACE"/super/ -exec touch -t 200901010000.00 {} \;
zstd -3 -f "$GITHUB_WORKSPACE"/super/super.img -o "$GITHUB_WORKSPACE"/firmware/images/super.img.zst --rm
End_Time 压缩super.img.zst
#生成ZIP刷机包
echo -e "${Red}- 开始生成ZIP刷机包${NC}"
Start_Time
sudo $a7z a "$GITHUB_WORKSPACE"/zip/Myron-HyperOS-${vendor_os_version}-CypressFjord.zip "$GITHUB_WORKSPACE"/firmware/* >/dev/null
sudo rm -rf "$GITHUB_WORKSPACE"/images
End_Time 生成ZIP刷机包
#定制ROM包名
echo -e "${Red}- 开始定制ROM包名${NC}"
Start_Time
md5=$(md5sum "$GITHUB_WORKSPACE"/zip/Myron-HyperOS-${vendor_os_version}-CypressFjord.zip)
echo "MD5=${md5:0:32}" >>$GITHUB_ENV
zip_md5=${md5:0:10}
rom_name="Myron-HyperOS-${vendor_os_version}-CypressFjord-${zip_md5}.zip"
sudo mv "$GITHUB_WORKSPACE"/zip/Myron-HyperOS-${vendor_os_version}-CypressFjord.zip "$GITHUB_WORKSPACE"/zip/"${rom_name}"
echo "rom_name=$rom_name" >>$GITHUB_ENV
End_Time 定制ROM包名
End_Time 生成完整刷机包
###生成完整刷机包结束

End_Time 构建$device官改ROM
######构建$device官改ROM结束
