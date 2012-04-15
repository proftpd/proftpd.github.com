#!/usr/bin/env ruby1.9.1

require 'rubygems'

gem 'github_api', '>= 0.4.10'
require 'github_api'
require 'yaml'
require 'erubis'


config = YAML.load_file("github_upload.conf")
localdir = config["localdir"]
repoowner = config["repo-owner"]
repo = config["repo-name"]
@github = Github.new :login => config["login"], :password => config["password"]

# Upload & delete files on Github

puts "*** Building file lists from remote repository and local directory"
remotelisting = @github.repos.downloads repoowner, repo
localfiles = Dir.entries(localdir).delete_if { |f| f[0] == '.' }

remotefiles = Hash.new
remotelisting.each { |f| remotefiles[f[:name]] = f[:id] }

to_delete = remotefiles.keys - localfiles
to_upload = localfiles - remotefiles.keys

to_delete.each do |file|
	puts "*** Deleting from github: " + file
	@github.repos.delete_download repoowner, repo, remotefiles[file]
end

to_upload.each do |filename|
	puts "*** Uploading to github: " + filename
	localfilename = [localdir, filename].join('/')
	filesize = File.new(localfilename).size.to_i
	resource = @github.repos.create_download repoowner, repo,
		"name" => filename,
		"size" => filesize
	begin
		@github.repos.upload resource, localfilename
	rescue Exception => e
		puts "*** Failed to upload: " + filename
		puts e
		@github.repos.delete_download repoowner, repo, resource.id
	end
end


# Update the index.html

# Build a list of available versions based on filenames
versions = localfiles.map { |f| f.split(/\.tar/)[0] }
versions.uniq!

downloadbaseurl = "https://github.com/downloads/%s/%s/" % [ repoowner, repo ]
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


puts "*** Generating index.html"

erb = Erubis::Eruby.new(File.read('index.html.erb'))
File.open('index.html', 'w') { |f|
	f.write(erb.result(:downloads => file_listing))
}

puts "*** Pushing index.html to github"

cmd = "git commit -q index.html -m \"index.html auto-update: %s\"" % [ Time.now() ]
system(cmd)
cmd = "git push -q"
system(cmd)
