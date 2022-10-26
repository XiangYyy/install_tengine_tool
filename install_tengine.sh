#!/bin/bash
## Author：yanxiang
## Time:20220421
## 20220705:add use jemalloc
## 20221026:add support ubuntu
set -eu

# 无需配置，脚本使用全局变量
OS_NAME=""
OS_VERSION=""
OS_CPU_TOTAL=""
OS_RAM_TOTAL=""

# 初始化相关
function Init() {
    if [ ! -f "./install_tengine.conf" ]; then
        EchoError 'config file "./install_tengine.conf" not found'
        exit 1
    fi

    EchoInfo "load install config"
    # load config
    # shellcheck source=/dev/null
    source "./install_tengine.conf"

    TENGINE_PKG_NAME="tengine-${TENGINE_VERSION}.tar.gz"
    SERVICE_PATH="/etc/systemd/system"
    InitGetOSMsg
}

# 获取操作系统基本信息
function InitGetOSMsg() {
    if [ -f "/etc/redhat-release" ] && [ "$(awk '{print $1}' /etc/redhat-release)" = "CentOS" ]; then
        OS_NAME="CentOS"
        OS_VERSION="$(awk -F 'release ' '{print $2}' /etc/redhat-release | awk '{print $1}' | awk -F '.' -v OFS='.' '{print $1,$2}')"
    elif [ -f "/etc/redhat-release" ] && [ "$(awk -v OFS='' '{print $1,$2}' /etc/redhat-release)" = "RedHat" ]; then
        OS_NAME="RedHat"
        OS_VERSION="$(awk -F 'release ' '{print $2}' /etc/redhat-release | awk '{print $1}')"
    elif [ -f "/etc/issue" ] && [ "$(awk '{print $1}' /etc/issue)" = "Ubuntu" ]; then
        OS_NAME="Ubuntu"
        OS_VERSION="$(awk '{print $2}' /etc/issue | head -n 1)"
    else
        EchoError "OS Not Support"
        exit 1
    fi

    OS_CPU_TOTAL=$(grep -c 'processor' /proc/cpuinfo)
    OS_RAM_TOTAL=$(free -g | grep Mem | awk '{print $2}')

    echo "OS_NAME=$OS_NAME"
    echo "OS_VERSION=$OS_VERSION"
    echo "OS_CPU_TOTAL=$OS_CPU_TOTAL"
    echo "OS_RAM_TOTAL=$OS_RAM_TOTAL"
}

function CheckSystemExists() {

    if [ "$(systemctl status "${SYSTEMCTL_SERVER_NAME}" | wc -l)" -ne 0 ]; then
        EchoError "systemctl server $SYSTEMCTL_SERVER_NAME is exists"
        exit 1
    fi

    local nginx_systemctl_path="${SERVICE_PATH}/${SYSTEMCTL_SERVER_NAME}.service"
    if [ -e "${nginx_systemctl_path}" ]; then
        EchoError "systemctl server conf ${nginx_systemctl_path} is exists"
        exit 1
    fi
}

function Check() {
    if [ $UID -ne 0 ]; then
        echo -e "${REDCOLOR} Permission denied ! Please use root user ${RES}"
        exit 1
    fi

    if [ -e "$INSTALL_PATH" ] &&
        [ "$(find "$INSTALL_PATH" -maxdepth 1 ! -name "$(basename "$INSTALL_PATH")" |
            wc -l)" -ne 0 ]; then
        EchoError "$INSTALL_PATH is not empty directories"
        exit 1
    fi

    CheckSystemExists
}

# 打印错误
function EchoError() {
    red_color='\E[1;31m'
    res='\E[0m'
    echo -e "${red_color}ERROR:${1}${res}" >&2
}

# 打印INFO
function EchoInfo() {
    local green_color='\E[1;32m'
    local res='\E[0m'
    echo -e "${green_color}INFO:${1}${res}"
}

function PkgAddRepo() {
    if [ ! -e "/etc/yum.repos.d/epel.repo" ]; then
        EchoInfo "add epel repo"
        yum -y install wget
        #wget -O /etc/yum.repos.d/epel.repo http://mirrors.cloud.tencent.com/repo/epel-7.repo
        wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
        yum clean all && yum repolist
    fi
    EchoInfo "install jemalloc"
    if ! yum -y install jemalloc jemalloc-devel; then
        EchoError "Install sys pkgs faild"
        exit 1
    fi
}

# 安装依赖包
function YumInstall() {
    if [ "$(echo "$TENGINE_ADD_MODULE" | grep -c 'jemalloc')" -ne 0 ]; then
        PkgAddRepo
    fi

    EchoInfo "Install sys pkgs"
    if ! yum install -y gcc zlib zlib-devel pcre-devel openssl openssl-devel; then
        EchoError "Install sys pkgs faild"
        exit 1
    fi
}

function InstallSysPkgs() {
    if [ "$SKIP_SYS_PKG_INSTALL" -ne "0" ]; then
        EchoInfo "skip install sys pkgs"
        return 0
    fi

    if [ "$OS_NAME" = "CentOS" ] || [ "$OS_NAME" = "RedHat" ]; then
        YumInstall
    fi

    if [ "$OS_NAME" = "Ubuntu" ]; then
        if [ "$(echo "$TENGINE_ADD_MODULE" | grep -c 'jemalloc')" -ne 0 ]; then
            EchoInfo "install libjemalloc-dev"
            if ! apt -y update || ! apt -y install libjemalloc-dev; then
                EchoError "Install sys pkgs faild"
                exit 1
            fi
        fi

        EchoInfo "Install sys pkgs"
        if ! apt -y update || ! apt -y install gcc libaio1 libncurses5 \
            libpcre3-dev openssl libssl-dev zlib1g zlib1g-dev make; then
            EchoError "Install sys pkgs faild"
            exit 1
        fi
    fi
}

# 编译安装 Tengine
function BuildNginx() {
    if [ ! -e "$INSTALL_PATH" ]; then
        mkdir -p "$INSTALL_PATH"
    fi
    if [ -e "$INSTALL_PATH" ] &&
        [ "$(find "$INSTALL_PATH" -maxdepth 1 ! -name "$(basename "$INSTALL_PATH")" |
            wc -l)" -ne 0 ]; then
        EchoError "$INSTALL_PATH is not empty directories"
        exit 1
    fi

    EchoInfo "unzip tengine pkgs"
    tar -zxvf "$TENGINE_PKG_NAME"

    EchoInfo "Make install Tengine"
    cd "tengine-${TENGINE_VERSION}"
    ./configure --prefix=${INSTALL_PATH} $TENGINE_ADD_MODULE
    make
    make install
    EchoInfo "Make install Tengine Success"
}

function ChangeTengineDirOwner() {
    if ! id "${RUN_USER}"; then
        EchoInfo "add $RUN_USER"
        useradd -s /sbin/nologin -M -r "$RUN_USER"
    fi

    chown "${RUN_USER}"."${RUN_USER}" "${INSTALL_PATH}"
}

# 配置 systemctl
function AddNginxSystemd() {
    if [ "$(systemctl status "${SYSTEMCTL_SERVER_NAME}" | wc -l)" -ne 0 ]; then
        EchoError "systemctl server $SYSTEMCTL_SERVER_NAME is exists"
        exit 1
    fi

    local nginx_systemctl_path="${SERVICE_PATH}/${SYSTEMCTL_SERVER_NAME}.service"
    if [ -e "${nginx_systemctl_path}" ]; then
        EchoError "systemctl server conf ${nginx_systemctl_path} is exists"
        exit 1
    fi

    cp -rp ../nginx_init.service "${nginx_systemctl_path}"
    sed -i "s#{{ INSTALL_PATH }}#$INSTALL_PATH#g" "${nginx_systemctl_path}"
    systemctl enable "${SYSTEMCTL_SERVER_NAME}"
}

function AddDefaultConf() {
    cp -rp ../nginx.conf "${INSTALL_PATH}/conf/nginx.conf"
    chown "$RUN_USER"."$RUN_USER" "${INSTALL_PATH}"/conf/nginx.conf

    sed -i "s#{{ RUN_USER }}#$RUN_USER#g" "${INSTALL_PATH}"/conf/nginx.conf

    local worker_processes=4
    if [ "$OS_CPU_TOTAL" -lt 4 ]; then
        worker_processes=$OS_CPU_TOTAL
    fi

    sed -i "s#{{ WORKER_PROCESSES }}#$worker_processes#g" "${INSTALL_PATH}"/conf/nginx.conf

    mkdir -p "${INSTALL_PATH}/conf/configs/default"
    cp -rp ../default.conf "${INSTALL_PATH}/conf/configs/default/"
    chown "$RUN_USER"."$RUN_USER" "${INSTALL_PATH}/conf/configs/default/default.conf"
}

function EchoEnd() {
    EchoInfo "nginx install success"
    EchoInfo "nginx path: $INSTALL_PATH"
    EchoInfo "use \"systemctl start ${SYSTEMCTL_SERVER_NAME}\" to start tengine"
}

function main() {
    Init
    Check
    InstallSysPkgs
    BuildNginx
    ChangeTengineDirOwner
    EchoInfo "add nginx systemctl conf"
    AddNginxSystemd
    EchoInfo "add nginx default conf"
    AddDefaultConf
    EchoEnd
}

main
