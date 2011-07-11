#!/usr/bin/env ruby

## Filesync in ruby!
## 8/13/2005
## Jon Rafkind

## Needs nmap to run

## 11/15/2005 - Added arguments to force sync such that only arguments
## which match the regular expression given by {arg0,arg1,...} are synced

## 11/20/2005 - Removed need for lftp, using only ruby gems

## 12/3/2005 - Added -ll switch to only show files that need to be updated
## Also added -f to force all files to become up-to-date

## 10/15/2006 - Parameters to -l are treated as regex's that each file must
## to be displayed. No arguments lists all files, of course.

require 'digest/md5'
require 'net/ftp'
require 'timeout'
require 'net/sftp'
require 'termios'

class PROTOCOLS
	private_class_method :new
	def PROTOCOLS.ssh
		return 1
	end

	def PROTOCOLS.ftp
		return 2
	end

	def PROTOCOLS.name( m )
		case m
			when PROTOCOLS.ssh then "ssh"
			when PROTOCOLS.ftp then "ftp"
			else "unknown"
		end
	end
end

class FileSync

	def initialize()
		@filename = ".filesync";
		@files = []
		@server = ""
		@home = ""
		@user = ""
		@protocol = 0
		@username = nil
		@verbose = false
		@actions = []

		@read = false
		@write = false
	end

	attr_reader :verbose, :home, :protocol, :files, :server
	attr_accessor :username

	def user
		if @username != nil
			@username
		else
			@user
		end
	end

	def home=( h )
		@write = false
		@home = h
	end

	def protocol=( p )
		@write = false
		@protocol = p
	end

	def user=( u )
		@write = false
		@user = u
	end

	def files=( f )
		@write = false
		@files = f
	end

	def server=( s )
		@write = false
		@server = s
	end

	def verbose=( v )
		@verbose = v
	end

	def addAction( action )
		@actions << action
		return action
	end

	def action
		# @actions << HelpAction.new if @actions.size == 0
		for a in @actions
			a.execute( self, @verbose )
		end
	end

	def getFiles
		return @files.collect { |x|
			"#{x[0]}|#{x[1]}\n"
		}.join
	end

	def to_s
		return "Server = #{@server}\n" +
		       "Home = #{@home}\n" +
		       "Protocol = #{PROTOCOLS.name(@protocol)}\n" +
		       "Username = #{@user}\n" +
		       "Files\n" +
		       "-----\n" +
		       getFiles
	end

	def readSync
		return true if @read
		if not File.exists?( @filename )
			print "No filesync repository here. Use 'filesync -s' first\n"
			return true
		end
		@read = true
		file = File.open( @filename, "r" )
		for line in file do
			line.chomp!
			case line
				when /^Server:\s*(.*)/
					@server = $1
				when /^HomeDir:\s*(.*)/
					@home = $1
				when /^Protocol:\s*(\d*)/
					@protocol = $1.to_i
				when /^Username:\s*(.*)/
					@user = $1
				when /^File:\s*(.*?)\|(.*)/
					name = $1
					md5 = $2
					@files << [ name, md5 ]
			end
		end
		file.close
		return false
	end

	def writeSync
		return if @write
		file = File.open( @filename, "w" )
		if ! file then
			print "Could not write filesync repository\n"
			return
		end
		file << "Server: #{@server}\n"
		file << "HomeDir: #{@home}\n"
		file << "Protocol: #{@protocol}\n"
		file << "Username: #{@user}\n"
		for f in @files do
			name = f[ 0 ]
			md5 = f[ 1 ]
			file << "File: #{name}|#{md5}\n"
		end
		file.close
		@write = true
	end
end

class Action
	def initialize()
		@args = []
	end

	def addArg( arg )
		@args << arg if ! @args.include?( arg )
	end

	def execute( sync, verbose )
	end

	def getMD5( f )
		return 0 if ! File.exists?( f )
		d = Digest::MD5.new
		d << File.read( f )
		d.hexdigest
		## Using md5sum
		# return IO.popen( "md5sum #{f}" ).gets.chomp[ /^\s*(.*?)\s/ ].chomp( " " );
	end

end

class HelpAction < Action
	def execute( sync, verbose )
		puts "filesync [-s] [-l] [-a file+] [-r file+] [-c[c]] [-v] [sleep=#]";
		puts "-s : Start a new filesync repository. This will start an interactive session to get certain values from you, e.g: server, protocol, home directory";
		puts "-l : List current filesync properties. Any file with ** after it needs to be synced";
		puts "-ll : List only files that need to be synced with the remote repository"
		puts "-a : Add some files to the filesync repository";
		puts  "-f : Force all files to become up-to-date without syncing with remote repository"
		puts "-r : Remove some files from the filesync repository";
		puts "-c : Sync the filesync repository with the server using some method( filesync will figure it out, dont worry )";
		puts "-cc: Force a sync of all files";
		# puts "-e : Remove files on the other server side if they arent in the filesync repository";
		puts "-v : Be verbose because you are paranoid and dont trust my programming";
		puts "-u some-user : Change user to 'some-user' instead of what exists in the filesync repository"
		puts "sleep=X : This option is only for sync and force sync. When specified filesync will sleep for X number of seconds between sending files. Use this option if the server you are connecting to doesn't want you to send too much data too fast. e.g: 'filesync -c sleep=2' will sleep for 2 seconds between each file"
		puts
		puts "You can give multiple actions which will be executed sequentially"
		puts "Example: filesync -l -a foo -c -l"
		puts "Will list the files, add 'foo', sync the repository, then list them again"
		puts ""
		puts "About: filesync's job is to keep a remote filesystem in sync with your local copy."
		puts " It achieves this by remembering a list of files you want to store on the remote"
		puts "server, called the filesync repository. Whenever you modify a file in the list of "
		puts "files filesync will keep track of that by using md5 sums. When you do a 'sync' "
		puts "via filesync -c, filesync will only transfer those files that have changed since the "
		puts "last time you ran filesync, or all of the files if a sync has never occured."
		puts
		puts "Written by Jon Rafkind"
	end
end

class ListFiles < Action

	def showFiles( files )
		puts files.collect{ |x|
			file = x[ 0 ]
		        oldmd5 = x[ 1 ]
			md5 = getMD5( file )
			v = ""
			if md5 != oldmd5
				file + v + " **"
			else
				file + v
			end
		}.clone.delete_if{ |file|
			not @args.inject( true ){ |cy,regex|
				cy and /#{regex}/ === file
			}	
		}.join( "\n" )
	end

	def execute( sync, verbose )
		sync.readSync

		puts "Server = #{sync.server}"
		puts "Home = #{sync.home}"
		puts "Protocol = #{PROTOCOLS.name(sync.protocol)}"
		puts "Username = #{sync.user}"
		puts "Files"
		puts "-----"

		showFiles( sync.files )
	end
end

class ListNewFiles < ListFiles

	def showFiles( files )
		puts files.delete_if{ |x|
			getMD5( x[0] ) == x[1]
		}.collect{ |x|
			file = x[ 0 ]
		        oldmd5 = x[ 1 ]
			md5 = getMD5( file )
			v = ""
			if md5 != oldmd5
				file + v + " **"
			else
				file + v
			end
		}.join( "\n" )
	end

end

class AddFiles < Action

	def addArg( x )
		super if File.exists?( x ) and not File.new( x ).stat().directory?
	end

	def execute( sync, verbose )
		return if sync.readSync
		@args.each{ |file|
			files = sync.files
			if ! files.collect{ |x| x[ 0 ] }.include?( file )
				print "Adding #{file}\n"
				files << [ file, 0 ]
			end
			sync.files = files
		}
		sync.writeSync
	end
end

class RemoveFiles < Action
	def execute( sync, verbose )
		return if sync.readSync
		files = sync.files
		files.delete_if{ |x|
			if @args.include?( x[ 0 ] )
				print "Removing #{x[0]}\n"
				true
			end
		}
		sync.files = files
		sync.writeSync
	end
end

class CreateRepository < Action

	def getMethods( server )
		print "Discovering protocols..\n"
		protocols = []
		IO.popen( "nmap #{server}" ).each do |line|
			line.chomp!
			case line
				when /\bssh\b/ then protocols << PROTOCOLS.ssh
				when /\bftp\b/ then protocols << PROTOCOLS.ftp
			end
		end
		return protocols.sort
	end

	def getServer
		print "Server name: ";
		server = $stdin.gets
		server.chomp!
		return server
	end

	def getHome
		print "Home directory: ";
		home = $stdin.gets
		home.chomp!
		home = "." if home == "";
		return home
	end

	def getProtocol( server )
		methods = getMethods( server )

		if methods.size == 0
			print "No protocols available to #{server}. Aborting\n"
			methods << 0
		else
			print "Select a protocol\n"
		end
		protocol = 0;
		while ! methods.include?( protocol )
			for m in methods do
				print "#{m} : " + PROTOCOLS.name( m ) + "\n"
			end
			protocol = $stdin.gets.chomp.to_i
		end
		return protocol.to_i
	end

	def getUser
		print "Username: "
		user = $stdin.gets.chomp!
		return user
	end

	def execute( sync, verbose )
	
		@server = getServer
		@home = getHome
		@protocol = getProtocol( @server )
		@user = getUser

		sync.server = @server
		sync.home = @home
		sync.protocol = @protocol
		sync.user = @user
		sync.files = []

		sync.writeSync
	end
end

class ForceUpToDate < Action

	def execute( sync, verbose )
		return if sync.readSync
		puts "Forcing all files to be up-to-date"
		files = sync.files.collect{ |x|
			[ x[0], getMD5( x[ 0 ] ) ]
		}
		sync.files = files
		sync.writeSync
	end

end

class ChangeUser < Action

	def execute( sync, verbose )
		sync.username = @args.shift
	end
end

class Sync < Action

	def initialize
		@sleep = 0
	end

	def addArg( arg )
		if /sleep=(\d+)/ === arg
			@sleep = $1.to_i
		else
			super
		end
	end

	def getPassword
		# get current termios value of $stdin.
		orig = Termios.getattr($stdin)
		tios = orig.dup

		# make new value to be set by resetting ECHO and ICANON bit of
		# local modes: see termios(4).
		tios.c_lflag &= ~(Termios::ECHO|Termios::ICANON)

		# set new value of termios for $stdin.
		Termios.setattr($stdin, Termios::TCSANOW, tios)

		pass = ""
		begin
			while c = $stdin.getc and c != 10 # don't echoing and line buffering
				pass = pass + c.chr
				putc "*"
				$stdout.flush
			end
			puts
		ensure
			# restore original termios state.
			Termios::setattr($stdin, Termios::TCSANOW, orig)
		end
		return pass
	end

	def connectToFtp(sync, pass)
		ftp = false
		port = 21
		begin
			puts "Connecting to ftp://#{sync.server}"
			timeout(15){
				ftp = Net::FTP::new( sync.server )
				# ftp.debug_mode = true
				ftp.passive = true
				ftp.login( sync.user, pass )
			}
		rescue Timeout::Error
			$stderr.puts "Timeout while trying to connect to #{sync.server}:#{port}"
			return false
		end
		return ftp
	end

	def syncFTP( files, sync, verbose )
		puts "Password for #{sync.user}@#{sync.server}"
		password = getPassword
		ftp = connectToFtp(sync, password)
		puts "Changing to #{sync.home}" if verbose
		ftp.chdir( sync.home )
		
		files.each{|x|
			name = x[0]
			dirs = 0
			## Walk up the tree
			tries = 0
			begin
				timeout(30){
					name.gsub(/([^\/]+)\//){ |dir|
						puts "Making #{$1}" if verbose
						begin
							ftp.mkdir($1)
						rescue Net::FTPError
						end
						ftp.chdir($1)
						dirs += 1
					}
					puts "PWD = " + ftp.pwd if verbose
					puts "Sending #{name}"
					ftp.put(name){ |buf|
						print "."
						$stdout.flush
					}
					print "\n"
					## Walk back down
					dirs.times{ |d| ftp.chdir('..') }
					puts "Starting PWD = " + ftp.pwd if verbose
				}
			rescue Exception => e
				puts e
				tries += 1
				if tries > 10
					puts "Too many tries, giving up"
					return false
				end
				puts "Reconnecting in 5 seconds.."
				sleep 5
				ftp.close
				ftp = connectToFtp(sync, password)
				ftp.chdir(sync.home)
				retry
			end
			# sleep @sleep
		}
		ftp.close if ftp
		return true
	end

	def syncSSH( files, sync, verbose )
		puts "Password for #{sync.user}@sftp://#{sync.server}"
		# pass = $stdin.gets.chomp!
		pass = getPassword
		begin
			Net::SFTP.start(sync.server, sync.user, {:password => pass}){|sftp|
			# Net::SFTP.start(sync.server, sync.user){|sftp|
				files.each{ |x| 
					name = x[0]
					# puts sftp.pwd
					if /^(.*)\// === name
						dirname = sync.home + "/" + $1
						puts "Making #{dirname}" if verbose
						begin
							sftp.mkdir!( dirname, :permissions => 0775 )
						rescue Net::SFTP::Exception
						end
					end
					fname = sync.home + "/" + name
					puts "Transferring #{name} to #{fname}"
					sftp.upload!( name, fname )
					sftp.setstat!( fname, :permissions => 0664 )

					sleep @sleep
				}
			}
		rescue Net::SFTP::Exception
			$stderr.puts "SFTP error: " + $!
			return false
		end
		return true
	end

	def writeFiles( files, sync, verbose )
		if files.size == 0
			print "Up-to-date!\n"
			return
		end

		for i in files
			print "Syncing `#{i[0]}'\n"
		end

		return case sync.protocol
			when PROTOCOLS.ftp
				syncFTP( files, sync, verbose )
			when PROTOCOLS.ssh
				syncSSH( files, sync, verbose )
			else
				false
		end
	end

	def execute( sync, verbose )
		return if sync.readSync
		files = sync.files.collect{ |x|
			file = x[ 0 ]
			oldmd5 = x[ 1 ]
			md5 = getMD5( file )
			if md5 != oldmd5
				x[ 1 ] = md5
				x
			else
				nil
			end
		}.delete_if{ |x| x == nil }
		sync.files = sync.files
		sync.writeSync if writeFiles( files, sync, verbose )
	end
end

class ForceSync < Sync
	def execute( sync, verbose )
		puts @args
		return if sync.readSync
		files = sync.files.collect{ |x|
			file = x[ 0 ]
			oldmd5 = x[ 1 ]
			md5 = getMD5( file )
			x[ 1 ] = md5
			x
		}.delete_if{ |x| 
			x == nil or (not @args.empty? and not @args.inject( false ){ |cy,arg|
				p "Checking #{arg} vs #{x[0]}" if verbose
				r = /.*#{arg}.*/
				p r if verbose
				cy or r === x[ 0 ]
			})
		}
		sync.files = sync.files
		sync.writeSync if writeFiles( files, sync, verbose )
	end
end

operation = FileSync.new
action = Action.new
ARGV.each do |arg|
	action = case arg
		when /^-l$/ then operation.addAction( ListFiles.new )
		when /^-ll$/ then operation.addAction( ListNewFiles.new )
		when /^-s$/ then operation.addAction( CreateRepository.new )
		when /^-a$/ then operation.addAction( AddFiles.new )
		when /^-f$/ then operation.addAction( ForceUpToDate.new )
		when /^-r$/ then operation.addAction( RemoveFiles.new )
		when /^-c$/ then operation.addAction( Sync.new )
		when /^-cc$/ then operation.addAction( ForceSync.new )
		when /^-u$/ then operation.addAction( ChangeUser.new )
		when /^-h$|^--help$|^help$/ then operation.addAction( HelpAction.new )
		when /^-v$/ 
			operation.verbose = true
			action
		else
			action.addArg( arg )
			action
	end
end

operation.action
