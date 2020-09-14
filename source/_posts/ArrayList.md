---
title : ArrayList 源码解析
date : 2020-09-13 15:44:09
tag : [JAVA, ArrayList, 集合, 源码]
---



首先存储的数据结构为：

```
transient Object[] elementData;
```

#### 构造方法

构造方法有三种：

+ 无参构造方法：创建一个默认容量的空数组，但是这里用的是

  ```
  private static final Object[] DEFAULTCAPACITY_EMPTY_ELEMENTDATA = {};
  ```

  目的是与

  ```
  private static final Object[] EMPTY_ELEMENTDATA = {};
  ```

  区分，知道第一次添加元素该扩容多少，挖坑，后续填

+ 带初始容量的构造方法：在 `new ArrayList` 的时候指定一个整数参数，这个参数为初始容量大小，这里会做一个判断，分三种情况

  ```Java
  if (initialCapacity > 0) {
      this.elementData = new Object[initialCapacity];
  } else if (initialCapacity == 0) {
      this.elementData = EMPTY_ELEMENTDATA;
  } else {
      throw new IllegalArgumentException("Illegal Capacity: "+ initialCapacity);
  }
  ```

  1. 参数正常，非负且大于0，创建一个大小为传入值的数组
  2. 参数为0，使用 `EMPTY_ELEMENTDATA`
  3. 异常

+ 初始参数为集合，构造一个包含指定集合元素的列表，不过传入的列表的对象必须是 `Collection<? extends E>`

  1. 如果传入的集合没问题则创建一个元素为传入集合的`List`
  2. 如果传入的集合大小为0，则使用 `EMPTY_ELEMENTDATA`



#### 添加元素

添加元素的方法主要有四种

1. add(E e)

   在添加元素之前要确保容量够，会根据一个原有 size + 1 生成的`minCapacity` 去进行比较，如果为空时，且是之前无参构造方法创建的对象（`DEFAULTCAPACITY_EMPTY_ELEMENTDATA`），会扩容到默认初始值为 10，如果是之前有参构造函数创建的方法，就判断 `minCapacity` 是否大于原来数组的长度，如果比原来数组长度小，即添加的元素要数组越界了，必须先扩容再添加。

   ```Java
   // 省略部分代码
   int MAX_ARRAY_SIZE = Integer.MAX_VALUE - 8;
   private void grow(int minCapacity) {
           int oldCapacity = elementData.length;
           int newCapacity = oldCapacity + (oldCapacity >> 1);
       if (newCapacity - minCapacity < 0)
               newCapacity = minCapacity;
       if (newCapacity - MAX_ARRAY_SIZE > 0)
               newCapacity = hugeCapacity(minCapacity);
           elementData = Arrays.copyOf(elementData, newCapacity);
       }
   
   hugeCapacity(int minCapacity) {
           if (minCapacity < 0) // overflow
               throw new OutOfMemoryError();
           return (minCapacity > MAX_ARRAY_SIZE) ?
               Integer.MAX_VALUE :
               MAX_ARRAY_SIZE;
       }
   ```

   首先扩容是原来容量的 1.5 倍，这里还有一个容量最大问题，如果容量超过了 MAX_ARRAY_SIZE，要么溢出，要么使用 `Integer.MAX_VALUE`，至于为什么 `MAX_ARRAY_SIZE` 为 `nteger.MAX_VALUE - 8`，官方说法是有些虚拟机在数组中保留了一些”header words"，需要给这些“header words"留一些空间。

   中间还有一个 `newCapacity - minCapacity < 0` 的判断，以我的理解应该是 `oldCapacity` 已经非常大了，再增长 1.5 倍就会溢出了，所以如果溢出了就增长 1 即可。

   最后，添加元素

   ```
   elementData[size++] = e;
   ```




 2. add(int index, E element) 指定位置插入

    步骤与 1 基本一样，只是最后需要从 `index`开始都往后挪一个位置

    ```JAVA
    System.arraycopy(elementData, index, elementData, index + 1,size - index);
    ```

    再把插入的值放到 `index` 位置上。

	3. addAll(Collection<? extends E> c) 增加一个集合

    步骤与 1 也一样，只是确保容量的时候传的是原来 size + c.length，然后

    ```java
    System.arraycopy(a, 0, elementData, size, numNew);
    ```

	4. addAll(int index, Collection<? extends E> c) 指定位置插入集合

    步骤与 2 类似，只是将往后移动一个换成往后移动一段

#### 删除元素

1. remove(int index)

   先验证 index 是否合法，然后保存原来的值，最后

   ```
   System.arraycopy(elementData, index+1, elementData, index,numMoved);
   ```

   然后返回删除的值

2. remove(Object o)

   这个方法是删除对象的，删除 List 中出现的第一个与参数相等的对象，且不返回删除值。这里如果传入 null 则用 == 进行比较，如果非空则用 `equals` 进行比较，找到相等的后，调用一个私有的不进行 `index` 检查，不返回值的 `fastRemove`方法

3. clear()

   对数组每个元素置空，将 size 置0

4. removeAll(Collection<?> c)

   采用覆盖的方式，对原数组进行遍历，判断 c 中是否包含，如果包含就直接覆盖

   ```Java
   complement = false;
   for (; r < size; r++)
       if (c.contains(elementData[r]) == complement)
           elementData[w++] = elementData[r];
   ```

   最后再对未被覆盖且不需要的元素置空，以便 GC

5. retainAll(Collection<?> c)

   这个方法与 `removeAll` 相反，是保留，实现方式与 `removeAll` 一样，只是 `complement = true`

#### 查询数据

1. get(int index)

   直接返回下标为 `index` 的元素

2. indexOf(Object o)

   遍历数组，返回第一个等于 o 的元素的下标，否则返回 -1

3. lastIndexOf(Object o)

   反向遍历数组，返回最后一个等于 o 的元素的下标，否则返回 -1

4. contains(Object o)

   调用 indexOf()，判断返回值是否 >=0

5. subList(int fromIndex, int toIndex)

   `subList` 返回一个子 List，但共用父 `List`，只是在每个操作时对下标添加一个 `offset`，特别是 add 操作，每次添加都要移动父 `List` 的元素，所以效率不高。