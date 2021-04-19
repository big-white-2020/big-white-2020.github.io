---
title : Spark DataFrame 自增 ID
date : 2021-04-19 12:42:25
tag : [Spark, DataFrame]
---

Spark 添加一列自增 ID 有两种方式，一种是通过 Spark SQL 的窗口函数，另一种是通过 RDD 的 `zipWithIndex` 算子。

案例：

```scala
val seq = Range(1, 100, 2)
        val dataFrame = seq.toDF("index")
        dataFrame.show(10)`
```

输出：

```
+-----+
|index|
+-----+
|    1|
|    3|
|    5|
|    7|
|    9|
|   11|
|   13|
|   15|
|   17|
|   19|
+-----+
```

窗口函数方式：

```scala
val spec = Window.partitionBy().orderBy("index")
dataFrame.withColumn("id", row_number().over(spec)).show(10)
```

输出：

```
+-----+---+
|index| id|
+-----+---+
|    1|  1|
|    3|  2|
|    5|  3|
|    7|  4|
|    9|  5|
|   11|  6|
|   13|  7|
|   15|  8|
|   17|  9|
|   19| 10|
+-----+---+
```



`zipWithIndex` 算子方式：

```scala
dataFrame.rdd.zipWithIndex()
	.map{case(x, y) => (x, y + 1)}
	.take(10)
	.map(println)
```

 输出：

```
([1],1)
([3],2)
([5],3)
([7],4)
([9],5)
([11],6)
([13],7)
([15],8)
([17],9)
([19],10)
```

上面 `.map{case(x, y) => (x, y + 1)}` 的作用是让 id 初始值为 1

