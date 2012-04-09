#!/usr/bin/env ruby1.9.1

require 'rubygems'
require 'net/github-upload'
require 'yaml'
require 'erubis'


config = YAML.load_file("github_upload.conf")
localdir = config["localdir"]
repo = config["downloadrepo"]

gh = Net::GitHub::Upload.new(
	:login => config["login"],
	:token => config["token"]
)

downloadbaseurl = "https://github.com/downloads/%s/" % [ repo ]

puts "*** Building file lists from remote repository and local directory"
remotelisting = gh.list_files(repo)
localfiles = Dir.entries(localdir).delete_if { |f| f[0] == '.' }

versions = localfiles.map { |f| f.split(/\.tar/)[0] }
versions.uniq!

file_listing = Array.new
versions.each do |version|
	entry = Hash[
		:version => version,
		:mtime => File.mtime("%s/%s.tar.gz" % [localdir, version]),
		:gzlink => "%s%s.tar.gz" % [downloadbaseurl, version],
		:gzsig => "%s%s.tar.gz.asc" % [downloadbaseurl, version],
		:gzmd5 => "%s%s.tar.gz.md5" % [downloadbaseurl, version],
		:bz2link => "%s%s.tar.bz2" % [downloadbaseurl, version],
		:bz2sig => "%s%s.tar.bz2.asc" % [downloadbaseurl, version],
		:bz2md5 => "%s%s.tar.bz2.md5" % [downloadbaseurl, version]
	]
	file_listing.push entry
end

file_listing.sort! {|x,y| y[:mtime] <=> x[:mtime]}

remotefiles = Hash.new
remotelisting.each { |f| remotefiles[f[:name]] = f[:id] }

to_delete = remotefiles.keys - localfiles
to_upload = localfiles - remotefiles.keys


to_delete.each do |file|
	puts "*** Deleting from github: " + file
	gh.delete(repo, remotefiles[file])
end

to_upload.each do |file|
	puts "*** Uploading to github: " + file
	gh.upload(:repos => repo, :file => [localdir, file].join('/'))
end

puts "*** Generating index.html"

erb = Erubis::Eruby.new(File.read('index.html.erb'))
File.open('index.html', 'w') { |f|
	f.write(erb.result(:downloads => file_listing))
}

puts "*** Pushing index.html to github"

cmd = "git commit index.html -m \"auto-update: %s\"" % [ Time.now() ]
system(cmd)
cmd = "git push"
system(cmd)
