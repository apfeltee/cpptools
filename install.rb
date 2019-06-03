#!/usr/bin/ruby

def symlink_real(from, to)
  if not File.exists?(to) then
    printf("  [ln] from %p to %p ...\n", from, to)
    File.symlink(from, to)
  end
end

def symlink_home(file)
  bindir = File.join(ENV["HOME"], "/bin")
  abspath = File.absolute_path(file)
  basename = File.basename(abspath)
  finalname = basename.gsub(/\.\w+$/, "")
  dest = File.join(bindir, finalname)
  if File.symlink?(dest) then
    File.delete(dest)
  end
  symlink_real(abspath, dest)
end


def do_dir(name)
  puts("Symlinking #{name} scripts/programs ...")
  Dir.glob(File.join(__dir__, name, "/*")) do |file|
    symlink_home(file)
  end
end

## then, process scripts ...
do_dir("scripts")
