---
title : JAVA8 新特性2 —— Stream API
date : 2020年9月13日 17:25:45
tag : [JAVA, Stream API, JAVA8]
---



Steam API (java.util.stream.*)
![image-20200508212218878](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200508212218878.png)

三个步骤
①：将数据源转换成流
②：一系列中间操作
③：产生一个新流（不改变源数据）

流（Stream）是什么？
是数据渠道，用于操作数据源（集合、数组等）所生成的元素序列。
***集合讲的是数据，流讲的是计算！***

注意：
***①：Stream 自己不会存储元素。
②：Stream 不会改变源对象。会返回一个处理后的新Stream。
③：Stream 操作是延迟执行的。要等到需要结果的时候才执行***


一、创建 Stream

1、可以通过Collection 系列集合提供的 stream()  (串形流) 或 parallelStream() (并行流)获取流

    List<String> list = new ArrayList<>();
    Stream<String> stream = list.stream();

 2、通过Arrays 中的静态方法 stream() 获取数组流

    String[] strs = new String[5]
    Stream<String> stream1 = Arrays.stream(strs);

3、通过 Stream 类中的静态方法 of()
    
    Stream<String> stream3 = Stream.of("aa", "bb", "cc");

4、无限流

    Stream<Integer> stream4 = Stream.iterate(0, (x) -> x + 2);

此时的流是没有任何效果的，只是被创建出来了，要通过中间操作或者终止操作才有效果

二、中间操作
 ***中间操作，如果没有终止操作是不会有任何的执行***

1、筛选与切片
    filter：接收 Lambda，从流中排除某些元素
    limit：截断流，使元素不超过给定数量。
    skip(n)：跳过元素，返回一个扔掉前 n 个元素的流，若流中不足 n 个，返回空流，与 limit 互补
    distinct：筛选，通过流所生成的 hashCode() 和 equals() 去除重复元素
    
    

    // 假设有一个Person类和一个Person数组
    // 此时没有迭代，但是Stream API 会自动迭代，称为内部迭代    
    // filter 取出所有年龄大于35的
    Stream<Person> stream = persons.stream().filter((p) -> {
        System.out.println("Stream API 的中间操作");
        return p.getAge() > 35;
    });
    
    // limit 只会取出2个年龄大于35的，找到需要的数据之后，就不继续迭代，称为“短路”，提高效率
    Stream<Person> stream = persons.stream().filter((p) ->  p.getAge() > 35).limit(2)

终止操作：一次性执行全部内容，叫“惰性求值”或“延时加载“
    
    stream.forEach(System.out::println);

外部迭代

    Iterator<Person> it = persons.iterator();
    while(it.hasNext()){
        System.out.println(it.next()); 
    }

2、映射

map：接收 Lambda，将元素转换成其他形式或提取信息。接收一个函数作为参数，该函数会被应用每一个元素上，并将其映射成一个新的元素。

flatMap：接收一个函数作为参数，将流中的每个值都换成另一流，然后把所有流连接成一个流

map 案例

```
@Test
public void test(){   

List<String> stringList = Arrays.asList("aaa", "bbb", "ccc");   

stringList.stream()
    .map(x -> x.toUpperCase()) 
    .forEach(System.out::println);}
```
输出
![image-20200508212619241](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200508212619241.png)

flatMap
```
@Test 
public void test1(){     
List<String> stringList = Arrays.asList("aaa", "bbb", "ccc");     stringList.stream() 
    .flatMap(StreamAPI::filterChar) 
    .forEach(System.out::println); 
    
    }
    
    
 // 将字符串变成一个一个的字符 
 public static Stream<Character> filterChar(String str){ 
 
 List<Character> charList = new ArrayList<>();     
 for (char ch : str.toCharArray()) {         
        charList.add(ch);     
 }     
 return charList.stream(); 
 }
```
输出结果
![image-20200508212600760](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200508212600760.png)

map 和 flatMap 有点像 List 的 add 和 addAll
![image-20200508212538601](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200508212538601.png)

3、排序
sorted：自然排序
sorted(Comparator com)：订制排序

三、终止操作

1、查找与匹配
allMatch：检查是否匹配所以元素
anyMatch：检查是否至少匹配一个元素
noneMatch：检查是否没有匹配所有元素
findFirst：返回第一个元素
findAny：返回当前流的任意元素
count：返回流中元素的总个数
max：返回流中最大值
min：返回流中最小值

```
@Test
public void test3(){    
List<String> list = Arrays.asList("aaa", "aaa", "aaa", "aaa");    List<String> list1 = Arrays.asList("aaa", "bbb", "ccc", "ddd");    boolean b = list.stream().allMatch(x -> "aaa".equals(x));    System.out.println(b); 

boolean b1 = list1.stream() .anyMatch(x -> "aaa".equals(x));    System.out.println(b1);   

boolean b2 = list1.stream()  .noneMatch(x -> "fff".equals(x));    System.out.println(b2);    

Optional<String> first = list1.stream().findFirst();    System.out.println(first);    

Optional<String> any = list1.stream().findAny();    System.out.println(any);}

// 输出
true
true
true
Optional[aaa]
Optional[aaa]

List<Integer> list2 = Arrays.asList(111, 222, 333, 444);
long count = list2.stream().count();
System.out.println(count);

Optional<Integer> max = list2.stream().max(Integer::compareTo);
System.out.println(max);

Optional<Integer> min = list2.stream().min(Integer::compareTo);
System.out.println(min);

// 输出
4
Optional[444]
Optional[111]
```

2、归约
reduce(T identity, BinaryOperator)：将流中元素反复结合起来，得到一个值
```
// Person类
@Data
public class Person {    
private String name;    
private Integer age;    
private Integer salary;    
public Person(String name, int age, int salary) { 
this.name = name;        
this.age = age;        
this.salary = salary;    
}}

// reduce
// 把0作为初始值给x, 从流中拉取一个值给y完成相加操作，操作结果再给 x,再从流中拉取一个值完成操作，依次往复。
List<Integer> list = Arrays.asList(1, 2, 3, 4, 5, 6, 7, 8, 9);
Integer sum = list.stream()
                        .reduce(0, (x, y) -> x + y);
System.out.println(sum);

// 求person的工资总和

Optional<Integer> reduce = people.stream()
    .map(Person::getSalary)
    .reduce(Integer::sum);
System.out.println(reduce.get());

// 这种 map 与 reduce 连接的模式，可以成为 map-reduce 模式 

// 输出
45
27000



```

3、收集
collect：将流转换成其他形式，接收一个Collector接口实现，用于给Stream中元素做汇总的方法。

```
// 收集成list
List<String> collect = people.stream()       
    .map(Person::getName)       
    .collect(Collectors.toList());
    
 Set<String> set = people.stream()
        .map(Person::getName)        
        .collect(Collectors.toSet());
        
// 收集成其他集合类型
LinkedList<String> linkedList = people.stream()
            .map(Person::getName) 
            .collect(Collectors.toCollection(LinkedList::new));
            
 // 工资平均值
 Double avg = people.stream()
            .collect(Collectors.averagingInt(Person::getSalary));
            
// 求年龄最大的Person
Optional<Person> maxByAge = people.stream()
    .collect(Collectors.maxBy((p1, p2) -> p1.getAge().compareTo(p2.getSalary())));
    
 // 分组
 Map<Integer, List<Person>> groupByAge = people.stream()
        .collect(Collectors.groupingBy(Person::getAge));
        
// 多级分组,先按年龄再按工资分组
Map<Integer, Map<Integer, List<Person>>> collect1 = people.stream()
        .collect(Collectors.groupingBy(Person::getAge,
Collectors.groupingBy(Person::getSalary)));

// 分区, 按年龄18为分区标准
Map<Boolean, List<Person>> collect2 = people.stream()
        .collect(Collectors.partitioningBy(p -> p.getAge() > 18));
        
// 连接
// 结果：***zhangsan,lisi,wangwu,zhaoliu,tianqi***
String collect3 = people.stream()
        .map(Person::getName)
        .collect(Collectors.joining(",", "***", "***"));
System.out.println(collect3);
```

![image-20200508212352936](https://raw.githubusercontent.com/big-white-2020/notes-image/master/img/image-20200508212352936.png)