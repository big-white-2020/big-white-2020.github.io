---
title : Spark Join
date : 2021-07-06 20:10:20
tag : [Spark, Spark SQL, 大数据]
---



Join 是 SQL 中非常重要的语法，只要稍微复杂一点的场景就离不开 Join，甚至是多表 Join，如下图，Join 有三个关注点：Join 方式、Join 条件、过滤条件

![img](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/b7e98911b3c306b4f9d5d06d12bdb6d9.png)

<center>图片引用自<a href="https://cloud.tencent.com/developer/article/1005502">Spark SQL 之 Join 实现</a></center>

### Spark Join 实现方式

在聊实现方式前，需要了解什么 Hash Join，hash join 是指将一个表根据 Join Key 做 hash（暂且称为**查找表**），然后遍历另一个表（暂且称为**遍历表**），遍历时在 hash 表中根据 join key 查找，这样时间复杂度就是 O(M(遍历一个表) + 1(hash 查找))，入下图，Build Table 为查找表，Probe Table 为遍历表

![file](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/4149557144-5dd0c87c7683b_articlex)

<center>图片引用自<a href="https://segmentfault.com/a/1190000021033287">Spark难点 | Join的实现原理</a></center>

#### Broadcast Hash Join

ok，对 hash join 了解后，再来聊聊  `Broadcast Hash Join`。在 join 过程中有这么一种情况——一张很大的表 join 一张很小的表（一般是维表），这时如果对大表做 shuffle 代价可能比较大，Spark 会对这种情况进行优化，将小表作为广播变量广播到各个节点中，然后在节点中做 hash join。这样对一个大表的 shuffle 就变成对一个小表的广播，而 Spark 广播变量使用 `BitTorrent` 进行优化(感兴趣可以点这[Spark Accumulator & Broadcast](https://big-white-2020.github.io/2021/06/24/Spark-Accumulator-Broadcast/))，性能比 Shuffle 有很大的提省，只要每个节点的大表分区做一个 map 就可以完成，这种方式也被称为 map join。

![img](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/1*pO_40cT0UhaiSP0fdT-sWw.jpeg)

<center>图片引用自<a href="https://towardsdatascience.com/strategies-of-spark-join-c0e7b4572bcf">Spark Join Strategies — How & What?</a></center>

虽然 `Broadcast Hash Join` 的方式快，但是随着广播的表大小增长，性能也逐渐下降，所以 Spark 只会将小于 `spark.sql.autoBroadcastJoinThreshold` (默认 10M)的表采用 `Broadcast Hash Join`，`spark.sql.autoBroadcastJoinThreshold` 参数设置为 -1，可以关闭 BHJ，实现可见 `org.apache.spark.sql.execution.joins.BroadcastHashJoinExec`

特点：

* 只能用于等值连接
* 除了 `full outer join`，支持所有 join
* 广播表大小 < `spark.sql.autoBroadcastJoinThreshold` (default 10M)

```scala
val df = Seq((0, "a"), (1, "b"), (2, "c")).toDF("id", "value")
val frame = df.join(df, Seq("id"), "left")
frame.explain()
```



![image-20210707125506944](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20210707125506944.png)

```
== Physical Plan ==
CollectLimit 21
+- *Project [id#5, value#6, value#11]
   +- *BroadcastHashJoin [id#5], [id#10], LeftOuter, BuildRight
      :- LocalTableScan [id#5, value#6]
      +- BroadcastExchange HashedRelationBroadcastMode(List(cast(input[0, int, false] as bigint)))
         +- LocalTableScan [id#10, value#11]
```



#### Shuffle Hash Join

当 `Broadcast Table` 大到一定程度后，将整个表广播已经不太划算了，还不如 shuffle。这就会用到 `Shuffle Hash Join`，Spark 会根据 `Join Key` 进行 shuffle，那么相同的 key 一定都在同一个节点中，再根据 Hash Join 的方式进行单机 Join

![img](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/1*Yjw7V8mh7FipB09ngnBn6A.jpeg)

<center>图片引用自<a href="https://towardsdatascience.com/strategies-of-spark-join-c0e7b4572bcf">Spark Join Strategies — How & What?</a></center>

`Shuffle Hash Join` 需要在内存中建立 hash table 所以有 OOM 风险，使用 `Shuffle Hash Join` 的前提为 `spark.sql.join.preferSortMergeJoin` 必须为 `false`，实现见 `org.apache.spark.sql.execution.joins.ShuffledHashJoinExec`

特点：

* 只支持等值连接
* 除了 `full outer join`，支持所有 join
* `spark.sql.join.preferSortMergeJoin`  必须为 false
* 小表的大小 < `spark.sql.autoBroadcastJoinThreshold`(default 10M) * `spark.sql.shuffle.partitions`(default 200)
* 小表的大小 * 3 <= 大表大小

![image-20210707195601815](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20210707195601815.png)

```
== Physical Plan ==
CollectLimit 21
+- *Project [id#5, value#6, value#16]
   +- ShuffledHashJoin [id#5], [id#15], Inner, BuildRight
      :- Exchange hashpartitioning(id#5, 200)
      :  +- LocalTableScan [id#5, value#6]
      +- Exchange hashpartitioning(id#15, 200)
         +- LocalTableScan [id#15, value#16]
```



#### Sort Merge Join

既然 Shuffle 不可避免，那么有没有其他优化的方式呢？Spark Shuffle 对排序有着很好的支持，所以在 `Shuffle Write`完之后，两个表都是局部有序的，那么可不可以在 `Shuffle Read` 阶段就完成 Join。由于两个表根据 `Join Key` 分区数据都是有序的，那么在 `Shuffle Read` 时，可以根据采用 Hash Join 的思想，只不过这次的查找表不是 hash 查找，而是顺序查找。对遍历表一条一条遍历，对查找表顺序查找，下一条数据只要从当前位置查找即可，不需要从头开始查找。当 `Shuffle` 完成时，`Join` 也就完成了。

![img](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/1*03nmwDCmVaSDWVHMZTcFjA.jpeg)

<center>图片引用自<a href="https://towardsdatascience.com/strategies-of-spark-join-c0e7b4572bcf">Spark Join Strategies — How & What?</a></center>

显然，如果要使用 `Sort Merge Join` ，`Join Key` 必须是可排序的，实现可见 `org.apache.spark.sql.execution.joins.SortMergeJoinExec`

特点：

* 只支持等值连接
* 支持所有类型的 join
* Join key 必须可排序

```scala
val df = Seq((0, "a"), (1, "b"), (2, "c")).toDF("id", "value") 
val df1 = Seq((0, "a"), (1, "b"), (2, "c")).toDF("id", "value")
                                                               
val frame = df.join(df1, Seq("id"), "left")                    
frame.explain()                                                
```



![image-20210707193248812](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20210707193248812.png)

```
== Physical Plan ==
CollectLimit 21
+- *Project [id#5, value#6, value#16]
   +- SortMergeJoin [id#5], [id#15], LeftOuter
      :- *Sort [id#5 ASC NULLS FIRST], false, 0
      :  +- Exchange hashpartitioning(id#5, 200)
      :     +- LocalTableScan [id#5, value#6]
      +- *Sort [id#15 ASC NULLS FIRST], false, 0
         +- Exchange hashpartitioning(id#15, 200)
            +- LocalTableScan [id#15, value#16]
```



#### Broadcast nested loop join

```
for record_1 in table_1
	for record_2 in table_2
		// join
```

如上面代码所示，`Broadcast nested loop join` 通过循环嵌套的方式进行 join，效率非常低。具体实现见 `org.apache.spark.sql.execution.joins.BroadcastNestedLoopJoinExec`

特点：

* 支持等值和不等值连接
* 支持所有类型的 join

```scala
// 需要配置
// spark.conf.set("spark.sql.crossJoin.enabled", "true")
val df = Seq((0, "a"), (1, "b"), (2, "c")).toDF("id", "value")          
val df1 = Seq((0, "a"), (1, "b"), (2, "c")).toDF("id", "value")         
                                                                        
val frame = df.join(df1, Nil, "left")                              
frame.explain()                                                         
```

![image-20210707192937662](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20210707192937662.png)

```
== Physical Plan ==
CollectLimit 21
+- BroadcastNestedLoopJoin BuildRight, LeftOuter
   :- *LocalLimit 21
   :  +- LocalTableScan [id#5, value#6]
   +- BroadcastExchange IdentityBroadcastMode
      +- LocalTableScan [id#15, value#16]
```





#### Cartesian product join(Shuffle-and-replicate nested loop join)

笛卡尔积 join，与普通 SQL 一样，如果 join 时不加连接条件就会产生笛卡尔积连接。具体实现可以看看 `org.apache.spark.sql.execution.joins.CartesianProductExec`

特点：

* 支持等值和不等值连接
* 只支持 inner join

```scala
// 需要配置
// spark.conf.set("spark.sql.crossJoin.enabled", "true")
val df = Seq((0, "a"), (1, "b"), (2, "c")).toDF("id", "value")
val df1 = Seq((0, "a"), (1, "b"), (2, "c")).toDF("id", "value")

val frame = df.crossJoin(df1)
frame.explain()
```

需要开启 `spark.conf.set("spark.sql.crossJoin.enabled", "true")`

![image-20210707192503866](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20210707192503866.png)

```
== Physical Plan ==
CollectLimit 21
+- CartesianProduct
   :- LocalTableScan [id#5, value#6]
   +- LocalTableScan [id#15, value#16]
```



#### Join 方式选择

既然有这么多种 Join 方式，那么 Spark 是怎么选择合适的 Join 方式呢？

Spark 根据等值和非等值连接进行划分

**等值连接**

![image-20210706203757108](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20210706203757108.png)

其中用户选择遵循下方代码顺序

```scala
def createJoinWithoutHint() = {                                                           
  createBroadcastHashJoin(                                                                
    canBroadcast(left) && !hint.leftHint.exists(_.strategy.contains(NO_BROADCAST_HASH)),  
    canBroadcast(right) && !hint.rightHint.exists(_.strategy.contains(NO_BROADCAST_HASH)))
    .orElse {                                                                              
      if (!conf.preferSortMergeJoin) {                                                     
        createShuffleHashJoin(                                                             
          canBuildLocalHashMap(left) && muchSmaller(left, right),                          
          canBuildLocalHashMap(right) && muchSmaller(right, left))                         
      } else {                                                                             
        None                                                                               
      }                                                                                    
    }                                                                                      
    .orElse(createSortMergeJoin())                                                         
    .orElse(createCartesianProduct())                                                      
    .getOrElse {                                                                           
      // This join could be very slow or OOM                                               
      val buildSide = getSmallerSide(left, right)                                          
      Seq(joins.BroadcastNestedLoopJoinExec(                                               
        planLater(left), planLater(right), buildSide, joinType, nonEquiCond))              
    }                                                                                      
}                                                                                         
```

即 `Broadcast Hash Join`, `Sort Merge Join`, `Shuffle Hash Join`, `Cartesian Product Join`, `Broadcast Nested Loop Join` 的顺序

**非等值连接**

![image-20210706204039720](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20210706204039720.png)

用户选择顺序为：

```scala
createBroadcastNLJoin(hintToBroadcastLeft(hint), hintToBroadcastRight(hint))
	.orElse { if (hintToShuffleReplicateNL(hint)) createCartesianProduct() else None }
	.getOrElse(createJoinWithoutHint())
```

即 `Broadcast Nested Loop Join`,  `Cartesian Product Join`。上图有两次 `Broadcast Nested Loop Join`，是因为第一次 `Broadcast Nested Loop Join` 会先尝试是否能广播左表或者右表，如果都不能则选择 `Cartesian Product Join`，最后再用 `Broadcast Nested Loop Join` 兜底

```scala
def createJoinWithoutHint() = {
  createBroadcastNLJoin(canBroadcast(left), canBroadcast(right))
    .orElse(createCartesianProduct())
    .getOrElse {
      // This join could be very slow or OOM
      Seq(
        joins.BroadcastNestedLoopJoinExec(
          planLater(left), planLater(right), desiredBuildSide, joinType, condition))
    }
}
```



### Spark 中特殊的 Join

#### left semi join

`left semi join` 是以左表为准，如果查找成功就返回左表的记录，如果查找失败则返回 null，如下图所示。

![img](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/1500347041788_7705_1500347041941.png)

<center>图片引用自<a href="https://cloud.tencent.com/developer/article/1005502">Spark SQL 之 Join 实现</a></center>

#### left anti join

`left anti join` 则是与 `left semi join` 相反，也是以左表为准，如果查找成功就返回 null，如果查找失败则返回左表记录，如下图

![img](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/1500347061364_4191_1500347061481.png)

<center>图片引用自<a href="https://cloud.tencent.com/developer/article/1005502">Spark SQL 之 Join 实现</a></center>

我不知道这两种特殊的 Join 方式是不是 Spark 特有的，但是是我学习 Spark 之后才知道有这两种 Join 方式

#### 参考资料

[Spark Join Strategies — How & What?](https://towardsdatascience.com/strategies-of-spark-join-c0e7b4572bcf)

[每个 Spark 工程师都应该知道的五种 Join 策略](https://blog.csdn.net/wypblog/article/details/108570977)

[Spark SQL 之 Join 实现](https://cloud.tencent.com/developer/article/1005502)