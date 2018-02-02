# lua-resty-iplocation

根据IP地址定位所在区域的工具函数(IP数据来源于[ip2region](https://github.com/lionsoul2014/ip2region))

# Overview

    lua_package_path '/the/path/to/your/project/lib/?.lua';
	lua_shared_dict ip_data 100m;

	server {
		location =/iplocation {
			default_type text/html;
			content_by_lua_block {
				local ip2region = require 'resty.ip2region.ip2region';
				local location = iplocation:new({file = "/the/path/to/your/project/lib/resty/ip2region/ip2region/data/ip2region.db"});
                local  data = location:search('202.108.22.5');
				--[[
                  {
					country = "中国",
                    region = "华东"
					province = "浙江", 
					city = "杭州", 
					isp = "电信"
                  }
                --]]
			}
		}
	}


# Methods

## new

用法:ip2region_obj, err = ip2region:new({path = 'the/path/to/the/data/file', dict = 'shared dict name'})

功能：初始化iplocation模块

参数：是一个table，里面有两个元素
     
   file：数据文件所在路径

   dict:共享字典的名称(默认为ip_data，注：字典的大小建议为5m，因为文件存到内存中所占内存大约为1.５多M),
   
   mode:查询方式(支持内存(memory)查找,二进制(binary)查找和二叉树(btree)查找)

## search

用法:ip_tab,err = ip2region_obj:search(ip, multi)

功能：通过一个范围查找它的中位数以及它对应的IP数据(根据初始化参数调用相应的查询方法)

参数：
     
   ip:查询的IP

   multi:是否多次查找(多次查询不会关闭文件流，但需要手动调用close方法关闭文件流)
   
返回数据说明：
   
如果查询成功，则得到一个table数据，其结构如下：
   
       {
           country = "中国",
           region = "华东"
           province = "浙江",
       	　　city = "杭州",
       	　　isp = "电信",
      
       }
   
字段说明：
   
  
   country：为国家名称(都是中文)
   
   region : 大区名称
  
   province：省级行政区名称(不带行政区行政单位名称)
   
   city:城市名称
   
   isp:网络提供商
   

## memory_search

用法:ip_tab,err = ip2region_obj:memory_search(ip)

功能：通过从内存数据中查找数据(如果没有对应的字典，则从数据文件中查找)

参数：

　　ip:查询的IP


返回值与search方法相同

## bin_search

用法:ip_tab,err = ip2region_obj:bin_search(ip)

功能：通过二进制文件查找

参数：

　　ip:查询的IP

　　multi:是否多次查找(多次查询不会关闭文件流，但需要手动调用close方法关闭文件流)

返回值与search方法相同

## btree_search

用法:ip_tab,err = ip2region_obj:btree_search(ip)

功能：通过btree方法在文件中查找

参数：

　　ip:查询的IP

　　multi:是否多次查找(多次查询不会关闭文件流，但需要手动调用close方法关闭文件流)

返回值与search方法相同


## loadfile

用法：content, err = ip2region_obj:loadfile()

功能：加载数据文件并返回数据文件中的数据(内部使用)

## close

用法：ip2region_obj:close()

功能：关闭文件流



# TODO

数据文件进一步加工(返回更多的字段)

# contact

也请各位同学反馈bug

E-mail:ishixinke@qq.com

website:[www.shixinke.com](http://www.shixinke.com "诗心客的博客")
