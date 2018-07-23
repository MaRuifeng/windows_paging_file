# Cookbook Name:: windows_paging_file
# Recipe:: get page file information
# Licensed Materials - Property of IBM
# Copyright (c) 2016 IBM, All Rights Reserved.
# Copyright (c) 2016 The Authors, All Rights Reserved.

#########################################################
# Author: Ruifeng Ma
# Date: 2016-May-18
# Purpose: Get the virtual memory (paging file) information of the Windows OS
# Attributes: 
#   name              >>            path to the customized paging file and must be "X:/pagefile.sys" where X is the drive name
# Note: the page file name must be pagefile.sys (case sensitive), otherwise a nasty error termed as 'Provider does not support put extensions' occurs. See http://blog.mpecsinc.ca/2011/09/wmic-pagefileset-create-error-provider.html
# 
#########################################################

win_page_file_page_file_info 'get_page_file' do
  name node['parameters']['name']          # e.g. 'C:/pagefile.sys'
  action :get
end