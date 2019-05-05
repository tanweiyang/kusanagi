###############################################################################
#
# @author TWY
# @date 26th June 2017 
# @version 0.5
#
# This package contains subroutines that parses *.cgraph files and build the
# cgraph hash table.
#
###############################################################################
package CGraphBuilder;

use strict;
use warnings;
use File::Find;
use Cwd;
use Data::Dumper;
use Exporter('import');
use CGraphCommon;

our @EXPORT_OK = ('build_cgraph_hash_table', 
                  'print_cgraph_hash_table', 
                  'read_cgraph_hash_table',
                  'validate_cgraph_hash_table');


###############################################################################
#
# Constants
#
###############################################################################
# Constant pattern for matching identifiers in GCC RTL.
use constant IDENTIFIER_REGEX_ => '[_a-zA-Z][_a-zA-Z0-9]{0,30}';

# For things like stack pointer, the first character is an asterisk.
# For 
use constant SYMBOL_REGEX_ => '[_a-zA-Z*][_a-zA-Z0-9.]+';

# Operator for private symbol.
use constant SYMB_PRIV_OP => '@';

# Printing indentation.
use constant INDENT => '  ';

# Mandatory fields. Note that this is a list.
use constant MANDATORY_FIELDS => ('name', 'filename', 'type', 'visibility');

# Optional fields. This is also a list.
use constant OPTIONAL_FIELDS => ('references', 'referring', 'calls', 
                                 'called_by');

# Mandatory fields. Note that this is a list.
use constant NON_ARRAY_FIELDS => ('name', 'type', 'visibility');

# Optional fields. This is also a list.
use constant ARRAY_FIELDS => ('references', 'referring', 'calls', 'called_by',
                              'filename');


###############################################################################
#
# Subroutines (private)
#
###############################################################################
# ==============================================================
# Misc subroutines
# ==============================================================
# Remove right side white spaces.
# Argument:
#   - input string
# Return the trimmed string.
sub trimright_
{
    my $str = $_[0];
    $str =~ s/\s+$//;
    
    return $str;
}


# Remove all the duplicated strings or integers in the input array.
#
# Arguments:
#   - input array reference that you want to remove its duplicated elements.
sub remove_duplicates_
{
    my $array_ref = $_[0];

    # map() will apply the block to each element in the array. So I am basically
    # creating a new hash where the elements of the array is the key of the has
    # and the value is 0.
    my %hash = map {$_, 0} @$array_ref;

    # Now the keys of the hash will be unique!
    @$array_ref = keys(%hash);
}


# Remove the element in the array based on the index. If index is beyond the
# range of the array, warning will occur and the last element will be removed.
#
# Arguments:
#   - array_ref: the array reference
#   - index: the index of the array that you want to remove
#
sub remove_array_element_
{
    my $array_ref = $_[0];
    my $index = $_[1];

    splice(@$array_ref, $index, 1);
}


# ==============================================================
# Subroutines on parsing files
# ==============================================================
# Parse '[a,b,...]' into an array reference
#
# Arguments:
#   - string input
#
# Returns array reference, or undef if the input str does not parse correctly.
sub parse_array_
{
    my $input_str = $_[0];

    if($input_str =~ /^\[(.*?)\]$/)
    {
        my @item_array = split(', ', $1);
        return \@item_array;
    }

    return undef;        
}


# ==============================================================
# Subroutines on private / public symbol
# ==============================================================
# Check if the symbol is private version.
#
# Arguments:
#   - symbol string
#
# Return 1 if it is private version; 0 otherwise.
sub is_symb_priv_
{
    my $symb = $_[0];

    if(index($symb, SYMB_PRIV_OP) == -1)
    {
        # Cannot find substring.
        return 0;
    }
    else
    {
        return 1;
    }
}


# Change the symbol to non-public version.
#
# Arguments:
#   - the symbol string
#   - the file name
#
# Return the non-public version of the symbol.
sub conv_to_non_public_symb_
{
    my $symb = $_[0];
    my $filename = $_[1];

    return "$symb\@$filename";
}


# Change the symbol to public version.
#
# Arguments:
#   - the symbol string
#
# Return the public version of the symbol.
sub conv_to_public_symb_
{
    my $symb = $_[0];
    $symb =~ s/@.+$//;

    return $symb;
}


# Get both public and non-public versions of the symbols
#
# Arguments:
#   - symbol string
#   - filename string
#
# Return a tuple (public_symb, non_public_symb)
sub get_public_priv_symb_
{
    my $input_symb = $_[0];
    my $filename = $_[1];

    my $non_public_symb;
    my $public_symb;

    if(is_symb_priv_($input_symb))
    {
        $non_public_symb = $input_symb;
        $public_symb = conv_to_public_symb_($input_symb);
    }
    else
    {
        $public_symb = $input_symb;
        $non_public_symb = conv_to_non_public_symb_($input_symb, $filename);
    }

    return ($public_symb, $non_public_symb);
}


# ==============================================================
# Subroutines on cgraph hash table
# ==============================================================
# Check if the symbol entry is spurious, meaning that there is no 'references',
# 'referring', 'calls' and 'called_by' fields.
#
# Arguments:
#   - symbol name string
#   - cgraph hash table reference
#
# Return 1 if there is a deletion; 0 otherwise.
sub delete_spurious_cgraph_symb_
{
    my $symb = $_[0];
    my $cgraph_hash_table_ref = $_[1];

    # Check if the fields in the hash table exist.
    foreach my $field (OPTIONAL_FIELDS)
    {
        if(exists($$cgraph_hash_table_ref{$symb}{$field}))
        {
            return 0;
        }
    }

    # Delete the entry.
    delete($$cgraph_hash_table_ref{$symb});

    return 1;
}


# Append data to the value of the hash table, which is an array reference.
# If the to-append-to array reference is not defined, return.
#
# Arguments:
#   - symbol string
#   - field string (i.e. the field of the symbol which you want to append data)
#   - cgraph hash table reference
#   - datan array reference which you want to append to
sub append_unique_data_to_cgraph_hash_
{
    my $symb = $_[0];
    my $field = $_[1];
    my $cgraph_hash_table_ref = $_[2];
    my $data_array_ref = $_[3];

    # If data_array_ref is not even defined in the first place, then just return.
    if(!defined($data_array_ref))
    {
        return;
    }

    # I think you need to code in this way to take into account of when the 
    # field may not exist in the hash table in the first place.
    my $value_ref = $$cgraph_hash_table_ref{$symb}{$field};
    push(@$value_ref, @$data_array_ref);

    # Going to remove duplication first then later on find multiple potential matches
    # such as private and public calling the same public symb.
    remove_duplicates_($value_ref);

    $$cgraph_hash_table_ref{$symb}{$field} = $value_ref;
}


# Check that the 'visibility' and 'type' of the source and destination symbols
# entries are the same (if destination symbol exists). If so, merge all the 
# fields' data from source to destination. After that delete the source symbol
# entry. If destination symbol does not exist, then it is just merely a 
# replacement of the key string. 
#
# This is mainly used to merge multiple public same symbol.
#
# Arguments:
#   - destination symbol
#   - source symbol
#   - cgraph hash table reference
#
# Return 1 if merging is successful; 0 otherwise.
sub merge_cgraph_symb_
{
    my $dest_symb = $_[0];
    my $src_symb = $_[1];
    my $cgraph_hash_table_ref = $_[2];


    # Source symbol entry MUST exists.
    if(!exists($$cgraph_hash_table_ref{$src_symb}))
    {
        die "Error in merge_cgraph_symb_: source symbol doesn't exist!";
        return 0;
    } 

    # a mere key replacement.
    if(!exists($$cgraph_hash_table_ref{$dest_symb}))
    {
        # This replaces the key string from src_symb to dest_symb.
        $$cgraph_hash_table_ref{$dest_symb} = 
            delete($$cgraph_hash_table_ref{$src_symb});

        return 1;
    }


    # Need to ensure that the types and visibility are the same.
    foreach my $field ('visibility', 'type')
    {
        if($$cgraph_hash_table_ref{$dest_symb}{$field} ne 
           $$cgraph_hash_table_ref{$src_symb}{$field})
        {
            print Dumper($cgraph_hash_table_ref);

            die "Error in merge_cgraph_symb_: fields' don't match!\n".
                "dest_symb: $dest_symb src_symb: $src_symb\n".
                "dest $field: $$cgraph_hash_table_ref{$dest_symb}{$field} ".
                "src $field: $$cgraph_hash_table_ref{$src_symb}{$field}\n";

            return 0;
        }
    }


    # If the destination symbol filename is an empty string, which implies that
    # destination symbol is an external symbol and so will be assigned to src
    # symbol filename.
    my $dest_filenames_ref = $$cgraph_hash_table_ref{$dest_symb}{'filename'};
    my $src_filenames_ref = $$cgraph_hash_table_ref{$src_symb}{'filename'};
    push(@$dest_filenames_ref, @$src_filenames_ref);
    $$cgraph_hash_table_ref{$dest_symb}{'filename'} = $dest_filenames_ref;


    # Append data from src fields to dest fields.
    foreach my $field (OPTIONAL_FIELDS)
    {
        append_unique_data_to_cgraph_hash_(
            $dest_symb, 
            $field, 
            $cgraph_hash_table_ref, 
            $$cgraph_hash_table_ref{$src_symb}{$field});
    }

    # Delete the src symb entry.
    delete($$cgraph_hash_table_ref{$src_symb});

    return 1;
}


# Resolve all the symbols in the optional fields
#
# Arguments: 
#   - cgraph_hash_table_ref: The hash table reference.
#
sub resolve_fields_symb_
{
    CGraphCommon::print_debug("Resolving fields' symbols\n", 1);

    my $cgraph_hash_table_ref = $_[0];
    my @hash_keys = keys(%$cgraph_hash_table_ref);

    CGraphCommon::print_debug("Resolving fields' symbols First Pass\n", 1);

#print Dumper($cgraph_hash_table_ref);


    # Loop through entire cgraph table (first pass)
    # First pass guarantees that 
    # i) All forward step field symbols are properly resolve to private or 
    #    public version.
    # ii) If hash key symb is private, will append this hash key symb to 
    #     all the fields' symbol's opposite field.
    foreach my $symb (@hash_keys)
    {
        # Loop through each of the 'forward-step' fields
        foreach my $field ('references', 'calls')
        {
            my $opp_field;
            if($field eq 'references')
            {
                $opp_field = 'referring';
            }
            else
            {
                $opp_field = 'called_by';
            }


            # Reference to the array of symbols for $field.
            my $field_val_ref = $$cgraph_hash_table_ref{$symb}{$field};

            if(!defined($field_val_ref))
            {
                next;
            }


            my @updated_field_vals = ();
            my $has_weak_symbs = (scalar(@$field_val_ref) > 1);

            # Loop through each symbol in the array of the field
            #for(my $i = 0; $i < scalar(@$field_val_ref);)
            foreach my $field_symb (@$field_val_ref)
            {
                #my $field_symb = $$field_val_ref[$i];

                my $filenames = $$cgraph_hash_table_ref{$symb}{'filename'};
                foreach my $curr_filename (@$filenames)
                {
                    (my $pub_ver_symb, my $priv_ver_symb) = get_public_priv_symb_($field_symb, $curr_filename);
                    my $field_symb_test = $field_symb;

                    CGraphCommon::print_debug(
                        "resolve_fields_symb_: ($symb) curr_filename: $curr_filename field_symb_test: $field_symb_test\n", 2);

                    # Check if such private version of symbol exists as key in 
                    # cgraph. If so, replaces the symbol in the field with the 
                    # private version.
                    if(exists($$cgraph_hash_table_ref{$priv_ver_symb}))
                    {
                        # Note that $field_symb is an alias to the value of the 
                        # array field_val_ref. So any modification of $field_symb
                        # will modify the value in the array.
                        CGraphCommon::print_debug(
                            "#### resolve_fields_symb_: ($field, $symb) $field_symb_test -> $priv_ver_symb\n", 2);

                        $field_symb_test = $priv_ver_symb;
                    }

                    CGraphCommon::print_debug(
                        "#### resolve_fields_symb_ ($symb, $field): field_symb is now $field_symb_test\n", 2);


                    # You need this because even public hash key you should
                    # also append. And you will remove all field symbols that
                    # should not exists. If there are more than 1 file name =>
                    # there are weak symbols. I assume weak symbols must be 
                    # public, so if there are weak symbols, I need to check if 
                    # the field symb opposite field has symb in it. If so, then
                    # I will push into updated array of symbols for current 
                    # field. 
                    if(exists($$cgraph_hash_table_ref{$field_symb_test}) && 
                       (!$has_weak_symbs || CGraphCommon::is_str_in_array($symb, $$cgraph_hash_table_ref{$field_symb_test}{$opp_field})))
                    {
                        # Append if hash key is private to field symb's opposite field
                        # So here even if field symb is public also append.
                        if(is_symb_priv_($symb))
                        {
                            # Update the opposite field for hash key $priv_ver_symb
                            # Question is, should this opposite field has the public
                            # version of $symb.

                            CGraphCommon::print_debug(
                                "#### resolve_fields_symb_: ($opp_field, $field_symb_test) Append $symb\n", 2);

                            my $field_arr_ref = $$cgraph_hash_table_ref{$field_symb_test}{$opp_field};
                            push(@$field_arr_ref, $symb);
                            $$cgraph_hash_table_ref{$field_symb_test}{$opp_field} = $field_arr_ref;
                        }

                        push(@updated_field_vals, $field_symb_test);
                    }
                } # foreach filename
            } # foreach field symbol

            $$cgraph_hash_table_ref{$symb}{$field} = \@updated_field_vals;

        } # foreach field
    } # foreach hash key symb


#print Dumper($cgraph_hash_table_ref);

    CGraphCommon::print_debug("Resolving fields' symbols Second Pass\n", 1);

    # Loop through entire cgraph table (second pass)
    # So here second pass will remove all spurious backward field's public 
    # symbols.
    foreach my $symb (@hash_keys)
    {
        # Loop through each of the 'backward-step' fields
        foreach my $field ('referring', 'called_by')
        {
            # Reference to the array of symbols for $field.
            my $field_val_ref = $$cgraph_hash_table_ref{$symb}{$field};

            if(!defined($field_val_ref))
            {
                next;
            }

            # Loop through each symbol in the array of the field. We will
            # append the results to the final version.

            my @new_field_val = ();
            foreach my $field_symb (@$field_val_ref)
            {
                # We are not going to care about private symbols bec they are
                # already taken care of at first pass.
                if(is_symb_priv_($field_symb))
                {
                    push(@new_field_val, $field_symb);
                    next;
                }


                # Find all the matching public symbols as hash keys and remove
                # if necessary (which is due to artificial symbols).
                if(exists($$cgraph_hash_table_ref{$field_symb}))
                {
                    my $opp_field;
                    if($field eq 'referring')
                    {
                        $opp_field = 'references';
                    }
                    else
                    {
                        $opp_field = 'calls';
                    }

                    if(CGraphCommon::is_str_in_array(
                        $symb, $$cgraph_hash_table_ref{$field_symb}{$opp_field}))
                    {
                        # Remove this as this means the field symbol should be replaced
                        # after first pass.
                        CGraphCommon::print_debug(
                            "#### resolve_fields_symb_: ($symb, $field) Retained $field_symb\n", 2);

                        push(@new_field_val, $field_symb);
                    }
                }
            } # for each field symb

            $$cgraph_hash_table_ref{$symb}{$field} = \@new_field_val;

        } # foreach field
    }

#print Dumper($cgraph_hash_table_ref);

}


# ==============================================================
# Subroutines on parsing strings for building cgraph hash table
# ==============================================================
# Return the regex for fields for matching cgraph table fields.
#
# Arguments:
#   - field type string
# Return the regex for matching the field.
sub cgraph_template_field_regex_
{
    my $regex = "  $_[0]: (.*)\$";
    return $regex;
}


# Parse the input line for name and symbol and set hash filename too.
# The symbol will be always be assumed to be non-public version of the 
# symbol first until visibility parsing shows that it is public.
#
# Arguments:
#   - symbol string
#   - name string
#   - filename
#   - cgraph hash table reference
#
# Return a tuple (symb, name), where symb may be changed to non-public version.
sub parse_cgraph_symb_name_
{
    my $symb = $_[0];
    my $name = $_[1];
    my $filename = $_[2];
    my $cgraph_hash_table_ref = $_[3];


    # We will first assume this is a private symbol until visibility field 
    # shows that it is public.
    $symb = conv_to_non_public_symb_($symb, $filename);

    # It is okay to have identifical symb name as long as we do our deletion
    # or merging or converting to public symb version properly.
    if(exists($$cgraph_hash_table_ref{$symb}))
    {
        ($$cgraph_hash_table_ref{$symb}{'name'} eq $name &&
         CGraphCommon::is_str_in_array(
            $filename, 
            $$cgraph_hash_table_ref{$symb}{'filename'})) or
        die "Error in parse_cgraph_symb_name_: Same symb but ".
            "$$cgraph_hash_table_ref{$symb}{'name'} vs $name AND ".
            "$$cgraph_hash_table_ref{$symb}{'filename'} vs $filename.";
    }

    # Update hash
    $$cgraph_hash_table_ref{$symb}{'name'} = $name;
    my $curr_filenames = $$cgraph_hash_table_ref{$symb}{'filename'};
    push(@$curr_filenames, $filename);
    $$cgraph_hash_table_ref{$symb}{'filename'} = $curr_filenames;
    
    return ($symb, $filename);
}


# Parse the input line for type.
# Arguments:
#   - symb string
#   - input string
#   - cgraph hash table reference
#
# Return the value of 'type'. If undef means there is no parsing as the symbol
# entry does not exist.
sub parse_cgraph_type_
{
    my $symb = $_[0];
    my $input_str = $_[1];
    my $cgraph_hash_table_ref = $_[2];
    my $result;

    if(!exists($$cgraph_hash_table_ref{$symb}))
    {
        return $result;
    }

    if(index($input_str, 'function') != -1)
    {
        $result = 'function';
    }
    elsif(index($input_str, 'variable') != -1)
    {
        $result = 'variable';
    }
    else
    {
        die "parse_cgraph_type_ error: Neither function nor variable!";
    }

    # Error in parsing... type should not be different as what has been already
    # stored in the hash table!
    if(exists($$cgraph_hash_table_ref{$symb}{'type'}) &&
       $$cgraph_hash_table_ref{$symb}{'type'} ne $result)
    {
        die "parse_cgraph_type_ error: Stored in table is ". 
            "$$cgraph_hash_table_ref{$symb}{'type'} but parsed result is ".
            "$result";
    }

    $$cgraph_hash_table_ref{$symb}{'type'} = $result;

    return $result;    
}


# Parse the input line for visibility.
#
# Arguments:
#   - symb string
#   - input string
#   - filename
#   - cgraph hash table reference
#
# Return a tuple (symb, visiblity) where symb is the new symb value if there 
# is any modification made to it, and visibility is either public or '' or
# undef (when cannot find symbol entry in table).
sub parse_cgraph_visibility_
{
    my $symb = $_[0];
    my $input_str = $_[1];
    my $filename = $_[2];
    my $cgraph_hash_table_ref = $_[3];
    my $result = '';

    if(!exists($$cgraph_hash_table_ref{$symb}))
    {
        return ($symb, undef);
    }

    # Hypothesis:
    # - artificial and public do not coexist.
    # - external implies public.
    # - no public implies private.
    # - if weak and is not external and is public, if there is alr a filename,
    #   ignore, else use its current filename.
    # - no more than one non-weak public same symbol.
    my $is_public = (index($input_str, 'public') == -1) ? 0 : 1;
    my $is_artificial = (index($input_str, 'artificial') == -1) ? 0 : 1;
    my $is_external = (index($input_str, 'external') == -1) ? 0 : 1;
    my $is_weak = (index($input_str, 'weak') == -1) ? 0 : 1;

    if($is_artificial && $is_public)
    {
        die "Error in parse_cgraph_visibility_! Hypothesis wrong in " .
            "$input_str: it is both artificial and public.";
    }

    if($is_external && !$is_public)
    {
        die "Error in parse_cgraph_visibility_! Hypothesis wrong in " .
            "$input_str: it is external but not public.";
    }

    if($is_weak && !$is_public)
    {
        die "Error in parse_cgraph_visibility_! Hypothesis wrong in " .
            "$input_str: it is weak but not public.";
    }


    # Need to check if the curr name indicates private symbol.
    # if so, need to check that the parse field is non-public too,
    # else merge all the fields to the public one!

    # if it is non-public, modify the hash key to the new one.
    if($is_public)
    {
        # Symbol is public.

        # If it is external, it means the definition is found in another file.
        if($is_external)
        {
            $$cgraph_hash_table_ref{$symb}{'filename'} = [];
        }


        $result = 'public';
        $$cgraph_hash_table_ref{$symb}{'visibility'} = $result;

        my $new_symb = conv_to_public_symb_($symb);

        # Now we need to start merging hash symbol entries.
        merge_cgraph_symb_($new_symb, $symb, $cgraph_hash_table_ref);
            
        $symb = $new_symb;
    }
    elsif($is_artificial && 
          !exists($$cgraph_hash_table_ref{$symb}{'visibility'}))
    {
        # This means that there is no prior record of visibility, because
        # when dumped, Visibility field will always be dumped out regardless
        # if there is any value to it, and we will thus definitely have a 
        # record of it.
        return ($symb, 'artificial');
    }

    $$cgraph_hash_table_ref{$symb}{'visibility'} = $result;

    return ($symb, $result);
}


# Parse the input line for references. Similarly, if no such symbol entry, 
# do nothing.
#
# Arguments:
#   - symb string
#   - input string
#   - cgraph hash table reference
#
# Return the array of references.
sub parse_cgraph_references_
{
    my $symb = $_[0];
    my $input_str = $_[1];
    my $cgraph_hash_table_ref = $_[2];


    if(!exists($$cgraph_hash_table_ref{$symb}))
    {
        return undef;
    }

    # Remove all the (...) and /<num>.
    $input_str =~ s/\(\w+\)|\/\d+//g; 

    my @results = split(' ', $input_str);

    # Append result array to the hash table value; this will automatically
    # create a new array if the hash value does not exist.
    append_unique_data_to_cgraph_hash_(
        $symb, 'references', $cgraph_hash_table_ref, \@results);

    return @results;
}


# Parse the input line for referring. Similarly, if no such symbol entry, 
# do nothing.
#
# Arguments:
#   - symb string
#   - input string
#   - cgraph hash table reference
#
# Return the array of symbols that has references to this symbol.
sub parse_cgraph_referring_
{
    my $symb = $_[0];
    my $input_str = $_[1];
    my $cgraph_hash_table_ref = $_[2];

    if(!exists($$cgraph_hash_table_ref{$symb}))
    {
        return undef;
    }


    # Remove all the (...) and /<num>.
    $input_str =~ s/\(\w+\)|\/\d+//g; 

    my @results = split(' ', $input_str);
    
    # Append result array to the hash table value; this will automatically
    # create a new array if the hash value does not exist.
    append_unique_data_to_cgraph_hash_(
        $symb, 'referring', $cgraph_hash_table_ref, \@results);

    return @results;
}


# Parse the input line for called by. Similarly, if no such symbol entry, 
# do nothing.
#
# Arguments:
#   - symb string
#   - input string
#   - cgraph hash table reference
#
# Return the array of symbols that calls this symbol.
sub parse_cgraph_called_by_
{
    my $symb = $_[0];
    my $input_str = $_[1];
    my $cgraph_hash_table_ref = $_[2];

    if(!exists($$cgraph_hash_table_ref{$symb}))
    {
        return undef;
    }

    # Remove all the (...) and /<num>.
    $input_str =~ s/\(.+?\)|\/\d+//g; 

    my @results = split(' ', $input_str);

    # Append result array to the hash table value; this will automatically
    # create a new array if the hash value does not exist.
    append_unique_data_to_cgraph_hash_(
        $symb, 'called_by', $cgraph_hash_table_ref, \@results);

    return @results;
}


# Parse the input line for calls. Similarly, if no such symbol entry, 
# do nothing.
#
# Arguments:
#   - symb string
#   - input string
#   - cgraph hash table reference
#
# Return the array of symbols that are called by this symbol.
sub parse_cgraph_calls_
{
    my $symb = $_[0];
    my $input_str = $_[1];
    my $cgraph_hash_table_ref = $_[2];


    if(!exists($$cgraph_hash_table_ref{$symb}))
    {
        return undef;
    }


    # Remove all the (...) and /<num>.
    $input_str =~ s/\(.+?\)|\/\d+//g; 

    my @results = split(' ', $input_str);

    # Append result array to the hash table value; this will automatically
    # create a new array if the hash value does not exist.
    append_unique_data_to_cgraph_hash_(
        $symb, 'calls', $cgraph_hash_table_ref, \@results);

    return @results;
}


# This subroutine will extract data from a line of the symbol table of a 
# cgraph file. It will also look for spurious entry and delete it.
#
# Arguments:
#   - input string
#   - filename string
#   - current function symbolic name reference
#   - cgraph hash_table reference
#
sub parse_cgraph_line_
{
    my $input_str = $_[0];
    my $filename = $_[1];
    my $curr_symb_ref = $_[2];
    my $cgraph_hash_table_ref = $_[3];

    #my $identifier_regex = IDENTIFIER_REGEX_;
    # Realised that the symbol and name can be a function prototype for c++
    # And hopefully there is no '@' symbol...
    my $identifier_regex = '.+?';

    # -------------------------------------------
    # Regex for extracting data from line.
    # -------------------------------------------
    # $1 will match the symbol; $2 will match the name; $3 will match the hexadecimal
    my $name_regex = 
        "^($identifier_regex)/\\d+ \\(($identifier_regex)\\) \@0x([[:xdigit:]]+)\$";
    my $type_regex = cgraph_template_field_regex_('Type');
    my $visibility_regex = cgraph_template_field_regex_('Visibility');
    my $references_regex = cgraph_template_field_regex_('References');
    my $referring_regex = cgraph_template_field_regex_('Referring');
    my $calls_regex = cgraph_template_field_regex_('Calls');
    my $called_by_regex = cgraph_template_field_regex_('Called by');

    if($input_str =~ /$name_regex/)
    {
        # Just to be safe, check for our SYMB_PRIV_OP
        if(index($1, SYMB_PRIV_OP) != -1 ||
           index($2, SYMB_PRIV_OP) != -1)
        {
            die "Error in parse_cgraph_line: There is SYMB_PRIV_OP in either ".
                "symbol $1 or name $2";
        } 

        if($1 ne $$curr_symb_ref)
        {
            # A new symbol is parsed! Start checking previous symbol and delete
            # it if it is a spurious one. Spurious here means there is no 
            # references / being referenced / calls / being called to / from 
            # other symbols.

            if($$curr_symb_ref ne "")
            {
                # There is a previously parsed a symbol, so you need to do 
                # checking for this previously parsed symbol and delete it 
                # whether it is spurious or not.
                delete_spurious_cgraph_symb_($$curr_symb_ref, $cgraph_hash_table_ref);
            }

            # Update the current symb to the parsed one.
            $$curr_symb_ref = $1;
        }
       
        ($$curr_symb_ref, my $name) = parse_cgraph_symb_name_(
                                        $1, 
                                        $2, 
                                        $filename, 
                                        $cgraph_hash_table_ref);
    }
    elsif($input_str =~ /$type_regex/)
    {
        parse_cgraph_type_($$curr_symb_ref, $1, $cgraph_hash_table_ref);
    }
    elsif($input_str =~ /$visibility_regex/)
    {
        ($$curr_symb_ref, my $vis) = parse_cgraph_visibility_(
                                        $$curr_symb_ref,
                                        $1, 
                                        $filename, 
                                        $cgraph_hash_table_ref);

        # Need to check if this is spurious... if so, should just delete it.
        # As of now, I will delete all "artificial" visibility.
        if(defined($vis) && $vis eq 'artificial')
        {
            delete($$cgraph_hash_table_ref{$$curr_symb_ref});
        }
    }
    elsif($input_str =~ /$references_regex/)
    {
        parse_cgraph_references_($$curr_symb_ref, $1, $cgraph_hash_table_ref);
    }
    elsif($input_str =~ /$referring_regex/)
    {
        parse_cgraph_referring_($$curr_symb_ref, $1, $cgraph_hash_table_ref);
    }
    elsif($input_str =~ /$calls_regex/)
    {
        parse_cgraph_calls_($$curr_symb_ref, $1, $cgraph_hash_table_ref);
    }
    elsif($input_str =~ /$called_by_regex/)
    {
        parse_cgraph_called_by_($$curr_symb_ref, $1, $cgraph_hash_table_ref);
    }
}


# Parse input cgraph file. It will also check the last symbol of table for
# spurious entry and delete when appropriate. Note that the second argument
# is to remove the entire file path name when storing the file name in the
# hash table.
#
# Arguments:
#   - entire file path name.
#   - root path that you are searching.
#   - cgraph hash table reference.
sub parse_cgraph_file_
{
    my $input_file = $_[0];
    my $root_path_to_be_removed = $_[1];
    my $cgraph_hash_table_ref = $_[2];

    CGraphCommon::print_debug("Parsing file: $input_file\n", 1);

    # The header string to indicate the start of parsing of file.
    my $header_str = "Initial Symbol table:";
    #my $header_str = "Final Symbol table:";

    # 1 when parsing the table.
    my $start_parsing = 0;

    # The current function / variable symbol.
    my $curr_symb = '';

    my $filename_no_root = $input_file;
    $filename_no_root =~ s/$root_path_to_be_removed//;

    open(my $fh, '<', $input_file) or die "Error opening file - $!\n";
    while(<$fh>) 
    {
        chomp;
        my $trimmed_str = trimright_($_);

        # Should I check for other types of Symbol table and quit just to play safe?
        #if($trimmed_str =~ /^(\w+) Symbol table/)
        #{
        #    print "### Debug: symbol table type is $1\n";
        #}


        if($start_parsing == 1)
        {
            if($trimmed_str eq "")
            {
                # End of table, hence can quit reading the rest of file.
                last;
            }
            else
            {
                parse_cgraph_line_($trimmed_str,
                                   $filename_no_root,
                                   \$curr_symb, 
                                   $cgraph_hash_table_ref);
            }
        }
        else
        {
            if($trimmed_str eq $header_str)
            {
                $start_parsing = 1;
                <$fh>; # Because next line immediately is a blank line; want to discard that.
            }
        }
    }

    close $fh or warn $! ? 
        "Error closing file $input_file: $!" : 
        "Exit status of file $input_file $?";

    # Check the last symbol entry if it is spurious.
    delete_spurious_cgraph_symb_($curr_symb, $cgraph_hash_table_ref);
}


# ==============================================================
# Subroutines on printing and reading
# ==============================================================
# Simple printing of hash tables array values, which will be sequences in YAML.
#
# Argument:
#   - the array reference
#   - file handler
sub print_array_seq_
{
    my $array_ref = $_[0];
    my $fh = $_[1];

    # array_ref must be defined
    if(defined($array_ref))
    { 
        # $indent will be INDENT repeated $depth times.
        my $joined_array = join(', ', @$array_ref);

        print $fh "[$joined_array]";
    }

    print $fh "\n";
}


# Simple printing of hash tables field.
#
# Argument:
#   - field string
#   - the hash table reference of the value of the symbol entry
#   - depth; which level this array will be at (0 means top level)
#   - file handler
#
# Return 1 if field is printed; 0 if there is no such field.
sub print_cgraph_hash_table_field_
{
    my $field = $_[0];
    my $cgraph_hash_table_value_ref = $_[1];
    my $depth = $_[2];
    my $fh = $_[3];

    # $indent will be INDENT repeated $depth times.
    my $indent = INDENT x $depth;

    if(!exists($$cgraph_hash_table_value_ref{$field}))
    {
        return 0;
    }

    print $fh "${indent}$field: ";
    return 1;
}


###############################################################################
#
# Subroutines (public APIs)
#
###############################################################################
# This subroutine will recursively parse files and load the function calls
# tables.
#
# The hash table containing information about each function and global extern 
# variable. The key is the "symbol" of the variable / function, and the value
# is another hash which contains the following field:
# - 'name'      (The exact name of the variable or function. 
#                Value: string)
# - 'type'      (Either 'variable' or 'function'. Default is ""...
#                Value: string)
# - 'visibility'(Can be either '' or 'public'. Default is private. 
#                Value: string)
# - 'filename'  (The file name which this entity is defined. External 
#                visibility will not have filename. Due to possible 'weak'
#                symbols used, this becomes an array of strings instead.
#                Value: array of strings)
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
#
# Arguments:
#   - $root_path: the path you want to recursively traverse.
#
# Return a reference to the created hash table.
#
sub build_cgraph_hash_table
{
    CGraphCommon::print_debug("Building cgraph hash table\n", 1);


   	my $root_path = $_[0];
    CGraphCommon::print_debug("Root path: $root_path\n", 1);

	my %cgraph_hash_table;

    
    # If you want to have a nested subroutine, you should make it anonymous
    # and assign it to some variable.
    my $parse_cgraph_files_ref =
        sub
        {
            my $suffix = "cgraph";
            if ($_ =~ /.*?\.$suffix$/)
            {                
                parse_cgraph_file_($File::Find::name, $root_path, \%cgraph_hash_table);
            }
        };

    # Find all files recursively, and each file will be parsed if suffix is 
    # '.cgraph'.
    # Note that the first parameter should be enclosed using braces instead
    # of parenthesis, as we want to pass in hash reference instead of hash.
    find({wanted => $parse_cgraph_files_ref, no_chdir => 1}, $root_path);

    # Resolve all the private public symbols.
    resolve_fields_symb_(\%cgraph_hash_table);

    return \%cgraph_hash_table;
}


# Check that the hash table is well-formed. Well-formed here means that every
# entry must have a name, type, visibility and filename. Then validate that
# for each of the optional field, the symbols must appear in the corresponding
# opposite field where it is the key of the hash table. For example, if symbol
# A has this symbol B in field 'referring', then symbol B must have A inside 
# its field 'references'.
#
# Arguments:
#   - cgraph hash table reference
#
# Return 1 if well-formed; 0 otherwise.
sub validate_cgraph_hash_table
{
    CGraphCommon::print_debug("Validating hash table\n", 1);

    my $cgraph_hash_table_ref = $_[0];
    my $result = 1;

    foreach my $symb (keys %$cgraph_hash_table_ref)
    {
        foreach my $field (MANDATORY_FIELDS)
        {
            if(!exists($$cgraph_hash_table_ref{$symb}{$field}) && 
               ($$cgraph_hash_table_ref{$symb}{$field} && $field ne 'visibility'))
            {
                print STDERR "Field $field for symbol $symb does not exist!";
                $result = 0;
            }
        }


        foreach my $field (OPTIONAL_FIELDS)
        {
            # Reference to the array of symbols for $field.
            my $field_val_ref = $$cgraph_hash_table_ref{$symb}{$field};

            foreach my $field_symb (@$field_val_ref)
            {
                if($field eq 'references')
                {
                    if(!CGraphCommon::is_str_in_array($symb, $$cgraph_hash_table_ref{$field_symb}{'referring'}))
                    {
                        CGraphCommon::print_debug("Error in validate_cgraph_hash_table_: " .
                                                  "$symb -> references -> $field_symb but no $field_symb -> referring -> $symb\n", 0);
                
                        $result = 0;
                    }
                }
                elsif($field eq 'referring')
                {
                    if(!CGraphCommon::is_str_in_array($symb, $$cgraph_hash_table_ref{$field_symb}{'references'}))
                    {
                        CGraphCommon::print_debug("Error in validate_cgraph_hash_table_: " .
                                                  "$symb -> referring -> $field_symb but no $field_symb -> references -> $symb\n", 0);

                        $result = 0;
                    }
                }    
                elsif($field eq 'calls')
                {
                    if(!CGraphCommon::is_str_in_array($symb, $$cgraph_hash_table_ref{$field_symb}{'called_by'}))
                    {
                        CGraphCommon::print_debug("Error in validate_cgraph_hash_table_: " .
                                                  "$symb -> calls -> $field_symb but no $field_symb -> called_by -> $symb\n", 0);
 
                        $result = 0;
                    }
                }
                elsif($field eq 'called_by')
                {
                    if(!CGraphCommon::is_str_in_array($symb, $$cgraph_hash_table_ref{$field_symb}{'calls'}))
                    {
                        CGraphCommon::print_debug("Error in validate_cgraph_hash_table_: " .
                                                  "$symb -> called_by -> $field_symb but no $field_symb -> calls -> $symb\n", 0);
                        

                        $result = 0;
                    }
                }
                else
                {
                    die "This should never happen; the field is not correct!\n";
                }
            } 
        }
    }

    return $result;
}


# Simple printing of hash tables. Hoping to be compatible with YAML.
#
# Argument:
#   - the hash table you want to print out.
#   - file handler. If undef, will be default to STDOUT.
sub print_cgraph_hash_table
{
    my $cgraph_hash_table_ref = $_[0];
    my $fh = (@_ == 2) ? $_[1] : \*STDOUT;

    foreach my $symb (sort keys %$cgraph_hash_table_ref)
    {
        print $fh "$symb:\n";

        foreach my $field (NON_ARRAY_FIELDS)
        {
            if(print_cgraph_hash_table_field_(
                $field, $$cgraph_hash_table_ref{$symb}, 1, $fh))
            {
                print $fh "$$cgraph_hash_table_ref{$symb}{$field}\n";
            }
        }

        foreach my $field (ARRAY_FIELDS)
        {
            if(print_cgraph_hash_table_field_(
                $field, $$cgraph_hash_table_ref{$symb}, 1, $fh))
            {
                print_array_seq_($$cgraph_hash_table_ref{$symb}{$field}, $fh);
            }
        }
    }
}


# Read in hash table from file handler.
#
# Arguments:
#   - file handler for the hash table file. If undef, STDIN will be used.
#
# Return the hash table reference if successfully read; undef otherwise.
sub read_cgraph_hash_table
{
    my $fh = (@_ == 1) ? $_[0] : \*STDIN;

    my %cgraph_hash_table;

    my $curr_symb;
    while (my $line = <$fh>)
    {
        chomp($line);
      
        CGraphCommon::print_debug("read_cgraph_hash_table: parsing line $line\n", 2);
 
        # Remove all comments and all whitespace lines.
        $line =~ s/#.*//;
        $line = trimright_($line);


        if($line =~ /^(\S+):/)
        {
            # Symbol
            $curr_symb = $1;
        } 
        elsif($line =~ /^  (\S+):\s*(.*)$/)
        {
            # Check that you must have a line that describes what symbol name
            # first. If not then this file format is wrong.
            if(!defined($curr_symb))
            {
                print STDERR "Error in reading: First valid line should ".
                             "always be describing the symbol name!\n";
                return undef;
            }

            my $found_field = 0;
            foreach my $field (MANDATORY_FIELDS)
            {
                if($1 eq $field)
                {
                    if(exists($cgraph_hash_table{$curr_symb}{$1}))
                    {
                        print STDERR "Error in reading: There should not be ".
                                     " two definitions for this same field ".
                                     "$1!\n";
                        return undef;
                    }

                    if($field eq 'filename')
                    {
                        $cgraph_hash_table{$curr_symb}{$field} = 
                            parse_array_($2);

                        print STDERR "Error in reading: filename is not " .
                                     "properly parsed in line: $line\n" 
                            if(!defined($cgraph_hash_table{$curr_symb}{$field}));
                    }
                    else
                    {
                        $cgraph_hash_table{$curr_symb}{$field} = $2;
                    }

                    $found_field = 1;
                    last;
                }    
            }

            if($found_field == 1)
            {
                next;
            }

            foreach my $field (OPTIONAL_FIELDS)
            {
                if($1 eq $field)
                {
                    if(exists($cgraph_hash_table{$curr_symb}{$1}))
                    {
                        print STDERR "Error in reading: There should not be ".
                                     " two definitions for this same field ".
                                     "$1!\n";
                        return undef;
                    }

                    # need to start reading from an array
                    $cgraph_hash_table{$curr_symb}{$field} = 
                            parse_array_($2);


                    if(defined($cgraph_hash_table{$curr_symb}{$field}))
                    {
                        $found_field = 1;
                        last;
                    }
                    else
                    {
                        print STDERR "Error in reading: The array value of " .
                                     "field $field is not properly formatted" .
                                     " in line $line\n";

                        return undef;

                    }
                }           
            }


            if($found_field == 0)
            {
                print STDERR "Error in reading: Field is $1 and we don't ".
                             "support this yet.\n";
                return undef;
            }
        }
    }


    return \%cgraph_hash_table;
}


1

