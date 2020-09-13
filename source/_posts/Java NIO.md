---
title : JAVA NIO
date : 2020年9月13日 17:21:45
tag : [JAVA, NIO, 并发]
---

直接内存，间接内存
&#8195;java.nio 从 Java 1.4开始引入，可以叫New I/O，也可叫Non-Blocking I/O。java.nio 有三个核心概念Selector、Channel、Buffer，在java.nio中我们是面向块（block）或者缓冲区（buffer）编程，而不是像 java.io 中的面向流编程。buffer 是内存中的一块区域，底层的实现是数组，所有数据的读或者写都是通过 buffer 来实现。

&#8195;对于Java的8中基本数据类型都有（除了 Boolean）对应的 Buffer 类型，如 ByteBuffer、CharBuffer、IntBuffer 等
&#8195;Channel 是指可以写入或者读取数据的对象，类似于 java.io 中的 Stream，不过 Channel 是双向的，可以进行读写。但是所有的读写操作都是通过 Buffer 进行，不会直接通过 Channel 读写数据。

#### Buffer
&#8195;Buffer 中有几个重要的属性 mark、position、limit、capacity，其中 0 <= mark <= position <= limit <= capacity。
&#8195;capacity 表示缓冲区 Buffer 的容量，不能为负数。limit 为缓冲区的限制，不能为负，限制代表缓冲区中第一个不能读取或者写入元素的索引（下标）。
![image-20200508213658067](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200508213658067.png)
&#8195;position 代表下一个要读取或者写入元素的索引（下标），不能为负。
![image-20200508213713359](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200508213713359.png)
&#8195;mark 表示缓冲区的标记，标记的作用是调用 reset() 方法时，会将 position 位置重置到 mark 位置，标记不是必须的，而且标记不能大于 position，如果定义了 mark ，再将 position 或 limit 重置到比 mark 小的位置时会丢弃 mark，将 mark 置为 -1。如果未定义 mark 在调用 reset() 方法时会抛出 InvalidMarkException 异常。
总结：
 1 ）缓冲区的 capacity 不能为负数，缓冲区的 limit 不能为负数，缓冲区的 position 不能
为负数 。
2) position 不能大于其 limit 。
3) limit 不能大于其 capacity 。
4 ）如果定义了 mark ，则在将 position 或 limit 调整为小于该 mark 的值时，该 mark 被
丢弃 。
5 ）如果未定义 mark ，那么调用 reset（） 方法将导致抛出 InvalidMarkException 异常 。
6 ）如果 position 大于新的 limit ，则 position 的值就是新 limit 的值 。
7 ）当 limit 和 position 值一样时，在指定的 position 写入数据时会 出现异常，因为此位
置是被限制的 。

#### flip() 方法
例子：
```
FileInputStream fileInputStream = new FileInputStream("niotest1.txt");
FileChannel channel = fileInputStream.getChannel();

ByteBuffer buffer = ByteBuffer.allocate(512);
channel.read(buffer);

buffer.flip();

while (buffer.hasRemaining()){
    System.out.println((char) buffer.get());
}



```
上述例子中，将 niotest1.txt 读入 buffer 后进行了一次 flip 操作，下面是 flip 方法的源码。flip 操作将 limit 设置为当前的 position，下次读取操作时就不会超过赋值的界限，保证读取的数据都是有效的。然后 position 设置为 0，下次读取时能从下标 0 开始读，mark 设置为 -1
```
public final Buffer flip() {
    limit = position;
    position = 0;
    mark = -1;
    return this;
}
```

#### clear() 方法

&#8195;clear 方法只是将 limit 设置为 capacity，position 设置为 0，并没有将数据删除，而只是将 buffer 数组设置为初始状态，下次写操作时直接覆盖，而读操作可以把原来的数据读出来。下面是 clear 方法的源码
```
public final Buffer clear() {
    position = 0;
    limit = capacity;
    mark = -1;
    return this;
}
```

相对位置和绝对位置
ByteBuffer 类型化 put 和 get方法
就是，将其他类型 put 进 ByteBuffer，但是，put 什么类型，get 就是什么类型，顺序不能变。

#### 共享底层数组 slice 共享相同的数组


#### 直接缓冲和零拷贝 DirectBuffer
![image-20200508213733285](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200508213733285.png)

#### 内存映射文件 MappedByteBuffer
将文件的全部或者一部分映射到堆外内存中，Java即可以直接操作内存，而不用操作文件，减少I/O操作，提升操作效率

#### 关于 Buffer 的 Scattering（分散）和 Gathering（收集）
Scattering 是指在使用 Channel 进行读取的时候，如果我们传入的是一个 buffer 数组，那么会将第一个 buffer 读满后再读入第二个 buffer 依次进行。
Gathering 是指写出的时候传入一个 buffer 数组，会将第一个 buffer 全部写出，再将第二个 buffer 全部写出，依次进行。

unicode 是编码方式
utf 是存储方式
utf-8 是unicode的实现方式