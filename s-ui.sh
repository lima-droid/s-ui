#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# 检查root权限
[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 请使用root权限运行此脚本 \n " && exit 1

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

# 获取服务状态
get_service_status() {
    if systemctl is-active --quiet s-ui; then
        echo "运行中"
    else
        echo "已停止"
    fi
}

# 获取自启状态
get_autostart_status() {
    if systemctl is-enabled --quiet s-ui 2>/dev/null; then
        echo "是"
    else
        echo "否"
    fi
}

show_menu() {
    echo ""
    echo -e "${green}  S-UI 管理脚本 ${plain}"
    echo -e "${green}————————————————————————————————${plain}"
    echo -e "  0. 退出"
    echo -e "${green}————————————————————————————————${plain}"
    echo -e "  1. 安装"
    echo -e "  2. 更新"
    echo -e "  3. 自定义版本"
    echo -e "  4. 卸载"
    echo -e "${green}————————————————————————————————${plain}"
    echo -e "  5. 重置管理员账户为默认"
    echo -e "  6. 设置管理员账户"
    echo -e "  7. 查看管理员账户"
    echo -e "${green}————————————————————————————————${plain}"
    echo -e "  8. 重置面板设置"
    echo -e "  9. 设置面板参数"
    echo -e "  10. 查看面板设置"
    echo -e "${green}————————————————————————————————${plain}"
    echo -e "  11. 启动 S-UI"
    echo -e "  12. 停止 S-UI"
    echo -e "  13. 重启 S-UI"
    echo -e "  14. 检查 S-UI 状态"
    echo -e "  15. 查看 S-UI 日志"
    echo -e "  16. 启用 S-UI 开机自启"
    echo -e "  17. 禁用 S-UI 开机自启"
    echo -e "${green}————————————————————————————————${plain}"
    echo -e "  18. 启用/禁用 BBR"
    echo -e "  19. SSL 证书管理"
    echo -e "  20. Cloudflare SSL 证书"
    echo -e "${green}————————————————————————————————${plain}"
    
    # 显示状态信息
    if [[ -e /usr/local/s-ui/sui ]]; then
        echo -e "状态: ${green}$(get_service_status)${plain}"
        echo -e "开机自启: ${green}$(get_autostart_status)${plain}"
        echo ""
    fi
}

check_installed() {
    if [[ ! -e /usr/local/s-ui/sui ]]; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return 1
    fi
    return 0
}

# 安装S-UI
install_sui() {
    if [[ -e /usr/local/s-ui/ ]]; then
        echo -e "${red}错误: S-UI 已经安装！${plain}"
        return
    fi
    
    echo -e "${green}开始安装 S-UI...${plain}"
    bash <(curl -Ls https://raw.githubusercontent.com/lima-droid/s-ui/master/install.sh)
}

# 更新S-UI
update_sui() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装，无法更新！${plain}"
        return
    fi
    
    echo -e "${yellow}检查更新中...${plain}"
    
    last_version=$(curl -s "https://api.github.com/repos/alireza0/s-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$last_version" ]]; then
        echo -e "${red}获取最新版本失败！${plain}"
        return
    fi
    
    current_version=$(/usr/local/s-ui/sui version 2>/dev/null || echo "未知")
    echo -e "当前版本: ${current_version}"
    echo -e "最新版本: ${last_version}"
    
    if [[ "$current_version" == "$last_version" ]]; then
        echo -e "${green}已经是最新版本！${plain}"
        return
    fi
    
    echo -e "${yellow}开始更新到版本 ${last_version}...${plain}"
    
    # 停止服务
    systemctl stop s-ui 2>/dev/null
    
    # 下载新版本
    arch=$(uname -m)
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
        *) arch="amd64" ;;
    esac
    
    wget -O /tmp/s-ui-linux-${arch}.tar.gz https://github.com/alireza0/s-ui/releases/download/${last_version}/s-ui-linux-${arch}.tar.gz
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载失败！${plain}"
        systemctl start s-ui 2>/dev/null
        return
    fi
    
    # 解压并安装
    tar -zxvf /tmp/s-ui-linux-${arch}.tar.gz -C /tmp/
    cp -f /tmp/s-ui/sui /usr/local/s-ui/
    chmod +x /usr/local/s-ui/sui
    rm -rf /tmp/s-ui*
    
    # 启动服务
    systemctl start s-ui
    echo -e "${green}更新完成！${plain}"
}

# 自定义版本
custom_version() {
    read -p "请输入要安装的版本号 (例如: v1.0.0): " version
    if [[ -z "$version" ]]; then
        echo -e "${red}版本号不能为空！${plain}"
        return
    fi
    
    echo -e "${yellow}开始安装版本 ${version}...${plain}"
    bash <(curl -Ls https://raw.githubusercontent.com/lima-droid/s-ui/master/install.sh) ${version}
}

# 卸载S-UI
uninstall_sui() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return
    fi
    
    echo -e "${red}警告: 这将卸载 S-UI，包括所有配置文件！${plain}"
    read -p "确定要卸载吗？(y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${yellow}取消卸载${plain}"
        return
    fi
    
    echo -e "${yellow}正在卸载 S-UI...${plain}"
    
    # 停止服务
    systemctl stop s-ui 2>/dev/null
    systemctl disable s-ui 2>/dev/null
    
    # 删除文件
    rm -rf /usr/local/s-ui
    rm -f /usr/bin/s-ui 2>/dev/null
    rm -f /etc/systemd/system/s-ui.service 2>/dev/null
    systemctl daemon-reload
    
    echo -e "${green}S-UI 已卸载完成！${plain}"
}

# 重置管理员账户
reset_admin() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return
    fi
    
    echo -e "${yellow}正在重置管理员账户...${plain}"
    local usernameTemp=$(head -c 6 /dev/urandom | base64)
    local passwordTemp=$(head -c 6 /dev/urandom | base64)
    
    /usr/local/s-ui/sui admin -username ${usernameTemp} -password ${passwordTemp}
    
    echo -e "${green}管理员账户已重置！${plain}"
    echo -e "${green}────────────────────────────────${plain}"
    echo -e "${green}用户名:${plain} ${usernameTemp}"
    echo -e "${green}密  码:${plain} ${passwordTemp}"
    echo -e "${green}────────────────────────────────${plain}"
    echo -e "${red}请务必保存好以上信息！${plain}"
}

# 设置管理员账户
set_admin() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return
    fi
    
    read -p "请输入用户名: " username
    read -p "请输入密码: " password
    
    if [[ -z "$username" || -z "$password" ]]; then
        echo -e "${red}用户名和密码不能为空！${plain}"
        return
    fi
    
    echo -e "${yellow}正在设置管理员账户...${plain}"
    /usr/local/s-ui/sui admin -username $username -password $password
    echo -e "${green}管理员账户设置完成！${plain}"
}

# 查看管理员账户
view_admin() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return
    fi
    
    echo -e "${yellow}当前管理员账户信息:${plain}"
    /usr/local/s-ui/sui admin -show
}

# 重置面板设置
reset_settings() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return
    fi
    
    echo -e "${red}警告: 这将重置所有面板设置为默认值！${plain}"
    read -p "确定要重置吗？(y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${yellow}取消重置${plain}"
        return
    fi
    
    echo -e "${yellow}正在重置面板设置...${plain}"
    /usr/local/s-ui/sui setting -reset
    systemctl restart s-ui
    echo -e "${green}面板设置已重置为默认值！${plain}"
}

# 设置面板参数
set_settings() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return
    fi
    
    echo -e "${yellow}设置面板参数${plain}"
    echo -e "${green}────────────────────────────────${plain}"
    echo -e "输入新值（留空保持原样）"
    echo -e ""
    
    read -p "面板端口 (默认: 2053): " port
    read -p "面板路径 (默认: /ui): " path
    read -p "订阅端口 (默认: 2054): " subPort
    read -p "订阅路径 (默认: /sub): " subPath
    
    params=""
    [[ -n "$port" ]] && params="$params -port $port"
    [[ -n "$path" ]] && params="$params -path $path"
    [[ -n "$subPort" ]] && params="$params -subPort $subPort"
    [[ -n "$subPath" ]] && params="$params -subPath $subPath"
    
    if [[ -n "$params" ]]; then
        echo -e "${yellow}正在应用设置...${plain}"
        /usr/local/s-ui/sui setting ${params}
        systemctl restart s-ui
        echo -e "${green}面板设置已更新！${plain}"
    else
        echo -e "${yellow}没有修改任何设置${plain}"
    fi
}

# 查看面板设置
view_settings() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return
    fi
    
    echo -e "${yellow}当前面板设置:${plain}"
    echo -e "${green}────────────────────────────────${plain}"
    /usr/local/s-ui/sui uri
    echo -e "${green}────────────────────────────────${plain}"
}

# 启动服务
start_sui() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return
    fi
    
    echo -e "${yellow}正在启动 S-UI 服务...${plain}"
    systemctl start s-ui
    sleep 1
    echo -e "${green}S-UI 服务已启动${plain}"
}

# 停止服务
stop_sui() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return
    fi
    
    echo -e "${yellow}正在停止 S-UI 服务...${plain}"
    systemctl stop s-ui
    echo -e "${green}S-UI 服务已停止${plain}"
}

# 重启服务
restart_sui() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return
    fi
    
    echo -e "${yellow}正在重启 S-UI 服务...${plain}"
    systemctl restart s-ui
    sleep 1
    echo -e "${green}S-UI 服务已重启${plain}"
}

# 检查状态
check_status() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return
    fi
    
    echo -e "${yellow}S-UI 服务状态:${plain}"
    systemctl status s-ui --no-pager
}

# 查看日志
check_logs() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return
    fi
    
    echo -e "${yellow}显示 S-UI 日志 (按 Ctrl+C 退出)${plain}"
    journalctl -u s-ui -f
}

# 开启开机自启
enable_autostart() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return
    fi
    
    echo -e "${yellow}正在设置开机自启...${plain}"
    systemctl enable s-ui
    echo -e "${green}开机自启已启用${plain}"
}

# 关闭开机自启
disable_autostart() {
    if ! check_installed; then
        echo -e "${red}错误: s-ui未安装！${plain}"
        return
    fi
    
    echo -e "${yellow}正在取消开机自启...${plain}"
    systemctl disable s-ui
    echo -e "${green}开机自启已禁用${plain}"
}

# 管理BBR
manage_bbr() {
    echo -e "${yellow}BBR 加速管理${plain}"
    echo -e "${yellow}此功能暂未实现${plain}"
}

# SSL证书管理
manage_ssl() {
    echo -e "${yellow}SSL 证书管理${plain}"
    echo -e "${yellow}此功能暂未实现${plain}"
}

# Cloudflare SSL
cloudflare_ssl() {
    echo -e "${yellow}Cloudflare SSL 证书配置${plain}"
    echo -e "${yellow}此功能暂未实现${plain}"
}

# 主循环
main_menu() {
    while true; do
        show_menu
        
        read -p "请输入选项编号 [0-20]: " choice
        case $choice in
            0)
                echo -e "${green}感谢使用，再见！${plain}"
                exit 0
                ;;
            1)
                install_sui
                ;;
            2)
                update_sui
                ;;
            3)
                custom_version
                ;;
            4)
                uninstall_sui
                ;;
            5)
                reset_admin
                ;;
            6)
                set_admin
                ;;
            7)
                view_admin
                ;;
            8)
                reset_settings
                ;;
            9)
                set_settings
                ;;
            10)
                view_settings
                ;;
            11)
                start_sui
                ;;
            12)
                stop_sui
                ;;
            13)
                restart_sui
                ;;
            14)
                check_status
                ;;
            15)
                check_logs
                ;;
            16)
                enable_autostart
                ;;
            17)
                disable_autostart
                ;;
            18)
                manage_bbr
                ;;
            19)
                manage_ssl
                ;;
            20)
                cloudflare_ssl
                ;;
            *)
                echo -e "${red}无效选项，请重新输入！${plain}"
                sleep 2
                continue
                ;;
        esac
        
        echo ""
        read -p "按回车键返回主菜单..." dummy
    done
}

# 判断是命令行模式还是交互模式
if [[ $# -eq 0 ]]; then
    # 交互模式
    main_menu
else
    # 命令行模式
    case "$1" in
        "start")
            start_sui
            ;;
        "stop")
            stop_sui
            ;;
        "restart")
            restart_sui
            ;;
        "status")
            check_status
            ;;
        "enable")
            enable_autostart
            ;;
        "disable")
            disable_autostart
            ;;
        "log")
            check_logs
            ;;
        "update"|"upgrade")
            update_sui
            ;;
        "install")
            install_sui
            ;;
        "uninstall")
            uninstall_sui
            ;;
        "help")
            echo -e "${green}使用方法:${plain}"
            echo -e "  s-ui          显示管理菜单"
            echo -e "  s-ui start    启动服务"
            echo -e "  s-ui stop     停止服务"
            echo -e "  s-ui restart  重启服务"
            echo -e "  s-ui status   查看状态"
            echo -e "  s-ui update   更新版本"
            echo -e "  s-ui log      查看日志"
            ;;
        *)
            echo -e "${red}未知命令: $1${plain}"
            echo -e "使用 ${green}s-ui help${plain} 查看帮助"
            ;;
    esac
fi
