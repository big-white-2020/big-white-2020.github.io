---
title : JAVA8 新特性1 —— Lambda 表达式
date : 2020-09-14 17:15:45
tag : [JAVA, Lambda, JAVA8]
---



JAVA8的新特性核心是Lambda表达式和Steam API

#### 一、Lambda表达式：
1、语法：Java8中引入了一个新的操作符“->”，称为箭头操作符或Lambda操作符，箭头操作符将Lambda表达式拆分成两部分：
左侧：Lambda表达式的参数列表
右侧：Lambda表达式中所执行的功能，也称Lambda体

语法格式一：无参数，无返回值

    () -> System.out.println("Hello World!");

语法格式二：有一个参数且无返回值
    
    (X) -> System.out.println(X);
    
    // 若只有一个参数小括号可以省略
    (X) -> System.out.println(X);

语法格式三：有两个及以上的参数，有返回值，并且Lambda体中有多条语句
    
    Comparator<Integer> com = (c1, c2) -> {
        System.out.println("Lambda体");
        return Integer.compare(x, y);
    }

语法格式四：如果Lambda体只有一条语句，大括号和 return 可以省略不写

     Comparator<Integer> com = (c1, c2) ->  Integer.compare(x, y);

注：Lambda 表达式的参数列表的数据类型可以不用写，JVM可以通过上下文可以自动推断数据类型。

2、Lambda 表达式需要“函数式接口”支持
函数式接口：接口中只有一个抽象方法的接口，称为函数式接口。可以使用注解@FunctionalInterface 修饰检查是否为函数式接口
用一个例子来说明：

```java
// 先定义一个Fun接口
public Interface Fun {    

    public Integer getValue(); 

}

// 测试类
public void test() {

    // 求平方
    Integer num = operat(100, (X) -> X * X);
    
}

public Integer operat(Integer num, Fun f) {
    return f.getValue(num);
}

```
Lambda使用：
①：声明一个函数式接口，接口中声明一个抽象方法。
②：类中编写方法使用接口作为参数。
③: 在调用②中方法时，接口参数部分使用 Lambda 表达式。

JAVA8 提供以下四大核心函数式接口

```java
// 1、消费型接口
Comsumer<T>: 
    void acpect(T t)
    
// 2、供给型接口
Supplier<T>: 
    T get();
    
// 3、函数型接口，T为参数类型，R为返回类型
Function<T, R>: 
    R apply(T t)

// 4、断言型接口
Predicate<T>: 
    boolean test(T t);

```
更多函数式接口可在java8官方文档中查看


#### Lambda 方法引用

若Lambda体中的内容有方法已经实现了，可以用“方法引用”
注意：
**lambda体中调用方法的参数列表与返回类型必须一致**

1、类::静态方法名
```java
// 原格式
Comparator<Integer> com = (c1, c2) -> Integer.compare(c1, c2);

// 类::静态方法名格式
Comparator<Integer> com = Integer::compare
```

2、对象::实例方法名
```java
// 原格式
Comsumer<String> com = x -> System.out.printlln(x);

// 对象::实例方法名格式
PrintStream ps = Sysout.out;
Comsumer<String> com = ps::println;
com.accept("test");
```
3、类::实例方法名
若Lambda 参数列表的第一个参数是实例方法的调用者，第个参数是实例方法的参数是，可以使用ClassName::method
```java
// 原格式，BiPredicate<T, U>{ boolean test(T t, U u)}是Predicate的扩展
BiPredicate<String, Strng> bp = (x, y) -> x.equals(y);

// 类::实例方法名
BiPredicate<String, Strng> bp2 = Stirng::equals
bp2.test("abc", "def");
```

#### 构造器引用 
ClassName :: new
注意：需要调用的构造器的参数列表要与函数式接口中的抽象方法列表必须一致！

```
// 原格式
Supplier<Person> sup = () -> new Person();

// 构造器引用方式、自动匹配对应参数的构造器
Supplier<Person> sup1 = Person::new;

Function<String, Person> fun = (name) -> new Person(name);

Function<String, Person> fun1 = Person::new;

fun1.apply("zhangsan");
```

##### 数组引用
格式：Type[]::new

```
// 原格式
Function<Integer, String[]> fun = x -> new String[x];

// Type[]::new格式
Function<Integer, String[]> fun1 = Stirng[]::new;
Stirng[] strs = fun2.apply(20); // 返回长度为20的字符串数组
```