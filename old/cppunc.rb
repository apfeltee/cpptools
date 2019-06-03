#!/usr/bin/ruby --disable-gems

require "rbconfig"
require "ostruct"
require "optparse"
require "tempfile"
require "shell"
require "shellwords"

DEFAULT_CPP_EXE = "gcc"
DEFAULT_CPP_FLAGS = ["-w", "-E", "-P"]
DEFAULT_EXT = "cpp"

# ppc tokens that should remain as-is.
# some tokens, like '#line' are mostly just clutter that
# do not actually modify the resulting text in any meaningful way
VALID_PRETOKS = [
  "include",
  "__include_macros",
  "define",
  "undef",
  #"line",
  "error",
  "pragma",
  "import",
  "include_next",
  "warning",
  #"ident",
  #"sccs",
  #"assert",
  #"unassert",
  "if",
  "ifdef",
  "ifndef",
  "elif",
  "else",
  "endif"
]

def uncrlf(str)
  if str[-1] == "\n" then
    str = str[0 .. -2]
    if str[-1] == "\r" then
      return str[0 .. -2]
    end
  end
  return str
end

def fixpath(path)
  if RbConfig::CONFIG["host"].match(/cygwin/) then
    require "~/dev/gems/lib/cygpath.rb"
    return Cygpath::cyg2win(path)
  end
  return path
end

# reads from $infh, and attempts to
# pre-preprocess input - mostly just removing #include's and/or
# invalid ppc dirs.
# fun fact: this makes it usable on languages that use '#' as comment character.
# now you know.
def preprocess(infh, opts, fabsdir, &b)
  skipline = false
  ln = opts.lang
  tfh = Tempfile.new(["cppunc", ".#{(ln.nil? || ln.empty?) ? DEFAULT_EXT : ln}"], fabsdir || nil)
  infh.each_line.with_index do |line, no|
    line = uncrlf(line)
    if line.match(/^\s*#/) != nil then
      if (m=line.match(/^\s*#\s*(?<token>\w+)/)) != nil then
        tok = m["token"].downcase
        if (opts.filtincludes) && (tok == "include") then
          #$stderr.printf("skipping include at %d: %p\n", no+1, line)
          skipline = true
        elsif (opts.filtinvalid) && (not VALID_PRETOKS.include?(tok)) then
          skipline = true
        end
      else
        # line is something like '# ...', but not a valid ppc dir, so skip it
        skipline = true
      end
    end
    if skipline then
      ci = 0
      # this will attempt to filter shit like this:
      #
      #   #include \
      #       <dingdon.g>
      #
      # as for those who actually write like that:
      # go sit in the middle of a busy street
      #
      if line.end_with?("\\") then
        while skipline do
          begin
            tmpline = uncrlf(infh.readline)
            if tmpline.end_with?("\\") then
              next
            else
              line = uncrlf(infh.readline)
              skipline = false
            end
          # in the event the text is so b0rked, it didn't even terminate properly
          rescue EOFError
            skipline = false
          end
        end
      else
        skipline = false
        next
      end
      skipline = false
    end
    #$stderr.printf(">> %p\n", line)
    tfh.puts(line)
  end
  tfh.close
  begin
    b.call(fixpath(tfh.path))
  ensure  
    # this is stupid
    keep = opts.keeptemp
    data = nil
    path = nil
    if keep then
      path = tfh.path
      data = File.read(path)
    end
    tfh.unlink
    if keep then
      File.write(path, data)
    end
  end
end

# call preprocess, feed it to DEFAULT_CPP, and write the whole shit
# to $outfh
def main(inpfh, outfh, opts, fabsdir)
  cmd = [opts.cppexe]
  cmd.push(*opts.cppraw)
  preprocess(inpfh, opts, fabsdir) do |path|
    cmd.push(path)
    if opts.verboseprint then
      ci = 0
      $stderr.printf("path: %p\n", path)
      $stderr.printf("cmd:  %s\n", cmd.map(&:dump).join(" "))
      if opts.debugprint then
        File.foreach(path) do |line|
          line = uncrlf(line)
          $stderr.printf("+%-5d %s\n", ci, line)
          ci += 1
        end
      end
    end
    
    IO.popen(cmd) do |pipe|
      pipe.each_line do |ln|
        outfh.write(ln)
      end
    end
  end
end

begin
  opts = OpenStruct.new({
    filtincludes: true,
    filtinvalid: true,
    cppraw: [*DEFAULT_CPP_FLAGS],
    cppexe: DEFAULT_CPP_EXE,
    outfilename: nil,
    lang: nil,
    readstdin: false,
  })
  outfh = $stdout
  OptionParser.new{|prs|
    prs.on("-h", "--help", "show this help and exit"){
      print(prs.help)
      exit()
    }
    prs.on("-i", "force reading from stdin"){
      opts.readstdin = true
    }
    prs.on("-e<s>", "specify executable of the preprocessor"){|v|
      opts.cppexe = v
    }
    prs.on("-l<s>", "force operating as language <s>"){|s|
      opts.lang = s
    }
    prs.on("-s", "keep temporary files"){|_|
      opts.keeptemp = true
    }
    prs.on("-n", "--keepincludes", "do not strip '#include' lines"){|_|
      opts.filtincludes = false
    }
    prs.on("-o<file>", "--output=<file>", "write output to <file> instead of stdout"){|v|
      opts.outfilename = v
      outfh = File.open(opts.outfilename, "wb")
    }
    prs.on("-d", "--debug", "print some debugging stuff"){|_|
      opts.debugprint = true
    }
    prs.on("-v", "--verbose", "toggle verbose mode"){|_|
      opts.verboseprint = true
    }
    prs.on("-D<str>", "--define=<str>", "pass a definition to the preprocessor"){|v|
      opts.cppraw.push("-D#{v}")
    }
    prs.on("-U<str>", "undefine name <str>"){|v|
      opts.cppraw.push("-U#{v}")
    }
    prs.on("-I<s>", "add an inclusion path to the preprocessor"){|v|
      opts.cppraw.push("-I#{v}")
    }
    prs.on("-X<str>", "pass raw option <str> (i.e., '-X\"-w\"')"){|v|
      opts.cppraw.push(v)
    }
  }.parse!
  begin
    if ARGV.empty? then
      if $stdout.tty? && (opts.readstdin == false) then
        $stderr.printf("usage: cppunc [<opts...> ] <files...>\n")
        exit(1)
      else
        main($stdin, outfh, opts, Dir.pwd)
      end
    else
      if (opts.outfilename != nil) && (ARGV.length > 1) then
        $stderr.printf("option '-o' can only be used with a single file argument\n")
        exit(1)
      end
      ARGV.each do |arg|
        fdir = File.dirname(arg)
        fabsdir = File.absolute_path(fdir)
        if opts.lang == nil then
          ext = arg.split(".")[-1].downcase
          if %w(c c99).include?(ext) then
            opts.lang = "c"
          #elsif %w(cc cxx c++ cpp).include?(ext) then
          else
            opts.lang = "cpp"
          end
        end
        File.open(arg, "rb") do |infh|
          main(infh, outfh, opts, fabsdir)
        end
      end
    end
  ensure
    if opts.outfilename != nil then
      outfh.close
    end
  end
end
