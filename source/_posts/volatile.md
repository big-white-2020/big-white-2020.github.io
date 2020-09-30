---
title : Java 并发 —— Volatile
date : 2020-9-20 15:15:45
tag : [Java, 并发, volatile]
---

volatile 是轻量级的 synchronized，它在多处理器开发中保证共享变量的可见性，可见性是指当一个线程修改一个共享变量时，另一个线程能够读取到修改后的值。volatile 的执行成本比 sychronized 更低，因为 volatile 不会引起线程的上下文切换。

##### 1.1 volatile 的定义与原理

在连接 volatile 的原理之前，先看看实现原理相关的 CPU 术语

![image-20200510145308329](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200510145308329.png)

volatile 是怎么保证可见性的呢？通过获取 JIT 编译器生成的汇编指令来查看

Java 代码

`` instance = new Singleton();   // instance 是 volatile 变量 ``

转换为汇编后

``` 
0x01a3de1d: movb $0×0,0×1104800(%esi);
0x01a3de24: lock addl $0×0,(%esp);
```

有 volatile 修饰的共享变量在进行写操作时会多出第二行汇编代码，第二行代码是一个 Lock 前缀的指令，在多核处理器下会引发：

1. 将当前处理器缓存行的数据写会到系统内存。
2. 这个写会内存操作会使其它处理器缓存了该内存地址的数据无效

为了提高处理速度，处理器会将系统内存的数据读到高速缓存中（L1、L2），但是对高速缓存操作后不知道什么时候写回到内存中，如果对用 volatile 修饰的变量进行写操作后，JVM 会向处理器发送一条 Lock 前缀的指令，这时就会将修改后的变量写回到内存中，但是，即使将变量写回后，在多处理器的情况下，其它处理器缓存的还是旧的值，所以就有了 __缓存一致性协议__ 。每个处理器通过嗅探总线上传播的数据来检查自己的缓存值是不是过期了，如果发现自己缓存行对应的内存地址进行过修改，那就将自己的缓存行设置为无效，下次进行操作时，再到内存中读到缓存中。

volatile 的两条实现原则

1. Lock 前缀指令会引起处理器缓存写到内存

    以前，在多处理器环境下，Lock# 信号在声言该信号期间，处理器会独占共享内存，对于 Intel486 和奔腾系列处理器，在锁操作时，总是在总线上声言 Lock# 信号。但是，在最近的处理器中 Lock# 信号一般不锁总线，而是锁定缓存。如果需要访问的内存区域已经缓存在处理器内部，则不会声言 Lock# 信号，它会锁定这块内存区域的缓存并写回到处理器内部，并使用缓存一致性机制来保证修改的原子性，称为 __缓存锁定__ ，缓存一致性会阻止同时修改两个及以上处理器缓存的内存区域数据。

2. 一个处理器将缓存写回到内存导致其它处理器缓存的数据失效

    IA-32处理器和Intel 64处理器使用MESI（修改、独占、共享、无效）控制协议去维护内部缓存和其他处理器缓存的一致性。在多核处理器系统中进行操作的时候，IA-32和Intel 64处理器能嗅探其他处理器访问系统内存和它们的内部缓存。处理器使用嗅探技术保证它的内部缓存、系统内存和其他处理器的缓存的数据在总线上保持一致。

##### volatile 的使用优化

在 JDK7 的并发包中新增了一个队列集合类 LinkedTransferQueue，代码如下

```java
/** 队列中的头部节点 */
private transient final PaddedAtomicReference<QNode> head;
/** 队列中的尾部节点 */
private transient final PaddedAtomicReference<QNode> tail;
static final class PaddedAtomicReference <T> extends AtomicReference T> {
	// 使用很多4个字节的引用追加到64个字节
	Object p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, pa, pb, pc, pd, pe;
	PaddedAtomicReference(T r) {
	super(r);
	}
}
public class AtomicReference <V> implements java.io.Serializable {
	private volatile V value;
	// 省略其他代码
｝
```

它使用内部类来定义头节点（head）和尾节点（tail），这个内部类相对于父类只是将共享变量追加到 64 字节。一个对象引用占 4 个字节，追加 15 个变量（60 字节），再加上父类的 value 变量，一共是64 字节。因为现在主流的处理器的 L1、L2、L3的高速缓存行是64字节宽，不支持充分填充行，所以如果头结点和尾节点都不足64字节时，处理器会将他们读到一个缓存行中，多处理器下会缓存同样的头、尾节点，当一个处理器试图修改头节点时，会将整个缓存行锁定，那么在缓存一致性协议下，其它的处理器不能访问自己缓存的尾节点，严重影响效率。

以下两种情况使用 volatile 变量时不应该追加到64字节

1. 缓存行非64字节宽的处理器。
2. 共享变量不会被频繁写，因为追加字节会导致处理器要读取更多的字节到高速缓存中，会消耗更多的性能。

##### volatile 的特性

理解 volatile 特性的一个好方法就是把对 volatile 变量的单个读写看成是使用同一个锁对这些单个读/写操作做了同步。

```
class VolatileFeaturesExample {
	volatile long vl = 0L; 		// 使用volatile声明64位的long型变量
	public void set(long l) {
		vl = l; 				// 单个volatile变量的写
	} 
	public void getAndIncrement () {
		vl++; 					// 复合（多个）volatile变量的读/写
	} 
	public long get() {
		return vl; 				// 单个volatile变量的读
	}
}
```

如果多个线程分别调用上面程序的3个方法，这个程序的语义和下面的程序等价

```
class VolatileFeaturesExample {
	long vl = 0L; 							// 64位的long型普通变量
	public synchronized void set(long l) {  // 对单个的普通变量的写用同一个锁同步
		vl = l;
	} 
	public void getAndIncrement () { 		// 普通方法调用
		long temp = get(); 					// 调用已同步的读方法
		temp += 1L; 						// 普通写操作
		set(temp); 							// 调用已同步的写方法
	} 
	public synchronized long get() { 		// 对单个的普通变量的读用同一个锁同步
		return vl;
	}
}
```

可见性。对一个volatile变量的读，总是能看到（任意线程）对这个volatile变量最后的写入。
原子性：对任意单个volatile变量的读/写具有原子性，但类似于volatile++这种复合操作不具有原子性  

##### volatile写-读建立的happens-before关系  

从内存语义的角度来说，volatile的写-读与锁的释放-获取有相同的内存效果：volatile写和锁的释放有相同的内存语义；volatile读与锁的获取有相同的内存语义。  

```
class VolatileExample {
	int a = 0;
	volatile boolean flag = false;
	public void writer() {
		a = 1; 			// 1
		flag = true; 	// 2
	} 
	public void reader() {
		if (flag) { 	// 3
		int i = a; 		// 4
		……
		}
	}
}
```

假设线程A执行writer()方法之后，线程B执行reader()方法。根据happens-before规则，这个过程建立的happens-before关系可以分为3类：  

1. 根据程序次序规则，1 happens-before 2;3 happens-before 4
2. 根据volatile规则，2 happens-before 3 
3. 根据happens-before的传递性规则，1 happens-before 4  

![](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/20200513164407.png)

##### volatile写-读的内存语义  

当写一个 volatile 变量时，JMM 会把该线程对应的本地内存中的共享变量值刷新到主内存。

当读一个volatile 变量时，JMM 会把该线程对应的本地内存置为无效，线程接下来将从主内存中读取共享变量。

##### volatile内存语义的实现  

下表是JMM针对编译器制定的volatile重排序规则表  

![](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/20200513164854.png)

当第一个操作为普通变量的读或写时，如果第二个操作为volatile写，则编译器不能重排序这两个操作，可以保证在volatile写之前，其前面的所有普通写操作已经对任意处理器可见了。

当第二个操作是volatile写时，不管第一个操作是什么，都不能重排序。这个规则确保volatile写之前的操作不会被编译器重排序到volatile写之后  

当第一个操作是volatile读时，不管第二个操作是什么，都不能重排序。这个规则确保volatile读之后的操作不会被编译器重排序到volatile读之前  

当第一个操作是volatile写，第二个操作是volatile读时，不能重排序

为了实现volatile的内存语义，编译器在生成字节码时，会在指令序列中插入内存屏障来禁止特定类型的处理器重排序。对于编译器来说，发现一个最优布置来最小化插入屏障的总数几乎不可能。为此，JMM采取保守策略  

1. 在每个volatile写操作的前面插入一个StoreStore屏障。  
2. 在每个volatile写操作的后面插入一个StoreLoad屏障。
3. 在每个volatile读操作的后面插入一个LoadLoad屏障。
4. 在每个volatile读操作的后面插入一个LoadStore屏障。  

![](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/20200511164748.png)

下面是 volatile 写插入内存屏障后生成的指令序列示意图

![](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/20200513165731.png)

StoreStore屏障可以保证在volatile写之前，其前面的所有普通写操作已经对任意处理器可见了。这是因为StoreStore屏障将保障上面所有的普通写在volatile写之前刷新到主内存。  

这里比较有意思的是，volatile写后面的StoreLoad屏障。此屏障的作用是避免volatile写与后面可能有的volatile读/写操作重排序。因为编译器常常无法准确判断在一个volatile写的后面是否需要插入一个StoreLoad屏障（比如，一个volatile写之后方法立即return）。为了保证能正确实现volatile的内存语义，JMM在采取了保守策略：__在每个volatile写的后面，或者在每个volatile读的前面插入一个StoreLoad屏障__。从整体执行效率的角度考虑，JMM最终选择了在每个volatile写的后面插入一个StoreLoad屏障。因为volatile写-读内存语义的常见使用模式是：一个写线程写volatile变量，多个读线程读同一个volatile变量。当读线程的数量大大超过写线程时，选择在volatile写之后插入StoreLoad屏障将带来可观的执行效率的提升。从这里可以看到JMM在实现上的一个特点：首先确保正确性，然后再去追求执行效率。  

下面是 volatile 读插入内存屏障后生成的指令序列示意图

![](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/20200513170010.png)

在实际执行时，只要不改变volatile写-读的内存语义，编译器可以根据具体情况省略不必要的屏障。例如下面这个例子

```
class VolatileBarrierExample {
	int a;
	volatile int v1 = 1;
	volatile int v2 = 2;
	void readAndWrite() {
		int i = v1; 	// 第一个volatile读
		int j = v2; 	// 第二个volatile读
		a = i + j; 		// 普通写
		v1 = i + 1; 	// 第一个volatile写
    	v2 = j * 2; 	// 第二个 volatile写
	} …
// 其他方法
}
```

针对readAndWrite()方法，编译器在生成字节码时可以做如下的优化  

![](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/20200513172121.png)

注意，最后的StoreLoad屏障不能省略。因为第二个volatile写之后，方法立即return。此时编译器可能无法准确断定后面是否会有volatile读或写，为了安全起见，编译器通常会在这里插入一个StoreLoad屏障。  