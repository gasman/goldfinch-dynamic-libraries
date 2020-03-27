; test loading of dynamically linked objects
	org 0x2000
	
	include "esxdos.inc"
	
	; get library name argument
	ld de,lib_name
	ld bc,63
	call get_command_arg

	ld hl,0x8000
	ld (first_module_address),hl
	ld (module_load_address),hl
	ld hl,import_table
	ld (import_table_next_address),hl

	ld hl,lib_name
	call locate_module
	
	; jump to the first item in the resulting symbol table
	ld e,(hl)
	inc hl
	ld d,(hl)
	push de
	
	ret

	include "get_command_arg.asm"

; Locate the symbol table for a module, loading it first if necessary.
; enter with hl = pointer to null-terminated basename
; return with hl = pointer to symbol table
locate_module
	ex de,hl
	ld hl,(first_module_address)
	
locate_module_lp
	ld a,(hl)	; check 'next module address' field
	inc hl
	or (hl)
	inc hl
	; if zero, we've reached the end of the list (and this isn't a module)
	jr nz,not_end_of_module_list
	ex de,hl
	jr load_module
not_end_of_module_list
	; hl now at offset 2. Check if name matches
	push hl
	inc hl	; skip past symbol table pointer
	inc hl
	ld c,(hl)	; get module name length
	inc hl
	ld b,(hl)
	inc hl
	push de
	
compare_name_lp
	ld a,(de)
	cp (hl)
	jr nz,compare_name_failed
	inc hl
	inc de
	dec bc
	ld a,b
	or c
	jr nz,compare_name_lp
; compare name succeeded; check for trailing null at de
	ld a,(de)
	or a
	jr nz,compare_name_failed
; compare name really succeeded; return symbol table pointer
	pop de
	pop hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	ex de,hl
	ret

compare_name_failed
	pop de
	pop hl
	; advance to next module entry in the list
	dec hl	; rewind to 'next module entry' field
	ld a,(hl)	; high byte
	dec hl
	ld l,(hl)
	ld h,a
	jr locate_module_lp

; Load and link a .dog file
; enter with hl = pointer to null-terminated basename (without .dog extension) of a .dog file in the /lib directory
load_module
	; populate full filename
	ld de,buffer
copy_filename_lp
	ld a,(hl)
	or a
	jr z,copy_filename_done
	ldi
	jr copy_filename_lp
copy_filename_done
; add .dog extension
	ld hl,dog_ext
	ld bc,5	; length of '.dog' plus null
	ldir
	ld hl,lib_path	; start of filename
	
	ld a,'*'
	ld b,FA_READ
	rst 0x08
	db F_OPEN
	ret c
	; file handle now in A
	ld (file_handle),a
	
	ld hl,buffer
	ld bc,6
	rst 0x08
	db F_READ
	ret c
	
	ld b,6
	ld hl,buffer
	ld de,expected_magic_number
check_magic_number_lp
	ld a,(de)
	cp (hl)
	jr nz,check_magic_number_fail
	inc hl
	inc de
	djnz check_magic_number_lp
	jr check_magic_number_ok
check_magic_number_fail
	xor a
	ld hl,err_not_valid_dog_file
	scf
	ret
	
check_magic_number_ok
	
	; start dependency import table at next available position
	ld hl,(import_table_next_address)
	ld (import_table_start_address),hl
	
	; get number of dependencies
	ld hl,buffer
	ld bc,1
	ld a,(file_handle)
	rst 0x08
	db F_READ
	ret c
	ld a,(buffer)
	or a
	jr z,no_dependencies
	ld b,a
	
get_dependency_lp
	; get length of dependency name
	push bc
	ld hl,dependency_name_length
	ld bc,2
	ld a,(file_handle)
	rst 0x08
	db F_READ
	pop bc
	ret c
	; get dependency name
	push bc
	ld bc,(dependency_name_length)
	ld hl,buffer
	ld a,(file_handle)
	rst 0x08
	db F_READ
	pop bc
	ret c
	
	; null-terminate dependency name
	ld hl,buffer
	ld de,(dependency_name_length)
	add hl,de
	ld (hl),0
	
	; find dependency. Need to save file handle, import table start address, and dependency counter on stack, as this may recurse
	push bc
	ld bc,(import_table_start_address)
	push bc
	ld a,(file_handle)
	push af
	
	ld hl,buffer
	call locate_module
	pop de	; file handle now in d - can't pop af because we need to check carry flag
	pop bc
	ld (import_table_start_address),bc
	pop bc
	ret c
	ld a,d
	ld (file_handle),a
	
	; save symbol table address into import table
	ex de,hl
	ld hl,(import_table_next_address)
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ld (import_table_next_address),hl
	
	djnz get_dependency_lp
	
no_dependencies
	; read title length
	ld hl,(module_load_address)
	inc hl	; leave two bytes free as a pointer to the next module
	inc hl
	inc hl	; and two bytes for the symbol table pointer
	inc hl
	
	ld bc,2
	ld a,(file_handle)
	push hl
	rst 0x08
	db F_READ
	pop hl
	ret c
	
	; load that many bytes
	ld c,(hl)
	inc hl
	ld b,(hl)
	inc hl
	push bc
	push hl
	ld a,(file_handle)
	rst 0x08
	db F_READ
	pop hl
	pop bc
	add hl,bc
	ld (code_address),hl
	
	; how many bytes of code?
	ld hl,code_size
	ld bc,2
	ld a,(file_handle)
	rst 0x08
	db F_READ
	ret c
	ld bc,(code_size)
	; load that many bytes
	ld hl,(code_address)
	ld a,(file_handle)
	rst 0x08
	db F_READ
	ret c
	
	; how many symbol declarations, and how many global?
	ld hl,symbol_declaration_count
	ld bc,4
	ld a,(file_handle)
	rst 0x08
	db F_READ
	ret c
	
	; where to load them
	ld hl,(code_address)
	ld bc,(code_size)
	add hl,bc
	ld (symbol_table_address),hl
	
	ld bc,(symbol_declaration_count)
	ld de,(symbol_table_address)
read_symbols_lp
	ld a,b
	or c
	jr z,read_symbols_done
	dec bc
	push bc
	push de
	ld a,(file_handle)
	ld bc,3
	ld hl,buffer
	rst 0x08
	db F_READ
	pop de
	ld hl,buffer
	ld a,(hl)
	cp 'A'	; absolute value
	jr nz,symbol_type_not_absolute
	inc hl
	ldi
	ldi
	
	pop bc
	jr read_symbols_lp
symbol_type_not_absolute	; assume relative instead
	ld hl,(buffer+1)
	ld bc,(code_address)
	add hl,bc
	ex de,hl
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ex de,hl
	
	pop bc
	jr read_symbols_lp
	
read_symbols_done

	; get length of patch code
	ld hl,buffer
	ld bc,2
	ld a,(file_handle)
	rst 0x08
	db F_READ
	ret c
	
	ld bc,(buffer)
	ld hl,buffer
	ld a,(file_handle)
	rst 0x08
	db F_READ
	ret c

; perform patching
	ld hl,buffer
	ld (patchcode_ptr),hl
	ld hl,patchcode_stack
	ld (patchcode_stack_ptr),hl
patch_lp
	ld hl,(patchcode_ptr)
	ld a,(hl)
	inc hl
	or a
	jr z,fetchlocal
	dec a
	jr z,write16
	dec a
	jr z,write8
	dec a
	jr z,patch_done
	dec a
	jr z,fetchexternal
	
	xor a
	ld hl,err_not_valid_dog_file
	scf
	ret
	
patch_done
	; set new module load address to just after the global declarations (it's OK to overwrite the local ones)
	ld hl,(global_symbol_count)
	add hl,hl	; symbols are 2 bytes each
	ld de,(symbol_table_address)
	add hl,de
	; fill next module address and symbol table address at start of module
	ld ix,(module_load_address)
	ld (ix+0),l
	ld (ix+1),h
	ld (ix+2),e
	ld (ix+3),d
	
	ld (module_load_address),hl
	
	; collapse import table to where it was before
	ld hl,(import_table_start_address)
	ld (import_table_next_address),hl

	ex de,hl	; return with hl = pointer to symbol table
	ret

fetchlocal
	ld e,(hl)	; get index number
	inc hl
	ld d,(hl)
	inc hl
	ld (patchcode_ptr),hl
	ex de,hl
	add hl,hl	; convert index number to byte offset into symbol table
	ld de,(symbol_table_address)
	add hl,de
	ld de,(patchcode_stack_ptr)
	ldi
	ldi
	ld (patchcode_stack_ptr),de
	jr patch_lp

write16
	ld e,(hl)	; get write address
	inc hl
	ld d,(hl)
	inc hl
	ld (patchcode_ptr),hl
	ld hl,(code_address)
	add hl,de
	ex de,hl
	
	ld hl,(patchcode_stack_ptr)
	dec hl
	dec hl
	ld (patchcode_stack_ptr),hl
	ldi
	ldi
	jr patch_lp

write8
	ld e,(hl)	; get write address
	inc hl
	ld d,(hl)
	inc hl
	ld (patchcode_ptr),hl
	ld hl,(code_address)
	add hl,de
	ex de,hl
	
	ld hl,(patchcode_stack_ptr)
	dec hl
	dec hl
	ld (patchcode_stack_ptr),hl
	ldi
	jp patch_lp
	
fetchexternal
	ld a,(hl)	; get library index
	inc hl
	ld e,(hl)	; get symbol index
	inc hl
	ld d,(hl)
	inc hl
	ld (patchcode_ptr),hl
	
	ld l,a	; look up library symbol table address in import table
	ld h,0
	add hl,hl
	ld bc,(import_table_start_address)
	add hl,bc
	ld c,(hl)
	inc hl
	ld b,(hl)
	
	ex de,hl	; now hl = symbol table index
	add hl,hl	; convert index number to byte offset into symbol table
	add hl,bc	; and then to absolute address
	ld de,(patchcode_stack_ptr)	; copy what we find there to the patchcode stack
	ldi
	ldi
	ld (patchcode_stack_ptr),de
	jp patch_lp

lib_name
	ds 64

expected_magic_number
	db "ZXDOG", 1

err_not_valid_dog_file
	db "Not a valid .dog fil", "e"+0x80

err_unknown_patch_opcode
	db "Unknown patch opcod", "e"+0x80

dog_ext
	db ".dog", 0

file_handle		db 0
first_module_address		dw 0
module_load_address		dw 0
code_address		dw 0
code_size		dw 0

symbol_declaration_count		dw 0
global_symbol_count		dw 0	; these two must be together, to match file format

symbol_table_address		dw 0
patchcode_ptr		dw 0
patchcode_stack_ptr		dw 0
dependency_name_length		dw 0

import_table_start_address	dw 0
import_table_next_address	dw 0

patchcode_stack		ds 16

lib_path	db '/lib/'	; filename is copied to buffer after this point
buffer		ds 256
import_table	ds 256
