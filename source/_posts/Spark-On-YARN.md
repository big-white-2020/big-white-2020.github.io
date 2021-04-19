---

title : Spark on YARN
date : 2021-04-18 16:30:09
tag : [Spark, YARN, 大数据]

---

1. YARN

    YARN(Yet Another Resource Negotiator) 是 Hadoop 2.x 新增的资源调度器。首先看下 Hadoop 1.x 是怎么调度的
    ![图片](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/20210418141945)

    Hadoop 1.x 的运行流程：

    1. client 提交任务给 `Job Tracker`
    2. `Job Tracker` 接收任务，并根据 Job 的参数向 `NameNode` 请求包含这些文件的 `DataNode` 节点列表
    3. `Job Tracker` 确定执行计划：确认 `Map`、`Reduce` 的 Task 数量，将这些 Task 分配到离数据块最近的节点上执行

    随着发展部署任务越来越多，虽然 `Job Tracker` 可以部署多个，但是只有一个 `Job Tracker` 处于 active 状态，其它的 `Job Tracker` 都是 standby 并不能接收任务，所以 `Job Tracker` 变成了 Hadoop 的瓶颈。

    那么 YARN 是怎么解决这个问题的呢？YARN 采用 Master/Slave 的结构，采用双层调度架构，第一层是 `ResourceManager` 和 `NodeManager` : `ResourceManager` 是 Master 节点，相当于 `Job Tracker`，有 `Scheduler` 和 `Application Manager` 两个组件，分别用于资源调度和应用管理；`NodeManager` 是 Slave 节点，可以部署在独立的机器上，用于管理及其上的资源。

    第二层是 `NodeManager` 和 `Container` ，`NodeManager` 将 CPU 内存等资源抽象成一个个的 `Container` 并管理它们的生命周期。

    这种架构的好处：

    * `Scheduler` 由原来管理的 CPU 等资源变成了管理 `Container` 粒度变粗了，降低了负载。

    * `Application Manager` 只需要管理 `App Master` 不需要管理任务调度的完整信息，也降低了负载。

    下图为 YARN 的架构图
    ![Yarn架构图](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/20210418142709.gif)

    组件说明：

    * ResourceManager：

        * 定时调度器(Scheduler)：从本质上来说，定时调度器就是一种策略，或者说一种算法。当 Client 提交一个任务的时候，它会根据所需要的资源以及当前集群的资源状况进行分配。注意，它只负责向应用程序分配资源，并不做监控以及应用程序的状态跟踪。
        * 应用管理器(ApplicationManager)：同样，听名字就能大概知道它是干嘛的。应用管理器就是负责管理 Client 用户提交的应用。上面不是说到定时调度器（Scheduler）不对用户提交的程序监控嘛，其实啊，监控应用的工作正是由应用管理器（ApplicationManager）完成的。

    * NodeManager:

        * Container：容器（Container）这个东西是 Yarn 对资源做的一层抽象。就像我们平时开发过程中，经常需要对底层一些东西进行封装，只提供给上层一个调用接口一样，Yarn 对资源的管理也是用到了这种思想。
        ![container](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/20210418144121.jpg)
            需要注意两点：

            1. 容器由 NodeManager 启动和管理，并被它所监控。
            2. 容器被 ResourceManager 进行调度。

    * ApplicationMaster

        每当 Client 提交一个 Application 时候，就会新建一个 `ApplicationMaster` 。由这个 `ApplicationMaster` 去与 `ResourceManager` 申请容器资源，获得资源后会将要运行的程序发送到容器上启动，然后进行分布式计算。这个 `ApplicationMaster` 可能运行在某个 `Container` 中，也可能运行在 Clinet 中，由不同的部署方式决定。

    YARN 的部署流程：
    1. Client 向 `ResourceManager` 提交一个作业。
    2. `ResourceManager` 向 `NodeManager` 请求一个 `Container` 并在这个 `Container` 中运行 `ApplicationMaster`
    3. `ApplicationMaster` 向 `ResourceManager` 注册，注册之后，客户端就可以查询 `ResourceManager` 获得自己 `ApplicationMaster` 的详情以及直接和 `ApplicationMaster` 交互；
    4. `ApplicationMaster` 启动后将作业拆分一个个的 Task，然后向 `ResourceManager` 请求 `Container` 资源用于运行 Task，并定时向 `ResourceManager` 发送心跳
    5. `ApplicationMaster` 请求到资源后，`ApplicationMaster` 会跟对应的 `NodeManager` 通信，并将 Task 分发到对应的 `NodeManager` 中的 `Container` 中运行。
    6. `ApplicationMaster` 定时向 `ResourceManager` 发送心跳，汇报作业运行情况。程序运行完成后再向 `ResourceManager` 注销释放资源。 

2. Spark On YARN

    首先看下 Spark 资源管理架构图：
    ![图片](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/20210418150911)
    组件说明：

    * ClusterManager ：也就是 Master，是 Spark 的主控节点，可以部署多个 Master，但是只有一个是 active 状态。
    * Work：是 Spark 的工作节点，向 Master 汇报资源、Executor 的执行状态，由 Master 控制 Worker 的启动。
    * Driver：是应用程序的驱动程序，每个应用包含多个小任务，Driver 负责推动这些小任务执行。
    * Executor：是 Spark 的工作进程，由 Worker 管理，负责具体任务的执行。

    Spark 的架构与 YARN 的架构非常像，简单看下角色的对比，Master 与 `ResourceManager` 相对应，Worker 和 `NodeManager` 对应，Driver 和 `ApplicationMaster` 对应，Executor 和 `Container` 相对应。

    Spark 的部署模式：

    * Local 模式：部署在同一个进程中，只有 Driver 角色，接受任务后创建 Driver 负责应用的调度执行，不涉及 Master 和 Worker；
    * Local- Cluster 模式：部署在同一个进程上，存在 Master 和 Worker 角色，它们作为独立线程存在于这个进程内；
    * Standalone：Spark 真正的集群模式，在这个模式下 Master 和 Worker 是独立的进程；
    * 第三方部署模式：构建于 YARN 或者 Mesos 上，由第三方负责资源管理。

    Spark On YARN-Cluster 部署流程：

    1. Client 向 `ResourceManager` 提交任务
    2. `ResourceManager` 接收任务并找到一个 Container 创建 `ApplicationMaster`，此时 `ApplicationMaster` 上运行的是 Spark Driver
    3. `ApplicationMaster` 向 `ResourceManager` 申请 `Container` 并启动
    4. Spark Driver 在 `Container` 上启动 Spark Executor，并调度 Spark Task 在 Spark Executor 上运行
    5. 等作业执行完后向 `ResourceManager` 注销释放资源
    ![图片](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/20210418161432.jpeg)

    可以看出这个执行流程和 Yarn 对一个任务的处理过程几乎一致，不同的是在 Spark on Yarn 的 Job 处理过程中 App Master、Container 是交由 Spark 相对应的角色去处理的。

    Spark on YARN 还有一种部署方式：Spark On YARN-Client，与 Spark On YARN-Cluster 的区别就是 Spark on Yarn-Client 的客户端在提交完任务之后不会将 Spark Driver 托管给 Yarn，而是在客户端运行。App Master 申请完 Container 之后同样也是由 Spark Driver 去启动 Spark Executor，执行任务。
    ![图片](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/20210418170340)

3. 参考资料

    [深入浅出 Hadoop YARN](https://zhuanlan.zhihu.com/p/54192454)

    [Spark on Yarn | Spark，从入门到精通](https://mp.weixin.qq.com/s?__biz=MzU5ODU5MjM2Mw==&mid=2247484270&idx=2&sn=f287173c5d676625f11c7ef415b81cf4&chksm=fe409d6ac937147c2bd197104a3e4070c9d12786c9c37c17d699039a5d96858cafcc8eee53e5&scene=21#wechat_redirect)