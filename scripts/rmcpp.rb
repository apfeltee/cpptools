#!/usr/bin/ruby

=begin
NB.
properly parsing C comments (/* blah blah */) and C++ comments (// blah blah), as well
as preprocessor (# ... blah blah ...) cannot be done correctly using regular expressions.
=end

require "ostruct"
require "optparse"

module Utils
  # also skips CR
  def self.readchar(fh)
    ch = fh.getc
    if (ch == "\r") then
      return readchar(fh)
    end
    return ch
  end

  def self.fpeek(fh)
    ch = fh.getc
    if ch != nil then
      fh.ungetc(ch)
    end
    return ch
  end
end

class RmCPP
  def initialize(opts)
    @opts = opts
    @outfile = opts.outfile
    @idx = 0
    @line = 1
    @curch = nil
    @nextch = nil
    @prevch = nil
    @instring = false
    @waseol = false
    @strbegin = nil
  end

  def out(*vals)
    vals.each do |val|
      if val != nil then
        @outfile.write(val)
      end
    end
  end

  # read more;
  #  set @prevch to the value that was @curch
  #  set @curch to the current char
  #  @nextch peeks to the next char
  # also increases @line incase of EOL
  def more(fh)
    @prevch = @curch
    @curch = Utils.readchar(fh)
    @nextch = Utils.fpeek(fh)
    if (@nextch == "\n") then
      @line += 1
    end
    return @curch
  end

  def out_if_keep_ansi
    if @opts.keep_ansicomment then
      out(@curch)
    end
  end

  def out_if_keep_cplusplus
    if @opts.keep_cplusplus then
      out(@curch)
    end
  end

  def check_is_eol_or_whitespace(ch)
    return (
      # these account for the beginning of the file
      # if nothing was read yet, @idx will be 0
      (@idx == 0)
      # whitespace
      (ch == " ") ||
      (ch == "\n") ||
      (ch == "\t")
    )
  end

  def was_eol_or_whitespace
    return check_is_eol_or_whitespace(@prevch)
  end

  def isdel(s)
    if @opts.deleteme.include?(s) then
      return true
    end
    return false
  end

  def do_handle(infh)
    while true do
      more(infh)
      if @curch == nil then
        return
      else
        if (((@curch == '"') || (@curch == "'")) && (@prevch != '\\')) && (@strbegin != nil) then
          # only toggle if it matches string character
          # i.e., "'" would not terminate '"', and vice versa
          if @instring && (@curch == @strbegin) then
            @instring = false
            # also unset @strbegin - this takes care of stuff like "'blah'" and '"foo"'
            # which would otherwise be ambigious
            @strbegin = nil
          else
            @strbegin = @curch
            @instring = true
          end
          out(@curch)
        # ANSI C comment "/* blah blah */"
        # just keep eating until "*/"
        elsif (((@curch == '/') && (@nextch == '*')) && (not @instring)) then
          while true do
            more(infh)
            out_if_keep_ansi
            if ((@curch == '*') && (@nextch == '/')) then
              more(infh)
              out_if_keep_ansi
              break
            end
          end
        # C++ comment "// blah blah"
        # keep eating until EOL
        elsif (((@curch == '/') && (@nextch == '/')) && (was_eol_or_whitespace && (not @instring))) then
          while true do
            more(infh)
            out_if_keep_cplusplus
            if (@curch == "\n") then
              out_if_keep_cplusplus
              break
            end
          end
        # preprocessor
        elsif ((@curch == '#') && (was_eol_or_whitespace && (not @instring)))
          # buffer for preprocessor name ("include", "define", etc)
          cppword = []
          # build buffer, in case a preprocessor line needs to be discarded
          buffer = []
          skipcpp = false
          endofcpp = false
          if not @opts.delete_preprocessor then
            buffer.push(@curch)
          end
          while true do
            more(infh)
            if check_is_eol_or_whitespace(@curch) || (not @curch.match?(/^[a-z]$/i)) then
              if not cppword.empty? then
                sw = cppword.join.downcase
                cppword = []
                if isdel(sw) then
                  skipcpp = true
                  buffer = []
                end
              end
            else
              cppword.push(@curch)
            end
            if (not @opts.delete_preprocessor) && (not skipcpp) then
              buffer.push(@curch)
            end
            if ((@curch == "\n") && (@prevch != '\\')) then
              endofcpp = true
            end
            # finally, once all of the line(s) are consumed, print out buffer (unless specified otherwise)
            # and continue with the other tasks
            if endofcpp then
              if not skipcpp then
                out(*buffer)
              end
              break
            end
          end
        else
          if @opts.ignorecommentlines.length > 0 then
            @opts.ignorecommentlines.each do |pat|
              # todo
            end
          end
          out(@curch)
        end
      end
      @idx += 1
    end
  end

  def do_file(path)
    File.open(path, "rb") do |fh|
      do_handle(fh)
    end
  end
end

begin
  $stdout.sync = true
  opts = OpenStruct.new({
    delete_preprocessor: false,
    deleteme: [],
    keep_ansicomment: false,
    keep_cplusplus: false,
    have_outfile: false,
    outfile: $stdout,
    ignorecommentlines: [],
  })
  (prs=OptionParser.new{|prs|
    prs.on("-h", "--help", "show this help and exit"){
      puts(prs.help)
      exit(0)
    }
    prs.on("-o<file>", "--output=<file>", "write output to <file> (default: stdout)"){|s|
      begin
        opts.outfile = File.open(s, "wb")
      rescue => ex
        $stderr.printf("error: can not open %p for writing: (%s) %s\n", s, ex.class.name, ex.message)
        exit(1)
      else
        opts.have_outfile = true
      end
    }
    prs.on("-p", "--delete-preprocessor", "also remove preprocessor lines (lines starting with '#')"){
      opts.delete_preprocessor = true
    }
    prs.on("-c", "--keep-cpp", "--keep-cplusplus", "keep C++ comments (lines starting with '//')"){
      opts.keep_cplusplus = true
    }
    prs.on("-a", "--keep-ansi", "keep ANSI C comments (blocks starting with '/*' and ending with '*/')"){
      opts.keep_ansicomment = true
    }
    prs.on("-i", "--delete-includes", "delete #include statements"){
      opts.deleteme.push("include")
    }
    prs.on("-x<stmt>", "--delete=<stmt>", "delete #<stmt> statements (may be comma separated)"){|v|
      all = v.to_s.split(",").map{|s| s.strip.downcase }.reject(&:empty?)
      opts.deleteme.push(*all)
    }
  }).parse!
  begin
    rmc = RmCPP.new(opts)
    if ARGV.empty? then
      if $stdin.tty? then
        $stderr.printf("need some files here!\n")
        $stderr.puts(prs.help)
        exit(1)
      else
        rmc.do_handle($stdin)
      end
    else
      if opts.have_outfile then
        if ARGV.length > 1 then
          $stderr.printf("error: '-o' can only be used with one file\n")
          exit(1)
        end
      end
      ARGV.each do |arg|
        rmc.do_file(arg)
      end
    end
  ensure
    if opts.have_outfile then
      opts.outfile.close
    end
  end
end


