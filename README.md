新设备部署指南：
1. 先安装node
2. 输入 node -v 和 npm -v 出现版本号则表示没问题
3. 安装 git
4. 配置 SSH Key 参考[github 配置 ssh key](https://www.cnblogs.com/ayseeing/p/3572582.html)
5. 安装 hexo
```
npm install hexo-cli
```
6. hexo s 成功后访问 localhost:4000 表示成功
7. 更新博客：
	* 在 `source/_posts` 中编写博客
	* 运行 `hexo s` 查看效果
	* 运行 deploy.sh 脚本部署到 github 上
8. 运行 `update.sh` 更新源文件到 github 上备份
