const std = @import("std");
const builtin = @import("builtin");

const parse_dir_colors = @import("color.zig").parse_dir_colors;
const initlinedraw = @import("color.zig").initlinedraw;
const fancy = @import("color.zig").fancy;

pub fn print() void {
    parse_dir_colors();
    initlinedraw(false);
    var buf: [1024]u8 = undefined;
    var fw = std.fs.File.stderr().writer(&buf);
    defer fw.interface.flush() catch {};

    fancy(&fw.interface, @constCast("usage: \x08tree\r [\x08-acdfghilnpqrstuvxACDFJQNSUX\r] [\x08-L\r \x0clevel\r [\x08-R\r]] [\x08-H\r [-]\x0cbaseHREF\r]\n" ++
        "\t[\x08-T\r \x0ctitle\r] [\x08-o\r \x0cfilename\r] [\x08-P\r \x0cpattern\r] [\x08-I\r \x0cpattern\r] [\x08--gitignore\r]\n" ++
        "\t[\x08--gitfile\r[\x08=\r]\x0cfile\r] [\x08--matchdirs\r] [\x08--metafirst\r] [\x08--ignore-case\r]\n" ++
        "\t[\x08--nolinks\r] [\x08--hintro\r[\x08=\r]\x0cfile\r] [\x08--houtro\r[\x08=\r]\x0cfile\r] [\x08--inodes\r] [\x08--device\r]\n" ++
        "\t[\x08--sort\r[\x08=\r]\x0cname\r] [\x08--dirsfirst\r] [\x08--filesfirst\r] [\x08--filelimit\r[\x08=\r]\x0c#\r] [\x08--si\r]\n" ++
        "\t[\x08--du\r] [\x08--prune\r] [\x08--charset\r[\x08=\r]\x0cX\r] [\x08--timefmt\r[\x08=\r]\x0cformat\r] [\x08--fromfile\r]\n" ++
        "\t[\x08--fromtabfile\r] [\x08--fflinks\r] [\x08--info\r] [\x08--infofile\r[\x08=\r]\x0cfile\r] [\x08--noreport\r]\n" ++
        "\t[\x08--hyperlink\r] [\x08--scheme\r[\x08=\r]\x0cschema\r] [\x08--authority\r[\x08=\r]\x0chost\r] [\x08--opt-toggle\r]\n" ++
        "\t[\x08--compress\r[\x08=\r]\x0c#\r] [\x08--condense\r] [\x08--version\r] [\x08--help\r]" ++
        (if (comptime builtin.os.tag == .linux) " [\x08--acl\r] [\x08--selinux\r]\n" else "\n") ++
        "\t[\x08--\r] [\x0cdirectory\r \x08...\r]\n"));
}

pub fn print_all() void {
    parse_dir_colors();
    initlinedraw(false);
    var buf: [4096]u8 = undefined;
    var fw = std.fs.File.stdout().writer(&buf);
    defer fw.interface.flush() catch {};

    fancy(&fw.interface, @constCast("usage: \x08tree\r [\x08-acdfghilnpqrstuvxACDFJQNSUX\r] [\x08-L\r \x0clevel\r [\x08-R\r]] [\x08-H\r [-]\x0cbaseHREF\r]\n" ++
        "\t[\x08-T\r \x0ctitle\r] [\x08-o\r \x0cfilename\r] [\x08-P\r \x0cpattern\r] [\x08-I\r \x0cpattern\r] [\x08--gitignore\r]\n" ++
        "\t[\x08--gitfile\r[\x08=\r]\x0cfile\r] [\x08--matchdirs\r] [\x08--metafirst\r] [\x08--ignore-case\r]\n" ++
        "\t[\x08--nolinks\r] [\x08--hintro\r[\x08=\r]\x0cfile\r] [\x08--houtro\r[\x08=\r]\x0cfile\r] [\x08--inodes\r] [\x08--device\r]\n" ++
        "\t[\x08--sort\r[\x08=\r]\x0cname\r] [\x08--dirsfirst\r] [\x08--filesfirst\r] [\x08--filelimit\r[\x08=\r]\x0c#\r] [\x08--si\r]\n" ++
        "\t[\x08--du\r] [\x08--prune\r] [\x08--charset\r[\x08=\r]\x0cX\r] [\x08--timefmt\r[\x08=\r]\x0cformat\r] [\x08--fromfile\r]\n" ++
        "\t[\x08--fromtabfile\r] [\x08--fflinks\r] [\x08--info\r] [\x08--infofile\r[\x08=\r]\x0cfile\r] [\x08--noreport\r]\n" ++
        "\t[\x08--hyperlink\r] [\x08--scheme\r[\x08=\r]\x0cschema\r] [\x08--authority\r[\x08=\r]\x0chost\r] [\x08--opt-toggle\r]\n" ++
        "\t[\x08--compress\r[\x08=\r]\x0c#\r] [\x08--condense\r] [\x08--version\r] [\x08--help\r]" ++
        (if (comptime builtin.os.tag == .linux) " [\x08--acl\r] [\x08--selinux\r]\n" else "\n") ++
        "\t[\x08--\r] [\x0cdirectory\r \x08...\r]\n"));

    fancy(&fw.interface, @constCast("  \x08------- Listing options -------\r\n" ++
        "  \x08-a\r            All files are listed.\n" ++
        "  \x08-d\r            List directories only.\n" ++
        "  \x08-l\r            Follow symbolic links like directories.\n" ++
        "  \x08-f\r            Print the full path prefix for each file.\n" ++
        "  \x08-x\r            Stay on current filesystem only.\n" ++
        "  \x08-L\r \x0clevel\r      Descend only \x0clevel\r directories deep.\n" ++
        "  \x08-R\r            Rerun tree when max dir level reached.\n" ++
        "  \x08-P\r \x0cpattern\r    List only those files that match the pattern given.\n" ++
        "  \x08-I\r \x0cpattern\r    Do not list files that match the given pattern.\n" ++
        "  \x08--gitignore\r   Filter by using \x08.gitignore\r files.\n" ++
        "  \x08--gitfile\r \x0cX\r   Explicitly read a gitignore file.\n" ++
        "  \x08--ignore-case\r Ignore case when pattern matching.\n" ++
        "  \x08--matchdirs\r   Include directory names in \x08-P\r pattern matching.\n" ++
        "  \x08--metafirst\r   Print meta-data at the beginning of each line.\n" ++
        "  \x08--prune\r       Prune empty directories from the output.\n" ++
        "  \x08--info\r        Print information about files found in \x08.info\r files.\n" ++
        "  \x08--infofile\r \x0cX\r  Explicitly read info file.\n" ++
        "  \x08--noreport\r    Turn off file/directory count at end of tree listing.\n" ++
        "  \x08--charset\r \x0cX\r   Use charset \x0cX\r for terminal/HTML and indentation line output.\n" ++
        "  \x08--filelimit\r \x0c#\r Do not descend dirs with more than \x0c#\r files in them.\n" ++
        "  \x08--condense\r    Condense directory singletons to a single line of output.\n" ++
        "  \x08-o\r \x0cfilename\r   Output to file instead of stdout.\n" ++
        "  \x08------- File options -------\r\n" ++
        "  \x08-q\r            Print non-printable characters as '\x08?\r'.\n" ++
        "  \x08-N\r            Print non-printable characters as is.\n" ++
        "  \x08-Q\r            Quote filenames with double quotes.\n" ++
        "  \x08-p\r            Print the protections for each file.\n" ++
        "  \x08-u\r            Displays file owner or UID number.\n" ++
        "  \x08-g\r            Displays file group owner or GID number.\n" ++
        "  \x08-s\r            Print the size in bytes of each file.\n" ++
        "  \x08-h\r            Print the size in a more human readable way.\n" ++
        "  \x08--si\r          Like \x08-h\r, but use in SI units (powers of 1000).\n" ++
        "  \x08--du\r          Compute size of directories by their contents.\n" ++
        "  \x08-D\r            Print the date of last modification or (-c) status change.\n" ++
        "  \x08--timefmt\r \x0cfmt\r Print and format time according to the format \x0cfmt\r.\n" ++
        "  \x08-F\r            Appends '\x08/\r', '\x08=\r', '\x08*\r', '\x08@\r', '\x08|\r' or '\x08>\r' as per \x08ls -F\r.\n" ++
        "  \x08--inodes\r      Print inode number of each file.\n" ++
        "  \x08--device\r      Print device ID number to which each file belongs.\n" ++
        (if (comptime builtin.os.tag == .linux)
            "  \x08--acl\r         Print permissions with a + if an ACL is present.\n" ++
                "  \x08--selinux\r     Print the selinux security label if present.\n"
        else
            "")));

    fancy(&fw.interface, @constCast("  \x08------- Sorting options -------\r\n" ++
        "  \x08-v\r            Sort files alphanumerically by version.\n" ++
        "  \x08-t\r            Sort files by last modification time.\n" ++
        "  \x08-c\r            Sort files by last status change time.\n" ++
        "  \x08-U\r            Leave files unsorted.\n" ++
        "  \x08-r\r            Reverse the order of the sort.\n" ++
        "  \x08--dirsfirst\r   List directories before files (\x08-U\r disables).\n" ++
        "  \x08--filesfirst\r  List files before directories (\x08-U\r disables).\n" ++
        "  \x08--sort\r \x0cX\r      Select sort: \x08\x0cname\r,\x08\x0cversion\r,\x08\x0csize\r,\x08\x0cmtime\r,\x08\x0cctime\r,\x08\x0cnone\r.\n" ++
        "  \x08------- Graphics options -------\r\n" ++
        "  \x08-i\r            Don't print indentation lines.\n" ++
        "  \x08-A\r            Print ANSI lines graphic indentation lines.\n" ++
        "  \x08-S\r            Print with CP437 (console) graphics indentation lines.\n" ++
        "  \x08-n\r            Turn colorization off always (\x08-C\r overrides).\n" ++
        "  \x08-C\r            Turn colorization on always.\n" ++
        "  \x08--compress\r \x0c#\r  Compress indentation lines.\n" ++
        "  \x08------- XML/HTML/JSON/HYPERLINK options -------\r\n" ++
        "  \x08-X\r            Prints out an XML representation of the tree.\n" ++
        "  \x08-J\r            Prints out an JSON representation of the tree.\n" ++
        "  \x08-H\r \x0cbaseHREF\r   Prints out HTML format with \x0cbaseHREF\r as top directory.\n" ++
        "  \x08-T\r \x0cstring\r     Replace the default HTML title and H1 header with \x0cstring\r.\n" ++
        "  \x08--nolinks\r     Turn off hyperlinks in HTML output.\n" ++
        "  \x08--hintro\r \x0cX\r    Use file \x0cX\r as the HTML intro.\n" ++
        "  \x08--houtro\r \x0cX\r    Use file \x0cX\r as the HTML outro.\n" ++
        "  \x08--hyperlink\r   Turn on OSC 8 terminal hyperlinks.\n" ++
        "  \x08--scheme\r \x0cX\r    Set OSC 8 hyperlink scheme, default \x08\x0cfile://\r\n" ++
        "  \x08--authority\r \x0cX\r Set OSC 8 hyperlink authority/hostname.\n" ++
        "  \x08------- Input options -------\r\n" ++
        "  \x08--fromfile\r    Reads paths from files (\x08.\r=stdin)\n" ++
        "  \x08--fromtabfile\r Reads trees from tab indented files (\x08.\r=stdin)\n" ++
        "  \x08--fflinks\r     Process link information when using \x08--fromfile\r.\n" ++
        "  \x08------- Miscellaneous options -------\r\n" ++
        "  \x08--opt-toggle\r  Enable option toggling.\n" ++
        "  \x08--version\r     Print version and exit.\n" ++
        "  \x08--help\r        Print usage and this help message and exit.\n" ++
        "  \x08--\r            Options processing terminator.\n"));
}
