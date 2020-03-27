Dynamic libraries for Goldfinch - proof of concept
==================================================

In this example, we have two code files: border.asm, and whitens.asm which depends on border.asm. These are compiled to .obj files using z80asm from the z88dk framework. We want to load these at a memory location of our choice, resolving dependencies and patching address references as we go.

To do this, we introduce a new file format for dynamically loadable object code, .dog. Like the .obj file format, this consists of:

* compiled, unlinked code;
* a list of symbols exported by this module;
* a list of external symbols that this module depends on;
* a list of addresses within the code that need to be patched once the code and its dependencies have been loaded into memory, as they contain values that are only known at linking time.

The .dog format differs from .obj in several key ways:

* Rather than symbols being arbitrary strings, they are references of the form "the Nth symbol in module foo.dog";
* The patching is done using a form of bytecode. (The .obj format stores expression strings to be evaluated - these can contain arbitrary arithmetic operators, and parsing these on the Spectrum would be too much overhead.)

.dog files can be created from .obj files using the dog.rb tool:

    ruby ./dog.rb -i some_dependency.obj -I some_dependency_dir/ infile.obj outfile.dog

dyload.asm implements loading of .dog files (and their dependencies) as an ESXDOS command:

    .dyload whitens

This expects to find whitens.dog (and its dependency, border.dog) in the '/lib' directory, which is proposed as the standard location for all .dog files. Having loaded the module, it will then jump to the first symbol defined in the module.


.dog file format
================

A .dog file consists of the following sections. All two-byte values within the file are little-endian.

Magic number
------------

All .dog files must begin with the bytes 5a 58 44 4f 47 01 ("ZXDOG" + 0x01).

Future versions of the format will probably be indicated by incrementing the 0x01 byte.

Dependency list
---------------

A list of module names to be loaded before this one.

Consists of one byte for the number of names, then for each name: two bytes for the string length, followed by the string.

For each name in the list, we check if that module has been loaded already. If not, we load and link it (by finding a file named "/lib/{module_name}.dog" and following this process recursively. This is where LFN would come in very handy :-) ). Either way, having located the module, we make a note of the location of its symbol table in memory. The order of module names is significant, because during the patching step, external symbols will be identified as "symbol number X of module number Y", where Y is the (zero-based) index of the module in this list.

Module name
-----------

The name of this module; should match the module's filename (minus the .dog extension). This is kept in memory when the file is loaded; during dependency loading, we do a string compare against this name to check whether the module is already loaded.

Consists of two bytes for the string length, followed by the string.

Code block
----------

Consists of two bytes for the code length, followed by the code itself. If there are references within this code that need to be resolved at linking time, these will be left as 'placeholder' bytes - e.g. LD HL,some_symbol will appear as 21 00 00 here.

Symbol declarations
-------------------

This data will be used to build a symbol table for the module: an array of two-byte values, one for each label in the original source file. (In the .obj file this would be a mapping of labels to values, but here we only reference them by their index number.) The symbol table contains both 'global' symbols - ones which are defined with XLIB / XDEF declarations in the source file and may be referenced by other modules - and 'local' symbols which are only needed during the patching step, and can be overwritten once linking of the module is complete. Global symbols always appear before local ones in the list.

Consists of the following fields:
    * Total number of symbols in the table - two bytes
    * Number of global symbols in the table (i.e. number of entries that need to be retained in memory after loading/linking) - two bytes
Followed by this structure for each symbol:
    * Symbol type - one byte: 'A' (absolute) or 'R' (relative). 'A' values are stored in the table as-is; 'R' values are relative to the start of the code, and have the start address added to them before being stored.
    * Symbol value - two bytes

Patch code
----------

A list of instructions, in a stack-based bytecode language, for patching unresolved references within the loaded code. Consists of a two byte value for the length of the patch code, followed by the code itself. The currently implemented instructions are as follows:

00 qq pp - Fetch local
Retrieve the value at index ppqq in the current module's symbol table, and push it onto the stack.

01 qq pp - Write 16bit
Pop a value from the stack, and write it to the address at offset ppqq within the code as a two-byte value.

02 qq pp - Write 8bit
Pop a value from the stack, and write it to the address at offset ppqq within the code as a one-byte value.

03 - End
Exit the bytecode interpreter.

04 nn qq pp - Fetch external
Locate the module at index nn of the current module's dependency list; retrieve the value at index ppqq of its symbol table; and push it onto the stack.


Future development
==================

* Extend the bytecode with arithmetic operations, so that we can support expressions like "label1 + label2"
* Define a library file format so that we can have multiple independently loadable modules within a single file. (I can't see any advantage to sharing data between the modules - e.g. the dependency list - so this will probably just be a straightforward wrapper around multiple .dog files.)
* Come up with a way to make calls between modules loaded into different memory pages
