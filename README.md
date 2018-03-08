## getaddrinfo failed in only-IPv6 network on iOS9

我们知道，即使是在only-IPv6的环境里，IPv4依然是被支持的。但是在最近的工作中，发现IPv4的一些网络服务在iOS9的only-IPv6环境中工作得并不正常。结合网络上的一些信息和分析后，定位了问题出在**getaddrinfo**这个**libc接口**上。

当我们像如下这样使用getaddrinfo接口，去将一个域名解析成IP地址时，如果返回值ret等于0，就表示我们得到了对应的解析结果，可以在后续的流程里去使用对应的IP地址和端口号了。
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
这样的使用方式在其他平台是没有任何问题的；但是在iOS9的only-IPv6环境中，如果一个解析结果的协议族为**IPv4**，那么出参h中的ai_addr字段的端口号部分会被**置成0！！**（此时返回值ret确实也等于0）所以我们有了如下的修改方案：
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
另外一种解决方案是：在调用getaddrinfo时，第二个参数service直接使用对应服务的名字，如"http", "ssh"等等，但是实际使用时，多数的那些非知名的端口是没有这样的服务的名字的。因此，前述修改方案应该是一种更为通用且更好的方式。

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
