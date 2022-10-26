# Tengine 安装脚本
+ 支持 Centos/Ubuntu

## 配置文件说明(install_tengine.conf)
+ TENGINE_VERSION：要安装的 Tengine 版本
+ INSTALL_PATH：Tengine 部署路径
+ TENGINE_ADD_MODULE：Tengine build 额外安装的模块
+ RUN_USER：Tengine 运行用户
+ SYSTEMCTL_SERVER_NAME：注册如系统的服务名
  + 如服务名设置为 nginx，则使用 systemctl restart nginx 重启

## 使用
+ Centos

```bash
$ sudo sh install_tengine.sh
```
+ Ubuntu

```bash
$ sudo bash install_tengine.sh
```