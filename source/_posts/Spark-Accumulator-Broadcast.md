---
title : Spark Accumulator & Broadcast
date : 2021-06-24 12:29:44
tag : [Spark, 大数据]
---

Spark 中有两类共享变量，即累加器（Accumulator）和广播变量（Broadcast）

### Accumulator

累加器，顾名思义，是用于累加计数的，那么为什么需要累加器呢，普通变量不能计数吗？先看一段代码

```scala
var counter = 0
sc.parallelize(Seq(1, 2, 3, 4, 5)).foreach(x => counter += x)
println(counter)
```

这段代码的输出结果为 0，为什么呢？这里涉及到一个 Spark 闭包问题，所谓的闭包可以理解为 **在函数作用域中修改作用域外的变量**。在计算前 Spark 会将闭包序列化并发送到 executor 上，上面代码中会将 `counter` 序列化打包，然后在 executor 中反序列化，这时 Driver 端和每个 Executor 中都有一个 `counter`，但是 Executor 中的 `counter` Driver 端的副本，也就是说如果在 Executor 中修改了 `counter` 是不会影响 Driver 端 `counter` 的值，所以没法起到计数的效果。所以计数就需要用到 Accumulator

```scala
// LongAccumulator 是 Accumulator 的一种
class LongAccumulator extends AccumulatorV2[jl.Long, jl.Long] {
  private var _sum = 0L
  private var _count = 0L
 }
```
从 `LongAccumulator` 代码看来 `_sum` 也只是普通的变量，那为什么 `LongAccumulator` 中的变量就能起到计数的效果呢
在 `LongAccumulator` 里有一个 `merge` 方法，这个 `merge` 方法在 task 运行完成后被调用，会将不同 Executor 的变量合并到 Driver 上。

```scala
  override def merge(other: AccumulatorV2[jl.Long, jl.Long]): Unit = other match {
    case o: LongAccumulator =>
      _sum += o.sum
      _count += o.count
    case _ =>
      throw new UnsupportedOperationException(
        s"Cannot merge ${this.getClass.getName} with ${other.getClass.getName}")
  }
```
需要注意的是 Accumulator 的值只能在 Driver 端查看。

![image-20210623204446215](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20210623204446215.png)

上图左边为使用普通变量，右图为使用 Spark Accumulator，区别就在于 Spark Accumulator 在 Task 任务执行后将变量回传给 Driver 进行累加。

#### Accumulator 使用

Spark 内置有三种 Accumulator，分别是 `LongAccumulator`、`DoubleAccumulator` 和 `CollectionAccumulator`，分别对应 Long、Double、List 三种计数类型。在使用 Accumulator 时需要 action 算子触发计算。

```scala
val counter = sc.longAccumulator("counter")
sc.parallelize(Seq(1, 2, 3, 4, 5)).foreach(x => counter.add(x))
println(counter.value)
```

`SparkContext` 集成了三种 Accumulator，在使用时只需要传入一个 Accumulator name 即可，在 Spark Web UI 中的 Stages 页面可以查看声明的 Accumulator

![image-20210623205323917](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20210623205323917.png)

#### 自定义 Accumulator

自定义 Accumulatro 只需要继承 `AccumulatorV2` 即可

```scala
class UserDefineAccumulator extends AccumulatorV2[String, String] {

    private var str: StringBuilder = new StringBuilder

    override def isZero: Boolean = str.length == 0

    override def copy(): AccumulatorV2[String, String] = {
        val accumulator = new UserDefineAccumulator
        accumulator.str = str
        accumulator
    }

    override def reset(): Unit = str = new StringBuilder

    // 重点方法，增加操作
    override def add(v: String): Unit = str.append(s"#$v")
	
    // 重点方法，合并操作
    override def merge(other: AccumulatorV2[String, String]): Unit = str.append(s"#${other.value}")

    override def value: String = str.toString()
}
```

完成定义后，在使用时将 Accumulator 在 `SparkContext` 中注册即可

```scala
val accumulator = new UserDefineAccumulator
sc.register(accumulator, "udfAcc")
sc.parallelize(Seq("a", "b", "c", "d", "e", "f"))
	.foreach(x =>
		accumulator.add(x)
	)
println(accumulator.value)
```

运行上面的代码发现每次运行的结果都不一样

```
##d##e#f##b#c##a
##b#c##e#f##a##d
##e#f##a##d##b#c
```

这是因为 `merge` 的时候顺序是不确定的，哪个`task` 先执行完就先 merge 哪个，所以在自定义 `Accumulator` 的时候一定要注意**合并顺序不能影响最终结果**，这样才算是正确的 `Accumulator`

#### Accumulator 注意事项

下面这段代码，`counter` 第一次打印 15，第二次打印 30

```scala
val counter = sc.longAccumulator("counter")
val array = sc.parallelize(Seq(1, 2, 3, 4, 5)).map(x => counter.add(x))
array.count()
println(counter.value)
array.collect()
println(counter.value)
```

因为调用了两次 action 算子，这段代码会被构建成两个 job，每个 job 是从 DAG 最开始进行计算，都会对 counter 进行操作，所以第二次会打印 30

![image-20210624125938742](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20210624125938742.png)

我们只需要将中间结果 `cache` 隔断之前的血缘即可 ，就能解决这个问题

```scala
val counter = sc.longAccumulator("counter")
val array = sc.parallelize(Seq(1, 2, 3, 4, 5))
	.map(x => counter.add(x))
	.cache()
array.count()
println(counter.value)
array.collect()
println(counter.value)
```

这样两次打印的值就一样了。

#### Accumulator 小技巧

Accumulator 不仅可以作为累加器，还能作为“累减器“，只需要累加的数值改成负值即可，只适用于数值计算

```scala
sc.parallelize(Seq(1, 2, 3, 4, 5)).map(x => counter.add(-x))
```



### Broadcast

Spark 中另一个共享变量就是广播变量（broadcast）。一般一个 Executor 中会有多个 Task，如果不使用广播变量，Spark 需要将变量副本传输到每个 Task 中，造成带宽、内存和磁盘的浪费，降低执行效率，使用广播变量则只会传输一份副本到 Executor 中，Executor 中的 Task 共享这一份副本。假设有 100 个 Executor，每个 Executor 中有 10 个 Task，然后有一个 10M 大小的 List 需要考拷贝副本，如果不使用广播变量的情况需要拷贝 100 * 10 * 10 = 10000M，大概 10G；如果使用广播变量只需要 100 * 10 = 1000M，减小了 10 倍。所以广播变量是优化 Spark 任务的一个小技巧。

#### Broadcast 原理

broadcast 传输文件采用 `BitTorrent` 协议，也就是常说的 BT 下载，和点对点（point-to-point）的协议程序不同，它是用户群对用户群（peer-to-peer），可以看下这个小游戏 [BitTorrent](http://mg8.org/processing/bt.html)，大概思想为把一个文件切分成多个块，每个下载的机器上都存放一块或多块，有新机器加入下载就可以到不同的机器上下载不同的块，降低 Server 的负载。

![image-20210624205010620](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20210624205010620.png)

Spark Broadcast 的原理与 `BitTorrent` 类似，Spark 使用 blockManager 管理文件 block

写流程

1. 将需要广播的变量切分成一个个 `chunk` (默认 4M）
2. 计算这些 `chunk` 的 Adler-32 checksum
3. 每个 `chunk` 加上一个 pieceId （ "broadcast_" + broadcastId + "_" + "piece" + number），这个 pieceId 作为 blockId
4. 写入文件系统

读流程

1. 随机获取 pieceId
2. 根据 blockManager 获取 block
3. 校验校验和
4. 按照 pieceId 顺序拼接各个 block



#### Broadcast 使用

```scala
val set = Set(1, 2, 3, 4, 5)
val setBro = sc.broadcast(set)
setBro.value.foreach(println)
```

#### Broadcast 只读问题

为什么 Broadcast 只能读不能修改？因为广播变量会传输到多个 Executor 上，如果某个 Executor 能够修改了 Broadcast，那么 Spark 就要保证修改的 Broadcast 能及时同步到每台机器上，在同步的时候要保证数据的一致性以及同步失败怎么容错等等问题，所以 Spark 干脆就让 Broadcast 不可修改



#### 参考资料

[Spark笔记之累加器（Accumulator）](https://www.cnblogs.com/cc11001100/p/9901606.html)

[spark 广播变量的设计和实现](https://mp.weixin.qq.com/s/Wmi5oxODpOc8ZQdBhvfoOA?)