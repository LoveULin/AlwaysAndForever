
# about block-chain

## JobQueue
- ETH：以derived class继承Worker类的方式，获得worker线程的能力，进而通过override doWork等虚函数实现自己所需的在worker线程中干活的逻辑；线程管理也较简单，直接使用std::thread，且仅在交易验证，区块验证，监听端口，处理连接，CPU挖矿以及Worker内部等场景使用；
- BTC：有一个CScheduler类来实现JobQueue，但只起了一个线程去做，没有线程池，与脚本检查一样，使用boost的thread_group的create_thread创建线程；在执行某些参数的命令，HTTP server，UPnP，以及网络交互等场景时，直接使用std::thread；HTTP server使用了evhttp，以libevent做为event loop；与peer之间的网络通过原生接口处理(socket, connect, send, recv, listen, accept等)，没有I/O复用框架（每种网络行为起一个专门的线程去处理）
- Ripple：使用JobQueue以及线程池Workers，具体请参考下图

## 分布式MQ
- abbitMQ
- RocketMQ
- ZeroMQ
- ActiveMQ
- Redis
- kafka/jafka

## ripple
- standalone模式会有可能使用临时的DB，

1. 使用boost的program_options去解析命令行参数，然后在Config::loadFromString函数中去解析配置文件的每一个section和字段；
2. ApplicationImp的setup函数是整个程序初始化资源的核心。首先设置job queue的线程数量，根据该数量会reuse或new出来新的worker（即thread）；接着将
debug文件的输出级别调到kDebug或比它更低；
3. 然后如果是非standalone模式，则开始启动SNTPClinet模块。在启动SNTPClient模块时通过std::thread起了一个线程去处理与NTP服务器的交互，也有一个定时器
去周期性地发起与NTP服务器之间的通信；SNTPClock.cpp中的resolveComplete()函数里有一个地方到了36年会溢出（"The following line of code will 
overflow at 2036-02-07 06:28:16 UTC due to the 32 bit cast."）;
4. 接着初始化sqlite的3个DB（tx, ledger, wallet），包括执行建表以及创建相关索引的语句；
5. 接着InitPathTable；
6. 然后即开始startGenesisLedger；
7. 接着执行loadNodeIdentity加载本节点的pk，sk，优先通过配置文件里的node_seed来生成，其次尝试从walletDB中获取，都失败的话最后会尝试随机生成一对；
8. 接着建立信任的validators，即通过validators_->load以及validatorSites_->load；
9. 接着根据配置文件中指定的node_size，设置内存中一些Cache的TargetSize和TargetAge；
10. 接着即开始创建overlay对象

## SHAMap in ripple

### SHAMap 介绍
SHAMap是一个Merkle tree(http://en.wikipedia.org/wiki/Merkle_tree)，
也是一个最多16个子节点的radix tree(http://en.wikipedia.org/wiki/Radix_tree).

一个给定的SHAMap永远只存储以下三种类型的数据之一：
1. 带有元数据的交易
2. 不带有元数据的交易
3. 账户状态

所以一个特定的SHAMap上的所有叶子节点都会有一个统一的类型，内部节点（非叶子节点）除了它下面节点的hash值以外不携带任何数据。

### SHAMap 类型
创建和使用SHAMap有两种不同的方式：
1. 可变的SHAMap
2. 不可变的SHAMap

这两种方式的区别并不是那种经典的C++中的不可变意味着不改变的语义。一个不可变的SHAMap上的节点包含着不可变的节点。同时，一旦在一个不可变的SHAMap上找到
了一个节点，那么在这个SHAMap的整个生命周期中该节点一定会被保持在该SHAMap上。所以，有些反直觉得，一个不可变的SHAMap可能由于新节点地加入而增长，但是一
个不可变的SHAMap永远不会变小（直到它被销毁时完全消失）。一个节点一旦被加入进不可变SHAMap，也永远不会改变它在内存中的位置。所以不可变SHAMap中的节点可
以使用原始指针来操作（如果你足够小心的话）。

这种设计的其中一个后果就是一个SHAMap永远不可能被“裁剪”。没有任何办法可以识别那些在SHAMap中不需要了的可以被移除的节点。一旦一个节点被加入了内存中的
SHAMap，这个节点将在整个SHAMap的生命周期内始终保持在内存中。

大多数SHAMap是不可变的，它们不会修改或移除它们所包含的节点。

一个需要可变SHAMap的例子是当我们希望向LCL去实施交易时。为此我们生成一个状态树的可变快照，然后开始将交易实施于它。由于快照时可变的，改变快照中的节点不
会影响其他SHAMap中的节点。

一个使用不可变ledger的的例子是当有一个open的ledger时，一些代码想要去查询该ledger的状态。这时我们不想去改变SHAMap的状态，所以我们使用了一个不可变的
快照。

### SHAMap 创建
一个SHAMap通常不是凭空创建的。一旦一个初始的SHAMap被构造了出来，之后的SHAMap通常基于初始SHAMap调用snapShot(bool isMutable)被创建出来。这个新创建出来的SHAMap基于传入的标记拥有着所需的特性（可变或不可变）。

### SHAMap 线程安全性
### 遍历一个SHAMap
### 晚到达的节点
就像我们之前提到的一样，SHAMap（即使时不可变的）可能会增长。如果一个SHAMap正在查询某个节点然后运行到了一个空点，那么SHAMap将查看该节点是否存在，或时
还没有成为该map的一部分。这个操作是在SHAMap::fetchNodeExternalNT()函数中进行的。“NT”在这里表示不会抛出异常。

函数fetchNodeExternalNT()会经历三个阶段：
1. 通过调用getCache()来尝试找到TreeNodeCache中丢失节点的位置。TreeNodeCache是不可变的SHAMapTreeNodes的cache，不可变的SHAMapTreeNodes被所有
SHAMap共享。

任何一个不可变的SHAMapTreeNode都有一个为0的序列号。当一个可变的SHAMap被创建出来时，它的SHAMapTreeNodes被给予了一个非0的序列号。所以断言
assert (ret->getSeq() == 0)简单地确认了TreeNodeCache确实给了我们一个不可变的节点。

2. 如果这个节点不在TreeNodeCache中，我们尝试从数据库保存的历史数据中找到它。调用fetch(hash)为我们完成了这项工作。

3. 最后，如果ledgerSeq_不为0，且我们没有在历史数据中找到该节点，我们会调用一个MissingNodeHandler。

非0的ledgerSeq_表示这个SHAMap是一个属于某个指定（非0）序列号的历史ledger的完整map。所以，如果所有预期的数据都始终存在，MissingNodeHandler永远不应
该被执行。

同时，由于我们知道这个SHAMap并不能完全表示该ledger中的数据，我们将该SHAMap的序列号置为0。

如果阶段1返回了节点，那么我们就已经知道了这个节点是不可变的。然而如果任何一个阶段2执行成功，我们需要将返回的节点转变为一个不可变的节点。这通过在try块
中调用make_shared<SHAMapTreeNode>来实现。这些代码写在了try块里是因为fetchNodeExternalNT方法承诺了不会抛出异常。我们不想由于make_shared调用构造函
数时抛出异常而破坏我们的承诺。

## tokens
```
PoW：
比特币
莱特币
达世币(DarkCoin)

PoS:
未来币(NXT)

DPoS：
bitshare

PoW+PoS:
PeerCoin
```

## translation of ripple consensus protocol
```
前言：
当一些为解决拜占庭问题的一致性算法出现时，尤其是属于分布式支付系统的那些，许多都遭受了要求对全网所有节点的一致性进行同步所导致的高延迟问题；为了解这
个问题，我们提出了一个新奇的一致性算法，利用更大网络中一部分子网的集体信任特性，来绕过上述需求（要求全网所有节点的一致性）；我们展示出事实上这些子网
对信任的需求是非常小的，并且可以通过有原则地选择成员节点来进一步地减小这种需求。另外，我们展示出在这整个网络中，只需要很小的连通来保持一致性。这样的
结果是，一个在面对拜占庭失败问题时仍能保持鲁棒性，并且低延迟的一致性算法；我们将该算法展示在了ripple协议中。

1. 介绍
在最近几年，对分布式共识系统的兴趣和研究都显著地增加了，尤其是目光几乎都聚焦在了分布式支付网络上；这样的网络服务于不被中心源控制的，快速的低成本的交
易；虽然这种系统的经济利益和缺陷值得他们自己（分布式支付系统相关的机构）进行大量的研究，但这些工作其实专注于所有分布式支付系统都一定会面对的一些技术
挑战。虽然这里有各种各样的问题，但我们将它们分为主要的三类：正确性，一致性，可用性。
关于正确性，它的意思是对一个分布式系统来说，有能力去辨别一个正确的或是一个欺诈的交易是必要的。在传统的信托背景下，这是通过机构间的信任和加密签名来实
现的，加密签名保证了一笔交易确实来自于它声称来自的机构；然而在分布式系统中并没有这种信任，因为网络中任何一个乃至所有的成员的身份都可能是不知道的。因
此，必须使用另外的方法来确保正确性。
一致性是指在面对一个分布式记账系统时去维护一个单一的全局信任的问题。它与正确性问题很相似，不同之处在于，虽然网络的恶意用户可能无法创建欺诈性交易（违
反正确性），但他可能能够创建多个正确的交易，这些交易在某种程度上看不到对方，从而结合起来创造出了一个欺诈行为（双重支付）。例如，一个恶意的用户可以同
时发起两笔支付，其中他账户中的资金只够单独完成其中一笔交易，而不足以两笔一起支付。因此，每笔交易本身是正确的，但如果以这样一种整个分布式网络不同时知
道两者的方式执行，一个明确的问题就出现了，通常把这称之为“双花攻击”。因此，一致性问题可以概括为在网络中只存在一组全局认可的交易集的需求。
可用性是一个略微更加抽象的问题，我们经常将它定义为分布式支付系统的“实用性”，但实际上常常将它简化为系统的延迟性。一个既能保证正确又能确保一致性，但是
处理一笔交易要花一年时间的（只是举个例子）分布式系统，显然是一个无法生存下去的支付系统。可用性的其他方面可能还包括确保正确性和一致性过程中所需要的算
力水平，或终端用户在网络中避免被欺骗所需的技术熟练程度。
  在现代分布式计算机系统出现之前，通过一个被称为“拜占庭将军问题”的问题，许多这样的问题就已经被探索过了。在这个问题里，一组将军每个将军控制一部分的军
队，他们必须通过相互发送信使来协调一次攻击的行为。由于这些将军们位于不熟悉并且敌对的领土上，信使有可能不能到达他们的目的地（就像是在一个分布式网络中
一个节点有可能失败，或是没有发送预期中的消息而是发送了损坏的数据）。问题的另外一个方面是，其中一部分将军可能是叛徒，或是独立的，或是密谋一起的，所以
因此信使可能到达以预期为那些忠诚的将军创建一个注定会失败的假的计划（就像是一个分布式系统中恶意的成员可能会试图让系统去确信和接受欺骗的交易，或者是同
一个可信交易可能出现了多个版本导致了double-spend.因此一个分布式支付系统必须是在面对标准失败和所谓的可能源于网络中多源的协调和起源的“拜占庭”失败时都
能表现的稳健。
  在这项工作中，我们分析了分布式支付系统的一种特殊的实现：ripple协议。我们聚焦用来实现上述正确性，一致性和可用性目标的算法，并且展示所有遇到的事情
（包括很好理解的必要的预先设定的容忍阈值）。另外，我们提供了模拟共识过程的代码，其中包含参数化的网络规模，恶意用户的数量，消息发送的延迟。
  
2. 定义，公式化和以前的工作
  我们以定义ripple协议的组件来开始。为了证明正确性，一致性，可用性这些特性，我们先把这些特性公式化为公理。这些特性，当组合在一起的时候，便形成了共识
的概念：一种网络中的节点达成正确的一致性的状态。接着我们对一些与共识算法相关的之前的结果进行强调，最后在我们的公式化框架中陈述ripple协议中共识的目
标。
2.1 ripple协议组件
  我们通过定义如下的名词来开始我们对ripple网络的描述：
  Server：Server是指任意一个运行了ripple server软件的实体（与ripple clientr软件相对应，它只能允许用户发送和接收款项），它将参与到共识过程之中。
  Ledger：ledger是每一个用户的账号中拥有的全部现金的记录，并且代表了整个网络的基础事实。ledger会被成功地通过了共识过程地交易反复地更新。
  Last-Closed Ledger：last-closed ledger是最近一个被共识过程批准地ledger，因此它代表了整个网络地当前状态。
  Open Ledger：open ledger是一个节点的当前运行状态（每个节点保持一个它自己的open ledger），一个指定server的终端用户发起的交易应用于该server的
open ledger，但是交易不会被认为是最终的，直到通过了协商过程，在那一点上open ledger变成了last closed ledger。
  Unique Node List (UNL)：每一个server，s，保持一个unique node list，它是一个决定共识时s会向哪些server发起查询的其他server的集合。只有s的UNL中
其他成员的投票才会被s考虑（与整个网络的每个节点相对应）。因此UNL代表了整个网络的一个子集，当它们采取集体行动时，s信任它们不会共谋去企图欺骗网络。注意
这里信任的定义不需要UNL中每个独立的成员都是可信的。
  Proposer：任何server都可以广播交易以将它们加入共识过程中，并且当每一轮新的共识开始时每一个server都会尝试将所有合法的交易包含进来。然而，在共识过
程中，只有一个server s的UNL中的server的提案才会被s考虑。
2.2 公式化
  我们使用nonfaulty来表示在网络中表现诚实并且没有任何错误的节点。相反，faulty的节点是指一个经历过错误的节点，它可能是诚实的节点（可能由于数据损坏，
实现错误等等）或是恶意的（拜占庭错误），我们将验证一个交易的概念简化为一个简单的二元决策问题：每个节点必须基于它被给予的信息来决定0还是1.
  正如Attiya, Dolev, and Gill, 1984 [3]，我们根据下面的三条公理来定义共识：
  1. (C1)：每个nonfaulty节点在一个有限时间内做出决定
  2. (C2)：所有nonfaulty节点达成相同的决定值
  3. (C3)：对所有nonfaulty节点来说，0和1都是有可能的值（这一条移除了一种没有意义的解决方案，即所有节点无论它们被展示的信息是什么都决定0或1）
2.3 现有的共识算法
  关于在面对拜占庭错误时实现共识的算法方面，已经做了大量的研究工作。这些之前的工作包括对于网络中的所有参与者事先并不互相知道的扩展，且这里的消息也是
被异步地发送（一个独立的节点在做出某个决策时需要的总时间是没有限制的），并且这里在强和弱的共识的概念之间有一个界限。一个关于共识算法的相关的之前的工
作结果是Fischer, Lynch和Patterson的，1985 [4]，它证明了在异步的情况下，没有终止对一个共识算法来说总是有可能的，即使其中只有一个错误的进程。它引入
了基于时间的启发式算法的必要性，以确保收敛（或者至少是对不收敛的反复迭代）。我们将在第三部分为ripple协议描述这些启发式算法。
  共识算法的强度通常依据它能容忍的错误进程的比例来衡量。已经被证明了，对于拜占庭将军问题（即使已经假设了是同步的情况，并且参与者都是已知的），没有解
决方案能够容忍超过(n-1)/3的拜占庭错误，或者说能够容忍整个网络的33%表现的是恶意的 [2]。不过，这个解决方案并不需要证实在节点之间传输的消息的真实性（数
字签名）。如果消息的不可伪造性的保证是可能的话，在同步的情况下，算法将具有更高的错误容忍度。
  在异步的情况下，对于拜占庭共识提出了一些复杂度很高的算法。 FaB Paxos [5]在一个n个节点的网络中可以容忍(n-1)/5的拜占庭错误，相当于对网络中高达20%节
点的串通作恶的容忍。Attiya, Doyev, and Gill [3]为异步的情况引入了一个相位算法，它可以容忍(n-1)/4的错误，或者说可以容忍整个网络的25%（串通作恶）。
Lastly, Alchieri et al., 2008 [6]提出了BFT-CUP，实现了在异步情况下即使是参与者未知的情况下的拜占庭共识，它有着最大可以容忍(n-1)/3的错误的上限，但
对底层网络的连接情况有额外的限制。
to be continued...
```

## getaddrinfo failed in only-IPv6 network on iOS9

我们知道，即使是在only-IPv6的环境里，IPv4依然是被支持的。但是在最近的工作中，发现IPv4的一些网络服务在iOS9的only-IPv6环境中工作得并不正常。结合网络
上的一些信息和分析后，定位了问题出在**getaddrinfo**这个**libc接口**上。

当我们像如下这样使用getaddrinfo接口，去将一个域名解析成IP地址时，如果返回值ret等于0，就表示我们得到了对应的解析结果，可以在后续的流程里去使用对应的
IP地址和端口号了。
```
struct addrinfo *h(nullptr);
struct addrinfo hints;
(void)memset(&hints, 0, sizeof(hints));
hints.ai_family = AF_UNSPEC;
hints.ai_socktype = SOCK_STREAM;
hints.ai_protocol = IPPROTO_TCP;
hints.ai_flags = AI_ADDRCONFIG | AI_V4MAPPED;
const auto ret(getaddrinfo("www.baidu.com", "80", &hints, &h));
if (0 == ret) {
  ...
```
这样的使用方式在其他平台是没有任何问题的；但是在iOS9的only-IPv6环境中，如果一个解析结果的协议族为**IPv4**，那么出参h中的ai_addr字段的端口号部分会被
**置成0！！**（此时返回值ret确实也等于0）所以我们有了如下的修改方案：
```
const auto getaddrinfo(name_to_resolve, port_string, &hints, &h);
if (0 == ret) {
  const struct addrinfo *rp(h);
  while (NULL != rp) {
    // 只有IPv4的结果需要处理
    if (AF_INET == rp->ai_family) {
      struct sockaddr_in * const sockaddr(static_cast<struct sockaddr_in*>(static_cast<void*>(rp->ai_addr)));
      // 确保只有有问题的时候（值等于0）才会手工将端口号再给重新写进去
      if (0 == sockaddr->sin_port) {
        sockaddr->sin_port = htons(_port);
      }
    }
    ...
```
另外一种解决方案是：在调用getaddrinfo时，第二个参数service直接使用对应服务的名字，如"http", "ssh"等等，但是实际使用时，多数的那些非知名的端口是有
这样的服务的名字的。因此，前述修改方案应该是一种更为通用且更好的方式。

to be continued...

## Welcome to GitHub Pages

You can use the [editor on GitHub](https://github.com/LoveULin/AlwaysAndForever/edit/master/README.md) to maintain and preview the content for your website in Markdown files.

Whenever you commit to this repository, GitHub Pages will run [Jekyll](https://jekyllrb.com/) to rebuild the pages in your site, from the content in your Markdown files.

### Markdown

Markdown is a lightweight and easy-to-use syntax for styling your writing. It includes conventions for

```markdown
Syntax highlighted code block

# Header 1
## Header 2
### Header 3

- Bulleted
- List

1. Numbered
2. List

**Bold** and _Italic_ and `Code` text

[Link](url) and ![Image](src)
```

For more details see [GitHub Flavored Markdown](https://guides.github.com/features/mastering-markdown/).

### Jekyll Themes

Your Pages site will use the layout and styles from the Jekyll theme you have selected in your [repository settings](https://github.com/LoveULin/AlwaysAndForever/settings). The name of this theme is saved in the Jekyll `_config.yml` configuration file.

### Support or Contact

Having trouble with Pages? Check out our [documentation](https://help.github.com/categories/github-pages-basics/) or [contact support](https://github.com/contact) and we’ll help you sort it out.
