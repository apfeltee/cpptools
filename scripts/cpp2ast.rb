#!/usr/bin/ruby --disable-gems

require "optparse"
require "tempfile"
require "shell"
require "shellwords"

CRUDREMOVALRX = /__attribute__\(\(?.*\)?\)/

def __runclang(args)
  cmd = ["clang++", "-cc1", "-ast-print", "-std=c++14", "-fcxx-exceptions", "-fexceptions"]
  cmd.push(*args)
  $stderr.printf("command: %s\n", cmd.shelljoin.gsub(/\\+/, ""))
  exec(*cmd)

end

class CppToAST
  attr_accessor :cflags

  def initialize
    @lang = "c++"
    @cflags = []
    @prevflags = []
    @sharedflags = ["-w", "-fexceptions", "-fcxx-exceptions", "-fms-extensions"]
    @sharedflags_cpp = ["-std=c++17"]
    #define("__attribute__(...)", "")
    #define("__declspec(...)", "")
    #@cflags.push("-D__attribute__(...)=")
    #@cflags.push("-D__int64=long long")
    #@cflags.push("-D__unaligned=")
  end

  def set_lang(lang)
    $stderr.printf("set_lang(%p)\n", lang)
    @lang = lang
    @prevflags.push("-x#{lang}")
  end

  def lang_is?(*strs)
    if @lang == nil then
      return false
    end
    return strs.map(&:downcase).include?(@lang.downcase)
  end

  def get_extension
    if lang_is?("c++") then
      return ".cpp"
    elsif lang_is?("c") then
      return ".c"
    elsif lang_is?("f", "f95", "f99", "f77", "fortran") then
      return ".for"
    #else
      #raise "language #{@lang.inspect} is not handled yet, apparently"
    end
    return ".undef"
  end

  def get_compiler
    if lang_is?("c++") then
      return "clang++"
    elsif lang_is?("c") || lang_is?("f", "f95", "f77", "for") then
      return "clang"
    end
    return "clang"
  end

  def push_raw_cflag(*things)
    @cflags.push(*things)
  end

  def push_raw_shared(*things)
    @sharedflags.push(*things)
  end

  def define(name, value=nil)
    t = "-D#{name}"
    if not value.nil? then
      t += "=#{value}"
    end
    @cflags.push(t)
  end
  
  def incl(path)
    @cflags.push("-I", path)
  end

  def run(infile, outfh, outname)
    sh = Shell.new
    oext = get_extension
    obin = get_compiler
    tfile = Tempfile.new(["cpp2ast", oext], ".")
    tmpath = tfile.path
    combshared = []
    combshared.push(*@sharedflags)
    if lang_is?("c++") then
      combshared.push(*@sharedflags_cpp)
    end
    #tmpath = "cpp2ast.tmp.cpp"
    precmd = [obin, *@prevflags, infile, "-E", "-P", *combshared, *@cflags, "-o", tmpath]
    astcmd = [obin, "-cc1", *@prevflags, "-ast-print", *combshared, tmpath]
    begin
      sh.transact do
        if sh.system(*precmd) then
          $stderr.printf("preprocessing completed...\n")
          sh.system(*astcmd).each do |line|
            line.scrub!
            line.rstrip!
            #line.gsub!(CRUDREMOVALRX, "")
            outfh.puts(line)
          end
        else
          $stderr.printf("command failed: %p\n", precmd)
          exit(1)
        end
      end
    ensure
      tfile.unlink
    end
  end
end

begin
  outfh = $stdout
  outname = "<stdout>"
  opened_outfile = false
  cpp = CppToAST.new
  prs = OptionParser.new{|prs|
    prs.on("-o<file>", "--output=<file>", "set output file to <file>"){|v|
      outname = v
      outfh = File.open(outname, "w+")
      opened_outfile = true
    }
    prs.on("-I<path>", "--include=<path>", "add <path> to includes"){|v|
      cpp.incl(v)
    }
    prs.on("-x<lang>", "--lang=<lang>", "set -x flag"){|v|
      cpp.set_lang(v)
    }
    prs.on("-X<opt>", "--raw=<opt>", "set raw option"){|v|
      cpp.push_raw_shared(v)
    }
  }
  prs.parse!
  infile = ARGV.shift
  if infile.nil? then
    puts(prs.help)
  else
    begin
      cpp.run(infile, outfh, outname)
    ensure
      $stderr.printf("closing handle to %p\n", outname)
      outfh.close if opened_outfile
    end
  end
end

