
#include <iostream>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <vector>
#include <string>

#include "optionparser.hpp"

namespace Utils
{
    // also skips CR
    template<typename Stream>
    int readchar(Stream& fh)
    {
        int ch;
        ch = fh.get();
        if(ch == '\r')
        {
            return readchar(fh);
        }
        return ch;
    }

    template<typename Stream>
    int fpeek(Stream& fh)
    {
        int ch;
        ch = fh.get();
        if(ch != EOF)
        {
            fh.unget();
        }
        return ch;
    }

    std::string& ToLower(std::string& str)
    {
        std::transform(str.begin(), str.end(), str.begin(), ::tolower);
        return str;
    }
    
    template<typename Type>
    std::string Join(const std::vector<Type>& vec, std::string sep="")
    {
        int i;
        std::stringstream ss;
        for(i=0; i<vec.size(); i++)
        {
            ss << vec[i];
            if((i + 1) != vec.size())
            {
                ss << sep;
            }
        }
        return ss.str();
    }
}

struct Options
{
    bool delete_preprocessor = false;
    bool keep_ansicomment = false;
    bool keep_cplusplus = false;
    bool have_outfile = false;


    std::ostream* outfile = &std::cout;
    std::vector<std::string> deleteme;
    std::vector<std::string> ignorecommentlines;
};

class RmCPP
{
    private:
        Options m_opts;
        int m_idx = 0;
        int m_line = 1;
        int m_curch = EOF;
        int m_nextch = EOF;
        int m_prevch = EOF;
        bool m_instring = false;
        bool m_waseol = false;
        int m_strbegin = EOF;

    public:
        RmCPP(Options opts): m_opts(opts)
        {
        }

        template<typename... Args>
        void out(Args&&... args)
        {
            auto& st = *(m_opts.outfile);
            ((st << std::forward<Args>(args)), ...);
        }

        /* read more;
        *    set m_prevch to the value that was m_curch
        *    set m_curch to the current char
        *    m_nextch peeks to the next char
        * also increases m_line incase of EOL
        */
        template<typename Stream>
        int more(Stream& fh)
        {
            m_prevch = m_curch;
            m_curch = Utils::readchar(fh);
            m_nextch = Utils::fpeek(fh);
            if (m_nextch == '\n')
            {
                m_line += 1;
            }
            return m_curch;
        }

        void out_if_keep_ansi()
        {
            if(m_opts.keep_ansicomment)
            {
                out(char(m_curch));
            }
        }

        void out_if_keep_cplusplus()
        {
            if(m_opts.keep_cplusplus)
            {
                out(char(m_curch));
            }
        }

        bool check_is_eol_or_whitespace(int ch)
        {
            return (
                // these account for the beginning of the file
                // if nothing was read yet, m_idx will be 0
                (m_idx == 0) ||
                // whitespace
                (ch == ' ') ||
                (ch == '\n') ||
                (ch == '\t')
            );
        }

        bool was_eol_or_whitespace()
        {
            return check_is_eol_or_whitespace(m_prevch);
        }

        bool isdel(const std::string& s)
        {
            //if(m_opts.deleteme.include?(s))
            /*
            if((m_optss))
            {
                return true;
            }
            */
            return false;
        }

        bool isletter(int ch)
        {
            int ilowbegin = 97;
            int ilowend = 122;
            int iupbegin = 65;
            int iupend = 90;
            return (
                ((ch >= ilowbegin) && (ch <= ilowend)) ||
                ((ch >= iupbegin) && (ch <= iupend))
            );
        };

        template<typename Stream>
        void do_handle(Stream& infh)
        {
            while(true)
            {
                more(infh);
                if(m_curch == EOF)
                {
                    return;
                }
                else
                {
                    // check that m_strbegin was set, because otherwise nested strings will
                    // completely defeat this statemachine!!
                    if((((m_curch == '"') || (m_curch == '\'')) && (m_prevch != '\\')) && (m_strbegin != EOF))
                    {
                        // only toggle if it matches string character
                        // i.e., "'" would not terminate '"', and vice versa
                        if(m_instring && (m_curch == m_strbegin))
                        {
                            m_instring = false;
                            // also unset m_strbegin - this takes care of stuff like "'blah'" and '"foo"'
                            // which would otherwise be ambigious
                            m_strbegin = EOF;
                        }
                        else
                        {
                            m_strbegin = m_curch;
                            m_instring = true;
                        }
                        out(char(m_curch));
                    }
                    // ANSI C comment "/* blah blah */"
                    // just keep eating until "*/"
                    else if(((m_curch == '/') && (m_nextch == '*')) && (not m_instring))
                    {
                        while(true)
                        {
                            more(infh);
                            out_if_keep_ansi();
                            if((m_curch == '*') && (m_nextch == '/'))
                            {
                                more(infh);
                                out_if_keep_ansi();
                                break;
                            }
                        }
                    }
                    // C++ comment "// blah blah"
                    // keep eating until EOL
                    else if(((m_curch == '/') && (m_nextch == '/')) && (was_eol_or_whitespace() && (not m_instring)))
                    {
                        while(true)
                        {
                            more(infh);
                            out_if_keep_cplusplus();
                            if (m_curch == '\n')
                            {
                                out_if_keep_cplusplus();
                                if(m_prevch != '\\')
                                {
                                    break;
                                }
                            }
                        }
                    }
                    // preprocessor
                    else if((m_curch == '#') && (was_eol_or_whitespace() && (not m_instring)))
                    {
                        // buffer for preprocessor name ("include", "define", etc)
                        std::vector<char> cppword;
                        // build buffer, in case a preprocessor line needs to be discarded
                        std::vector<char> buffer;
                        bool skipcpp = false;
                        bool endofcpp = false;
                        if(!m_opts.delete_preprocessor)
                        {
                            buffer.push_back(m_curch);
                        }
                        while(true)
                        {
                            more(infh);
                            //if(check_is_eol_or_whitespace(m_curch) || (not m_curch.match?(/^[a-z]$/i)))
                            if(check_is_eol_or_whitespace(m_curch) || (isletter(m_curch) == false))
                            {
                                if(!cppword.empty())
                                {
                                    std::string sw = Utils::Join(cppword);
                                    Utils::ToLower(sw);
                                    cppword.clear();
                                    if(isdel(sw))
                                    {
                                        skipcpp = true;
                                        buffer.clear();
                                    }
                                }
                            }
                            else
                            {
                                cppword.push_back(m_curch);
                            }
                            if((!m_opts.delete_preprocessor) && (!skipcpp))
                            {
                                buffer.push_back(m_curch);
                            }
                            if((m_curch == '\n') && (m_prevch != '\\'))
                            {
                                endofcpp = true;
                            }
                            // finally, once all of the line(s) are consumed, print out buffer (unless specified otherwise)
                            // and continue with the other tasks
                            if(endofcpp)
                            {
                                if(!skipcpp)
                                {
                                    for(char ch: buffer)
                                    {
                                        out(ch);
                                    }
                                }
                                break;
                            }
                        }
                    }
                    else
                    {
                        if(m_opts.ignorecommentlines.size() > 0)
                        {
                            // todo
                        }
                        out(char(m_curch));
                    }
                }
                m_idx += 1;
            }
        }

        void do_file(const std::string& path)
        {
            std::fstream fh(path, std::ios::in | std::ios::binary);
            do_handle(fh);
        }
};

int main(int argc, char* argv[])
{
    using Value = OptionParser::Value;
    Options opts;
    //(prs=OptionParser.new{|prs|
    OptionParser prs;
    prs.on({"-h", "--help"}, "show this help and exit", [&]
    {
        std::cout << prs.help() << std::endl;
        exit(0);
    });
    /*prs.on({"-o?", "--output=?"}, "write output to <file> (default: stdout)", [&](const Value& v)
    {
            begin
                opts.outfile = File.open(s, "wb")
            rescue => ex
                $stderr.printf("error: can not open %p for writing: (%s) %s\n", s, ex.class.name, ex.message)
                exit(1)
            else
                opts.have_outfile = true
            }
    });
    */
    prs.on({"-p", "--delete-preprocessor"}, "also remove preprocessor lines (lines starting with '#')", [&]
    {
        opts.delete_preprocessor = true;
    });
    prs.on({"-c", "--keep-cpp", "--keep-cplusplus"}, "keep C++ comments (lines starting with '//')", [&]
    {
        opts.keep_cplusplus = true;
    });
    prs.on({"-a", "--keep-ansi"}, "keep ANSI C comments (blocks starting with '/*' and ending with '*/')", [&]
    {
        opts.keep_ansicomment = true;
    });
    prs.on({"-i", "--delete-includes"}, "delete #include statements", [&]
    {
        opts.deleteme.push_back("include");
    });
    /*prs.on("-x<stmt>", "--delete=<stmt>", "delete #<stmt> statements (may be comma separated)"){|v|
        all = v.to_s.split(",").map{|s| s.strip.downcase }.reject(&:empty?)
        opts.deleteme.push(*all)
    }
    */
    
    try
    {
        prs.parse(argc, argv);
        RmCPP rmc(opts);
        auto args = prs.positional();
        if(args.empty())
        {
                rmc.do_handle(std::cin);
        }
        else
        {
            if(opts.have_outfile)
            {
                if(args.size() > 1)
                {
                    std::cerr << "error: '-o' can only be used with one file\n";
                    return 1;
                }
            }
            for(int i=1; i<args.size(); i++)
            {
                rmc.do_file(args[i]);
            }
        }
    }
    catch(std::runtime_error& err)
    {
        std::cerr << "error: " << err.what() << std::endl;
    }
    if(opts.have_outfile)
    {
        //opts.outfile->close();
    }
}



