#!/usr/bin/env ruby

# =TM Integrity Checker (Simple) Program Overview
#
# Version:: 1.1 | July 22, 2014
# Author:: Jon Stacey
# Email:: jon@jonsview.com
# Website:: jonsview.com
#
# ==Description
# Fork of my original TM Integrity checker that simplifies to simple directory and file existence check to make it much faster, but less accurate.
#
# How it works:
# (1) Look at every file on the live filesystem and make sure it exists on the latest backup set of the time machine and that the mtims match
#
# ==Usage
# Modify the first four constants of the script as needed: ACCOUNT_NAME, DRIVE_NAME, START_PATH, TIME_MACHINE_NAME
#
# ./tm_integrity_checker_simple.rb
#
# ==License
# Copyright (c) 2014 Jon Stacey
#
# I grant the right of modification and redistribution of this application for non-profit use
# under the condition that the above Copyright and author information is retained.
#
# ==Disclaimer
# This script is provided "AS-IS" with no warranty or guarantees.
#
# ==Changelog
# 1.1 - 7/22/2014: Check for existence of the time machine path before starting. Useful as a heads up particularly when rotating disks.
# 1.0 - 7/18/2014: Forked from TM Integrity Checker and simplified

require 'find'
require 'time'
require 'colorize'
require 'active_support'

include ActionView::NumberHelper

I18n.config.enforce_available_locales = false


class TMIntegrityChecker

  def initialize(start_path)
    abort("Oops! No start_path provided.".bold.red) unless !start_path.nil? && File.exists?(start_path)

    @ACCOUNT_NAME       = "Jon Stacey\u2019s iMac"   # Name of your Mac
    @DRIVE_NAME         = "Fusion"                   # Name of your primary hard drive
    @TIME_MACHINE_NAME  = "Time Machine"           # The name of your Time Machine Backup drive
    @START_PATH         = start_path                 # The starting directory (if you don't want to start at the root level) [INCLUDE prefixed forward slash]

    # Note: Excludes file cannot end in wildcard like the rsync exclude file.
    @EXCLUDE_FILES      = IO.readlines("excludes_file.txt").map &:chomp

    @TIME_MACHINE_PATH  = File.join('/Volumes/', @TIME_MACHINE_NAME, '/Backups.backupdb/', @ACCOUNT_NAME, '/Latest/', @DRIVE_NAME)

    abort("Oops! That Time Machine path does not exist [#{@TIME_MACHINE_PATH}].".bold.red) unless File.exists?(@TIME_MACHINE_PATH)

    @bytes_processed    = 0
    @files_processed    = 0
    @total_bytes        = 0
    @total_files        = 0
    @total_alerts       = 0
    @files              = Array.new
    @current_file       = String.new
    @last_file          = String.new
    @iteration          = nil           # Integer
    @last_msg_was_alert = false         # Boolean
    @last_time_read     = nil           # Time
    @skip_realpath      = true          # Boolean
    @alert_buffer       = Array.new
  end

  def show_progress
    # "\e[A" moves cursor up one line
    # "\e[K" clears from the cursor position to the end of the line
    # "\r" moves the cursor to the start of the line

    # Clear the last 2 lines of the console
    print "\r\e[K"
    print "\e[A\e[K" * 2

    # Show alerts
    if @alert_buffer.size > 0
      @alert_buffer.each { |alert| puts alert}
      @total_alerts += @alert_buffer.size
      @alert_buffer = Array.new
    end

    print "Current File   :".bold  + " #{@current_file}\n"
    print "Total Progress : ".bold +
          "#{number_to_percentage((@files_processed.to_f / @total_files.to_f)*100, precision: 2)}".green.bold +
          " (#{number_to_delimited(@files_processed)} / #{number_to_delimited(@total_files)})\n"
    # print "Total Progress : " +
    #       "#{number_to_percentage((@bytes_processed.to_f / @total_bytes.to_f)*100, precision: 2)}".green.bold +
    #       " (#{number_to_human_size(@bytes_processed)} / #{number_to_human_size(@total_bytes)})\n"
  end

  def _file_or_symlink_exists?(file)
    File.exists?(file) || File.symlink?(file)
  end

  def collect_inventory
    Find.find(@START_PATH) do |path|
      # next if File.directory? path
      if File.directory? path
        @EXCLUDE_FILES.each do |exclude_filter|
          if File.fnmatch?(exclude_filter, path)
            @alert_buffer << "Notice:".yellow.bold + " #{path}".blue + " directory excluded."
            Find.prune
            break
          end
        end
        next

      end

      begin
        if @skip_realpath
          @files << path
        else
          @files << File.realpath(path)   # Use the true real path
        end
        @total_files += 1
        @total_bytes += File.lstat(path).size
      rescue
        next # The full path can't be resolved for some reason, probably because this is a broken symlink, so skip.
      end
    end
    @files.reverse!
  end

  def check(file)
    tm_file = File.join(@TIME_MACHINE_PATH, file)

    begin
      if _file_or_symlink_exists?(tm_file)
        if File.lstat(file).mtime == File.lstat(tm_file).mtime
          if !File.symlink?(file) && (File.size(file) != File.size(tm_file))
            @alert_buffer << "!!! ALERT !!!".white.on_red.bold + " #{file}".blue + " file sizes don't match."
          end
        elsif (File.lstat(file).mtime - File.lstat(tm_file).mtime) > 86400
          @alert_buffer << "Warning: ".yellow.bold + " #{file}".blue + " mtimes are more than 24 hours out of sync."
        end
      else
        @alert_buffer << "!!! ALERT !!!".white.on_red.bold + " #{file}".blue + " is missing from Time Machine."
      end
    rescue => e
      @alert_buffer << "Warning: ".yellow.bold + " #{file}".blue + " read error because #{e}"
    end
  end

  def iterate
    until @files.empty?
      file              = @files.pop
      @current_file     = file
      @files_processed += 1

      check file
    end

    Thread.exit
  end

  def _show_collection_progress
    print "\r\e[KApproximately #{number_to_delimited(@total_files)} files (#{number_to_human_size(@total_bytes)}) to analyze."
  end

  def _run_worker(worker_method, progress_method, trailing_progress = true, frequency = 1)
    worker = Thread.new { self.send(worker_method) }
    worker.abort_on_exception = true
    unless progress_method.nil?
      until worker.status == false
        self.send progress_method
        sleep 1
      end
      self.send progress_method if trailing_progress
    end

    return worker
  end

  def run
    puts "Collecting live inventory . . .".bold
    _run_worker :collect_inventory, :_show_collection_progress

    puts ""
    print '-' * 50
    print "\n" * 4

    _run_worker :iterate, :show_progress

    puts ""
    print ('=' * 50).bold
    puts "\nDone!".bold + " Checked the integrity of #{number_to_delimited(@files_processed)} files. There are #{number_to_delimited(@total_alerts)} alerts or notices."
  end

end

checker = TMIntegrityChecker.new(ARGV[0])
checker.run
