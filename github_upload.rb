#!/usr/bin/env ruby1.9.1

require 'rubygems'
require 'net/github-upload'
require 'yaml'
require 'erubis'

repo = 'proftpd/proftpd-downloads'
prefix = "https://github.com/downloads/proftpd/proftpd-downloads/"

config = YAML.load_file("github_upload.conf")

localdir = config["localdir"]

gh = Net::GitHub::Upload.new(
	:login => config["login"],
	:token => config["token"]
)

remotelisting = gh.list_files(repo)
localfiles = Dir.entries(localdir).delete_if { |f| f[0] == '.' }

versions = localfiles.map { |f| f.split(/\.tar/)[0] }
versions.uniq!

file_listing = Array.new
versions.each do |version|
	entry = Hash[
		:version => version,
		:mtime => File.mtime("%s/%s.tar.gz" % [localdir, version]),
		:gzlink => "%s%s.tar.gz" % [prefix, version],
		:gzsig => "%s%s.tar.gz.asc" % [prefix, version],
		:gzmd5 => "%s%s.tar.gz.md5" % [prefix, version],
		:bz2link => "%s%s.tar.bz2" % [prefix, version],
		:bz2sig => "%s%s.tar.bz2.asc" % [prefix, version],
		:bz2md5 => "%s%s.tar.bz2.md5" % [prefix, version]
	]
	file_listing.push entry
end

file_listing.sort! {|x,y| y[:mtime] <=> x[:mtime]}

remotefiles = Hash.new
remotelisting.each { |f| remotefiles[f[:name]] = f[:id] }

to_delete = remotefiles.keys - localfiles
to_upload = localfiles - remotefiles.keys

if to_upload.count == 0 && to_delete.count == 0
	puts "No new/deleted files, exiting"
#	exit
end

to_delete.each do |file|
	puts "Deleting from github: " + file
	gh.delete(repo, remotefiles[file])
end

to_upload.each do |file|
	puts "Uploading to github: " + file
	gh.upload(:repos => repo, :file => [localdir, file].join('/'))
end

erb = Erubis::Eruby.new(File.read('index.html.erb'))
File.open('index.html', 'w') { |f|
	f.write(erb.result(:downloads => file_listing))
}

cmd = "git commit index.html -m \"auto-update: %s\"" % [ Time.now() ]
system(cmd)
cmd = "git push"
system(cmd)
