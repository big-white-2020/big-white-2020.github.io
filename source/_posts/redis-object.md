---
title: Redis 对象和编码
date: 2020-09-22 19:29:56
tags: [Redis]
---

1. ### 对象

   在 `Redis` 中用对象来表示键和值，每次创建一个键值对时至少创建两个对象，一个用于存放键对象，一个用于存放值对象。例如：

   ```
   SET msg "hello redis"
   ```

   上面命令中，存储键是一个 `msg` 的字符串对象，存储值是一个 `hello redis` 的字符串对象。

   Redis 的对象由一个 `redisObject` 结构体表示，结构代码如下：

   ```C
   typedef struct redisObject {
       // 类型
       unsigned type:4;
       
       // 编码
       unsigned encoding:4;
       
       // 指针，指向底层实现数据结构
       void *ptr;
       
       // ...
   } robj;
   ```

   

2. ### 类型

   上面代码中的 `type` 记录对象是什么类型（字符串、集合、哈希、列表、有序集合），`type` 的常量由下表所示：

   | 常量         | 对象类型 | TYPE 命令输出 |
   | :----------- | :------- | :------------ |
   | REDIS_STRING | 字符串   | string        |
   | REDIS_LIST   | 列表     | list          |
   | REDIS_HASH   | 哈希     | hash          |
   | REDIS_SET    | 集合     | set           |
   | REDIS_ZSET   | 有序集合 | zset          |

   Redis 中的键总是字符串对象

   可以使用 `type <key>` 命令查看值是什么对象

   ```C
   > set msg "hello redis"
   OK
   > type msg
   string
   > rpush name "zhangsan" "lisi" "wangwu"
   3
   > type name
   list
   ```

   

3. ### 编码

   在 `redisObject` 中提到 `ptr` 是指向底层数据结构，因为每种对象底层有多种实现方式，所以 `ptr` 到底指向什么结构是由 `encoding` 决定的，`encoding` 记录了对象当前的编码（是什么数据结构实现）。`encoding` 常量由下表所示：

   | 常量                      | 数据结构          |
   | :------------------------ | :---------------- |
   | REDIS_ENCODING_INT        | long 类型整数     |
   | REDIS_ENCODING_EMBSTR     | embstr 编码的 SDS |
   | REDIS_ENCODING_RAW        | SDS               |
   | REDIS_ENCODING_HT         | 字典              |
   | REDIS_ENCODING_LINKEDLIST | 双端链表          |
   | REDIS_ENCODING_ZIPLIST    | 压缩列表          |
   | REDIS_ENCODING_INTSET     | 整数集合          |
   | REDIS_ENCODING_SKIPLIST   | 跳跃表和字典      |

   `Redis` 每个对象至少使用两种编码，如下表

   | 类型         | 编码                      | 对象实现方式                | OBJECT ENCODING 命令输出 |
   | ------------ | ------------------------- | --------------------------- | ------------------------ |
   | **字符串**   |                           |                             |                          |
   | REDIS_STRING | REDIS_ENCODING_INT        | 整数值                      | int                      |
   | REDIS_STRING | REDIS_ENCODING_EMBSTR     | embstr 编码的简单动态字符串 | embstr                   |
   | REDIS_STRING | REDIS_ENCODING_RAW        | 简单动态字符串              | raw                      |
   | **列表**     |                           |                             |                          |
   | REDIS_LIST   | REDIS_ENCODING_ZIPLIST    | 压缩列表                    | ziplist                  |
   | REDIS_LIST   | REDIS_ENCODING_LINKEDLIST | 双端链表                    | linkedlist               |
   | **哈希**     |                           |                             |                          |
   | REDIS_HASH   | REDIS_ENCODING_ZIPLIST    | 压缩列表                    | ziplist                  |
   | REDIS_HASH   | REDIS_ENCODING_HT         | 字典                        | hashtable                |
   | **集合**     |                           |                             |                          |
   | REDIS_SET    | REDIS_ENCODING_INTSET     | 整数集合                    | intset                   |
   | REDIS_SET    | REDIS_ENCODING_HT         | 字典                        | hashtable                |
   | **有序集合** |                           |                             |                          |
   | REDIS_ZSET   | REDIS_ENCODING_ZIPLIST    | 压缩列表                    | ziplist                  |
   | REDIS_SET    | REDIS_ENCODING_SKIPLIST   | 跳跃表与字典                | skiplist                 |

   可以使用 `object encoding <key>` 命令查看键对象的底层数据结构

   ```C
   > object encoding msg
   embstr
   > object encoding name
   ziplist
   ```

   使用 `enconding` 设定不同场景下不同的底层结构，有助于提升 `redis` 的灵活性和效率，例如，当一个列表元素较少时，底层使用压缩列表实现，压缩列表比双端链表更省空间，随着元素增多，使用压缩列表的优势慢慢消失，对象底层实现将转变成双端链表。

