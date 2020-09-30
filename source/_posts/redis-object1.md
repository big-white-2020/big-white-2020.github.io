---
title: 字符串
date: 2020-09-23 20:31:50
tags: [Redis]
---

1. ### 字符串

   字符串的编码有 `int`、`raw`、`embstr`。

   1. #### 整数

      如果字符串对象保存的是一个整数时，Redis 可以用 long 类型来表示，在上节中 `redisObject` 的 `encoding` 置为 `REDIS_ENCODING_INT`，`ptr` 将保存整数值（void* 转换为 long）。例如下面这个例子

      ```C
      > set number 10086
      OK
      > type number
      string
      > object encoding number
      int
      ```

      ![image-20200923204602079](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200923204602079.png)

      **补充**：可以用 `long` 、`double` 表示的浮点数在 redis 中也是用字符串值保存

      ```C
      redis> SET pi 3.14
      OK
      
      redis> OBJECT ENCODING pi
      "embstr"
      ```

      在需要的时候再把字符串转换成浮点值。下表是 redis 保存各种数值类型的编码

      | 数值类型                                         | 编码        |
      | ------------------------------------------------ | ----------- |
      | 可以用 long 表示的整数                           | int         |
      | 可以用 long 、double 表示的浮点数                | embstr、raw |
      | 长度太大，无法用 long、double 表示的整数或浮点数 | embstr、raw |

      

   2. #### raw 字符串

      如果字符串对象保存的是一个字符，且字符串长度大于 **39** 字节，redis 将采用 raw 编码。

      ```C
      redis> SET story "Long, long, long ago there lived a king ..."
      OK
      
      redis> STRLEN story
      (integer) 43
      
      redis> OBJECT ENCODING story
      "raw"
      ```

      ![image-20200923205008945](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200923205008945.png)

   3. #### embstr 字符串

      如果保存的字符小于等于 **39** 字节，redis 采用 `embstr` 编码保存字符串，`embstr` 底层实现也是 `SDS` 只是将 `redisObject` 与 `sdshdr` 分配在一块连续的空间，如下图：

      ![image-20200923205334860](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200923205334860.png)

      `embstr` 优点：

      * `raw` 编码方式需要调用两次内存分配，分别为 `redisObject` 、`sdshdr` 分配空间，而 `embstr` 只需要调用一次内存分配即可
      * 释放内存时也只需要一次
      * 连续内存能更好的利用缓存

      ```C
      > set msg "hello"
      OK
      > object encoding msg
      embstr
      ```

      ![image-20200923205720156](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200923205720156.png)

   4. 编码转换

      * int 编码转 raw

        当对 int 编码的对象执行一些命令使其不是整数时，将转换成 raw 编码

        ```C
        redis> SET number 10086
        OK
        
        redis> OBJECT ENCODING number
        "int"
        
        redis> APPEND number " is a good number!"
        (integer) 23
        
        redis> GET number
        "10086 is a good number!"
        
        redis> OBJECT ENCODING number
        "raw"
        ```

      * embstr 编码转 raw

        redis 没有为 embstr 编码类型编写任何修改程序（只有对 int 和 raw 编码的修改程序），所以 embstr 实际上是只读字符串，任何对 embstr 编码字符串进行修改时，程序总会先转换成 raw 编码。

        ```C
        redis> SET msg "hello world"
        OK
        
        redis> OBJECT ENCODING msg
        "embstr"
        
        redis> APPEND msg " again!"
        (integer) 18
        
        redis> OBJECT ENCODING msg
        "raw"
        ```

   5. #### 命令实现

      | 命令        | int 编码实现                                                 | embstr 编码实现                                              | raw 编码实现                                                 |
      | ----------- | ------------------------------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ |
      | SET         | 使用 int 编码保存                                            | 使用 embstr 编码保存                                         | 使用 raw 编码保存                                            |
      | GET         | 先获取保存的整数，转换成字符串，返回客户端                   | 直接向客户端返回字符串值                                     | 直接向客户端返回字符串值                                     |
      | APPEND      | 先将对象转换成 raw 编码，再按 raw 编码执行操作               | 先将对象转换成 raw 编码，再按 raw 编码执行操作               | 调用 `sdscatlen` 函数，将给定字符串追加到现有字符末尾        |
      | INCRBYFLOAT | 取出整数值将其转换成 long double 类型的浮点的，再进行加法运算 | 取出字符串值，尝试转换成浮点数，再进行加法计算，如果不能转换，则返回错误 | 取出字符串值，尝试转换成浮点数，再进行加法计算，如果不能转换，则返回错误 |
      | INCRBY      | 进行加法计算                                                 | embstr 不能执行这个命令，返回错误                            | raw 不能执行这个命令，返回错误                               |
      | DECRBY      | 进行减法计算                                                 | embstr 不能执行这个命令，返回错误                            | raw 不能执行这个命令，返回错误                               |
      | STRLEN      | 先将对象转换成 raw 编码，再按 raw 编码执行操作               | 调用 sdslen 函数                                             | 调用 sdslen 函数                                             |
      | SETRANGE    | 先将对象转换成 raw 编码，再按 raw 编码执行操作               | 先将对象转换成 raw 编码，再按 raw 编码执行操作               | 将字符串特定索引上的值设置为给定的字符串                     |
      | GETRANGE    | 将对象转换成字符串值，然后取出并返回字符串指定索引上的字符   | 直接取出并返回字符串指定索引上的字符                         | 直接取出并返回字符串指定索引上的字符                         |

      

