---
title : Redis 基本数据结构
date : 2020年9月12日 15:15:45
tag : [Reids]
---

### 字符串

Redis 没有使用 C 语言原生的字符串，而是重新定义了一种数据结构——SDS（Simple Dynamic String）简单动态字符串，数据结构如下

![image-20200828194712926](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200828194712926.png)

`free` : 表示 `buf` 中可用的字节空间

`len` : 表示字符串的长度（不包括结束符）

buf : 字节数组，用于存放二进制字节

`free` 用于每次拼接前

SDS 较 C 语言原生字符串有何优势：

1. 获取字符串长度时不用遍历整个数组，直接读取 `len` 长度即可，时间复杂度为 `O(1)`，C 语言中获取字符串长度需要遍历整个数组，时间复杂度为 `O(n)` 。

2. 字符串拼接时不会出现内存溢出：

   C 字符串在做字符串拼接之前需要先手动进行内存重分配，再进行拼接，很容易遗忘这个步骤造成内存溢出；而 SDS 每次进行拼接前先判断 `free` 的长度是否够拼接的长度，如果不够，先进行扩容。

3. 减少修改字符串时的内存重分配次数

   C 字符串每次对字符串进行增长或缩短都需要对内存进行重分配。

   SDS 采用**空间预分配**和**惰性空间释放**的方式

   - 如果对 SDS 修改后，SDS 的空间未超过 1MB，则会分配和 `len` 属性同样大小的未使用空间，这时 `len` == `free`，例如：如果修改后 SDS 的大小为 20 字节，则会分配 20 字节的`free` 空间，此时 `len == free == 20`，`buf == 20 + 20 + 1` (1 字节用于保存空字符)

   * 如果 SDS 修改后大于等于 1MB ，则会分配 1MB 的 `free` 空间，例如：SDS 修改后为 20 MB，则会分配 1MB 的 `free` 空间，此时，`len == 30MB`，`free == 1MB`，`buf == 30MB + 1MB + 1byte`(1 字节用于保存空字符)
   * 在对 SDS 进行缩短操作后，不会马上释放空间，而是保存在 `buf`  里，如果以后做增长操作就能用上。再内存不足或者其他真正需要释放时就会进行释放。

4. 二进制安全

   C 字符串的字符必须符合某种编码（例如 ASCLL），并且处理结尾其它位置都不能出现空字符。而 SDS 是二进制安全的，就是在保存和读出的时候不对内容做任何操作，如过滤、筛选等等，存入的是什么，读出来就是什么。

5. 兼容 C 字符串的部分函数

   SDS 遵循 C 字符串中的以空字符串结尾的方式，所以 SDS 可以重用 `<string.h>` 库的部分函数，如 `strcasecmp(sds->buf, "hello world")`、`strcat(c_string, sds->buf)`等。

总结：SDS 与 C 字符的对比

| C 字符串                                             | SDS                                                  |
| :--------------------------------------------------- | :--------------------------------------------------- |
| 获取字符串长度的复杂度为 O(N) 。                     | 获取字符串长度的复杂度为 O(1) 。                     |
| API 是不安全的，可能会造成缓冲区溢出。               | API 是安全的，不会造成缓冲区溢出。                   |
| 修改字符串长度 `N` 次必然需要执行 `N` 次内存重分配。 | 修改字符串长度 `N` 次最多需要执行 `N` 次内存重分配。 |
| 只能保存文本数据。                                   | 可以保存文本或者二进制数据。                         |
| 可以使用所有 `<string.h>` 库中的函数。               | 可以使用一部分 `<string.h>` 库中的函数。             |



### 链表

Redis 的链表由 链表(list)和链表节点(listNode)组成。

```c
typedef struct listNode {

    // 前置节点
    struct listNode *prev;

    // 后置节点
    struct listNode *next;

    // 节点的值
    void *value;

} list;
```

![image-20200828204220580](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200828204220580.png)



```c
typedef struct list {

    // 表头节点
    listNode *head;

    // 表尾节点
    listNode *tail;

    // 链表所包含的节点数量
    unsigned long len;

    // 节点值复制函数
    void *(*dup)(void *ptr);

    // 节点值释放函数
    void (*free)(void *ptr);

    // 节点值对比函数
    int (*match)(void *ptr, void *key);

} list;
```

![image-20200828204307303](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200828204307303.png)

Redis 链表的特点如下：

- 双端： 链表节点带有 `prev` 和 `next` 指针， 获取某个节点的前置节点和后置节点的复杂度都是 O(1) 。

- 无环： 表头节点的 `prev` 指针和表尾节点的 `next` 指针都指向 `NULL` ， 对链表的访问以 `NULL` 为终点。

- 带表头指针和表尾指针： 通过 `list` 结构的 `head` 指针和 `tail` 指针， 程序获取链表的表头节点和表尾节点的复杂度为 O(1) 。

- 带链表长度计数器： 程序使用 `list` 结构的 `len` 属性来对 `list` 持有的链表节点进行计数， 程序获取链表中节点数量的复杂度为 O(1) 。

- 多态： 链表节点使用 `void*` 指针来保存节点值， 并且可以通过 `list` 结构的 `dup` 、 `free` 、 `match` 三个属性为节点值设置类型特定函数， 所以链表可以用于保存各种不同类型的值。


### 字典

1. #### 基本数据结构

   首先看下 Redis 中字典的哈希表：

   ```C
   typedef struct dictht {
   
       // 哈希表数组
       dictEntry **table;
   
       // 哈希表大小
       unsigned long size;
   
       // 哈希表大小掩码，用于计算索引值
       // 总是等于 size - 1
       unsigned long sizemask;
   
       // 该哈希表已有节点的数量
       unsigned long used;
   
   } dictht;
   ```

   其中：

   `table` 属性是一个数组，数组中的元素是指向 dictEntry 的指针，dictEntry 中保存一个键值对

   ![image-20200829171236706](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200829171236706.png)

   上图是一个大小为 4 的空的哈希表。

   

   然后我们看下哈希表节点：

   ```C
   typedef struct dictEntry {
   
       // 键
       void *key;
   
       // 值
       union {
           void *val;
           uint64_t u64;
           int64_t s64;
       } v;
   
       // 指向下个哈希表节点，形成链表
       struct dictEntry *next;
   
   } dictEntry;
   ```

   其中：

   `val` 可以是一个指针，也可以是 `uint64_t` 或 `int64_t` 整数

   `next` 是用来指向下一个节点的指针，用于解决冲突，没错，reids 哈希表用于解决冲突的方式就是**链地址法**

   ![image-20200829171438316](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200829171438316.png)

   然后我们看下 Redis 字典的结构：

   ```C
   typedef struct dict {
   
       // 类型特定函数
       dictType *type;
   
       // 私有数据
       void *privdata;
   
       // 哈希表
       dictht ht[2];
   
       // rehash 索引
       // 当 rehash 不在进行时，值为 -1
       int rehashidx; /* rehashing not in progress if rehashidx == -1 */
   
   } dict;
   ```

   其中 ：

   `type` 和 `privdata` 属性是针对不同类型的键值对

   `ht` 属性是大小为 2 的数组，一般只用 `ht[0]`，`ht[1]` 在 `rehash` 的时候才会使用

   `rehashidx` 是在 `rehash` 时记录下标的，后面讲 `rehash` 的时候会用到

   

   最后，看下 `dictType` 的实现：

   ```C
   typedef struct dictType {
   
       // 计算哈希值的函数
       unsigned int (*hashFunction)(const void *key);
   
       // 复制键的函数
       void *(*keyDup)(void *privdata, const void *key);
   
       // 复制值的函数
       void *(*valDup)(void *privdata, const void *obj);
   
       // 对比键的函数
       int (*keyCompare)(void *privdata, const void *key1, const void *key2);
   
       // 销毁键的函数
       void (*keyDestructor)(void *privdata, void *key);
   
       // 销毁值的函数
       void (*valDestructor)(void *privdata, void *obj);
   
   } dictType;
   ```

   ![image-20200829172318060](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200829172318060.png)

   上图是一个普通为进行 `rehash` 的字典

   

2. #### 哈希算法

   我们将一个 `<k, v>` 对添加到字典里的步骤是：

   * 计算 k 的 哈希值
   * 根据哈希值，通过 `sizemask` 计算除索引值
   * 根据索引放入哈希表数组中

   Redis 计算哈希值和索引的方式：

   ```C
   # 使用字典设置的哈希函数，计算键 key 的哈希值
   hash = dict->type->hashFunction(key);
   
   # 使用哈希表的 sizemask 属性和哈希值，计算出索引值
   # 根据情况不同， ht[x] 可以是 ht[0] 或者 ht[1]
   index = hash & dict->ht[x].sizemask;
   
   ```

   **注：Redis 使用 `MurmurHash2` 算法计算键的哈希值**

   

3. #### 解决哈希冲突

   Redis 的哈希表采用链地址法（separate chaining）来解决冲突

   ![image-20200829173039458](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200829173039458.png)

   因为 `dictEntry` 组成的链表没有指向表尾的指针，所有为了考虑速度，**总是将新节点添加到表头的位置**

   

4. #### rehash

   在容量固定的情况下，性能会随着 `<K, V>` 断增多而下降，因为， `<K, V>` 越来越多，造成哈希冲突的情况越来越多，`dictEntry` 链表越来越长，导致每次取值都要对链表进行遍历，所以这种情况就需要扩容; 另一种情况就是，哈希表有一个很大的容量，而里面的  `<K, V>`  越来越少（一开始不断扩容，随着使用，不断删除里面的 `<K, V>` ），这时为了避免空间浪费就需要收缩。而扩容与收缩都是通过 `rehash` （重新散列）来实现。`rehash` 步骤如下：

   * 为字典中的 `ht[1]` 分配空间，这里空间分配的大小取决于执行的操作
     * 如果是扩容，`ht[1]` 的大小为第一个大于等于 `ht[0].used * 2` 的 `2^n` （ 2 的 n 次幂），假设 `ht[0].used == 4`，那么 `4 * 2 = 8`，2 的 3 次方刚好是 8，所以 `ht[1]` 大小就为 8
     * 如果是收缩，`ht[1]` 的大小为第一个大于等于 `ht[0].used` 的 `2^n` （ 2 的 n 次幂）

   * 将 `ht[0]` 的 `<K, V>` rehash 到 `ht[1]` 上，rehash 就是重新计算哈希值和索引值

   * 迁移完后，释放 `ht[0]` , 将 `ht[1]` 设置为 `ht[0]`

     

   ![image-20200829174923728](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200829174923728.png)

   对上图进行扩容步骤

   先分配空间：`ht[0].used` 当前的值为 `4` ， `4 * 2 = 8` ， 而 `8` （2^3）恰好是第一个大于等于 `4` 的 `2` 的 `n` 次方， 所以程序会将 `ht[1]` 哈希表的大小设置为 `8`

   ![image-20200829175021598](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200829175021598.png)

   将 `ht[0]` 的 `<K, V>` rehash 到 `ht[1]` 上：

   ![image-20200829175137089](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200829175137089.png)

   重置指针，释放空间：

   ![image-20200829175209996](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200829175209996.png)

   

   什么时候进行扩容？以下两个条件满足其一就会进行扩容

   * 服务器没有在执行 `BGSAVE` 命令或 `BGREWRITEAOF` 命令的时候，负载因子大于等于 `1` 时
   * 服务器正在执行 `BGSAVE` 命令或 `BGREWRITEAOF` 命令的时候，负载因子大于等于 `5` 时

   （`BGSAVE` 和 `BGREWRITEAOF` 命令是 Redis 的持久化相关的命令）

   负载因子计算公式

   ```C
   # 负载因子 = 哈希表已保存节点数量 / 哈希表大小
   load_factor = ht[0].used / ht[0].size
   ```

   

5. #### 渐进式 rehash

   上面说到了 rehash 的过程，将 4 个  `<K, V>` rehash 可以很快完成，但是如果 `<K, V>` 是百万级、千万级、亿级呢？如果一次将 `ht[0` 中所有 `<K, V>` rehash 到 `ht[1]`，那这个计算量会导致服务停止服务一段时间，直到 rehash 完成。

   所以，rehash 并不是一次性完成的，而是分多次、渐进式的，渐进式 rehash 的步骤：

   * 为 `ht[1]` 分配空间， 让字典同时持有 `ht[0]` 和 `ht[1]` 两个哈希表
   * 在字典中维持一个索引计数器变量 `rehashidx` ， 并将它的值设置为 `0` ， 表示 rehash 工作正式开始
   * 在 rehash 进行期间， 每次对字典执行添加、删除、查找或者更新操作时， 程序除了执行指定的操作以外， 还会顺带将 `ht[0]` 哈希表在 `rehashidx` 索引上的所有键值对 rehash 到 `ht[1]` ， 当 rehash 工作完成之后， 程序将 `rehashidx` 属性的值增一
   * 随着字典操作的不断执行， 最终在某个时间点上， `ht[0]` 的所有键值对都会被 rehash 至 `ht[1]` ， 这时程序将 `rehashidx` 属性的值设为 `-1` ， 表示 rehash 操作已完成

   例如下面这个例子：

   准备 rehash

   ![image-20200829181122406](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200829181122406.png)

   rehash 索引 0 上的 `<K, V>`

   ![image-20200829181207456](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200829181207456.png)

   rehash 索引 1 上的 `<K, V>`

   ![image-20200829181222233](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200829181222233.png)

   依次 rehash 3、4 上的索引，在进行渐进式 rehash 的过程中，删除、查找、更新等操作都会在 `ht[0]` 和 `ht[1]` 两个哈希表上，但是每次添加都是添加到 `ht[1]` 中

### 跳表

这篇跳表的文章写得很不错[Skip List--跳表（全网最详细的跳表文章没有之一)](https://www.jianshu.com/p/9d8296562806)

### 整数集合

1、数据结构

```

```



