###############################################################################
#
# @author TWY
# @date 29th June 2017 
# @version 0.5
#
# This package contains functions and constants common to other CGraph packages
#
###############################################################################
package CGraphCommon;

use strict;
use warnings;
use List::Util 'any';
use Exporter('import');

our @EXPORT_OK = ('is_str_in_array', 'set_verbosity', 'print_debug');


###############################################################################
#
# Global 'Private' Variables
#
###############################################################################
# Default is not verbose.
my $Verbosity_ = 0;


###############################################################################
#
# Subroutines (public APIs)
#
###############################################################################
# Check if the element is in array (using string equality for comparison).
# 
# Arguments:
#   - element string
#   - array reference
#
# Return 1 if it is in the array, 0 otherwise.
sub is_str_in_array
{
    my $element = $_[0];
    my $array_ref = $_[1]; 
    
    if(!defined($array_ref))
    {
        return 0;
    }

    return (any {defined($_) && $element eq $_} @$array_ref);
}


# Print the current time based on localtime.
sub curr_time
{
    my @months = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
    #my @days_of_week = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
    return "$months[$mon] $mday $hour:$min:$sec";
}


# Print if the debug level is less than the verbosity level.
#
# Arguments:
#   - string to print out
#   - debug level
sub print_debug
{
    my $str = $_[0];
    my $debug_level = $_[1];

    if($debug_level <= $Verbosity_)
    {
        my $my_time = curr_time();
        print("[$my_time] $str");
    }
}


# Set the verbosity level (0 - 2 where 0 is least verbose)
#
# Arguments:
#   - verbosity level
sub set_verbosity
{
    $Verbosity_ = $_[0];

    print_debug("Setting verbosity to $Verbosity_\n", 1);
}




1

