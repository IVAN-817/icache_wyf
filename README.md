# **L1-Cache**
    Project: L1-Cache in Andes AX65 CPU
    Author: Wang Yifan
    Date:   2025.07.12



## **Introduction**
本项目是针对Andes AX65 multi-core CPU (我们配置为8核)

每个核都有一个自己的L1-Cache，共享同一个L2-Cache；本文只讨论L1-Cache

L1-Cache分为D-Cache和I-Cache

D-cache和I-cache各自又分为data_ram和tag_ram

然后继续细分，比如可分为  
core0_dcache_data_ram0,   
core0_dcache_data_ram1  
...     
core0_dcache_data_ram15，   
即为最小memory的单位(原项目中为ecc_ram_model进行参数配置后的实例)

实际上除了memory以外还应该有logic部分，负责replacement, write back, tag comparing等操作策略的实现。但是厂商不想让我们懂他们的代码所以把logic模块的代码给隐藏了。所以我们如果要自己写reference model，则应该调用它们现成的memory，自己根据specification中采用的policy写出对应的logic，然后拼接起来
## **Sepcification**
---

**4-way associated**

每个cacheline set有4个cacheline                           

**cache size = 64KiByte**

D-Cache和I-Cache各自64KiByte

**cacheline size = 64Byte (fixed)**               

数据宽度是64bit，也就是说每个cacheline有8个数据位宽。   
以D-cache举例，它的data分成了16个data_ram。每个ram的输入addr是9bit，每个addr对应1个64bit的数据。        
一个ram存储了$2^9*64=2^{15}$bit数据。也就是$2^6$个cacheline=$2^4$个cacheline set。     
16个ram则存储了$2^{15}*16=2^{19}$bit=64KiByte数据。也就是$2^{10}$个cacheline。      
还要注意的是，由于添加了ECC功能，所以实际的data_ram的数据位宽设置为72bit

**Virtually indexed and Physically tagged**

程序访问的是虚拟地址，通过MMO+TLB转换成物理地址后，再去操作实际的物理地址
如果cache采用VIPT，就不需要等虚拟地址转换成物理地址，直接用虚拟地址就可以去索引cache里的数据
而tag依旧采用物理地址，以确保数据一致性。（因为不同的进程有各自独立的虚拟地址空间，虚拟地址是可能重复的。比如进程A和进程B的虚拟地址可能一样，但是它们实际映射的物理地址其实不一样）
虚拟物理地址转换似乎不是logic或者memory里实现的样子。。。暂时不管

**Stride Prefetch**  

预测性地将可能在将来需要的数据或指令加载到缓存中，从而减少处理器等待内存访问的时间
github上有人做过：https://github.com/navneet-kour/2_level_cache_with_prefetcher/tree/main
有控制开关，可以把prefetch功能关掉（mcache_ctl.IPREF_EN或者DPREF_EN，默认就是为0，关掉的）

**D-Cache write-around support (write_back_no_allocate mode，可见14.2.4)**

当hit的时候，write through
当miss的时候，只写到memory里去，而不动cache
注意，只说了D-cache支持write-around，所以I-cache可能不支持？
开关：mcache_ctl.DC_WAROUND

**Custom cache control operation through CSR read/write**

字面意思，就是通过读写CSR寄存器控制cache

**ECC**                                                          

D-cache: single error corrected, double error detected；
支持ECC功能，但默认关闭（ECC_INJECT=0）
I-cache: replacement by refetch

**Pseudo-LRU replacement policy**

pseudo-Least Recently Used policy，通过二叉搜索树，优先替换最少被用到的cacheline。
注意，因为是伪，所以在某些情况下的结果只是LRU的近似