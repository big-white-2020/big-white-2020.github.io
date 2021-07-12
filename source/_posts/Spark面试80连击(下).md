---
title : Spark面试80连击(下)
date : 2021-07-12 12:55:00
tag : [Spark, 大数据]
---



### **Spark的UDF?**

因为目前 Spark SQL 本身支持的函数有限，一些常用的函数都没有，比如 len, concat...etc 但是使用 UDF 来自己实现根据业务需要的功能是非常方便的。Spark SQL UDF 其实是一个 Scala 函数，被 catalyst 封装成一个 Expression 结点，最后通过 eval 方法计根据当前 Row 计算 UDF 的结果。UDF 对表中的单行进行转换，以便为每行生成单个对应的输出值。例如，大多数 SQL 环境提供 UPPER 函数返回作为输入提供的字符串的大写版本。

用户自定义函数可以在 Spark SQL 中定义和注册为 UDF，并且可以关联别名，这个别名可以在后面的 SQL 查询中使用。作为一个简单的示例，我们将定义一个 UDF 来将以下 JSON 数据中的温度从摄氏度（degrees Celsius）转换为华氏度（degrees Fahrenheit）。

```javascript
{"city":"St. John's","avgHigh":8.7,"avgLow":0.6}
{"city":"Charlottetown","avgHigh":9.7,"avgLow":0.9}
{"city":"Halifax","avgHigh":11.0,"avgLow":1.6}
{"city":"Fredericton","avgHigh":11.2,"avgLow":-0.5}
{"city":"Quebec","avgHigh":9.0,"avgLow":-1.0}
{"city":"Montreal","avgHigh":11.1,"avgLow":1.4}
...
```

以下示例代码使用 SQL 别名为 CTOF 来注册我们的转换 UDF，然后在 SQL 查询使用它来转换每个城市的温度。为简洁起见，省略了 SQLContext 对象和其他代码的创建，每段代码下面都提供了完整的代码链接。

```javascript
# Python
df = sqlContext.read.json("temperatures.json")

df.registerTempTable("citytemps")
# Register the UDF with our SQLContext

sqlContext.registerFunction("CTOF", lambda degreesCelsius: ((degreesCelsius * 9.0 / 5.0) + 32.0))
sqlContext.sql("SELECT city, CTOF(avgLow) AS avgLowF, CTOF(avgHigh) AS avgHighF FROM citytemps").show()
# Scala
val df = sqlContext.read.json("temperatures.json")

df.registerTempTable("citytemps")
// Register the UDF with our SQLContext

sqlContext.udf.register("CTOF", (degreesCelcius: Double) => ((degreesCelcius * 9.0 / 5.0) + 32.0))
sqlContext.sql("SELECT city, CTOF(avgLow) AS avgLowF, CTOF(avgHigh) AS avgHighF FROM citytemps").show()
# Java
DataFrame df = sqlContext.read().json("temperatures.json");
df.registerTempTable("citytemps");

// Register the UDF with our SQLContext
sqlContext.udf().register("CTOF", new UDF1<Double, Double>() {
  @Override
  public Double call(Double degreesCelcius) {
    return ((degreesCelcius * 9.0 / 5.0) + 32.0);
  }
}, DataTypes.DoubleType);
sqlContext.sql("SELECT city, CTOF(avgLow) AS avgLowF, CTOF(avgHigh) AS avgHighF FROM citytemps").show();
```

注意，Spark SQL 定义了 UDF1 到 UDF22 共22个类，UDF 最多支持22个输入参数。上面的例子中使用 UDF1 来处理我们单个温度值作为输入。如果我们不想修改 Apache Spark 的源代码，对于需要超过22个输出参数的应用程序我们可以使用数组或结构作为参数来解决这个问题，如果你发现自己用了 UDF6 或者更高 UDF 类你可以考虑这样操作。

用户定义的聚合函数（User-defined aggregate functions, UDAF）同时处理多行，并且返回一个结果，通常结合使用 GROUP BY 语句（例如 COUNT 或 SUM）。为了简单起见，我们将实现一个叫 SUMPRODUCT 的 UDAF 来计算以库存来分组的所有车辆零售价值，具体的数据如下：

```javascript
{"Make":"Honda","Model":"Pilot","RetailValue":32145.0,"Stock":4}
{"Make":"Honda","Model":"Civic","RetailValue":19575.0,"Stock":11}
{"Make":"Honda","Model":"Ridgeline","RetailValue":42870.0,"Stock":2}
{"Make":"Jeep","Model":"Cherokee","RetailValue":23595.0,"Stock":13}
{"Make":"Jeep","Model":"Wrangler","RetailValue":27895.0,"Stock":4}
{"Make":"Volkswagen","Model":"Passat","RetailValue":22440.0,"Stock":2}
```

Apache Spark UDAF 目前只支持在 Scala 和 Java 中通过扩展 UserDefinedAggregateFunction 类使用。下面例子中我们定义了一个名为 SumProductAggregateFunction 的类，并且为它取了一个名为 SUMPRODUCT 的别名，现在我们可以在 SQL 查询中初始化并注册它，和上面的 CTOF UDF 的操作步骤很类似，如下：

```javascript
object ScalaUDAFExample {

  // Define the SparkSQL UDAF logic
  private class SumProductAggregateFunction extends UserDefinedAggregateFunction {
    // Define the UDAF input and result schema's
    def inputSchema: StructType =     // Input  = (Double price, Long quantity)
      new StructType().add("price", DoubleType).add("quantity", LongType)
    def bufferSchema: StructType =    // Output = (Double total)
      new StructType().add("total", DoubleType)
    def dataType: DataType = DoubleType
    def deterministic: Boolean = true // true: our UDAF's output given an input is deterministic

    def initialize(buffer: MutableAggregationBuffer): Unit = {
      buffer.update(0, 0.0)           // Initialize the result to 0.0
    }

    def update(buffer: MutableAggregationBuffer, input: Row): Unit = {
      val sum   = buffer.getDouble(0) // Intermediate result to be updated
      val price = input.getDouble(0)  // First input parameter
      val qty   = input.getLong(1)    // Second input parameter
      buffer.update(0, sum + (price * qty))   // Update the intermediate result
    }
    // Merge intermediate result sums by adding them
    def merge(buffer1: MutableAggregationBuffer, buffer2: Row): Unit = {
      buffer1.update(0, buffer1.getDouble(0) + buffer2.getDouble(0))
    }
    // THe final result will be contained in 'buffer'
    def evaluate(buffer: Row): Any = {
      buffer.getDouble(0)
    }
  }

  def main (args: Array[String]) {
    val conf       = new SparkConf().setAppName("Scala UDAF Example")
    val sc         = new SparkContext(conf)
    val sqlContext = new SQLContext(sc)

    val testDF = sqlContext.read.json("inventory.json")
    testDF.registerTempTable("inventory")
    // Register the UDAF with our SQLContext
    sqlContext.udf.register("SUMPRODUCT", new SumProductAggregateFunction)

    sqlContext.sql("SELECT Make, SUMPRODUCT(RetailValue,Stock) AS InventoryValuePerMake FROM inventory GROUP BY Make").show()
  }
}
```

Apache Spark 中的其他 UDF 支持，Spark SQL 支持集成现有 Hive 中的 UDF，UDAF 和 UDTF 的（Java或Scala）实现。UDTFs（user-defined table functions, 用户定义的表函数）可以返回多列和多行 - 它们超出了本文的讨论范围，我们可能会在以后进行说明。集成现有的 Hive UDF 是非常有意义的，我们不需要向上面一样重新实现和注册他们。Hive 定义好的函数可以通过 HiveContext 来使用，不过我们需要通过 spark-submit 的 –jars 选项来指定包含 HIVE UDF 实现的 jar 包，然后通过 CREATE TEMPORARY FUNCTION 语句来定义函数，如下：

```javascript
# Hive UDF definition in Java
package com.cloudera.fce.curtis.sparkudfexamples.hiveudf;

import org.apache.hadoop.hive.ql.exec.UDF;

public class CTOF extends UDF {
  public Double evaluate(Double degreesCelsius) {
    return ((degreesCelsius * 9.0 / 5.0) + 32.0);
  }
}
# 在 Python 中使用 Hive UDF
df = sqlContext.read.json("temperatures.json")
df.registerTempTable("citytemps")

# Register our Hive UDF
sqlContext.sql("CREATE TEMPORARY FUNCTION CTOF AS 'com.cloudera.fce.curtis.sparkudfexamples.hiveudf.CTOF'")

sqlContext.sql("SELECT city, CTOF(avgLow) AS avgLowF, CTOF(avgHigh) AS avgHighF FROM citytemps").show()
```

注意，Hive UDF 只能使用 Apache Spark 的 SQL 查询语言来调用 - 换句话说，它们不能与 Dataframe API 的领域特定语言（domain-specific-language, DSL）一起使用。

另外，通过包含实现 jar 文件（在 spark-submit 中使用 -jars 选项）的方式 PySpark 可以调用 Scala 或 Java 编写的 UDF（through the SparkContext object’s private reference to the executor JVM and underlying Scala or Java UDF implementations that are loaded from the jar file）。下面的示例演示了如何使用先前 Scala 中定义的 SUMPRODUCT UDAF：

```javascript
# Scala UDAF definition
object ScalaUDAFFromPythonExample {
  // … UDAF as defined in our example earlier ...
}

  // This function is called from PySpark to register our UDAF
  def registerUdf(sqlCtx: SQLContext) {
    sqlCtx.udf.register("SUMPRODUCT", new SumProductAggregateFunction)
  }
}
# Scala UDAF from PySpark
df = sqlContext.read.json("inventory.json")
df.registerTempTable("inventory")

scala_sql_context  =  sqlContext._ssql_ctx
scala_spark_context = sqlContext._sc
scala_spark_context._jvm.com.cloudera.fce.curtis.sparkudfexamples.scalaudaffrompython.ScalaUDAFFromPythonExample.registerUdf(scala_sql_context)

sqlContext.sql("SELECT Make, SUMPRODUCT(RetailValue,Stock) AS InventoryValuePerMake FROM inventory GROUP BY Make").show()
```

每个版本的 Apache Spark 都在不断地添加与 UDF 相关的功能，比如在 2.0 中 R 增加了对 UDF 的支持。作为参考，下面的表格总结了本博客中讨论特性版本：

了解 Apache Spark UDF 功能的性能影响很重要。例如，Python UDF（比如上面的 CTOF 函数）会导致数据在执行器的 JVM 和运行 UDF 逻辑的 Python 解释器之间进行序列化操作；与 Java 或 Scala 中的 UDF 实现相比，大大降低了性能。缓解这种序列化瓶颈的解决方案如下：

- 从 PySpark 访问 Hive UDF。Java UDF 实现可以由执行器 JVM 直接访问。
- 在 PySpark 中访问在 Java 或 Scala 中实现的 UDF 的方法。正如上面的 Scala UDAF 实例。

参考：https://my.oschina.net/cloudcoder/blog/640009

### **Mesos下粗粒度和细粒度对比?**

1. 粗粒度运行模式: Spark 应用程序在注册到 Mesos 时会分配对应系统资源，在执行过程中由 SparkContext 和 Executor 直接交互，该模式优点是由于资源长期持有减少了资源调度的时间开销，缺点是该模式下 Mesos 无法感知资源使用的变化，容易造成系统资源的闲置，无法被 Mesos 其他框架使用，造成资源浪费。
2. 细粒度的运行模式: Spark 应用程序是以单个任务的粒度发送到 Mesos 中执行，在执行过程中 SparkContext 并不能和 Executor 直接交互，而是由 Mesos Master 进行统一的调度管理，这样能够根据整个 Mesos 集群资源使用的情况动态调整。该模式的优点是系统资源能够得到充分利用，缺点是该模式中每个人物都需要从 Mesos 获取资源，调度延迟较大，对于 Mesos Master 开销较大。

### **Spark Local和Standalone有什么区别**

Spark一共有5种运行模式：Local，Standalone，Yarn-Cluster，Yarn-Client 和 Mesos。

1. Local: Local 模式即单机模式，如果在命令语句中不加任何配置，则默认是 Local 模式，在本地运行。这也是部署、设置最简单的一种模式，所有的 Spark 进程都运行在一台机器或一个虚拟机上面。
2. Standalone: Standalone 是 Spark 自身实现的资源调度框架。如果我们只使用 Spark 进行大数据计算，不使用其他的计算框架（如MapReduce或者Storm）时，就采用 Standalone 模式就够了，尤其是单用户的情况下。Standalone 模式是 Spark 实现的资源调度框架，其主要的节点有 Client 节点、Master 节点和 Worker 节点。其中 Driver 既可以运行在 Master 节点上中，也可以运行在本地 Client 端。当用 spark-shell 交互式工具提交 Spark 的 Job 时，Driver 在 Master 节点上运行；当使用 spark-submit 工具提交 Job 或者在 Eclipse、IDEA 等开发平台上使用 `new SparkConf.setManager(“spark://master:7077”)` 方式运行 Spark 任务时，Driver 是运行在本地 Client 端上的。

Standalone 模式的部署比较繁琐，需要把 Spark 的部署包安装到每一台节点机器上，并且部署的目录也必须相同，而且需要 Master 节点和其他节点实现 SSH 无密码登录。启动时，需要先启动 Spark 的 Master 和 Slave 节点。提交命令类似于:

```javascript
./bin/spark-submit \
  --class org.apache.spark.examples.SparkPi \
  --master spark://Oscar-2.local:7077 \
  /tmp/spark-2.2.0-bin-hadoop2.7/examples/jars/spark-examples_2.11-2.2.0.jar \
  100
```

其中 master:7077是 Spark 的 Master 节点的主机名和端口号。当然集群是需要提前启动。

### **说说SparkContext和SparkSession有什么区别?**

1. Application: 用户编写的 Spark 应用程序，Driver 即运行上述 Application 的 main() 函数并且创建 SparkContext。Application 也叫应用。
2. SparkContext: 整个应用的上下文，控制应用的生命周期。
3. RDD: 不可变的数据集合，可由 SparkContext 创建，是 Spark 的基本计算单元。
4. SparkSession: 可以由上节图中看出，Application、SparkSession、SparkContext、RDD之间具有包含关系，并且前三者是1对1的关系。SparkSession 是 Spark 2.0 版本引入的新入口，在这之前，创建一个 Application 对应的上下文是这样的：

```javascript
//set up the spark configuration and create contexts
val sparkConf = new SparkConf().setAppName("SparkSessionZipsExample").setMaster("local")
// your handle to SparkContext to access other context like SQLContext
val sc = new SparkContext(sparkConf).set("spark.some.config.option", "some-value")
val sqlContext = new org.apache.spark.sql.SQLContext(sc)
```

现在 SparkConf、SparkContext 和 SQLContext 都已经被封装在 SparkSession 当中，并且可以通过 builder 的方式创建：

```javascript
// Create a SparkSession. No need to create SparkContext
// You automatically get it as part of the SparkSession
val warehouseLocation = "file:${system:user.dir}/spark-warehouse"
val spark = SparkSession
   .builder()
   .appName("SparkSessionZipsExample")
   .config("spark.sql.warehouse.dir", warehouseLocation)
   .enableHiveSupport()
   .getOrCreate()
```

通过 SparkSession 创建并操作 Dataset 和 DataFrame，代码中的 spark 对象就是 SparkSession:

```javascript
//create a Dataset using spark.range starting from 5 to 100, with increments of 5
val numDS = spark.range(5, 100, 5)
// reverse the order and display first 5 items
numDS.orderBy(desc("id")).show(5)
//compute descriptive stats and display them
numDs.describe().show()
// create a DataFrame using spark.createDataFrame from a List or Seq
val langPercentDF = spark.createDataFrame(List(("Scala", 35), ("Python", 30), ("R", 15), ("Java", 20)))
//rename the columns
val lpDF = langPercentDF.withColumnRenamed("_1", "language").withColumnRenamed("_2", "percent")
//order the DataFrame in descending order of percentage
lpDF.orderBy(desc("percent")).show(false)
```

![650](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/2021/07/12/b7dcc3d19cd5d8e76d89a03c69b004d4-650-9ba56d.jpeg)

### **如果Spark Streaming停掉了，如何保证Kafka的重新运作是合理的呢**

首先要说一下 Spark 的快速故障恢复机制，在节点出现故障的勤快下，传统流处理系统会在其他节点上重启失败的连续算子，并可能冲洗能运行先前数据流处理操作获取部分丢失数据。在此过程中只有该节点重新处理失败的过程。只有在新节点完成故障前所有计算后，整个系统才能够处理其他任务。在 Spark 中，计算将会分成许多小的任务，保证能在任何节点运行后能够正确合并，因此，就算某个节点出现故障，这个节点的任务将均匀地分散到集群中的节点进行计算，相对于传递故障恢复机制能够更快地恢复。

### **列举Spark中 Transformation 和 Action算子**

Transformantion: Map, Filter, FlatMap, Sample, GroupByKey, ReduceByKey, Union, Join, Cogroup, MapValues, Sort, PartionBy

Action: Collect, Reduce, Lookup, Save （主要记住，结果不是 RDD 的就是 Action）

### **Spark经常说的Repartition是个什么玩意**

简单的说：返回一个恰好有numPartitions个分区的RDD，可以增加或者减少此RDD的并行度。内部，这将使用shuffle重新分布数据，如果你减少分区数，考虑使用coalesce，这样可以避免执行shuffle。目的：

- 避免小文件
- 减少 Task 个数
- 但是会增加每个 Task 处理的数据量

参考：https://blog.csdn.net/dax1n/article/details/53431373

### **Spark Streaming Duration的概念**

Spark Streaming 是微批处理。

```javascript
 SparkConf sparkConf = new SparkConf().setAppName("SparkStreaming").setMaster("local[*]"); 
 JavaStreamingContext javaStreamingContext = new JavaStreamingContext(sparkConf, Durations.seconds(1000));
```

Durations.seconds(1000)设置的是sparkstreaming批处理的时间间隔，每个Batch Duration时间去提交一次job，如果job的处理时间超过Batch Duration，会使得job无法按时提交，随着时间推移，越来越多的作业被拖延，最后导致整个Streaming作业被阻塞，无法做到实时处理数据。

更多的可以阅读一下源码。

### **简单写一个WordCount程序**

```javascript
scala> sc.textFile("/Users/runzhliu/workspace/spark-2.2.1-bin-hadoop2.7/README.md").flatMap(_.split(" ")).map(x => (x, 1)).reduceByKey(_ + _).map(x => (x._2, x._1)).sortByKey(false).map(x => (x._2, x._1)).take(10
res0: Array[(String, Int)] = Array(("",71), (the,24), (to,17), (Spark,16), (for,12), (##,9), (and,9), (a,8), (can,7), (run,7))
```

### **说说Yarn-cluster的运行阶段**

在 Yarn-cluset 模式下，当用户向 Yarn 提交一个应用程序后，Yarn 将两个阶段运行该应用程序:

1. 第一阶段是把 Spark 的 Driver 作为一个 Application Master 在 Yarn 集群中先启动。
2. 第二阶段是由 Application Master 创建应用程序，然后为它向 Resource Manager 申请资源，并启动 Executor 来运行任务集，同时监控它的整个过程，直到运行介绍结束。

### **Mesos粗细度对比**

Mesos 粗粒度运行模式中，Spark 程序在注册到 Mesos 的时候会分配对应系统资源，在执行过程中由 SparkContext 和 Executor 直接进行交互。该模式优点是由于资源长期持有，减少了资源调度的时间开销，缺点是该模式之下，Mesos 无法感知资源使用的变化，容易造成资源的闲置，无法被 Mesos 其他框架所使用，从而造成资源浪费。

而在细粒度运行模式下，Spark 应用程序是以单个任务的粒度发送到 Mesos 中执行，在执行过程中 SparkContext 并不能与 Executor 直接进行交互，而是由 Mesos Master 进行统一的调度管理，这样能够根据整个 Mesos 集群资源使用的情况动态调整。该模式的优点是系统资源能够得到充分利用，缺点是该模式中每个任务都需要从 Mesos 获取资源，调度延迟比较大，对于 Mesos 开销比较大。

### **说说Standalone模式下运行Spark程序的大概流程**

Standalone 模式分别由客户端、Master 节点和 Worker 节点组成。在 Spark Shell 提交计算搜狗日志行数代码的时候，所在机器作为客户端启动应用程序，然后向 Master 注册应用程序，由 Master 通知 Worker 节点启动 Executor，Executor 启动之后向客户端的 Driver 注册，最后由 Driver 发送执行任务给 Executor 并监控任务执行情况。该程序代码中，在触发计算行数动作之前，需要设置缓存代码，这样在执行计算行数行为的时候进行缓存数据，缓存后再运行计算行数。

### **如何区分 Appliction(应用程序)还有 Driver(驱动程序)**

Application 是指用户编写的 Spark 应用程序，包含驱动程序 Driver 和分布在集群中多个节点上运行的 Executor 代码，在执行过程之中由一个或多个做作业组成。

Driver 是 Spark 中的 Driver 即运行上述 Application 的 main 函数并且创建 SparkContext，其中创建 SparkContext 的目的是为了准备 Spark 应用程序的运行环境。在 Spark 中由 sc 负责与 ClusterManager 通信，进行资源的申请，任务的分配和监控等。当 Executor 部分运行完毕后，Driver 负责把 sc 关闭，通常 Driver 会拿 SparkContext 来代表。

### **介绍一下 Spark 通信的启动方式**

Spark 启动过程主要是 Master 与 Worker 之间的通信，首先由 Worker 节点向 Master 发送注册消息，然后 Master 处理完毕后，返回注册成功消息或失败消息，如果成功注册，那么 Worker 就会定时发送心跳消息给 Master。

### **介绍一下 Spark 运行时候的消息通信**

用户提交应用程序时，应用程序的 SparkContext 会向 Master 发送应用注册消息，并由 Master 给该应用分配 Executor，Excecutor 启动之后，Executor 会向 SparkContext 发送注册成功消息。当 SparkContext 的 RDD 触发行动操作之后，将创建 RDD 的 DAG。通过 DAGScheduler 进行划分 Stage 并把 Stage 转化为 TaskSet，接着 TaskScheduler 向注册的 Executor 发送执行消息，Executor 接收到任务消息后启动并运行。最后当所有任务运行时候，由 Driver 处理结果并回收资源。

### **解释一下Stage**

每个作业会因为 RDD 之间的依赖关系拆分成多组任务集合，称为调度阶段，也叫做任务集。调度阶段的划分由 DAGScheduler 划分，调度阶段有 Shuffle Map Stage 和 Result Stage 两种。

### **描述一下Worker异常的情况**

Spark 独立运行模式 Standalone 采用的是 Master/Slave 的结构，其中 Slave 是由 Worker 来担任的，在运行的时候会发送心跳给 Master，让 Master 知道 Worker 的实时状态，另一方面，Master 也会检测注册的 Worker 是否超时，因为在集群运行的过程中，可能由于机器宕机或者进程被杀死等原因造成 Worker 异常退出。

### **描述一下Master异常的情况**

Master 出现异常的时候，会有几种情况，而在独立运行模式 Standalone 中，Spark 支持几种策略，来让 Standby Master 来接管集群。主要配置的地方在于 spark-env.sh 文件中。配置项是 `spark.deploy.recoveryMode` 进行设置，默认是 None。

1. ZOOKEEPER: 集群元数据持久化到 Zookeeper 中，当 Master 出现异常，ZK 通过选举机制选举新的 Master，新的 Master 接管的时候只要从 ZK 获取持久化信息并根据这些信息恢复集群状态。StandBy 的 Master 随时候命的。
2. FILESYSTEM: 集群元数据持久化到本地文件系统中，当 Master 出现异常的时候，只要在该机器上重新启动 Master，启动后新的 Master 获取持久化信息并根据这些信息恢复集群的状态。
3. CUSTOM: 自定义恢复方式，对 StandaloneRecoveryModeFactory 抽象类进行实现并把该类配置到系统中，当 Master 出现异常的时候，会根据用户自定义的方式进行恢复集群状态。
4. NONE: 不持久化集群的元数据，当出现异常的是，新启动 Master 不进行信息恢复集群状态，而是直接接管集群。

### **Spark的存储体系**

![651](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/2021/07/12/00dc8f66afe19aa788607c6257e3585c-651-418b23.png)

简单来讲，Spark存储体系是各个Driver与Executor实例中的BlockManager所组成的；但是从一个整体来看，把各个节点的BlockManager看成存储体系的一部分，那存储体系就有了更多衍生的内容，比如块传输服务、map任务输出跟踪器、Shuffle管理器等。详细可以参考：https://blog.csdn.net/LINBE_blazers/article/details/89048435

### **简述Spark Streaming**

具有高吞吐量和容错能力强的特点，输入源有很多，如 Kafka, Flume, Twitter 等待。

关于流式计算的做法，如果按照传统工具的做法把数据存储到数据库中再进行计算，这样是无法做到实时的，而完全把数据放到内存中计算，万一宕机、断电了，数据也就丢失了。

因此 Spark 流式计算引入了检查点 CheckPoint 和日志，以便能够从中恢复计算结果。而本质上 Spark Streaming 是接收实时输入数据流并把他们按批次划分，然后交给 Spark 计算引擎处理生成按照批次划分的结果流。

### **知道 Hadoop MRv1 的局限吗**

1. 可扩展性查，在运行的时候，JobTracker 既负责资源管理，又负责任务调度，当集群繁忙的时候，JobTracker 很容易成为瓶颈，最终导致可扩展性的问题。
2. 可用性差，采用单节点的 Master 没有备用 Master 以及选举操作，这导致一旦 Master 出现故障，整个集群将不可用。
3. 资源利用率低，TaskTracker 使用 slot 等量划分本节点上的资源量，slot 代表计算资源将各个 TaskTracker 上的空闲 slot 分配给 Task 使用，一些 Task 并不能充分利用 slot，而其他 Task 无法使用这些空闲的资源。有时会因为作业刚刚启动等原因导致 MapTask 很多，而 Reduce Task 任务还没调度的情况，这时 Reduce slot 也会被闲置。
4. 不能支持多种 MapReduce 框架，无法通过可插拔方式将自身的 MapReduce 框架替换为其他实现，例如 Spark，Storm。

### **说说Spark的特点，相对于MR来说**

1. 减少磁盘 I/O，MR 会把 map 端将中间输出和结果存储在磁盘中，reduce 端又需要从磁盘读写中间结果，势必造成磁盘 I/O 称为瓶颈。Spark 允许将 map 端的中间结果输出和结果存储在内存中，reduce 端在拉取中间结果的时候避免了大量的磁盘 I/O。
2. 增加并行度，由于把中间结果写到磁盘与从磁盘读取中间结果属于不同的缓解，Hadoop 将他们简单地通过串行执行衔接起来，Spark 则把不同的环节抽象成为 Stage，允许多个 Stage 既可以串行又可以并行执行。
3. 避免重新计算，当 Stage 中某个分区的 Task 执行失败后，会重新对此 Stage 调度，但在重新调度的时候会过滤已经执行成功的分区任务，所以不会造成重复计算和资源浪费。
4. 可选的 Shuffle 排序，MR 在 Shuffle 之前有着固定的排序操作，而 Spark 则可以根据不同场景选择在 map 端排序还是 reduce 排序。
5. 灵活的内存管理策略，Spark 将内存分为堆上的存储内存、堆外的存储内存，堆上的执行内存，堆外的执行内存4个部分。

### **说说Spark Narrow Dependency的分类**

- OneToOneDependency
- RangeDependency

### **Task和Stage的分类**

Task指具体的执行任务，一个 Job 在每个 Stage 内都会按照 RDD 的 Partition 数量，创建多个 Task，Task 分为 ShuffleMapTask 和 ResultTask 两种。ShuffleMapStage 中的 Task 为 ShuffleMapTask，而 ResultStage 中的 Task 为 ResultTask。ShuffleMapTask 和 ResultTask 类似于 Hadoop 中的 Map 任务和 Reduce 任务。

### **Spark的编程模型**

![652](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/2021/07/12/abb683c88c3acfef2fe623a7bc163e1a-652-5b3ae0.jpeg)

![653](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/2021/07/12/87d7f17bd2a66a131a17ea045bc436c3-653-296ce2.jpeg)

```javascript
import org.apache.spark.{SparkConf, SparkContext}

object WordCount {
  def main (args: Array[String]){
  
    val conf = new SparkConf().setAppName("WordCount")
    val sc = new SparkContext(conf)

    val inputRDD = sc.textFile("README.md")
    val pythonLinesRDD = inputRDD.filter(line => line.contains("Python"))
    val wordsRDD = pythonLinesRDD.flatMap(line => line.split(" "))
    val countsRDD = wordsRDD.map(word => (word, 1)).reduceByKey(_ + _)

    countsRDD.saveAsTextFile("outputFile")
    sc.stop()
  }
}
```

1.创建应用程序 `SparkContext`

2.创建RDD，有两种方式，方式一：输入算子，即读取外部存储创建RDD，Spark与Hadoop完全兼容，所以对Hadoop所支持的文件类型或者数据库类型，Spark同样支持。方式二：从集合创建RDD

3.Transformation 算子，这种变换并不触发提交作业，完成作业中间过程处理。也就是说从一个RDD 转换生成另一个 RDD 的转换操作不是马上执行，需要等到有 Action 操作的时候才会真正触发运算。

4.Action 算子，这类算子会触发 SparkContext 提交 Job 作业。并将数据输出 Spark系统。

5.保存结果

6.关闭应用程序

### **Spark的计算模型**

没有标准答案，可以结合实例讲述。

![654](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/2021/07/12/2a4917e3af611b98c7dc2ef4008f0053-654-3052cd.jpeg)

用户程序对RDD通过多个函数进行操作，将RDD进行转换。

Block-Manager管理RDD的物理分区，每个Block就是节点上对应的一个数据块，可以存储在内存或者磁盘。

而RDD中的partition是一个逻辑数据块，对应相应的物理块Block。

本质上一个RDD在代码中相当于是数据的一个元数据结构，存储着**数据分区**及其**逻辑结构映射关系**，存储着**RDD之前的依赖转换关系**。

### **总述Spark的架构**

从集群部署的角度来看，Spark 集群由集群管理器 Cluster Manager、工作节点 Worker、执行器 Executor、驱动器 Driver、应用程序 Application 等部分组成。

**Cluster Manager:** 主要负责对集群资源的分配和管理，Cluster Manager 在 YARN 部署模式下为 RM，在 Mesos 下为 Mesos Master，Standalone 模式下为 Master。CM 分配的资源属于一级分配，它将各个 Worker 上的内存、CPU 等资源分配给 Application，但是不负责对 Executor 的资源分类。Standalone 模式下的 Master 会直接给 Application 分配内存、CPU 及 Executor 等资源。

**Worker**: Spark 的工作节点。在 YARN 部署模式下实际由 NodeManager 替代。Worker 节点主要负责，把自己的内存、CPU 等资源通过注册机制告知 CM，创建 Executor，把资源和任务进一步分配给 Executor，同步资源信息，Executor 状态信息给 CM 等等。Standalone 部署模式下，Master 将 Worker 上的内存、CPU 以及 Executor 等资源分配给 Application 后，将命令 Worker 启动 CoarseGrainedExecutorBackend 进程（此进程会创建 Executor 实例）。

**Executor**: 执行计算任务的一线组件，主要负责任务的执行及与 Worker Driver 信息同步。

Driver: Application 的驱动程序，Application 通过 Driver 与 CM、Executor 进行通信。Driver 可以运行在 Application 中，也可以由 Application 提交给 CM 并由 CM 安排 Worker 运行。

**Application**: 用户使用 Spark 提供的 API 编写的应用程序，Application 通过 Spark API 将进行 RDD 的转换和 DAG 的创建，并通过 Driver 将 Application 注册到 CM，CM 将会根据 Application 的资源需求，通过一级资源分配将 Excutor、内存、CPU 等资源分配给 Application。Drvier 通过二级资源分配将 Executor 等资源分配给每一个任务，Application 最后通过 Driver 告诉 Executor 运行任务。

### **一句话说说 Spark Streaming 是如何收集和处理数据的**

在 Spark Streaming 中，数据采集是逐条进行的，而数据处理是按批 mini batch进行的，因此 Spark Streaming 会先设置好批处理间隔 batch duration，当超过批处理间隔就会把采集到的数据汇总起来成为一批数据交给系统去处理。

### **解释一下窗口间隔window duration和滑动间隔slide duration**

![655](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/2021/07/12/8a653ca571fe0f920f7f05c83e61d568-655-089282.jpeg)

1. 红色的矩形就是一个窗口，窗口 hold 的是一段时间内的数据流。
2. 这里面每一个 time 都是时间单元，在官方的例子中，每隔 window size 是3 time unit， 而且每隔2个单位时间，窗口会 slide 一次。

所以基于窗口的操作，需要指定2个参数:

> window length - The duration of the window (3 in the figure)slide interval - The interval at which the window-based operation is performed (2 in the figure). 

1. 窗口大小，个人感觉是一段时间内数据的容器。
2. 滑动间隔，就是我们可以理解的 cron 表达式吧。

窗口间隔一般大于（批处理间隔、滑动间隔）。这都是理解窗口操作的关键。

### **介绍一下Spark Streaming的foreachRDD(func)方法**

将函数应用于 DStream 的 RDD 上，这个操作会输出数据到外部系统，比如保存 RDD 到文件或者网络数据库等。需要注意的是 func 函数是运行该 Streaming 应用的 Driver 进程里执行的。

### **简单描述一下Spark Streaming的容错原理**

Spark Streaming 的一个特点就是高容错。

首先 Spark RDD 就有容错机制，每一个 RDD 都是不可变的分布式可重算的数据集，其记录这确定性的操作血统，所以只要输入数据是可容错的，那么任意一个 RDD 的分区出错或不可用，都是可以利用原始输入数据通过转换操作而重新计算出来的。

预写日志通常被用于数据库和文件系统中，保证数据操作的持久性。预写日志通常是先将操作写入到一个持久可靠的日志文件中，然后才对数据施加该操作，当加入施加操作中出现了异常，可以通过读取日志文件并重新施加该操作。

另外接收数据的正确性只在数据被预写到日志以后接收器才会确认，已经缓存但还没保存的数据可以在 Driver 重新启动之后由数据源再发送一次，这两个机制确保了零数据丢失，所有数据或者从日志中恢复，或者由数据源重发。

### **DStream 有几种转换操作**

分为三类，普通的转换操作，窗口操作和输出操作。

参考：https://blog.csdn.net/zhy_2117/article/details/84348553

### **聊聊Spark Streaming的运行架构**

![656](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/2021/07/12/556c72519fcfe9004aaa97476618fa45-656-1e8cc8.jpeg)

### **说说DStreamGraph**

Spark Streaming 中作业生成与 Spark 核心类似，对 DStream 进行的各种操作让它们之间的操作会被记录到名为 DStream 使用输出操作时，这些依赖关系以及它们之间的操作会被记录到明伟 DStreamGraph 的对象中表示一个作业。这些作业注册到 DStreamGraph 并不会立即运行，而是等到 Spark Streaming 启动之后，达到批处理时间，才根据 DG 生成作业处理该批处理时间内接收的数据。

### **创建RDD的方式以及如何继承创建RDD**

参考：https://blog.csdn.net/a1043498776/article/details/54891946

### **分析一下Spark Streaming的transform()和updateStateByKey()两个操作**

- transform(func) 操作: 允许 DStream 任意的 RDD-to-RDD 函数。
- updateStateByKey 操作: 可以保持任意状态，同时进行信息更新，先定义状态，后定义状态更新函数。

### **说说Spark Streaming的输出操作**

其实就几个，比如 print(), saveAsTextFiles, foreachRDD 等等。

### **谈谈Spark Streaming Driver端重启会发生什么**

1. 恢复计算: 使用检查点信息重启 Driver 端，重构上下文并重启接收器
2. 恢复元数据块: 为了保证能够继续下去所必备的全部元数据块都被恢复
3. 未完成作业的重新形成: 由于失败而没有处理完成的批处理，将使用恢复的元数据再次产生 RDD 和对应的作业
4. 读取保存在日志中的块数据: 在这些作业执行的时候，块数据直接从预写日志中读出，这将恢复在日志中可靠地保存所有必要的数据
5. 重发尚未确认的数据: 失败时没有保存到日志中的缓存数据将由数据源再次发送

### **再谈Spark Streaming的容错性**

实时流处理系统需要长时间接收并处理数据，这个过程中出现异常是难以避免的，需要流程系统具备高容错性。Spark Streaming 一开始就考虑了两个方面。

1. 利用 Spark 自身的容错设计、存储级别和 RDD 抽象设计能够处理集群中任何 Worker 节点的故障
2. Spark 运行多种运行模式，其 Driver 端可能运行在 Master 节点或者集群中的任意节点，这样让 Driver 端具备容错能力是很大的挑战，但是由于其接收的数据是按照批进行存储和处理，这些批次数据的元数据可以通过执行检查点的方式定期写入到可靠的存储中，在 Driver 端重新启动中恢复这些状态

当接收到的数据缓存在 Executor 内存中的丢失风险要怎么处理呢？

如果是独立运行模式/Yarn/Mesos 模式，当 Driver 端失败的时候，该 Driver 端所管理的 Executor 以及内存中数据将终止，即时 Driver 端重新启动这些缓存的数据也不能被恢复。为了避免这种数据损失，就需要预写日志功能了。

当 Spark Streaming 应用开始的时候，也就是 Driver 开始的时候，接收器成为长驻运行任务，这些接收器接收并保存流数据到 Spark 内存以供处理。

1. 接收器将数据分成一系列小块，存储到 Executor 内存或磁盘中，如果启动预写日志，数据同时还写入到容错文件系统的预写日志文件。
2. 通知 StreamingContext，接收块中的元数据被发送到 Driver 的 StreamingContext，这个元数据包括两种，一是定位其 Executor 内存或磁盘中数据位置的块编号，二是块数据在日志中的偏移信息（如果启用 WAL 的话）。

### **流数据如何存储**

作为流数据接收器调用 Receiver.store 方式进行数据存储，该方法有多个重载方法，如果数据量很小，则攒多条数据成数据块再进行块存储，如果数据量大，则直接进行块存储。

### **StreamingContext启动时序图吗**

1. 初始化 StreamingContext 中的 DStreamGraph 和 JobScheduler，进而启动 JobScheduler 的 ReceiveTracker 和 JobGenerator。
2. 初始化阶段会进行成员变量的初始化，重要的包括 DStreamGraph（包含 DStream 之间相互依赖的有向无环图），JobScheduler（定时查看 DStreamGraph，然后根据流入的数据生成运行作业），StreamingTab（在 Spark Streaming 运行的时候对流数据处理的监控）。
3. 然后就是创建 InputDStream，接着就是对 InputDStream 进行 flatMap, map, reduceByKey, print 等操作，类似于 RDD 的转换操作。
4. 启动 JobScheduler，实例化并启动 ReceiveTracker 和 JobGenerator。
5. 启动 JobGenerator
6. 启动 ReceiverTracker

![657](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/2021/07/12/14c17c9caa0a0da54d58793163c537ac-657-c5e98b.png)

### **说说RDD和DataFrame和DataSet的关系**

这里主要对比 Dataset 和 DataFrame，因为 Dataset 和 DataFrame 拥有完全相同的成员函数，区别只是每一行的数据类型不同。

DataFrame 也可以叫 Dataset[Row]，每一行的类型是 Row，不解析，每一行究竟有哪些字段，各个字段又是什么类型都无从得知，只能用上面提到的 getAS 方法或者共性中的第七条提到的模式匹配拿出特定字段。

而 Dataset 中，每一行是什么类型是不一定的，在自定义了 case class 之后可以很自由的获得每一行的信息。

参考：https://www.cnblogs.com/starwater/p/6841807.html



#### 参考资料：

来自 [独孤九剑-Spark面试80连击(下)](https://cloud.tencent.com/developer/article/1498051)