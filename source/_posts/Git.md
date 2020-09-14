---
title : Git 基本使用
date : 2020年9月14日 20:49:20
tag : [git, tool]
---



主要参考[廖雪峰的官方网站-Git教程](https://www.liaoxuefeng.com/wiki/896043488029600)，删减上下文信息，把一些命令提取出来进行了简单的解释

#### 基本操作

1. 添加文件到仓库

   ```
    git add <file> // 一次添加单个文件到暂存区，或者 git add . 添加当前仓库目录内所有修改的文件到暂存区
    git commit -m "message" // 添加到版本库
   ```

2. 查看工作区状态

   ```
   git status // 哪些文件修改过
   git diff // 查看文件修改内容
   ```

3. 版本回退

   ```
   git reset --hard HEAD^ // HEAD^ 表示上个版本，HEAD^^ 表示上上个版本，HEAD~10 表示上100个版本
   git reset --hard <commit_id> // 回退到 commit_id 那个版本
   git log // 可以查看提交历史
   git reflog // 查看命令，决定回到哪个版本
   
   // 说明一下 --hard 和 --soft 的区别
   // hard 修改版本库，修改暂存区，修改工作区
   // soft 修改版本库，保留暂存区，保留工作区，即只回退 commit 信息
   
   // 还有一个回退命令
   git revert HEAD // revert 是用一次新的 commit来回滚之前的 commit，git reset是直接删除指定的 commit，在回滚这一操作上看，效果差不多。但是在日后继续merge以前的老版本时有区别
   ```

   

4. 工作区和版本库

   ![image-20200906170537776](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200906170537776.png)

   

5. 撤销修改

   ```
   工作区：
   git checkout -- file // 放弃工作区某个文件的修改
   暂存区：
   git reset HEAD <file> // 可以把暂存区的修改撤销掉（unstage），重新放回工作区，git reset命令既可以回退版本，也可以把暂存区的修改回退到工作区
   ```

6. 小结

   - 场景1：当你改乱了工作区某个文件的内容，想直接丢弃工作区的修改时，用命令`git checkout -- file`。
   - 场景2：当你不但改乱了工作区某个文件的内容，还添加到了暂存区时，想丢弃修改，分两步，第一步用命令`git reset HEAD <file>`，就回到了场景1，第二步按场景1操作。
   - 场景3：已经提交了不合适的修改到版本库时，想要撤销本次提交，参考[版本回退]，不过前提是没有推送到远程库。

7. 删除文件

   ```
   rm file // 系统手动删除
   git rm file // 删除文件
   git commit -m "remove file"
   ```

   先手动删除文件，然后使用git rm <file>和git add<file>效果是一样的

   ```
   手动删错了，但是版本库里还有，只需：
   git checkout -- file
   ```

#### 远程仓库

1. 添加远程库

~~~
git remote add origin git@server-name:path/repo-name.git // 关联一个远程库
git push -u origin master // 第一次推送master分支的所有内容
~~~

2. 克隆远程仓库

~~~\
git clone git@server-name:path/repo-name.git

// 指定分支
git clone -b branchName git@server-name:path/repo-name.git
~~~

#### 分支管理

1. 创建与合并分支

   ~~~
   git checkout -b <branch> 
   // git checkout 加上 -b 相当于以下两条命令
   git branch <branch>
   git checkout <branch>
   
   // 查看当前分支
   git branch
   
   // 合并分支
   git checkout master // 先切换到 master，也可以是 staging 等
   git merge <branch> // git merge 命令用于合并指定分支到当前分支，默认为 Fast forward，“快进模式”，也就是直接把master指向<branch>的当前提交，所以合并速度非常快
   
   // 删除分支
   git branch -d <branch>
   
   // 切换分支为 git checkout <branch>，而撤销修改则为 git checkout -- file，挺迷惑的，git 2.23 时添加了 switch 命令，用于切换分支
   // 创建并切换到分支
   git switch -c <branch>
   
   // 切换分支
   git switch <branch>
   ~~~

2. 解决冲突

   [解决冲突](https://www.liaoxuefeng.com/wiki/896043488029600/900004111093344)

3. 分支管理策略

   上面讲到了合并分支的 Fast forward 方式，在这种模式下，删除分支后，会丢掉分支信息，如果强制禁用 Fast forward 模式，git 在 merge 时会生成一个新的 commit，就能保留分支信息

   ```
   git merge --no-ff -m "merge with no-ff" <branch> // --no-ff 参数表示禁用 Fast forward
   ```

   ![image-20200906170521233](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200906170521233.png)

   好的分支管理策略应该像下图一样：

   ![image-20200906170458433](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200906170458433.png)

4. bug 分支

   当 master 分支出现 bug 需要紧急修复时，需要创建新的 bug 分支进行修复，而自己的工作又只做到一半需要保存时，先把工作现场

   ~~~
   git stash // 把当前工作现场隐藏起来，完成 bug 修复后
   git stash list // 查看隐藏的工作现场，可以通过以下两种方式恢复
   git stash apply // 这种方式恢复，stash 不会删除，需要 git stash drop 进行删除
   git stash pop // 恢复的同时把 stash 也删了
   ~~~

   修复 master 分支后发现当前工作的分支也有这个 bug，现在只需用

   ~~~ 
   git cherry-pick <commit-id> // 会复制 <commit-id> 这次提交的修改到当前分支，并自动提交一次当前分支
   ~~~

5. 删除没有合并的分支

   如果有一个实验性质没有合并的分支需要删除需要

   ~~~
   git branch -D <branch> // 没有合并的分支需要用 -D
   ~~~

6. 多人协作

   ~~~
   git remote -v // 查看远程分支
   git push origin <branch> // 推送分支，要指定本地分支，这样，Git就会把该分支推送到远程库对应的远程分支上
   
   // 从远程仓库 clone 时，默认是 master 分支，如果在本地创建和远程分支对应的分支
   git checkout -b <branch> origin/dev
   ~~~

   与远程分支建立联系

   ```
   git branch --set-upstream-to <branch-name> origin/<branch-name>
   ```

   一般多人协作的模式如下：

   - 首先，可以试图用git push origin <branch-name>推送自己的修改；


   - 如果推送失败，则因为远程分支比你的本地更新，需要先用git pull试图合并；


   - 如果合并有冲突，则解决冲突，并在本地提交；


   - 没有冲突或者解决掉冲突后，再用git push origin <branch-name>推送就能成功！


   - 如果git pull提示no tracking information，则说明本地分支和远程分支的链接关系没有创建，用命令git branch --set-upstream-to <branch-name> origin/<branch-name>。

     

7. Rebase

   理想状态下希望提交记录是一条直线

   ![image-20200906170422825](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200906170422825.png)

   可以通过 rebase 实现，一般把 rebase 叫变基，概念比较抽象，用下面几张图来解释a

初始情况：

![image-20200809152942552](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200809152942552.png)

使用 git rebase master 后，bugFix 分支上的工作在 master 的最顶端

![image-20200809153031449](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200809153031449.png)

然后切换到 master 分支，进行 git rebase bugFix

![image-20200809153745425](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200809153745425.png)

这里扩展一下 git pull 和 git pull --rebase 的区别

```
git pull = git fetch + git merge
git pull --rebase = git fetch + git rebase
```

参考：[简单对比git pull 和 git pull --rebase 的使用](https://www.cnblogs.com/kevingrace/p/5896706.html)

同时还有一个经常使用的 git rebase -i ，这个命令可以选取你连续提交的多次进行合并。

#### 标签管理

```
git tag v1.0 // 默认打在最新的 commit上，如果需要打在其他提交上
git tag v0.9 <commit-id>
git tag -a v0.1 -m "version 0.1 released" <commit-id> // 用-a指定标签名，-m指定说明文字，git show <tagname>可以看到说明文字

// 删除标签
git tag -d v0.1

// 因为创建的标签都只存储在本地，不会自动推送到远程。所以，打错的标签可以在本地安全删除。
// 如果要推送某个标签到远程，使用命令
git push origin <tagname>

git push origin --tags // 一次推送全部标签到远程

// 如果标签已经推送到远程，要删除远程标签就麻烦一点，先从本地删除：
git tag -d v0.9

// 然后，从远程删除。删除命令也是push，但是格式如下：
git push origin :refs/tags/v0.9
```

