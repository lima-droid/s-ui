#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# 检查root权限
[[ $EUID -ne 0 ]] && echo -e "${red}致命错误: ${plain} 请使用root权限运行此脚本 \n " && exit 1

# 检查操作系统并设置发行版变量
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "无法检测系统操作系统，请联系作者！" >&2
    exit 1
fi
echo "操作系统: $release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}不支持的CPU架构！ ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "系统架构: $(arch)"

install_base() {
    case "${release}" in
    centos | almalinux | rocky | oracle)
        yum -y update && yum install -y -q wget curl tar tzdata
        ;;
    fedora)
        dnf -y update && dnf install -y -q wget curl tar tzdata
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar timezone
        ;;
    *)
        apt-get update && apt-get install -y -q wget curl tar tzdata
        ;;
    esac
}

config_after_install() {
    echo -e "${yellow}正在执行数据迁移... ${plain}"
    /usr/local/s-ui/sui migrate
    
    echo -e "${yellow}安装/更新完成！出于安全考虑，建议修改面板设置 ${plain}"
    read -p "是否继续修改配置 [y/n]? ": config_confirm
    if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
        echo -e "请输入${yellow}面板端口${plain} (留空则使用现有/默认值):"
        read config_port
        echo -e "请输入${yellow}面板路径${plain} (留空则使用现有/默认值):"
        read config_path

        # 订阅配置
        echo -e "请输入${yellow}订阅端口${plain} (留空则使用现有/默认值):"
        read config_subPort
        echo -e "请输入${yellow}订阅路径${plain} (留空则使用现有/默认值):" 
        read config_subPath

        # 设置配置
        echo -e "${yellow}正在初始化，请稍候...${plain}"
        params=""
        [ -z "$config_port" ] || params="$params -port $config_port"
        [ -z "$config_path" ] || params="$params -path $config_path"
        [ -z "$config_subPort" ] || params="$params -subPort $config_subPort"
        [ -z "$config_subPath" ] || params="$params -subPath $config_subPath"
        /usr/local/s-ui/sui setting ${params}

        read -p "是否修改管理员凭据 [y/n]? ": admin_confirm
        if [[ "${admin_confirm}" == "y" || "${admin_confirm}" == "Y" ]]; then
            # 设置管理员凭据
            read -p "请输入用户名:" config_account
            read -p "请输入密码:" config_password

            # 设置凭据
            echo -e "${yellow}正在初始化，请稍候...${plain}"
            /usr/local/s-ui/sui admin -username ${config_account} -password ${config_password}
        else
            echo -e "${yellow}当前管理员凭据: ${plain}"
            /usr/local/s-ui/sui admin -show
        fi
    else
        echo -e "${red}取消配置...${plain}"
        if [[ ! -f "/usr/local/s-ui/db/s-ui.db" ]]; then
            local usernameTemp=$(head -c 6 /dev/urandom | base64)
            local passwordTemp=$(head -c 6 /dev/urandom | base64)
            echo -e "这是全新安装，将生成随机登录信息以确保安全:"
            echo -e "###############################################"
            echo -e "${green}用户名:${usernameTemp}${plain}"
            echo -e "${green}密码:${passwordTemp}${plain}"
            echo -e "###############################################"
            echo -e "${red}如果忘记登录信息，可以输入 ${green}s-ui${red} 进入配置菜单${plain}"
            /usr/local/s-ui/sui admin -username ${usernameTemp} -password ${passwordTemp}
        else
            echo -e "${red} 这是升级安装，将保留旧设置，如果忘记登录信息，可以输入 ${green}s-ui${red} 进入配置菜单${plain}"
        fi
    fi
}

prepare_services() {
    if [[ -f "/etc/systemd/system/sing-box.service" ]]; then
        echo -e "${yellow}正在停止sing-box服务... ${plain}"
        systemctl stop sing-box
        rm -f /usr/local/s-ui/bin/sing-box /usr/local/s-ui/bin/runSingbox.sh /usr/local/s-ui/bin/signal
    fi
    if [[ -e "/usr/local/s-ui/bin" ]]; then
        echo -e "###############################################################"
        echo -e "${green}/usr/local/s-ui/bin${red} 目录已存在！"
        echo -e "请检查内容并在迁移后手动删除 ${plain}"
        echo -e "###############################################################"
    fi
    systemctl daemon-reload
}

install_s-ui() {
    cd /tmp/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/alireza0/s-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}获取s-ui版本失败，可能是由于Github API限制，请稍后重试${plain}"
            exit 1
        fi
        echo -e "获取到s-ui最新版本: ${last_version}，开始安装..."
        wget -N --no-check-certificate -O /tmp/s-ui-linux-$(arch).tar.gz https://github.com/alireza0/s-ui/releases/download/${last_version}/s-ui-linux-$(arch).tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载s-ui失败，请确保服务器可以访问Github ${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/alireza0/s-ui/releases/download/${last_version}/s-ui-linux-$(arch).tar.gz"
        echo -e "开始安装 s-ui v$1"
        wget -N --no-check-certificate -O /tmp/s-ui-linux-$(arch).tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 s-ui v$1 失败，请检查版本是否存在${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/s-ui/ ]]; then
        systemctl stop s-ui
    fi

    tar zxvf s-ui-linux-$(arch).tar.gz
    rm s-ui-linux-$(arch).tar.gz -f

    chmod +x s-ui/sui s-ui/s-ui.sh
    cp s-ui/s-ui.sh /usr/bin/s-ui
    cp -rf s-ui /usr/local/
    cp -f s-ui/*.service /etc/systemd/system/
    rm -rf s-ui
    
    # === 新增：更新管理脚本到最新版本 ===
    echo -e "${yellow}正在更新管理脚本...${plain}"
    bash -c 'cd /tmp && wget -q https://raw.githubusercontent.com/lima-droid/s-ui/master/s-ui.sh -O s-ui.sh && chmod +x s-ui.sh && [[ -f /usr/bin/s-ui ]] && mv /usr/bin/s-ui /usr/bin/s-ui.backup.$(date +%s) && mv s-ui.sh /usr/bin/s-ui && echo "s-ui管理脚本更新成功！"'
    # === 新增结束 ===

    config_after_install
    prepare_services

    systemctl enable s-ui --now

    echo -e "${green}s-ui v${last_version}${plain} 安装完成，服务已启动并运行..."
    echo -e "可以通过以下URL访问面板:${green}"
    /usr/local/s-ui/sui uri
    echo -e "${plain}"
    echo -e ""
    s-ui help
}

echo -e "${green}正在执行...${plain}"
install_base
install_s-ui $1
