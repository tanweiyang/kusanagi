#!/usr/bin/perl -W

###############################################################################
#
# @author TWY
# @date 22nd May 2017 
# @version 0.5
#
# This script is an attempt to extend the Perl script "Egypt" version 1.10:
# https://github.com/lkundrak/egypt
#
###############################################################################
use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use File::Basename;
use CGraphBuilder;
use CGraphAlgo;


###############################################################################
#
# Subroutines
#
###############################################################################
# Print the help instructions. Yes I know I should use pod2usage, but maybe
# next time? I am kind of rushing for time.
sub print_help
{
    my $curr_file = basename($0);

    print(
        "Usage: $curr_file [OPTION]... [-read=<filename>|-root=<path>]... [-d]\n" .
        "Note that you cannot have both -read and -root options, and you " .
        "to specify either.\n" .
        " -h, --help\t\t Display this help and exit.\n" .
        " -v, --verbose=i\t Set verbosity level. i can be eiher 0 or 1.\n" .
        " --root=<path>\t\t The path which this script will recursively " .
        "parse all *.craph files.\n" .
        " --read=<filename>\t The input file which contains the data " .
        "structure of the entire call graph.\n" .
        " -d, --dump\t Dump the call graph to the file cgraph.yaml.\n"); 

    exit(0);
}


###############################################################################
#
# Main script 
#
###############################################################################
# A hash table containing information about each function and global extern 
# variable. The key is the "symbol" of the variable / function, and the value
# is another hash which contains the following field:
# - 'name'      (The exact name of the variable or function. 
#                Value: string)
# - 'type'      (Either 'variable' or 'function'. Default is ""...
#                Value: string)
# - 'visibility'(Can be either '' or 'public'. Default is private. 
#                Value: string)
# - 'filename'  (The file name which this entity is defined. External 
#                visibility will not have filename.
#                Value: string)
# - 'references'(Other functions which this function or variable will
#                symbolically reference. This implies indirect calls.
#                Value: reference to an array of strings)
# - 'referring' (Symbolically being referenced by other functions. Opposite of)
#                the field 'references'.
#                Value: reference to an array of strings)
# - 'calls'     (Direct function calls.
#                Value: reference to an array of strings)
# - 'called_by' (Function calls that are directly calling this function.
#                Opposite of the field 'calls'.
#                Value: reference to an array of strings)
#
# When there are duplicates, there should only be one public symbol and all
# other identical symbols should be non-public (i.e. exposed to the same 
# translation unit only). Hence, when the function or variable is non-public,
# its symbol will be appended with '@filename', where filename is the name
# of the file.
#
# Also note that during parsing, if the function or variable has zero length 
# array for references, referring, calls and called_by, this entry will be 
# removed.
#
# If the visibility is public, the filename will just be one of the instances
# which the symbol appears in. I think this will only happen for stack pointer.
# If the visibility is external, then filename will change to an empty string.
# During merging of entries, empty filename will be overwritten. We presume 
# that visibility that has 'external' implies 'public'.
my $cgraph_hash_table_ref;
 

# Get command line options...
my $verbosity = 0;
my $root_path;
my $cgraph_in_filename;
my $dump_cgraph = 0;
my $show_help = 0;
GetOptions('v|verbose=i' => \$verbosity,
           'root=s' => \$root_path,
           'read=s' => \$cgraph_in_filename,
           'd|dump' => \$dump_cgraph,
           'h|help|?' => \$show_help);


# If the options are not correct or if the help option is 
# specified, show the help message and exit.
if($show_help ||
   (!defined($root_path) && !defined($cgraph_in_filename)) ||
   (defined($root_path) && defined($cgraph_in_filename)))
{
    print_help();
}


# Set verbosity.
CGraphCommon::set_verbosity($verbosity);


# Read in the cgraph file.
if(defined($cgraph_in_filename))
{
print "cgraph_in_filename: $cgraph_in_filename\n";

    # Dump out the hash tables.
    open (my $fh_in, '<', $cgraph_in_filename) or 
        die "Error opening file - $!\n";

    $cgraph_hash_table_ref = 
        CGraphBuilder::read_cgraph_hash_table($fh_in);

    if(!defined($cgraph_hash_table_ref))
    {
        close $fh_in or warn $! ? 
            "Error closing file $cgraph_in_filename: $!" : 
            "Exit status of file $cgraph_in_filename $?";

        die "Error in reading file $cgraph_in_filename\n";
    }

    close $fh_in or warn $! ? 
        "Error closing file $cgraph_in_filename: $!" : 
        "Exit status of file $cgraph_in_filename $?";
}


# Build the call graph hash table by recursively parse all the *.cgraph files 
# from the $root_path.
if(defined($root_path))
{
    $cgraph_hash_table_ref = CGraphBuilder::build_cgraph_hash_table($root_path);
}


# Validate the call graph.
CGraphBuilder::validate_cgraph_hash_table($cgraph_hash_table_ref) or 
    die "Error in cgraph_hash_table: table is not well-formed!";


# After building the call graph, dump out to the output file.
if($dump_cgraph)
{
    my $cgraph_out_filename = 'cgraph.yaml';

    open(my $fh_out, '>', $cgraph_out_filename) or die "Error opening file - $!\n";
    
    CGraphBuilder::print_cgraph_hash_table($cgraph_hash_table_ref, $fh_out);
    
    close $fh_out or warn $! ? 
        "Error closing file $cgraph_out_filename: $!" : 
        "Exit status of file $cgraph_out_filename $?";
}


