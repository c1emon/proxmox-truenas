# wsx 脚本完整软件测试（2026-09-10）

输入为 fix/build-deploy-error-handling 工作树：4dc435f 加上恢复五服务重启列表、script-common.sh 抽离及最终阶段注释的未提交修改。未使用仅含旧提交的 git archive。此次不修改生产脚本，不提交或推送。

## 环境和结果

- wsx，独立 Debian bookworm-slim 容器；Debian 12.15，Node.js 18.20.4，Bash 5.2.15，GNU patch 2.7.6，diffutils 3.8，rsync 3.2.7。
- `bash -n build.sh deploy.sh script-common.sh`：通过。
- `node --test tests/*.test.cjs`：全部 8/8 通过，见 regression.tap。
- `node /tmp/package-tests.cjs`：18/18 场景通过，见 package-tests.log。测试工具保存在同目录 package-tests.cjs。
- 软件包来自官方签名 APT 仓库，仅下载和解包：bookworm 的 pve-manager 8.4.14 / libpve-storage-perl 8.3.7；trixie 的 pve-manager 9.2.10 / libpve-storage-perl 9.1.10。

## 补充覆盖

每个主版本各执行以下 9 个场景：

1. 从真实包文件首次安装 Patch，检查两个目标文件内容。
2. 重复安装 Patch，从保留的原始备份生成同样内容。
3. 切回 Native，恢复两个原文件并安装 Native 插件。
4. `-r -p`：APT 替身恢复软件包原文件，忽略刻意放置的旧备份，检查新备份及补丁结果。
5. `-r`：同上，Native 不恢复旧备份，并删除失效备份。
6. `-d`：安装后的 Helpers.pm 日志级别变为 debug。
7. sed 失败：非零退出，定位 debug 阶段，不重启、不报告完成。
8. systemctl 失败：非零退出，定位重启阶段、不报告完成。
9. 以真实原文件和补丁后的文件为 build 输入，生成补丁后再次 deploy，目标内容逐字节一致。

所有成功部署均核对准确的 `restart corosync pve-cluster pvedaemon pvestatd pveproxy` 参数和顺序。脚本从不同 cwd 调用。原 PVE 8 界面补丁成功应用时有 16/37 行偏移；其他原补丁无偏移或 fuzz 提示。

## 边界与复现

这是当前脚本范围内的完整软件测试，不是真实 PVE/TrueNAS 完整系统验收。版本查询、APT 重装和 systemctl 使用替身；文件复制、diff、patch、rsync、sed 使用容器内真实工具。未安装 PVE 包、运行包维护脚本、执行真实服务重启、加载 Perl 插件或操作 iSCSI/ZFS。未执行真实 ExtJS 浏览器交互。

package-tests.cjs 是一次性容器测试工具，仅应在可销毁容器运行：要求当前脚本及资源位于 /work，四个上述 .deb 位于 /packages，安装 nodejs、rsync、patch。它创建 /validation8 和 /validation9，目标路径被重写至这些目录；重复运行应使用新容器。

任务容器 truenas-full-EcuWm8、远程目录 /tmp/truenas-full-EcuWm8 和本轮新拉取的 Debian 镜像均已清理。日志及测试工具保留在本地规划分支，不进入上游修复代码 PR。

测试结束后按用户要求，为仓库每个 test 和本目录补充场景添加简短英文目的注释；未改变执行逻辑。最终三个 .cjs 文件均通过 node --check，差异格式检查通过；上述远程结果对应注释添加前的相同测试逻辑。
