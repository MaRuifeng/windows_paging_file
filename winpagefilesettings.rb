# Author:: Ruifeng Ma (<ruifengm@sg.ibm.com>)
# Provider:: winpagefilesettings
#
# Copyright (c) 2016 IBM, All Rights Reserved.

#####################################################
# This provider gets the current paging file information from a Windows Node.
# Tested Windows version: 2008, 2012
# Method: WMIC
# Deliverable v1.0[2016-06-01]: support Windows node with single page file only
# Deliverable v1.2[2016-06-06]: support Windows node with multiple page files (i.e. multiple disks)
#                             : the plugin checks all local locgical drives (DriveType=3, Local Disk) for page file settings
# 
# Note that this file needs to be in an Ohai cookbook's files/default/plugins directory. It's kept here only for reference purpose. 
#####################################################

Ohai.plugin(:Winpagefilesettings) do
  provides "winpagefilesettings"
  collect_data(:windows) do
    winpagefilesettings Mash.new
    logicaldisks Mash.new
    
    # Get local logical drive information (initial size in bytes)
    drive_info_list = get_logical_drives
    drive_info_list.split(/\n{3,}/).each do |section| # split by empty lines (3 new line characters in the case of wmic output)
      unless section.empty?
        drive_info = Mash.new
        section.split(/^$/).each do |line| # split by end of line
          field = line.split('=', 2).map!(&:strip)
          if field.is_a?(Array) && field[0].respond_to?(:to_sym)
            key = field[0].gsub(/\s+/, '').to_sym
            unless key.empty?
              if field[0] =~/.*FreeSpace.*/ || field[0]=~/.*Size.*/
                drive_info[key] = field[1].to_i/(1024*1024)  # change to MB unit
              else
              drive_info[key] = field[1]
              end
            end
          end
        end
        logicaldisks[drive_info[:Name]] = drive_info
      end
    end
    
    # Check whether page file is automatically managed by Windows
    page_file_auto_managed? ? winpagefilesettings[:AutomaticallyManaged] = true : winpagefilesettings[:AutomaticallyManaged] = false
    
    # Get page file information (initial size in MB)
    pagefile_info_list = get_all_page_file_info
    if pagefile_info_list =~ Regexp.new(".*No Instance\\(s\\) Available.*", Regexp::IGNORECASE)
      winpagefilesettings[:NoPageFileOnAnyDrive] = true
      pagefiles = Array.new
      logicaldisks.keys.each do |drive_label|
        pagefile_info = Mash.new
        pagefile_info[:Drive] = logicaldisks[drive_label]
        pagefile_info[:NoPageFile] = true
        pagefiles << pagefile_info
      end
      winpagefilesettings[:PageFiles] = pagefiles
    else
      pagefiles = Array.new
      pagefile_drive_labels = Array.new
      pagefile_info_list.split(/\n{3,}/).each do |section| # split by empty lines (3 new line characters in the case of wmic output)
        unless section.empty?
          pagefile_info = Mash.new
          section.split(/^$/).each do |line| # split by end of line
            field = line.split('=', 2).map!(&:strip)
            if field.is_a?(Array) && field[0].respond_to?(:to_sym)
              key = field[0].gsub(/\s+/, '').to_sym
              unless key.empty?
                if field[1]=~/\A[0-9]+\z/   # regular expression for a string of pure digits
                  pagefile_info[key] = field[1].to_i
                elsif field[1]=~/\A[0-9]{14}\.[0-9]+[\+\-][0-9]+\z/  # regular expression for DateTime format: YYYYMMDDhhmmss.<fraction>+/-<timedifference to UTC>
                  pagefile_info[key] = Time.parse(field[1])
                else
                  pagefile_info[key] = field[1]
                end
              end
            end
          end
          unless pagefile_info[:Name].nil?
            drive_label = pagefile_info[:Name].split(":")[0]  # get hard disk drive label
            pagefile_drive = Mash.new
            pagefile_drive[:Name] = drive_label + ":"
            pagefile_info[:Drive] = logicaldisks[pagefile_drive[:Name]].merge(pagefile_drive)
            pagefile_drive_labels << pagefile_drive[:Name]
            # Get initial and maximum size if customized
            unless winpagefilesettings[:AutomaticallyManaged] 
              pagefile_init_size = get_inti_size pagefile_info[:Name]
              field = pagefile_init_size.split('=', 2).map!(&:strip)
              if field.is_a?(Array) && field[0].respond_to?(:to_sym)
                key = field[0].gsub(/\s+/, '').to_sym
                init_size_value = field[1]
                unless key.empty?
                  if field[1]=~/\A[0-9]+\z/   # regular expression for a string of pure digits
                    pagefile_info[key] = field[1].to_i
                  else 
                    pagefile_info[key] = field[1]
                  end
                end
              end
              
              pagefile_max_size = get_max_size pagefile_info[:Name]
              field = pagefile_max_size.split('=', 2).map!(&:strip)
              if field.is_a?(Array) && field[0].respond_to?(:to_sym)
                key = field[0].gsub(/\s+/, '').to_sym
                max_size_value = field[1]
                unless key.empty?
                   if field[1]=~/\A[0-9]+\z/   # regular expression for a string of pure digits
                     pagefile_info[key] = field[1].to_i
                   else 
                     pagefile_info[key] = field[1]
                   end
                 end
              end
              
              # Check whether page file size is system managed
              if init_size_value == "0" && max_size_value == "0"
                pagefile_info[:SystemManaged] = true
              else 
                pagefile_info[:SystemManaged] = false
              end
            end 
            pagefiles << pagefile_info
          end
        end
      end
      
      # Check for drives without page file
      logicaldisks.keys.each do |drive_label|
        pagefile_info = Mash.new
        unless pagefile_drive_labels.include? drive_label
          pagefile_info[:Drive] = logicaldisks[drive_label]
          pagefile_info[:NoPageFile] = true
          pagefiles << pagefile_info
        end 
      end
      winpagefilesettings[:PageFiles] = pagefiles
    end
    
    # Return data object
    winpagefilesettings
  end
  
  def get_all_page_file_info 
    cmd = shell_out("#{wmic} pagefile list full")
    if cmd.stderr && !cmd.stderr.empty?
      cmd.stderr.encode('UTF-8', universal_newline: true)
    else 
      cmd.stdout.encode('UTF-8', universal_newline: true)
    end
  end
  
  def get_page_file_info pagefile
    cmd = shell_out("#{wmic} pagefile where name=\"#{win_friendly_path(pagefile)}\" get /format:list")
    if cmd.stderr && !cmd.stderr.empty?
      cmd.stderr.encode('UTF-8', universal_newline: true)
    else 
      cmd.stdout.encode('UTF-8', universal_newline: true)
    end
  end
  
  def page_file_auto_managed? 
    cmd = shell_out("#{wmic} computersystem where name=\"%computername%\" get AutomaticManagedPageFile /format:list")
    cmd.stderr.empty? && (cmd.stdout =~ /AutomaticManagedPagefile=TRUE/i)
  end
  
  def get_inti_size pagefile
    cmd = shell_out("#{wmic} pagefileset where name=\"#{win_friendly_path(pagefile)}\" get InitialSize /format:list")
    cmd.stdout.encode('UTF-8', universal_newline: true)
  end
  
  def get_max_size pagefile
    cmd = shell_out("#{wmic} pagefileset where name=\"#{win_friendly_path(pagefile)}\" get MaximumSize /format:list")
    cmd.stdout.encode('UTF-8', universal_newline: true)
  end
  
  def get_logical_drives
    cmd = shell_out("#{wmic} logicaldisk where drivetype=3 get name,description,size,freespace,filesystem,volumename /format:list")
    cmd.stdout.encode('UTF-8', universal_newline: true)
  end
  
  def wmic
    @wmic ||= begin
      locate_sysnative_cmd('wmic.exe')
    end
  end
  
  # returns windows friendly version of the provided path,
  # ensures backslashes are used everywhere
  def win_friendly_path(path)
    path.gsub(::File::SEPARATOR, '\\\\\\\\') if path
    path.gsub(::File::ALT_SEPARATOR, '\\\\\\\\') if path
    # NOTE: regex("\\\\") is intepreted as regex("\\" [escaped backslash] followed by "\\" [escaped backslash])
    #                     is intepreted as regex(\\)
    #                     is interpreted as a regex that matches a single literal backslash. --- Ruifeng Ma, May-18-2016
  end
  
end