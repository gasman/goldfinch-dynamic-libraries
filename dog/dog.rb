#!/usr/bin/env ruby

PATCHCODE_OPCODES = {
	:fetchlocal => "\x00",
	:write16 => "\x01",
	:write8 => "\x02",
	:end => "\x03",
	:fetchexternal => "\x04",
}

$LOAD_PATH.unshift File.dirname(__FILE__)
require 'lib/object_file'
require 'optparse'

external_object_files = []

OptionParser.new do |opts|
	opts.banner = "Usage: dog [options] infile outfile"
	opts.on("-i", "--include OBJFILE", "Specify an object file to resolve external references") do |obj|
		external_object_files << obj
	end
	opts.on("-I", "--incdir DIR", "Specify a directory containing .obj files to resolve external references") do |dir|
		external_object_files += Dir.glob(File.join(dir, '*.obj'))
	end
end.parse!

# read external object files so that we can resolve non-local symbol references
external_symbols = {}
for filename in external_object_files
	f = File.open(filename)
	obj = ObjectFile.read(f)
	f.close
	obj.global_name_declarations.each_with_index do |decl, index|
		external_symbols[decl.name] = { :object => obj, :index => index }
	end
end

in_file = File.open(ARGV[0])
obj = ObjectFile.read(in_file)
in_file.close

# Analyse input file
global_names = obj.global_name_declarations
local_names = obj.local_name_declarations
name_declarations = global_names + local_names

symbol_indexes_by_name = {}
name_declarations.each_with_index do |decl, i|
	symbol_indexes_by_name[decl.name] = i
end

# For each library name declaration, ensure that there is an object file defining it
dependencies = []
library_indexes_by_name = {}
for symbol in obj.library_name_declarations
	raise "Cannot find definition for imported symbol: #{symbol}" unless external_symbols.has_key?(symbol)
	obj_to_import = external_symbols[symbol][:object]
	unless dependencies.include?(obj_to_import.name)
		library_indexes_by_name[obj_to_import.name] = dependencies.size
		dependencies << obj_to_import.name
	end
end

patch_code = ''
for decl in obj.expression_declarations
	if decl.expression =~ /^[A-Z][A-Z0-9_]*$/ # just one symbol
		if symbol_indexes_by_name.has_key?(decl.expression) # local reference
			patch_code << PATCHCODE_OPCODES[:fetchlocal] << [symbol_indexes_by_name[decl.expression]].pack('v')
		elsif external_symbols.has_key?(decl.expression)
			external_symbol = external_symbols[decl.expression]
			external_lib_index = library_indexes_by_name[external_symbol[:object].name]
			external_symbol_index = external_symbol[:index]
			patch_code << PATCHCODE_OPCODES[:fetchexternal] << [external_lib_index, external_symbol_index].pack('Cv')
		else
			raise "Cannot find definition for symbol in expression: #{decl.expression}"
		end
		if decl.type == 'U' or decl.type == 'S'
			patch_code << PATCHCODE_OPCODES[:write8] << [decl.patchptr].pack('v')
		elsif decl.type == 'C'
			patch_code << PATCHCODE_OPCODES[:write16] << [decl.patchptr].pack('v')
		else
			raise "Cannot handle expression declarations of type #{decl.type}"
		end
	else
		raise "Cannot handle expression: #{decl.expression}"
	end
end
patch_code << PATCHCODE_OPCODES[:end]

# Write output

out_file = File.open(ARGV[1], 'w')
# magic number
out_file << "ZXDOG\x01"

# list of dependencies
out_file << [dependencies.size].pack('C')
for dep in dependencies
	out_file << [dep.length].pack('v') << dep
end

# module name
out_file << [obj.name.size].pack('v') << obj.name

# code block
out_file << [obj.code.size].pack('v') << obj.code

# name declarations
out_file << [name_declarations.size, global_names.size].pack('vv')
name_declarations.each do |decl|
	out_file << (decl.type == 'C' ? 'A' : 'R') << [decl.value].pack('v')
end

# patch code
out_file << [patch_code.size].pack('v') << patch_code

out_file.close