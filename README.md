# Baidu PCS Storage for Backup [![Build Status](https://travis-ci.org/lonre/backup-pcs.png?branch=master)](https://travis-ci.org/lonre/backup-pcs)

`PCS(Personal Cloud Storage)`是百度推出的针对个人用户的云存储服务

本 Gem 为 [Backup](https://github.com/meskyanichi/backup) Storage 插件，可以将数据备份到 `PCS`

使用 `backup-pcs` 前必须到 [百度开发者中心](http://developer.baidu.com/console) 开启指定应用的 PCS API 权限，参考 [开通PCS API权限](http://developer.baidu.com/wiki/index.php?title=docs/pcs/guide/api_approve)，并获取所设置的文件目录

## 安装

```
$ gem install backup-pcs
```
`backup-pcs` 当前支持 Ruby(MRI) 版本：1.9.3, 2.0.0

## 用法

此说明只提供了本 Gem 的配置使用方法，关于 Backup 的详细使用方法，请参考 [Backup GitHub Page](https://github.com/meskyanichi/backup)

用你喜欢的文本编辑器，打开 Backup model 文件，如：`~/Backup/models/mysite.rb`

### 引入依赖

在头部添加依赖

```ruby
require 'backup/pcs'
```

### 配置

在主体部分添加如下配置：

```ruby
store_with :PCS do |p|
  p.client_id     = 'a_client_id'
  p.client_secret = 'a_cliet_secret'
  p.dir_name      = 'Backups'         # 开通 PCS API 权限时所设置的文件目录
  p.path          = 'data'            # 保存路径，从 dir_name 算起
  # p.keep          = 2
  # p.max_retries   = 10              # 出错后重试次数，默认 10 次
  # p.retry_waitsec = 30              # 出错后重试等待秒数，默认 30 秒
end
```

### 注意

在配置完成之后，您必须手动在系统中运行一次 `Backup`，根据终端的提示完成授权。在授权完毕之后，授权信息会被缓存，这样，当后续自动任务触发 `Backup` 时，会自动加载此缓存授权信息。

## Copyright
MIT License. Copyright (c) 2013 Lonre Wang.
