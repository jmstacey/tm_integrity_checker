#!/usr/bin/env ruby

# =TM Integrity Checker Program Overview
#
# Version:: 1.0 | November 20, 2011
# Author:: Jon Stacey
# Email:: jon@jonsview.com
# Website:: jonsview.com
#
# ==Description
# The goal of this program is to serve as a simple early warning detector for silent data corruption. This progrma verifies the integrity of backups made by Apple's Time Machine (or any other directory based backup) by comparing the sha1 of the backup files to the "live" files.
#
# Assumptions:
# (1) Time Machine is doing it's job properly. This program ignores missing files.
# (2) Silent corruption has not been backed up.
#
# How it works:
# (1) Looks at every file on the backup and compares its sha1 hash with the corresponding live file sha1 hash.
# (2) If a mismatch is found, the mtime's are checked. If the mtimes are the same, it is assumed that any changes were unintentional and discrepency is reported to the user.

# This program compares
# This is a small script to transfer my latest work between my 2 macs in a somewhat automated and controlled manner.
#
# ==Usage
# Modify the first four constants of the script as needed: ACCOUNT_NAME, DRIVE_NAME, STARTING_DIRECTORY, TIME_MACHINE_NAME
#
# ./tm_integrity_checker.rb
#
# ==License
# Copyright (c) 2011 Jon Stacey
#
# I grant the right of modification and redistribution of this application for non-profit use
# under the condition that the above Copyright and author information is retained.
#
# ==Disclaimer
# This script is provided "AS-IS" with no warranty or guarantees.
#
# ==Changelog
# 1.0 - 11/20/2011: Completed

require 'find'
require 'digest/sha1'

ACCOUNT_NAME        = "Jon Stacey\u2019s iMac"   # Name of your Mac
DRIVE_NAME          = "Fusion"             # Name of your primary hard drive
STARTING_DIRECTORY  = 'Users/Jon'                # The starting directory (if you don't want to start at the root level) [INCLUDE prefixed forward slash]
TIME_MACHINE_NAME   = "Time Machine 2"     # The name of your Time Machine Backup drive

TIME_MACHINE_PATH   = File.join('/Volumes/', TIME_MACHINE_NAME, '/Backups.backupdb/', ACCOUNT_NAME, '/Latest/', DRIVE_NAME, '/', STARTING_DIRECTORY, '/')

def hash(file)
  buffer_size = 1024
  digest = Digest::SHA1.new

  begin
    open(file, "r") do |io|
      while (!io.eof)
        read_buffer = io.readpartial(buffer_size)
        digest.update(read_buffer)
      end
    end
  rescue => e
    puts "Unexpected error reading #{file}. Skipping."
    return nil
  end

  digest.hexdigest
end

def main
  count = 0
  Find.find(TIME_MACHINE_PATH) do |backup_file|
    live_file = File.join('/', STARTING_DIRECTORY, '/', backup_file.sub(TIME_MACHINE_PATH, ''))

    next if File.directory?(backup_file) || File.directory?(live_file)
    next if !File.exists?(live_file) # it obviously exists on the backup if we're here
    count += 1

    # Get sha1 hashes
    live_file_hash = String.new
    backup_file_hash = String.new

    # Assumption: the live file and backup file are on different physical devices.
    t1 = Thread.new { live_file_hash = hash(live_file) }
    t2 = Thread.new { backup_file_hash = hash(backup_file) }
    t1.join
    t2.join

    next if live_file_hash.nil? || backup_file_hash.nil? # Unexpected error, so skip

    # Potential mismatch
    if live_file_hash != backup_file_hash
      puts "Found mismatch on #{live_file}." if File.mtime(live_file) == File.mtime(backup_file)
    end

  end

  25.times { print '-' }
  puts "\nChecked the integrity of #{count} files total."
end

main
