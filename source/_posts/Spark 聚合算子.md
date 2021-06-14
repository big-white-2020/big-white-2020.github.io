---

title : Spark 聚合算子
date : 2021-06-14 15:44:09
tag : [Spark,大数据]

---



### combineByKey

在理解 `groupByKey` 和 `reduceByKey` 之前先看看 `combineByKey`
```scala
  def combineByKey[C](
      createCombiner: V => C,
      mergeValue: (C, V) => C,
      mergeCombiners: (C, C) => C): RDD[(K, C)] = self.withScope {
    combineByKeyWithClassTag(createCombiner, mergeValue, mergeCombiners)(null)
  }
```
`combineBykey` 需要三个参数：`createCombiner`、`mergeValue`、`mergeCombiners`

`createCombiner`：当碰到未出现过 key 时需要做的处理

`mergeValue`：当碰到出现过的 key 时需要做的处理

`mergeCombiners`：分布式环境下，多台机器的结果如何合并

假设我们有下列一个 kv list，现在需要将 value 按照类别放到不同的 list 中，将 key 为水果的 value 都放到一个单独 list 中，将 key 为动物的 value 放到一个单独的 list 中
```scala
Seq("fruit" -> "apple", "fruit" -> "banana", "animal" -> "monkey", "animal" -> "tiger")
```
```scala
val rdd = spark.sparkContext.parallelize(seq)
val res: RDD[(String, List[String])] = rdd.combineByKey(
    (k: String) => List[String](k), // 1、碰到未出现过的 key 时调用这个函数。这里的处理方式为创建一个 list，之后会维护一个 key -> list 的关系
    (c: List[String], k: String) => c.+:(k), // 2、碰到出现过的 key，会调用这个函数，并把 1 中维护的 list 作为参数 c。这里的处理方式为把 value 添加到 list 中，并返回 list
    (c1: List[String], c2: List[String]) => c1 ++ c2) // 多台机器上的结果集合并时会调用这个函数，这里的处理方式为将两个 list 相加
```
调用完 `combineByKey` 后，会返回一个 `(String, List[String])` 的映射关系，我们把 `res` 打印一下可以得出
```scala
(animal,List(monkey, tiger))
(fruit,List(apple, banana))
```
再贴一段代码，这段代码只需记住 `mapSideCombine` 默认值为 `true` 即可
```scala
def combineByKeyWithClassTag[C](
      createCombiner: V => C,
      mergeValue: (C, V) => C,
      mergeCombiners: (C, C) => C,
      partitioner: Partitioner,
      mapSideCombine: Boolean = true,
      serializer: Serializer = null)(implicit ct: ClassTag[C]): RDD[(K, C)] = self.withScope {
      
    // 省略几行...
    val aggregator = new Aggregator[K, V, C](
      self.context.clean(createCombiner),
      self.context.clean(mergeValue),
      self.context.clean(mergeCombiners))
    if (self.partitioner == Some(partitioner)) {
      self.mapPartitions(iter => {
        val context = TaskContext.get()
        new InterruptibleIterator(context, aggregator.combineValuesByKey(iter, context))
      }, preservesPartitioning = true)
    } else {
      new ShuffledRDD[K, V, C](self, partitioner)
        .setSerializer(serializer)
        .setAggregator(aggregator)
        .setMapSideCombine(mapSideCombine)
    }
  }
```
### groupByKey
再看看 `groupByKey`，`groupByKey` 有一个同胞兄弟 `groupBy`，`groupBy` 最终还是调用的 `groupByKey`，看看 `groupByKey` 的代码
```scala
  def groupByKey(): RDD[(K, Iterable[V])] = self.withScope {
    groupByKey(defaultPartitioner(self))
  }
  
  def groupByKey(partitioner: Partitioner): RDD[(K, Iterable[V])] = self.withScope {
    // groupByKey shouldn't use map side combine because map side combine does not
    // reduce the amount of data shuffled and requires all map side data be inserted
    // into a hash table, leading to more objects in the old gen.
    val createCombiner = (v: V) => CompactBuffer(v)
    val mergeValue = (buf: CompactBuffer[V], v: V) => buf += v
    val mergeCombiners = (c1: CompactBuffer[V], c2: CompactBuffer[V]) => c1 ++= c2
    val bufs = combineByKeyWithClassTag[CompactBuffer[V]](
      createCombiner, mergeValue, mergeCombiners, partitioner, mapSideCombine = false)
    bufs.asInstanceOf[RDD[(K, Iterable[V])]]
  }
```
可以看出 `groupBy` 也是调用 `combineByKeyWithClassTag`，只不过 `createCombiner`、`mergeValue`、`mergeCombiners` 不是自定义的。
```scala
val createCombiner = (v: V) => CompactBuffer(v)
```
`groupByKey` 的 `createCombiner` 是创建一个 `buffer`，这个 `buffer` 采用数组存储

`mergeValue` 则是将值加入数组

`mergeCombiners` 就将两个数组合并

注意 `groupByKey` 调用 `combineByKeyWithClassTag` 时传入的 `mapSideCombine` 为 `false` 表示不进行预聚合，即 `mergeValue` 不是发生在 `shuffle` 前
![](https://databricks.gitbooks.io/databricks-spark-knowledge-base/content/images/group_by.png)
<center style="font-size:14px;color:#C0C0C0;text-decoration:underline">图片来自：https://databricks.gitbooks.io</center>

### reduceByKey
再看看 `reduceByKey` 的实现，`reduceByKey` 也有一个兄弟叫 `reduce`，不过 `reduce` 没有调用 `reduceByKey`，而是使用的 `reduceLeft`。直接上 `reduceByKey` 的代码
```scala
def reduceByKey(func: (V, V) => V): RDD[(K, V)] = self.withScope {
    reduceByKey(defaultPartitioner(self), func)
  }
  
def reduceByKey(partitioner: Partitioner, func: (V, V) => V): RDD[(K, V)] = self.withScope {
    combineByKeyWithClassTag[V]((v: V) => v, func, func, partitioner)
  }
```
`reduceByKey` 最终也是调用 `combineByKeyWithClassTag`，只不过 `mergeValue` 和 `mergeCombiners` 都使用我们自定义的一个函数，不过需要注意这个函数 `func: (V, V) => V`，这个函数要求输入的两个参数类型必须一致且返回的类型和输入类型一致，所以一般将输入的两个参数进行聚合再返回。所以聚合后我们得到的是 `k -> v` 。所以在分布式环境下进行 `mergeCombiners` 时可以使用和 `mergeValue` 同一个函数即可。


![](https://databricks.gitbooks.io/databricks-spark-knowledge-base/content/images/reduce_by.png)
<center style="font-size:14px;color:#C0C0C0;text-decoration:underline">图片来自：https://databricks.gitbooks.io</center> 

从上面图中可以看出，`groupByKey` 在 `shuffle` 前是不进行预聚合的，而 `reduceBykey` 则是将 key 相同的数据聚合成一个，图中只是最简单的场景，生产环境中场景更加复杂，数据量大得多，所以在数据量相同的情况，`groupByKey` 的性能必然要比 `reduceByKey` 更差。

### aggregateByKey
先看代码
```scala
def aggregateByKey[U: ClassTag](zeroValue: U)(seqOp: (U, V) => U,
      combOp: (U, U) => U): RDD[(K, U)] = self.withScope {
    aggregateByKey(zeroValue, defaultPartitioner(self))(seqOp, combOp)
 }
  
def aggregateByKey[U: ClassTag](zeroValue: U, partitioner: Partitioner)(seqOp: (U, V) => U,
      combOp: (U, U) => U): RDD[(K, U)] = self.withScope {
      
   // 省略几行...
    val createZero = () => cachedSerializer.deserialize[U](ByteBuffer.wrap(zeroArray))

    // We will clean the combiner closure later in `combineByKey`
    val cleanedSeqOp = self.context.clean(seqOp)
    combineByKeyWithClassTag[U]((v: V) => cleanedSeqOp(createZero(), v),
      cleanedSeqOp, combOp, partitioner)
 }
```
  `aggregateByKey` 也有三个参数：

  `zeroValue` ：‘零值’，聚合之前的初始值，必须是可变的，每一个分区中的每一个 key 都有一个初始值
  `seqOp`：将 V 聚合进 U 的操作，作用于同一个分区里
  `combOp`：将两个 U 合并的操作，作用于不同分区之间

  `aggregateByKey` 和 `combineByKey` 非常相似，重点关注 `combineByKeyWithClassTag[U]((v: V) => cleanedSeqOp(createZero(), v),
      cleanedSeqOp, combOp, partitioner)` 发现 `createCombiner` 和 `mergeValue` 使用的是统一个函数，只不过 `createCombiner` 时传入了零值。所以当 `createCombiner` 和 `mergeValue` 操作一样时优先使用 `aggregateByKey`

  ### foldByKey
  show code
  ```scala
    def foldByKey(
      zeroValue: V,
      partitioner: Partitioner)(func: (V, V) => V): RDD[(K, V)] = self.withScope {
    
    // 省略几行...
    val createZero = () => cachedSerializer.deserialize[V](ByteBuffer.wrap(zeroArray))

    val cleanedFunc = self.context.clean(func)
    combineByKeyWithClassTag[V]((v: V) => cleanedFunc(createZero(), v),
      cleanedFunc, cleanedFunc, partitioner)
  }
  ```
  这个 `foldByKey` 相较于 `aggregateByKey` combine 的三个参数都使用一个函数，即 `crateCombiner`、`mergeValue`、`mergeCombiners` 都相同，只不过 `crateCombiner` 使用了零值
  ### 进阶版
  `combineByKey`
  ```scala
    def combineByKey[C](
      createCombiner: V => C,
      mergeValue: (C, V) => C,
      mergeCombiners: (C, C) => C,
      numPartitions: Int): RDD[(K, C)] = self.withScope {
    combineByKeyWithClassTag(createCombiner, mergeValue, mergeCombiners, numPartitions)(null)
  }
  
    def combineByKey[C](
      createCombiner: V => C,
      mergeValue: (C, V) => C,
      mergeCombiners: (C, C) => C,
      partitioner: Partitioner,
      mapSideCombine: Boolean = true,
      serializer: Serializer = null): RDD[(K, C)] = self.withScope {
    combineByKeyWithClassTag(createCombiner, mergeValue, mergeCombiners,
      partitioner, mapSideCombine, serializer)(null)
  }
  ```
  这两个进阶版的 `combineByKey` 比普通版的 `combineByKey` 分别多了可以指定分区数的
 `numPartitions` 参数和指定分区器的 `Partitioner` 参数，其它都一致。如果不指定分区器，则使用 `self` 即调用者的分区器类型

`groupByKey`、`reduceByKey` 和 `aggregateByKey` 的进阶版也一样，都只是增加了指定分区数和分区器的参数。

#### countByKey
`countByKey` 顾名思义，能根据 `key` 计数，看看源码
```scala
  def countByKey(): Map[K, Long] = self.withScope {
    self.mapValues(_ => 1L).reduceByKey(_ + _).collect().toMap
  }
```
`countByKey` 使用的就是 `reduceByKey`

#### countApproxDistinctByKey
统计每个 `key` 下去重后的近似值，可以根据 `relativeSD` 参数设置相对精度，默认值是 0.05，但必须大于 0.000017。`countApproxDistinctByKey` 底层采用 `HyperLogLog` 统计
```scala
  def countApproxDistinctByKey(relativeSD: Double = 0.05): RDD[(K, Long)] = self.withScope {
    countApproxDistinctByKey(relativeSD, defaultPartitioner(self))
  }
  
    def countApproxDistinctByKey(
      relativeSD: Double,
      partitioner: Partitioner): RDD[(K, Long)] = self.withScope {
    require(relativeSD > 0.000017, s"accuracy ($relativeSD) must be greater than 0.000017")
    val p = math.ceil(2.0 * math.log(1.054 / relativeSD) / math.log(2)).toInt
    assert(p <= 32)
    countApproxDistinctByKey(if (p < 4) 4 else p, 0, partitioner)
  }
```

 ### 总结
 `combineByKey`、`groupByKey`、`reduceBykey`、`aggregateByKey`、`foldByKey` 这几个算子都是基于 `combineByKeyWithClassTag`，而 `combineByKeyWithClassTag` 的核心参数就三个，分别是 `crateCombiner`、`mergeValue`、`mergeCombiners`。

 五个算子的主要区别：`combinerByKey` 和 `aggregateByKey` 输入输出类型可以不一致，而 `reduceByKey` 和 `foldByKey` 要求输入和输出参数一致，`groupByKey` 就不是聚合算子，只能算分组算子，且性能最差，因为会 `shuffle` 所有值。

 当 `crateCombiner` 和 `mergeValue` 是一样的操作时可以选用 `aggregateByKey`，而 `createCombiner`、`mergeValue` 和 `mergeCombiners` 都一样时，可以选用 `foldByKey`
，根据需要各取所需即可。

 ### 参考文章
 [结合Spark源码分析, combineByKey, aggregateByKey, foldByKey, reduceByKey](https://blog.csdn.net/wo334499/article/details/51689587)

 [Avoid GroupByKey](https://databricks.gitbooks.io/databricks-spark-knowledge-base/content/best_practices/prefer_reducebykey_over_groupbykey.html)