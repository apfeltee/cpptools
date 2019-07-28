#!/usr/bin/ruby -w

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
  def initialize(opts, infh)
    @opts = opts
    @infh = infh
    @outfile = opts.outfile
    @idx = 0
    @lineno = 1
    @curch = nil
    @nextch = nil
    @prevch = nil
    @havemore = true
    @state = nil
    @callback = nil
  end

  def out(*vals)
    vals.each do |val|
      if val != nil then
        if @callback != nil then
          @callback.call(val)
        else
          @outfile.write(val)
        end
      end
    end
  end

  # read more;
  #  set @prevch to the value that was @curch
  #  set @curch to the current char
  #  @nextch peeks to the next char
  # also increases @lineno incase of EOL
  def more()
    @prevch = @curch
    @curch = Utils.readchar(@infh)
    @nextch = Utils.fpeek(@infh)
    #if (@lineno == 1) then
    #end
    if (@nextch == "\n") then
      @lineno += 1
    end
    if (@curch == nil) then
      @havemore = false
    end
    @idx += 1
    return @curch
  end

  def out_if(boolval, before, after)
    if boolval == true then
      if before != nil then
        out(before)
      end
      out(@curch)
      if after != nil then
        out(after)
      end
    end
  end

  def out_if_keep_ansi(before=nil, after=nil)
    out_if(@opts.keep_ansicomment, before, after)
  end

  def out_if_keep_cplusplus(before=nil, after=nil)
    out_if(@opts.keep_cplusplus, before, after)
  end

  def out_if_keep_preprocessor(before=nil, after=nil)
    out_if(@opts.keep_preprocessor, before, after)
  end

  def check_is_eol_or_whitespace(ch)
    return (
      # these account for the beginning of the file
      # if nothing was read yet, @idx will be 0
      (@idx == 0) ||
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

  def dumpinfo(fn)
    $stderr.printf("%s: curch=%p, prevch=%p, nextch=%p\n", fn, @curch, @prevch, @nextch)
  end

  def do_stringliteral
    #endch = ( if @state == :quotstring then '"' else "'" end);
    endch = @prevch.dup
    while @havemore do
      out(@curch)
      if (@curch == endch) then
        return
      else
        # this is stupid.
        if (@curch == "\\") then
          while @havemore do
            more()
            out(@curch)
            if (@nextch != "\\")  
              break
            end
          end
        end
      end
      more()
    end #while
  end

  def do_commentblock
    out_if_keep_ansi(@prevch)
    while @havemore do
      out_if_keep_ansi
      if (@curch == '*') && (@nextch == '/') then
        more()
        break
      end
      more()
    end
    out_if_keep_ansi
  end

  def do_commentline
    out_if_keep_cplusplus
    while @havemore do
      out_if_keep_cplusplus
      if (@curch == "\n") then
        out(@curch)
        break
      end
      more()
    end
  end

  def do_preprocessor
    ### important: because outputting the preprocessor is conditional,
    ### nothing should be outputted before it has been processed!
    # contains the preprocessor word ("include", "pragma", "if", etc), if any
    cppword = []
    # build buffer, in case a preprocessor line needs to be discarded
    buffer = []
    skippre = false
    endofpre = false
    while @havemore do
      if (@curch == "/") && (@nextch == "*") then
        more()
        do_commentblock
        more
      end
      # a valid ppc word contains only letters (and "_"? maybe? idk)
      if check_is_eol_or_whitespace(@curch) || (not @curch.match?(/^[a-z_]$/i)) then
        if not cppword.empty? then
          sw = cppword.join.downcase
          cppword = []
          # word is marked for removal
          if isdel(sw) then
            skippre = true
            buffer = []
          end
        end
      else
        # keep building the word until a boundary (whitespace, etc) is encountered
        cppword.push(@curch)
      end
      if (@opts.keep_preprocessor == true) && (skippre == false) then
        buffer.push(@curch)
      end
      if ((@curch == "\n") && (@prevch != '\\')) then
        endofpre = true
      end
      # finally, once all of the line(s) are consumed, print out buffer (unless specified otherwise)
      # and continue with the other tasks
      if endofpre then
        if skippre == false then
          # "buffer" now contains the deparsed bits of the preprocessor line,
          # but without the '#'. hence why it needs to printed as well
          if @opts.keep_preprocessor then
            out("#")
          end
          out(*buffer)
        end
        break
      end
      more()
    end
  end

  def main
    while @havemore do
      if @state == nil then
        ###
        ## parsing strings is in fact needed, because they may
        ## contain strings resembling block comments (i.e., "foo /* bar")
        if (@curch == '"') then
          out(@curch)
          @state = :quotstring
        elsif (@curch == "'") then
          out(@curch)
          @state = :charstring
        elsif (@curch == '/') && (@nextch == '/') then
          @state = :commentline
        elsif (@curch == '/') && (@nextch == '*') then
          @state = :commentblock
        elsif (@curch == '#') && was_eol_or_whitespace then
          @state = :preprocessor
        else
          out(@curch)
        end
      else
        if (@state == :quotstring) || (@state == :charstring) then
          do_stringliteral
          @state = nil
        elsif @state == :commentline then
          do_commentline
          @state = nil
        elsif @state == :commentblock then
          do_commentblock
          @state = nil
        elsif @state == :preprocessor then
          do_preprocessor
          @state = nil
        else
          raise ArgumentError, sprintf("unrecognized/unhandled @state %p", @state)
          @state = nil
        end
      end
      # read more input for next loop
      more()
    end
  end

end

def do_handle(opts, hnd)
  RmCPP.new(opts, hnd).main
end

def do_file(opts, file)
  File.open(file, "rb") do |hnd|
    do_handle(opts, hnd)
  end
end

begin
  $stdout.sync = true
  opts = OpenStruct.new({
    deleteme: [],
    # by default, leave ppc as-is
    keep_preprocessor: true,
    # remove ansi-c comments ("/* this stuff */")
    keep_ansicomment: false,
    # remove C++ style comments ("// this stuff")
    keep_cplusplus: false,

    # not used atm: idea was something like regular expressions to whitelist some comments
    # stuff like doxygen, etc
    ignorecommentlines: [],

    ## other options
    have_outfile: false,
    outfile: $stdout,
    
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
      opts.keep_preprocessor = false
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
    if ARGV.empty? then
      if $stdin.tty? then
        $stderr.printf("need some files here!\n")
        $stderr.puts(prs.help)
        exit(1)
      else
        do_handle(opts, $stdin)
      end
    else
      if opts.have_outfile then
        if ARGV.length > 1 then
          $stderr.printf("error: '-o' can only be used with one file\n")
          exit(1)
        end
      end
      ARGV.each do |arg|
        do_file(opts, arg)
      end
    end
  rescue Errno::EPIPE
    exit(0)
  ensure
    if opts.have_outfile then
      opts.outfile.close
    end
  end
end


