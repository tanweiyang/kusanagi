# Kusanagi

Call graph builder based on GCC cgraph dumps.


## Features

This script will read in all the \*.cgraph recursively and build a gigantic 
hash table to represent the call graph. It is able to handle public and 
private symbols that are functions and global / static variables. Weak symbols
are also handled. We also remove artificial symbols like stack pointers, 
`__func__`, `*.LC0` etc.

The only missing piece will be local variables invoking 
indirect calls, but that can only be handled heuristically and is yet to be 
implemented.


## Data structure

Please refer to the code documentation of CGraphBuilder.pm.


## Algorithms

The following algorithms applicable to the call graph are provided:

* Forward reachability
* Backward reachability
* (TBC) Cycle detection

Currently it is set to backward reachability.


## Usage
First compile your source code using the following flag "-fdump-ipa-cgraph":

$ gcc -fdump-ipa-cgraph \*.c


Execute

$ perl -I. ./kusanagi --help

to get a list of options.


To read the database from file cgraph.yaml:

$ perl -I. ./kusanagi -read cgraph.yaml


Example:

$ perl -I. ./kusanagi --root . -d

## Credits
This project is an extension from the Egypt script: https://github.com/lkundrak/egypt

