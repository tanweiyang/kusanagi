
#
# @author TWY
# @date 26th June 2017 
# @version 0.5
#
# This package contains algorithms that are applied on the CGraph hash table.
#
###############################################################################
package CGraphAlgo;

use strict;
use warnings;
use List::Util 'any';
use Data::Dumper;
use Exporter('import');
use CGraphCommon;

our @EXPORT_OK = ('find_func_rev_cycle',
                  'find_func_cycle',
                  'find_rev_path',
                  'find_path');


###############################################################################
#
# Global Variables
#
###############################################################################


###############################################################################
#
# Subroutines (private)
#
###############################################################################
# Check if element is in array using regex matching.
# 
# Arguments:
#   - element
#   - array reference
#
# Return 1 if it is in the array, 0 otherwise.
sub does_element_regex_match_array_
{
    my $element = $_[0];
    my $array_ref = $_[1];
 
    if(!defined($array_ref))
    {
        return 0;
    }   

    return (any {defined($_) && $element =~ /$_/} @$array_ref);
}


# Checks if the symbol entry name matches the regex pattern and that it is of a
# function type.
#
# Arguments:
#   - symbol string
#   - cgraph hash table reference
#   - pattern regex
#
# Return the function name if matches, or undef if doesn't match. 
sub does_func_name_match_regex_
{
    my $symb = $_[0];
    my $cgraph_hash_table_ref = $_[1];
    my $regex_pattern = $_[2];

    my $type = $$cgraph_hash_table_ref{$symb}{'type'};
    my $name = $$cgraph_hash_table_ref{$symb}{'name'};

    if($name =~ /$regex_pattern/ && $type eq 'function')
    {
        return $name;
        #return 1;
    }
    else
    {
        return undef;
        #return 0;
    }
}


# ==============================================================
# Subroutines on finding paths and cycles
# ==============================================================
# This subroutine will look at the field of the symbol entry and find all 
# matching hash table keys. 
#
# Arguments:
#   - the current symbol string
#   - the field which you want to match the symbols found in this field
#   - the cgraph hash table reference
#   - type of matching; if backward step matching, value is 0, else any other
#     value indicates forward step matching
#
# Return an array of all matching symbols.
sub matching_field_hash_symbols_
{
    my $symb = $_[0];
    my $target_field = $_[1];
    my $cgraph_hash_table_ref = $_[2];
    my $matching_type = $_[3];

    my $field_values_ref = $$cgraph_hash_table_ref{$symb}{$target_field};
    my @matched_symbs = ();

    foreach my $field_value (@$field_values_ref)
    {
        # We grab all matching symbols be it public or private.
        if(exists($$cgraph_hash_table_ref{$field_value}))
        {
            push(@matched_symbs, $field_value);
        }
        else
        {
            die "Error in matching_field_hash_symbols_: the symbol " .
                "$field_value in the hash key symbols: $symb and field: " .
                "$target_field matches anything!";
        }
    }

    return @matched_symbs;
}


# Find all matching symbols which current symbol has a direct call or reference
# to.
#
# Arguments:
#   - current symbol string
#   - cgraph hash table reference
#
# Return an array of matching symbols.
sub next_step_symbols_
{
    my $symb = $_[0];
    my $cgraph_hash_table_ref = $_[1];

    my @matched_symbs;
    push(@matched_symbs, matching_field_hash_symbols_(
            $symb, 'calls', $cgraph_hash_table_ref, 1));
    push(@matched_symbs, matching_field_hash_symbols_(
            $symb, 'references', $cgraph_hash_table_ref, 1));

    return @matched_symbs;
}


# Find all matching symbols which current symbol will be called by or is being 
# referred to.
#
# Arguments:
#   - current symbol string
#   - cgraph hash table reference
#
# Return an array of matching symbols.
sub prev_step_symbols_
{
    my $symb = $_[0];
    my $cgraph_hash_table_ref = $_[1];

    my @matched_symbs;
    push(@matched_symbs, matching_field_hash_symbols_(
            $symb, 'called_by', $cgraph_hash_table_ref, 0));
    push(@matched_symbs, matching_field_hash_symbols_(
            $symb, 'referring', $cgraph_hash_table_ref, 0));

    return @matched_symbs;
}


# This subroutine will try to find a path that from starting function to the 
# ending function. If there is no terminating function regex pattern, then it
# will just stop at any last function call or variable.
#
# Arguments: 
#   - function name
#   - the hash table reference
#   - terminating function regex pattern
#   - array reference of function call patterns to ignore
#   - subroutine reference for finding the next step symbols
#   - function calls array reference
#
# Return 1 if the function name matches the terminating function regex pattern;
# 0 if function name cannot be found in the hash table.
sub find_matching_func_name_ 
{
    my $curr_symb = $_[0];
    my $cgraph_hash_table_ref = $_[1];
    my $terminate_func_regex = $_[2];
    my $ignore_func_array_ref = $_[3];
    my $next_step_subref = $_[4];
    my $found_func_array_ref = $_[5];

    CGraphCommon::print_debug("##### find_matching_func_name: curr_symb: $curr_symb\n", 2);
    #print Data::Dumper->Dump([$found_func_array_ref], [qw(found_func_array_ref)]);
    #print Data::Dumper->Dump([$ignore_func_array_ref], [qw(ignore_func_array_ref)]);

    my $curr_name = $$cgraph_hash_table_ref{$curr_symb}{'name'};
    if(!defined($curr_name))
    {
        die "Error in find_repeating_func_name_: There is no name for the ".
            "symbol entry $curr_symb!\n";
    }

    my $curr_type = $$cgraph_hash_table_ref{$curr_symb}{'type'};
    if(!defined($curr_name))
    {
        die "Error in find_repeating_func_name_: There is no type for the ".
            "symbol entry $curr_symb!\n";
    }

    # curr_name or curr_symb?
    #my $ignore = does_element_regex_match_array_($curr_symb, $ignore_func_array_ref);
    my $ignore = CGraphCommon::is_str_in_array($curr_symb, $ignore_func_array_ref);
    my $repeated = CGraphCommon::is_str_in_array($curr_symb, $found_func_array_ref);
    my $is_func = $curr_type eq 'function';


    # Whenever I match one of the to-be-ignored function calls, or found an
    # already visited function call, I will just return 0 immediately. Note
    # that I am assuming this symbol entry to be of function type. If not, I 
    # will continue.
    # Should i apply this check on variables too?
    #if(($repeated || $ignore) && $is_func)
    if($repeated || $ignore)
    {
        # We catch not only non-existing keys (i.e. no function calls in 
        # $curr_symb) but also cycles.
        return 0;
    }


    # I will first push this curr_symb inside; this will serve as 
    # an indication that i have already visited this function to break loops.
    push (@$found_func_array_ref, $curr_symb);


    if ($curr_name =~ /$terminate_func_regex/ && $is_func) 
    {
        # Found a path to the terminating function regex pattern.
        return 1;
    }
    

    # Note that the value of the hash table is a hash table reference.
    my @next_symbs = &$next_step_subref($curr_symb, $cgraph_hash_table_ref);
    foreach my $next_symb (@next_symbs) 
    {
        my $recur_result = find_matching_func_name_($next_symb,
                                                    $cgraph_hash_table_ref,
                                                    $terminate_func_regex,
                                                    $ignore_func_array_ref,
                                                    $next_step_subref,
                                                    $found_func_array_ref);

        if($recur_result) 
        {
            return 1;
        }
    }


    CGraphCommon::print_debug("%%%%% find_matching_func_name: pushing $curr_symb to ignore array\n", 2);

    # Need to pop the element out as this means curr_name is not
    # going to be part of solution.
    pop(@$found_func_array_ref);
    push(@$ignore_func_array_ref, $curr_symb);
    return 0;
}


# This subroutine will try to do a DFS that find same name that is already 
# inside the array of traversed func names.
#
# Arguments: 
#   - current symbol
#   - the cgraph hash table reference
#   - function patterns array reference that will be ignored
#   - subroutine reference for finding the next step symbols
#   - function calls array reference
#
# Return 1 if a cycle is found; 0 otherwise.
sub find_repeating_func_name_ 
{
    my $curr_symb = $_[0];
    my $cgraph_hash_table_ref = $_[1];
    my $ignore_func_array_ref = $_[2];
    my $next_step_subref = $_[3];
    my $found_func_array_ref = $_[4];

    CGraphCommon::print_debug("##### find_repeating_func_name: curr_symb: $curr_symb\n", 2);
    #print Data::Dumper->Dump([$found_func_array_ref], [qw(found_func_array_ref)]);

    my $curr_name = $$cgraph_hash_table_ref{$curr_symb}{'name'};
    if(!defined($curr_name))
    {
        die "Error in find_repeating_func_name_: There is no name for the ".
            "symbol entry $curr_symb!\n";
    }

    my $curr_type = $$cgraph_hash_table_ref{$curr_symb}{'type'};
    if(!defined($curr_name))
    {
        die "Error in find_repeating_func_name_: There is no type for the ".
            "symbol entry $curr_symb!\n";
    }


    my $ignore = CGraphCommon::is_str_in_array($curr_symb, $ignore_func_array_ref);
    my $repeated = CGraphCommon::is_str_in_array($curr_symb, $found_func_array_ref);
    my $is_func = $curr_type eq 'function';


    if($ignore)
    {
        return 0;
    }
  

    # Look for a pattern in the ignore_func_array_ref that matches the current 
    # function name. If so, ignore. Also, not only need to match the name, but 
    # also that it has to be a function.
    #if($repeated && $is_func)
    if($repeated)
    {
        # A cycle has been found.
#        if($ignore && $repeated)
#        {
#            return 0;
#        }
#        else
#        {
#            # Push again so your trace will show the repeated func call at tail.
#            # Remember, you are pushing function name, not symbol.
#            push(@$found_func_array_ref, $curr_name);
#            return 1;
#        }

         # Push again so your trace will show the repeated func call at tail.
         # Remember, you are pushing function name, not symbol.
         push(@$found_func_array_ref, $curr_name);
         return 1;
    }


    # Only now then I will push this curr_name inside; this will serve as 
    # the "visited" func call array. and I dont care if it is not a function
    # type because I will do checking of function type to decide if i shld
    # return 1 (look at previous if statement).
    push(@$found_func_array_ref, $curr_symb);


# This is the difficult part: finding the next call. I think we can refactor a 
# function out for this. By right, we should find the next symbol in the 
# following way:
# get two versions: public and non-public of the symbol 
# find all that are i) calls ii) references
    my @next_symbs = &$next_step_subref($curr_symb, $cgraph_hash_table_ref);
    foreach my $next_symb (@next_symbs) 
    {
        my $recur_result = find_repeating_func_name_($next_symb,
                                                     $cgraph_hash_table_ref, 
                                                     $ignore_func_array_ref,
                                                     $next_step_subref,
                                                     $found_func_array_ref);

        if ($recur_result) 
        {
            return 1;
        }
    }


    # Need to pop the element out as this means curr_name is not
    # going to be part of solution.
    pop(@$found_func_array_ref);
    push(@$ignore_func_array_ref, $curr_symb);
    return 0;
}


# This subroutine will try to find a path from starting function to the
# ending function.
#
# Arguments: 
#   - start function name regex pattern
#   - the hash table reference
#   - end function name regex pattern
#   - array reference of function call patterns to ignore
#   - the subroutine reference on how to get next step symbols (can be forward
#     or backward)
#
# Return an array of function calls starting with the function name that matches
# the first argument pattern, and ends with the function name that matches the
# second argument pattern.
sub find_generic_func_path_
{
    my $start_func_regex = $_[0]; 
    my $cgraph_hash_table_ref = $_[1]; 
    my $end_func_regex = $_[2]; 
    my $ignore_func_array_ref = $_[3];
    my $next_step_subref = $_[4];

    my @func_calls_array;

    foreach my $symb (keys %$cgraph_hash_table_ref)
    {
        my @ignore_func_array_tmp = @$ignore_func_array_ref;

        if(my $name = does_func_name_match_regex_($symb, 
                                                  $cgraph_hash_table_ref,
                                                  $start_func_regex))
        {
            if(does_element_regex_match_array_($name, $ignore_func_array_ref))
            {
                warn "Your array of patterns to ignore function calls [@$ignore_func_array_ref] matches ".
                     "the starting function name $name! Will still continue ".
                     "from starting function pattern.";
            }


            # Found matching start function. Here we are doing a forward 
            # search, so we are passing in the address of subroutine 
            # next_step_symbols_.
            my $result = find_matching_func_name_($symb,
                                                  $cgraph_hash_table_ref,
                                                  $end_func_regex,
                                                  \@ignore_func_array_tmp,
                                                  $next_step_subref,
                                                  \@func_calls_array);

            if ($result)
            {
                last;   # which means break I believe
            }
        }
    }

    return @func_calls_array;
}


# This subroutine will try to find a path that exhibits a cycle.
#
# Arguments: 
#   - start function name regex pattern
#   - the cgraph hash table reference
#   - array reference of function names pattern to ignore
#   - the subroutine reference on how to get next step symbols (can be forward
#     or backward)
#
# Return an array of function calls starting with the function name that matches
# the first argument pattern, and which also contains a cycle.
sub find_generic_func_cycle_
{
    my $start_func_regex = $_[0]; 
    my $cgraph_hash_table_ref = $_[1]; 
    my $ignore_func_array_ref = $_[2];
    my $next_step_subref = $_[3];

    my @func_calls_array;
    foreach my $symb (keys %$cgraph_hash_table_ref)
    {
        my @ignore_func_array_tmp = @$ignore_func_array_ref;

        # What user really want to match is the function name, not the symbol.
        # Hence, you need to get the name and make sure it is function type.
        if(my $name = does_func_name_match_regex_($symb, 
                                                  $cgraph_hash_table_ref,
                                                  $start_func_regex))
        {
            if(does_element_regex_match_array_($name, $ignore_func_array_ref))
            {
                warn "Your array of patterns to ignore function calls matches ".
                     "the starting function pattern! Will still continue from ".
                     "starting function pattern.";
            }

            # Found matching start function.
            my $result = find_repeating_func_name_($symb, 
                                                   $cgraph_hash_table_ref,
                                                   \@ignore_func_array_tmp,
                                                   $next_step_subref,
                                                   \@func_calls_array);

            if($result)
            {
                last;   # which means break I believe
            }
        }
    }

    return @func_calls_array;
}


###############################################################################
#
# Subroutines (public APIs)
#
###############################################################################
# This subroutine will try to find a path from starting function to the
# ending function.
#
# Arguments: 
#   - start function name regex pattern
#   - the hash table reference
#   - end function name regex pattern
#   - array reference of function call patterns to ignore
#
# Return an array of function calls starting with the function name that matches
# the first argument pattern, and ends with the function name that matches the
# second argument pattern.
sub find_path 
{
    my $start_func_regex = $_[0]; 
    my $cgraph_hash_table_ref = $_[1]; 
    my $end_func_regex = $_[2]; 
    my $ignore_func_array_ref = $_[3];

    if(!defined $ignore_func_array_ref)
    {
        $ignore_func_array_ref = []; # empty array ref
    }

    CGraphCommon::print_debug("Start finding reachability\n", 1);

    return find_generic_func_path_($start_func_regex,
                                   $cgraph_hash_table_ref,
                                   $end_func_regex,
                                   $ignore_func_array_ref,
                                   \&next_step_symbols_);
    
    CGraphCommon::print_debug("Done finding reachability\n", 1);
}


# This subroutine will try to find a reverse path from starting function to the
# ending function.
#
# Arguments: 
#   - start function name regex pattern
#   - the hash table reference
#   - end function name regex pattern
#   - array reference of function call patterns to ignore
#
# Return an array of function calls starting with the function name that matches
# the first argument pattern, and ends with the function name that matches the
# second argument pattern.
sub find_rev_path
{
    my $start_func_regex = $_[0]; 
    my $cgraph_hash_table_ref = $_[1]; 
    my $end_func_regex = $_[2]; 
    my $ignore_func_array_ref = $_[3];

    if(!defined $ignore_func_array_ref)
    {
        $ignore_func_array_ref = []; # empty array ref
    }

    CGraphCommon::print_debug("Start finding reverse reachability\n", 1);

    return find_generic_func_path_($start_func_regex,
                                   $cgraph_hash_table_ref,
                                   $end_func_regex,
                                   $ignore_func_array_ref,
                                   \&prev_step_symbols_);
    
    CGraphCommon::print_debug("Done finding reverse reachability\n", 1);
}


# This subroutine will try to find a path that exhibits a cycle.
#
# Arguments: 
#   - start function name regex pattern
#   - the cgraph hash table reference
#   - array reference of function names pattern to ignore
#
# Return an array of function calls starting with the function name that matches
# the first argument pattern, and which also contains a cycle.
sub find_func_cycle
{
    my $start_func_regex = $_[0]; 
    my $cgraph_hash_table_ref = $_[1]; 
    my $ignore_func_array_ref = $_[2];

    CGraphCommon::print_debug("Start finding cycles\n", 1);

    return find_generic_func_cycle_($start_func_regex, 
                                    $cgraph_hash_table_ref,
                                    $ignore_func_array_ref,
                                    \&next_step_symbols_);
    
    CGraphCommon::print_debug("Done finding cycles\n", 1);
}


# This subroutine will try to find a reverse path that exhibits a cycle.
#
# Arguments: 
#   - start function name regex pattern
#   - the cgraph hash table reference
#   - array reference of function names pattern to ignore
#
# Return an array of function calls starting with the function name that matches
# the first argument pattern, and which also contains a cycle.
sub find_func_rev_cycle
{
    my $start_func_regex = $_[0]; 
    my $cgraph_hash_table_ref = $_[1]; 
    my $ignore_func_array_ref = $_[2];

    CGraphCommon::print_debug("Start finding reverse cycles\n", 1);

    return find_generic_func_cycle_($start_func_regex, 
                                    $cgraph_hash_table_ref,
                                    $ignore_func_array_ref,
                                    \&prev_step_symbols_);
    
    CGraphCommon::print_debug("Done finding reverse cycles\n", 1);
}


1

