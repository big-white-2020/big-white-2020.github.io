---

title : Spark repartition vs coalesce

date : 2021-06-15 18:00:00

tag : [大数据, Spark]

---



在平时经常需要对 RDD 重新分区，或增加分区以提高并行度，或减少分区写文件以减少小文件数量，对 RDD 的分区数量操作有 `repartition` 和 `coalesce` 两个算子

## repartition

`repartition` 算子会返回一个指定分区数的新 `RDD`，可以用来增加或者减小分区数量以调整 `RDD` 的并行度。不过这种增加和减小分区数量是以 `shuffle` 为代价换来的。

```
  def repartition(numPartitions: Int)(implicit ord: Ordering[T] = null): RDD[T] = withScope {
    coalesce(numPartitions, shuffle = true)
  }
```

`repartition` 的代码很简单，接受一个分区数参数，然后调用 `coalesce` 方法

## coalesce

`coalesce` 有两种模式，分别是 `shuffle` 和非 `shuffle` 模式，从 `repartition` 调用的是 `shuffle` 模式，这一点从参数可以看出来。

```
def coalesce(numPartitions: Int, shuffle: Boolean = false,
               partitionCoalescer: Option[PartitionCoalescer] = Option.empty)
              (implicit ord: Ordering[T] = null)
      : RDD[T] = withScope {
    if (shuffle) {
      /** Distributes elements evenly across output partitions, starting from a random partition. */
      val distributePartition = (index: Int, items: Iterator[T]) => {
        var position = new Random(hashing.byteswap32(index)).nextInt(numPartitions)
        items.map { t =>
          // Note that the hash code of the key will just be the key itself. The HashPartitioner
          // will mod it with the number of total partitions.
          position = position + 1
          (position, t)
        }
      } : Iterator[(Int, T)]

      // include a shuffle step so that our upstream tasks are still distributed
      new CoalescedRDD(
        new ShuffledRDD[Int, T, T](
          mapPartitionsWithIndexInternal(distributePartition, isOrderSensitive = true),
          new HashPartitioner(numPartitions)),
        numPartitions,
        partitionCoalescer).values
    } else {
      new CoalescedRDD(this, numPartitions, partitionCoalescer)
    }
  }
```

如果 `shuffle` 参数为 `true` 则会将一个 `ShuffledRDD` 封装进 `CoalescedRDD`。如果 `shuffle` 参数为 `false(默认)` 则创建一个 `CoalescedRDD` 对象。主要看看非 `shuffle` 模式

`coalesce` 的非 `shuffle` 模式只能用来减少分区，例如有 1000 个分区，可用用 `coalesce(100)` 减少至 100 个分区，并且不会 `shuffle`；如果传入的参数比现在的分区数量多，则不会有任何效果，如果要添加分区数量可以使用 `repartition` 或者使用 `coalesce` 时 `shuffle` 参数传入 `false`。

### 原理

主要原理就是将多个 `partition` 划分成一个个 `partitionGroup`，例如前面的例子，有 1000 个分区，需要减少至 100 个分区，那么就会创建 100 个 `partitionGroup`，每个 `partitionGroup` 都有 10 个 `partition`，相当于将 1000 个分区分成 100 组，每组有 10 个分区，而一个 `partitionGroup` 则作为 `CoalescedRDD` 的一个分区。

```
class PartitionGroup(val prefLoc: Option[String] = None) {
  val partitions = mutable.ArrayBuffer[Partition]()
  def numPartitions: Int = partitions.size
}
```

重点看下 `getPartitions` 和 `compute` 方法

```
  override def getPartitions: Array[Partition] = {
    val pc = partitionCoalescer.getOrElse(new DefaultPartitionCoalescer())

    pc.coalesce(maxPartitions, prev).zipWithIndex.map {
      case (pg, i) =>
        val ids = pg.partitions.map(_.index).toArray
        CoalescedRDDPartition(i, prev, ids, pg.prefLoc)
    }
  }
```

这里会使用 `DefaultPartitionCoalescer` 进行 `coalesce`，然后封装到 `CoalescedRDDPartition` 中，这样一个 `partitionGroup` 就封装成一个 `partition` 了 再看下 `DefaultPartitionCoalescer` 的 `coalesce`

```
  def coalesce(maxPartitions: Int, prev: RDD[_]): Array[PartitionGroup] = {
    val partitionLocs = new PartitionLocations(prev)
    // setup the groups (bins)
    setupGroups(math.min(prev.partitions.length, maxPartitions), partitionLocs)
    // assign partitions (balls) to each group (bins)
    throwBalls(maxPartitions, prev, balanceSlack, partitionLocs)
    getPartitions
  }
```

通过 `setupGroups` 和 `throwBalls` 两个方法之后，会将 `dependencesRDD` 尽可能按 `preferredLocation` 划分好分组，放入 `val groupArr = ArrayBuffer[PartitionGroup]()` 中，最后调用 `DefaultPartitionCoalescer` 的 `getPartitions` 返回 `PartitionsGroup` 数组

```
def getPartitions: Array[PartitionGroup] = groupArr.filter( pg => pg.numPartitions > 0).toArray
```

再来看下 `compute` 方法

```
  override def compute(partition: Partition, context: TaskContext): Iterator[T] = {
    partition.asInstanceOf[CoalescedRDDPartition].parents.iterator.flatMap { parentPartition =>
      firstParent[T].iterator(parentPartition, context)
    }
  }
```

`compute` 中的 `Partition` 就是一个 `PartitionGroup`，`compute` 迭代一个 `partition` 就是迭代一个 `partitionGroup` 也就是上游的一组 `partition`，以此来达到减少分区的作用

## 总结

`repartition` 算子既可以增加分区数量也可以减少分区数量，但代价是会造成 `shuffle`，所以如果是减少分区操作可以使用 `coalesce` 算子。使用 `coalesce` 算子时，如果 `shuffle` 参数为 `false(默认)` 则只能减少分区数量，如果 `shuffle` 参数为 `true` 则可以增加或减少分数数，相当于 `repartition` 算子。

```
coalesce` 的主要原理为将分区划分为一个个的分组（`partitionGroup`），一个分组(`partitionGroup`) 由上游一个或多个 `partition` 组成，`coalesce` 里的 `partition` 就是一个 `partitionGroup` 所以在 `coalesce` 迭代一个 `partition` 就相当于迭代上游多个 `partition
```

## 参考文章

[浪尖说spark的coalesce的利弊及原理](https://blog.csdn.net/rlnLo2pNEfx9c/article/details/105283012)

[Spark RDD之Partition](https://blog.csdn.net/u011564172/article/details/53611109)