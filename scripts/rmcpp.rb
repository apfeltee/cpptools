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
    @curch = nil
    @nextch = nil
    @prevch = nil
    @instring = false
    @waseol = false
    @strchar = nil
  end

  def out(*vals)
    vals.each do |val|
      if val != nil then
        @outfile.write(val)
      end
    end
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
      (ch == " ") ||
      (ch == "\n") ||
      (ch == "\t")
    )
  end

  def was_eol_or_whitespace
    return check_is_eol_or_whitespace(@prevch)
  end

  def more(fh)
    @prevch = @curch
    @curch = Utils.readchar(fh)
    @nextch = Utils.fpeek(fh)
    return @curch
  end

  def do_handle(infh)
    while true do
      more(infh)
      if @curch == nil then
        return
      else
        if ((@curch == '"') || (@curch == "'")) && (@prevch != '\\') then
          # only toggle if it matches string character
          # i.e., "'" would not terminate '"', and vice versa
          if (@instring == true) && (@curch == @strchar) then
            @instring = false
          else
            @strchar = @curch
            @instring = true
          end
          out(@curch)
        # ANSI C comment "/* blah blah */"
        # just keep eating until "*/"
        elsif ((@curch == '/') && (@nextch == '*') && (@instring == false)) then
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
        elsif ((@curch == '/') && (@nextch == '/') && (((@idx == 0) || was_eol_or_whitespace) && (@instring == false))) then
          while true do
            more(infh)
            out_if_keep_cplusplus
            if (@curch == "\n") then
              out_if_keep_cplusplus
              break
            end
          end
          # preprocessor
        elsif ((@curch == '#') && (((@idx == 0) || was_eol_or_whitespace) && (@instring == false))) then
          cppword = []
          buffer = []
          skipcpp = false
          endofcpp = false
          if not @opts.delete_preprocessor then
            buffer.push(@curch)
          end
          while true do
            more(infh)
            if @opts.delete_includes then
              if check_is_eol_or_whitespace(@curch) || (not @curch.match?(/^[a-z]$/i)) then
                if not cppword.empty? then
                  sword = cppword.join.downcase
                  cppword = []
                  # if delete_includes is specified, then '#include's will be filtered here
                  if sword == "include" then
                    skipcpp = true
                    buffer = []
                  end
                end
              else
                cppword.push(@curch)
              end
            end
            if (@opts.delete_preprocessor == false) && (skipcpp == false) then
              buffer.push(@curch)
            end
            if ((@curch == "\n") && (@prevch != '\\')) then
              endofcpp = true
            end
            # finally, once all of the line(s) are consumed, print out buffer (unless specified otherwise)
            # and continue with the other tasks
            if endofcpp then
              if skipcpp == false then
                out(*buffer)
              end
              break
            end
          end
        else
          if @opts.ignorecommentlines.length > 0 then
            @opts.ignorecommentlines.each do |pat|
              
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
    delete_includes: false,
    keep_ansicomment: false,
    keep_cplusplus: false,
    have_outfile: false,
    outfile: $stdout,
    ignorecommentlines: [],
  })
  OptionParser.new{|prs|
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
      opts.delete_includes = true
    }
  }.parse!
  begin
    rmc = RmCPP.new(opts)
    if ARGV.empty? then
      if $stdin.tty? then
        $stderr.printf("usage: rmcpp [<options>] <file> ...\n")
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


