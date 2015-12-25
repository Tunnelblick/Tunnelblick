#!/usr/bin/env ruby
# share_schemes.rb

require 'xcodeproj'
xcproj = Xcodeproj::Project.open("tunnelblick/Tunnelblick.xcodeproj")
xcproj.recreate_user_schemes
xcproj.save
